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
import json
import os
import shutil
import sys
from urllib.parse import quote

from helper import IntelligenceError, api_key, config

INPUT_RATE = 16000
OUTPUT_RATE = 24000
CHUNK_BYTES = 3200  # 100 ms; signed 16-bit little-endian mono
HOST = "generativelanguage.googleapis.com"
PATH = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
MAX_MESSAGE = 24 * 1024 * 1024


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
    energy = sum(int(s) * int(s) for s in samples[::32]) / len(samples[::32])
    return round(min(1.0, (energy ** .5) / 7500), 3)


class VoiceSession:
    def __init__(self, model: str, voice: str, key: str):
        self.model, self.voice, self.key = model, voice, key
        self.muted = False
        self.running = True
        self.mic_allowed = asyncio.Event()
        self.mic_allowed.set()
        self.mic_proc = None
        self.out_proc = None
        self.play_queue = asyncio.Queue(maxsize=18)
        self.play_lock = asyncio.Lock()
        self.last_status = ""
        self.ws = None
        self.turn_ended = False

    def status(self, mode: str) -> None:
        if mode != self.last_status:
            self.last_status = mode
            emit("status", mode=mode)

    async def process(self, cmd: str, *options, stdin=None, stdout=None):
        return await asyncio.create_subprocess_exec(
            cmd, *options, stdin=stdin, stdout=stdout,
            stderr=asyncio.subprocess.DEVNULL,
        )

    async def stop_proc(self, proc) -> None:
        if proc is None:
            return
        if proc.returncode is None:
            proc.terminate()
        try:
            await asyncio.wait_for(proc.wait(), timeout=0.6)
        except (asyncio.TimeoutError, ProcessLookupError):
            if proc.returncode is None:
                proc.kill()
                await proc.wait()

    async def open_player(self) -> None:
        self.out_proc = await self.process(
            "pw-play", "--raw", "--format", "s16",
            "--rate", str(OUTPUT_RATE), "--channels", "1", "-",
            stdin=asyncio.subprocess.PIPE,
        )
        await asyncio.sleep(0)
        if self.out_proc.returncode is not None:
            raise RuntimeError("Audio playback couldn't start. Check the PipeWire service.")

    async def reset_audio(self) -> None:
        async with self.play_lock:
            while not self.play_queue.empty():
                self.play_queue.get_nowait()
                self.play_queue.task_done()
            await self.stop_proc(self.out_proc)
            self.out_proc = None
            self.turn_ended = False
            await self.open_player()

    async def listen(self) -> None:
        while self.running:
            await self.mic_allowed.wait()
            if not self.running:
                break
            self.mic_proc = await self.process(
                "pw-record", "--raw", "--format", "s16",
                "--rate", str(INPUT_RATE), "--channels", "1", "-",
                stdout=asyncio.subprocess.PIPE,
            )
            try:
                while self.running and not self.muted:
                    try:
                        chunk = await self.mic_proc.stdout.readexactly(CHUNK_BYTES)
                    except asyncio.IncompleteReadError:
                        raise RuntimeError("Microphone disconnected. Check input permissions and PipeWire.")
                    # Server-side VAD handles pauses and barge-in, no button
                    # needed for each utterance.
                    await self.ws.send(json.dumps(audio_packet(chunk)))
                    emit("level", value=pcm_level(chunk))
            finally:
                await self.stop_proc(self.mic_proc)
                self.mic_proc = None

    async def playback(self) -> None:
        await self.open_player()
        while self.running:
            chunk = await self.play_queue.get()
            try:
                async with self.play_lock:
                    if self.out_proc is None or self.out_proc.returncode is not None:
                        await self.open_player()
                    self.out_proc.stdin.write(chunk)
                    await self.out_proc.stdin.drain()
            except (BrokenPipeError, ConnectionResetError):
                raise RuntimeError("Audio output disconnected. Check the selected speaker.")
            finally:
                self.play_queue.task_done()
            if self.turn_ended and self.play_queue.empty():
                self.status("listening")

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
                self.status("listening")
            if sc.get("inputTranscription", {}).get("text"):
                emit("transcript", role="user", text=sc["inputTranscription"]["text"][:1200])
            if sc.get("outputTranscription", {}).get("text"):
                emit("transcript", role="assistant", text=sc["outputTranscription"]["text"][:1200])
            for part in (sc.get("modelTurn") or {}).get("parts", []):
                inline = part.get("inlineData") or {}
                if not inline.get("data"):
                    continue
                if "audio" not in inline.get("mimeType", "audio/pcm"):
                    continue
                try:
                    data = base64.b64decode(inline["data"], validate=True)
                except (ValueError, TypeError):
                    continue
                if self.play_queue.full():
                    # Avoid unbounded memory and audible delay on slow devices.
                    self.play_queue.get_nowait()
                    self.play_queue.task_done()
                self.play_queue.put_nowait(data)
                self.turn_ended = False
                self.status("speaking")
            if sc.get("turnComplete"):
                self.turn_ended = True
                if self.play_queue.empty():
                    self.status("listening")
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
                    self.mic_allowed.set()
                    self.status("listening")
            if action == "text" and isinstance(msg.get("text"), str):
                txt = msg["text"].strip()[:3000]
                if txt:
                    await self.ws.send(json.dumps({"realtimeInput": {"text": txt}}))
                    emit("transcript", role="user", text=txt)

    async def run(self) -> None:
        from websockets.asyncio.client import connect

        self.status("connecting")
        uri = "wss://" + HOST + PATH + "?key=" + quote(self.key, safe="")
        try:
            async with connect(uri, max_size=MAX_MESSAGE, open_timeout=12, ping_interval=15) as ws:
                self.ws = ws
                await ws.send(json.dumps(setup_message(self.model, self.voice)))
                raw = await asyncio.wait_for(ws.recv(), timeout=20)
                if "setupComplete" not in json.loads(raw):
                    raise RuntimeError("Gemini rejected voice setup. Verify the voice model and API access.")
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
