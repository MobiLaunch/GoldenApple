#!/usr/bin/env python3
"""Ephemeral Citron voice session: PipeWire PCM <-> Gemini Live WebSocket.

The API key stays in the user's keyring and never crosses QML, argv or stdout.
stdin / stdout are newline-delimited JSON *controls and status only*, never
recorded audio or API keys. Microphone capture begins only when summoned and
stops on mute/close. No voice history or recordings are persisted.
"""
from __future__ import annotations

import asyncio
import base64
from array import array
import ctypes
import json
import os
import signal
import shutil
import sys
from pathlib import Path
from urllib.parse import quote

from helper import IntelligenceError, api_key, config

INPUT_RATE = 16000
OUTPUT_RATE = 24000
CHUNK_BYTES = 3200  # 100 ms; signed 16-bit little-endian mono
HOST = "generativelanguage.googleapis.com"
PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
MAX_MESSAGE = 24 * 1024 * 1024
PR_SET_PDEATHSIG = 1


def die_with_parent() -> None:
    # Runs in each pw-record / pw-play child before exec: if this helper is
    # killed outright (SIGKILL, or the shell reloading), the kernel stops the
    # child too, so the microphone is never left recording on its own.
    try:
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def emit(event: str, **values) -> None:
    line = json.dumps({"event": event, **values}, ensure_ascii=False) + "\n"
    os.write(1, line.encode("utf-8"))


def setup_message(model: str, voice: str) -> dict:
    return {
        "setup": {
            "model": "models/" + model,
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voice}}},
            },
            "inputAudioTranscription": {},
            "outputAudioTranscription": {},
            "systemInstruction": {"parts": [{"text":
                "You are Citron, the helpful voice assistant built into CitronOS. "
                "Have a fluid, conversational, brief and warm dialogue. "
                "Listen carefully, accept interruptions and follow-up questions. "
                "Do not claim to access apps, the desktop or personal files, or "
                "to execute actions you cannot actually perform."}]},
        }
    }


def audio_packet(chunk: bytes) -> dict:
    return {"realtimeInput": {"audio": {
        "data": base64.b64encode(chunk).decode("ascii"),
        "mimeType": "audio/pcm;rate=16000",
    }}}


def pcm_level(chunk: bytes) -> float:
    # Lightweight UI visualizer: sample every 32nd value, no retained audio.
    samples = array("h")
    samples.frombytes(chunk[: len(chunk) & ~1])
    if not samples:
        return 0.0
    sparse = samples[::31]
    energy = sum(int(s) * int(s) for s in sparse) / len(sparse)
    return round(min(1.0, (energy ** .5) / 7500), 3)


def alive(pid: int) -> bool:
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False
    return b"live.py" in cmdline


class VoiceSession:
    def __init__(self, model: str, voice: str, key: str):
        self.model, self.voice, self.key = model, voice, key
        self.muted = False
        self.running = True
        self.mic_allowed = asyncio.Event()
        self.mic_allowed.set()
        self.mic_proc = None
        self.out_proc = None
        # Unbounded: the reply arrives faster than it plays, and the WebSocket
        # must keep being read meanwhile. Blocking the reader on a full queue
        # stalled keepalive pongs (Gemini dropped the call during long replies)
        # and held back "interrupted", so barge-in only took effect once the
        # backlog had played. A reply is at most a few MB of PCM.
        self.play_queue = asyncio.Queue()
        self.play_lock = asyncio.Lock()
        self.last_status = ""
        self.ws = None
        self.audio_epoch = 0
        self.turn_has_audio = False
        self.speaker_active = False
        # If PipeWire/WebRTC AEC is unavailable, protect speaker users with
        # half-duplex capture. Never send our own playback back to Gemini.
        self.half_duplex = True
        self.echo_module = None
        self.mic_target = ""
        self.play_target = ""

    def status(self, mode: str) -> None:
        if mode != self.last_status:
            self.last_status = mode
            emit("status", mode=mode)

    async def process(self, cmd: str, *options, stdin=None, stdout=None):
        return await asyncio.create_subprocess_exec(
            cmd, *options, stdin=stdin, stdout=stdout,
            stderr=asyncio.subprocess.DEVNULL, preexec_fn=die_with_parent,
        )

    async def stop_proc(self, proc) -> None:
        if proc is None:
            return
        try:
            if proc.returncode is None:
                proc.terminate()
        except ProcessLookupError:
            pass
        try:
            await asyncio.wait_for(proc.wait(), timeout=0.6)
        except (asyncio.TimeoutError, ProcessLookupError):
            if proc.returncode is None:
                proc.kill()
                await proc.wait()

    async def setup_echo_cancel(self) -> None:
        """Use a private PipeWire WebRTC echo-cancel source/sink when supported.

        The module is scoped to this voice session and unloaded on shutdown.
        Both pw-record and pw-play MUST use the matched virtual devices, since
        echo cancellation needs a reference of precisely the played audio.
        """
        if not shutil.which("pactl"):
            emit("notice", text="Speaker-safe mode: wait until Citron finishes before talking.")
            return
        await self.remove_stale_echo_cancel()
        suffix = str(os.getpid())
        mic = "citron_aec_mic_" + suffix
        speaker = "citron_aec_speaker_" + suffix
        proc = await self.process(
            "pactl", "load-module", "module-echo-cancel",
            "source_name=" + mic, "sink_name=" + speaker,
            "aec_method=webrtc", stdout=asyncio.subprocess.PIPE,
        )
        try:
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=4)
        except asyncio.TimeoutError:
            await self.stop_proc(proc)
            emit("notice", text="Speaker-safe mode: wait until Citron finishes before talking.")
            return
        number = out.decode("ascii", errors="ignore").strip()
        if proc.returncode == 0 and number.isdecimal():
            self.echo_module = number
            self.mic_target = mic
            self.play_target = speaker
            self.half_duplex = False
            # Let WirePlumber register the new devices before opening streams.
            await asyncio.sleep(0.2)
        else:
            emit("notice", text="Speaker-safe mode: wait until Citron finishes before talking.")

    async def remove_stale_echo_cancel(self) -> None:
        """Unload echo cancellers left by sessions that were killed outright.

        A helper stopped with SIGKILL (the shell reloading, a crash) can't
        unload its module, which then keeps the real microphone open and
        piles up virtual devices session after session.
        """
        try:
            proc = await self.process("pactl", "list", "short", "modules", stdout=asyncio.subprocess.PIPE)
            out, _ = await asyncio.wait_for(proc.communicate(), timeout=4)
        except (OSError, asyncio.TimeoutError):
            return
        for line in out.decode("utf-8", errors="ignore").splitlines():
            fields = line.split("\t")
            if len(fields) < 3 or fields[1] != "module-echo-cancel" or "citron_aec_mic_" not in fields[2]:
                continue
            owner = fields[2].split("citron_aec_mic_", 1)[1].split()[0]
            if owner.isdecimal() and not alive(int(owner)):
                try:
                    proc = await self.process("pactl", "unload-module", fields[0])
                    await asyncio.wait_for(proc.wait(), timeout=4)
                except (OSError, asyncio.TimeoutError):
                    pass

    async def remove_echo_cancel(self) -> None:
        if not self.echo_module:
            return
        module, self.echo_module = self.echo_module, None
        try:
            proc = await self.process("pactl", "unload-module", module)
            await asyncio.wait_for(proc.wait(), timeout=4)
        except (OSError, asyncio.TimeoutError):
            if "proc" in locals():
                await self.stop_proc(proc)

    async def open_player(self) -> None:
        target = ["--target", self.play_target] if self.play_target else []
        self.out_proc = await self.process(
            "pw-play", "--raw", "--format", "s16",
            "--rate", str(OUTPUT_RATE), "--channels", "1", *target, "-",
            stdin=asyncio.subprocess.PIPE,
        )
        await asyncio.sleep(0)
        if self.out_proc.returncode is not None:
            raise RuntimeError("Audio playback couldn't start. Check the PipeWire service.")

    async def reset_audio(self) -> None:
        # A genuine interruption discards only the superseded response.
        # The epoch also prevents an already-dequeued stale chunk replaying.
        self.audio_epoch += 1
        async with self.play_lock:
            while not self.play_queue.empty():
                self.play_queue.get_nowait()
                self.play_queue.task_done()
            await self.stop_proc(self.out_proc)
            self.out_proc = None
        self.turn_has_audio = False
        self.speaker_active = False
        if not self.muted:
            self.mic_allowed.set()

    async def listen(self) -> None:
        while self.running:
            await self.mic_allowed.wait()
            if not self.running:
                break
            target = ["--target", self.mic_target] if self.mic_target else []
            # Named, so the menu bar's microphone indicator says who's listening.
            self.mic_proc = await self.process(
                "pw-record", "--raw", "--format", "s16",
                "--rate", str(INPUT_RATE), "--channels", "1", *target,
                "-P", '{ application.name = "Citron" media.role = "Communication" }', "-",
                stdout=asyncio.subprocess.PIPE,
            )
            try:
                while self.running and not self.muted and self.mic_allowed.is_set():
                    try:
                        chunk = await self.mic_proc.stdout.readexactly(CHUNK_BYTES)
                    except asyncio.IncompleteReadError:
                        # Pausing capture for playback or user mute closes the
                        # subprocess intentionally, not a hardware failure.
                        if self.muted or not self.running or not self.mic_allowed.is_set():
                            break
                        raise RuntimeError("Microphone disconnected. Check input permissions and PipeWire.")
                    if self.muted or not self.running or not self.mic_allowed.is_set():
                        break
                    await self.ws.send(json.dumps(audio_packet(chunk)))
                    emit("level", value=pcm_level(chunk))
            finally:
                await self.stop_proc(self.mic_proc)
                self.mic_proc = None

    async def playback(self) -> None:
        # A None item marks the end of a turn. Closing pw-play's stdin and
        # waiting for exit ensures the speaker, not just Python's queue, has
        # finished before a half-duplex microphone is enabled again.
        while self.running:
            epoch, chunk = await self.play_queue.get()
            try:
                if epoch != self.audio_epoch:
                    continue
                if chunk is None:
                    async with self.play_lock:
                        if epoch != self.audio_epoch:
                            continue
                        if self.out_proc is not None:
                            try:
                                self.out_proc.stdin.close()
                                await asyncio.wait_for(self.out_proc.wait(), timeout=30)
                            except asyncio.TimeoutError:
                                await self.stop_proc(self.out_proc)
                            finally:
                                self.out_proc = None
                    # Allow the room's acoustic echo/reverb to decay.
                    if self.half_duplex:
                        await asyncio.sleep(0.35)
                    if epoch == self.audio_epoch:
                        self.speaker_active = False
                        if self.half_duplex and not self.muted:
                            self.mic_allowed.set()
                        self.status("muted" if self.muted else "listening")
                    continue
                async with self.play_lock:
                    if epoch != self.audio_epoch:
                        continue
                    if self.out_proc is None or self.out_proc.returncode is not None:
                        await self.open_player()
                    self.out_proc.stdin.write(chunk)
                    await self.out_proc.stdin.drain()
            except (BrokenPipeError, ConnectionResetError):
                raise RuntimeError("Audio output disconnected. Check the selected speaker.")
            finally:
                self.play_queue.task_done()

    async def receive(self) -> None:
        async for raw in self.ws:
            msg = json.loads(raw)
            if "goAway" in msg:
                emit("notice", text="This voice session is ending. Reopen Citron to keep talking.")
            if "setupComplete" in msg:
                self.status("listening")
            sc = msg.get("serverContent") or {}
            if sc.get("interrupted"):
                await self.reset_audio()
                self.status("muted" if self.muted else "listening")
            if sc.get("inputTranscription", {}).get("text"):
                emit("transcript", role="user", text=sc["inputTranscription"]["text"][:1200])
            if sc.get("outputTranscription", {}).get("text"):
                emit("transcript", role="assistant", text=sc["outputTranscription"]["text"][:1200])
            for part in (sc.get("modelTurn") or {}).get("parts", []):
                inline = part.get("inlineData") or {}
                if not inline.get("data") or "audio" not in inline.get("mimeType", "audio/pcm"):
                    continue
                try:
                    data = base64.b64decode(inline["data"], validate=True)
                except (ValueError, TypeError):
                    continue
                if self.half_duplex and not self.speaker_active:
                    # Pause before emitting any output so the mic can't feed
                    # Citron's speaker audio back to server-side VAD.
                    self.mic_allowed.clear()
                    await self.stop_proc(self.mic_proc)
                    emit("level", value=0)
                self.speaker_active = True
                self.turn_has_audio = True
                # Every chunk is kept (none dropped), without ever pausing the reader.
                self.play_queue.put_nowait((self.audio_epoch, data))
                self.status("speaking")
            if sc.get("turnComplete"):
                if self.turn_has_audio:
                    self.play_queue.put_nowait((self.audio_epoch, None))
                    self.turn_has_audio = False
                elif not self.speaker_active:
                    self.status("muted" if self.muted else "listening")
        if self.running:
            raise RuntimeError("Gemini closed the Live connection. Open voice mode again.")

    async def controls(self) -> None:
        stream = asyncio.StreamReader()
        loop = asyncio.get_running_loop()
        protocol = asyncio.StreamReaderProtocol(stream)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer)
        while self.running:
            data = await stream.readline()
            if not data:
                self.running = False
                await self.ws.close()
                return
            try:
                msg = json.loads(data)
            except (ValueError, UnicodeDecodeError):
                continue
            action = msg.get("action")
            if action == "stop":
                self.running = False
                await self.ws.close()
                return
            if action == "mute":
                self.muted = bool(msg.get("enabled", False))
                if self.muted:
                    self.mic_allowed.clear()
                    await self.stop_proc(self.mic_proc)
                    if self.ws:
                        await self.ws.send(json.dumps({"realtimeInput": {"audioStreamEnd": True}}))
                    emit("level", value=0)
                    self.status("muted")
                else:
                    if not self.half_duplex or not self.speaker_active:
                        self.mic_allowed.set()
                    self.status("speaking" if self.speaker_active else "listening")
            if action == "text" and isinstance(msg.get("text"), str):
                txt = msg["text"].strip()[:3000]
                if txt:
                    await self.ws.send(json.dumps({"realtimeInput": {"text": txt}}))
                    emit("transcript", role="user", text=txt)

    async def shutdown(self):
        self.running = False
        self.mic_allowed.set()
        if self.ws:
            await self.ws.close()

    async def run(self) -> None:
        from websockets.asyncio.client import connect

        # Quickshell stops the helper on Close. Intercept TERM so mic/speaker
        # subprocesses are torn down rather than left capturing audio.
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            loop.add_signal_handler(sig, lambda: asyncio.create_task(self.shutdown()))
        self.status("connecting")
        uri = "wss://" + HOST + PATH + "?key=" + quote(self.key, safe="")
        try:
            async with connect(uri, max_size=MAX_MESSAGE, open_timeout=12, ping_interval=15) as ws:
                self.ws = ws
                await ws.send(json.dumps(setup_message(self.model, self.voice)))
                raw = await asyncio.wait_for(ws.recv(), timeout=20)
                if "setupComplete" not in json.loads(raw):
                    raise RuntimeError("Gemini rejected voice setup. Verify the voice model and API access.")
                await self.setup_echo_cancel()
                self.status("listening")
                tasks = [
                    asyncio.create_task(self.controls()),
                    asyncio.create_task(self.listen()),
                    asyncio.create_task(self.playback()),
                    asyncio.create_task(self.receive()),
                ]
                done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for t in pending:
                    t.cancel()
                await asyncio.gather(*pending, return_exceptions=True)
                for t in done:
                    if not t.cancelled() and t.exception():
                        raise t.exception()
        finally:
            self.running = False
            self.mic_allowed.set()
            await self.stop_proc(self.mic_proc)
            await self.stop_proc(self.out_proc)
            await self.remove_echo_cancel()
            self.key = ""
            self.ws = None


async def main() -> int:
    try:
        cfg = config()
        if not cfg["enabled"]:
            raise IntelligenceError("Enable Citron Intelligence in Settings first.", "disabled")
        if not shutil.which("pw-record") or not shutil.which("pw-play"):
            raise RuntimeError("PipeWire audio tools are missing (pw-record / pw-play).")
        key = api_key()
        voice = VoiceSession(cfg["voiceModel"], cfg["voiceName"], key)
        await voice.run()
        emit("status", mode="stopped")
        return 0
    except ImportError:
        emit("error", text="Live voice support needs python-websockets. Install it with Software Update.")
    except IntelligenceError as e:
        emit("error", text=str(e))
    except Exception as e:
        # Never print WebSocket URI, server request headers or an API key.
        kind = type(e).__name__
        msg = str(e)
        if kind in ("RuntimeError",):
            text = msg[:180]
        else:
            text = "Couldn't connect or stream audio (" + kind + "). Verify your network, Gemini Live access and audio devices."
        emit("error", text=text)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        pass
