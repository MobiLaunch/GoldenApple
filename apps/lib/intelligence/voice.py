#!/usr/bin/env python3
"""Ephemeral Citron voice session, heard and spoken on this computer.

PipeWire microphone → speech gate → whisper-cpp (speech to text) → Aion Labs
(the reply, streamed) → Piper (text to speech) → PipeWire speaker. Only the
words go to Aion Labs; the voice itself never leaves the computer. Each
finished utterance is written to a private file in the runtime directory for
whisper-cpp to read and deleted at once; nothing is kept. stdin / stdout are
newline-delimited JSON controls and status only, never audio or API keys.
Microphone capture begins only when summoned and stops on mute/close. The
Whisper model and the Piper voice are fetched on first use and checked
against voices.json.
"""
from __future__ import annotations

import asyncio
from array import array
from collections import deque
import ctypes
import json
import math
import os
import re
import signal
import shutil
import tempfile
import threading
import time
import sys
import wave
from pathlib import Path

from helper import (CATALOG, LANGUAGES, IntelligenceError, api_key, config, fetch, needed, speech_file,
                    stream_chat, voice_files, voice_language)

INPUT_RATE = 16000
CHUNK_BYTES = 3200  # 100 ms; signed 16-bit little-endian mono
MAX_UTTERANCE = INPUT_RATE * 2 * 30   # 30 s of speech, then it's transcribed anyway
MIN_UTTERANCE = INPUT_RATE * 2 * 35 // 100   # under 350 ms is a cough, not a request
PR_SET_PDEATHSIG = 1
WHISPER = ("whisper-cli", "whisper-cpp")
PIPER = ("piper", "piper-tts")
# What Whisper writes for sound that isn't words, and the lines it imagines
# from silence at the end of a clip.
NOT_WORDS = re.compile(r"\[[^\]]*\]|\([^)]*\)|♪+|\*[^*]*\*")
PHANTOMS = {"thank you.", "thanks for watching!", "thank you for watching.", "you", "bye.", "."}
SENTENCE = re.compile(r"(.+?[.!?…。！？])(\s+|$)", re.S)


def die_with_parent() -> None:
    # Runs in each child (pw-record, pw-play, whisper-cpp, piper) before exec:
    # if this helper is killed outright (SIGKILL, or the shell reloading), the
    # kernel stops the child too, so the microphone is never left recording.
    try:
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


def emit(event: str, **values) -> None:
    line = json.dumps({"event": event, **values}, ensure_ascii=False) + "\n"
    os.write(1, line.encode("utf-8"))


def instructions(language: str) -> str:
    name = LANGUAGES.get(language, "English")
    return (
        "You are Citron, the helpful voice assistant built into CitronOS. "
        "This is a spoken conversation: answer in a sentence or three, warmly and plainly, "
        "with no lists, headings, emoji or markdown, since every word is read aloud. "
        f"Always answer in {name}, whatever language a word or name is in; switch only when "
        "the person clearly asks you to speak another language. "
        "What the person said reached you through speech recognition and may have small "
        "mistakes: answer what they most likely meant. "
        "Do not claim to access apps, the desktop or personal files, or to execute actions "
        "you cannot actually perform."
    )


def tool(names) -> str:
    return next((p for p in (shutil.which(n) for n in names) if p), "")


def clean(heard: str) -> str:
    """What Whisper heard, without its notes on sounds that aren't words."""
    words = " ".join(NOT_WORDS.sub(" ", heard).split())
    return "" if words.lower() in PHANTOMS else words


def sentences(buffer: str) -> tuple[list[str], str]:
    """Whole sentences ready to be spoken, and what's left over."""
    done, rest = [], buffer
    while (m := SENTENCE.match(rest)) and len(m.group(1).strip()) > 1:
        done.append(m.group(1).strip())
        rest = rest[m.end():]
    return done, rest


class SpeechGate:
    """Decides, 100 ms at a time, whether the microphone hears someone talking.

    Only speech is transcribed: silence, steady sound (a fan, hum, hiss, a
    held note) and lone clicks never leave the computer, so they can't start a
    reply. Speech is louder than the room's noise floor (learned as it goes),
    carries its energy in the voice band (not a low hum, not flat hiss), and
    keeps rising and falling with its syllables while it's loud. Opening takes
    200 ms of it; the 400 ms before are sent too, so the first syllable isn't
    lost; 600 ms of quiet protects normal word gaps before closing, and it
    also closes on a sound that has gone steady. While Citron itself is talking, speech must be
    clearly louder to count (talking over it), so its echo doesn't.
    """
    FRAME = 160            # 10 ms at 16 kHz
    OPEN_CHUNKS = 2        # 200 ms of speech to open
    HANGOVER = 6           # 600 ms of quiet; > natural brief word gaps
    PAUSES = 12.0          # dB it drops between syllables; less for 1.2 s is a steady sound

    def __init__(self):
        self.floor = -60.0
        self.open = False
        self.run = 0
        self.quiet = 0
        self.preroll = deque(maxlen=4)
        self.levels = deque(maxlen=120)     # 10 ms levels of the last 1.2 s

    @classmethod
    def features(cls, chunk: bytes):
        samples = array("h")
        samples.frombytes(chunk[: len(chunk) & ~1])
        n = len(samples)
        if n < cls.FRAME:
            return -90.0, 0.0, []
        energy = diff = 0
        levels = []
        prev = samples[0]
        for start in range(0, n - cls.FRAME + 1, cls.FRAME):
            e = 0
            for s in samples[start:start + cls.FRAME]:
                e += s * s
                d = s - prev
                diff += d * d
                prev = s
            energy += e
            levels.append(10 * math.log10(e / cls.FRAME / 32768 ** 2 + 1e-10))
        db = 10 * math.log10(energy / n / 32768 ** 2 + 1e-10)
        # The first difference weighs high frequencies: hum has almost none of
        # its energy there, flat hiss twice its energy; a voice lies between.
        tilt = diff / energy if energy else 0.0
        return db, tilt, levels

    def syllable(self, threshold: float) -> bool:
        """Whether, in the last 400 ms, a sound got loud and fell back by 10 dB
        or more: a syllable. A fan or a note starting up rises and stays."""
        frames = list(self.levels)[-40:]
        start = next((i for i, l in enumerate(frames) if l > threshold), None)
        if start is None:
            return False
        after = frames[start:]
        peak = after.index(max(after))
        return min(after[peak:]) < after[peak] - 10

    def depth(self, above: float, frames: int) -> float:
        """How far the last `frames` 10 ms frames louder than `above` rise and fall."""
        loud = sorted(l for l in list(self.levels)[-frames:] if l > above)
        if len(loud) < 10:
            return 0.0
        return loud[int(len(loud) * 0.9) - 1] - loud[int(len(loud) * 0.1)]

    def feed(self, chunk: bytes, talking_over: bool = False):
        """Returns (chunks to send now, whether the speech just ended)."""
        db, tilt, levels = self.features(chunk)
        self.levels.extend(levels)
        # Talking over Citron takes a voice near the microphone, whatever the
        # room: what's left of its own voice after echo cancelling is quieter.
        threshold = max(self.floor + 18.0, -42.0) if talking_over else max(self.floor + 10.0, -55.0)
        # Speech is quiet between syllables: its loudest 10 ms is what counts.
        peak = max(levels) if levels else db
        candidate = peak > threshold and 0.015 < tilt < 1.3
        if self.open:
            # Softer syllables and word endings keep it open too.
            self.quiet = 0 if candidate or peak > threshold - 6 else self.quiet + 1
            # Speech drops right down between syllables, again and again; a fan
            # or music held open by chance wanders a few dB and no more.
            steady = len(self.levels) == self.levels.maxlen and self.depth(-200.0, 120) < self.PAUSES
            if self.quiet >= self.HANGOVER or steady:
                self.open = False
                self.run = 0
                if steady:
                    self.floor = max(self.floor, min(-25.0, db))   # that sound is the room now
                else:
                    self.learn(db)
                return [], True
            return [chunk], False
        self.preroll.append(chunk)
        self.run = self.run + 1 if candidate else 0
        if self.run >= self.OPEN_CHUNKS and self.syllable(threshold):
            self.open = True
            self.quiet = 0
            out = list(self.preroll)
            self.preroll.clear()
            return out, False
        if not candidate:
            self.learn(db)
        elif self.run >= 10:
            # Loud for a second without syllables: the room got louder.
            self.learn(db)
        return [], False

    def learn(self, db: float) -> None:
        # The floor falls quickly to a quieter room and rises slowly to a louder one.
        rate = 0.3 if db < self.floor else 0.05
        self.floor = max(-80.0, min(-25.0, self.floor + (db - self.floor) * rate))

    def reset(self) -> None:
        self.open = False
        self.run = self.quiet = 0
        self.preroll.clear()
        self.levels.clear()


WORD = re.compile(r"\w+", re.UNICODE)


def echoes(heard: str, said: str) -> bool:
    """Whether what the microphone heard is Citron's own recent words: nearly
    all of at least five heard words appear, in order, among what it just said.
    (Whisper hears Citron's voice almost word for word; a person asking a
    follow-up with some of the answer's words, "what's the capital of Spain?",
    isn't an echo.)"""
    h = [w.lower() for w in WORD.findall(heard)]
    s = [w.lower() for w in WORD.findall(said)]
    if len(h) < 5 or not s:
        return False
    pairs = set(zip(s, s[1:]))
    matched = sum(1 for pair in zip(h, h[1:]) if pair in pairs)
    return matched / (len(h) - 1) >= 0.8


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
    return b"voice.py" in cmdline


class VoiceSession:
    def __init__(self, cfg: dict, key: str):
        self.cfg, self.key = cfg, key
        self.language = voice_language(cfg["voiceLanguage"])
        self.whisper_language = CATALOG["languages"][self.language]["whisper"]
        self.whisper = tool(WHISPER)
        self.piper = tool(PIPER) if cfg["speak"] else ""
        _, self.speech_model = speech_file(cfg)
        voice, files = voice_files(cfg)
        self.voice_rate = int(voice["rate"])
        self.voice_model = next(p for f, p in files if f["path"].endswith(".onnx"))
        self.voice_config = next(p for f, p in files if f["path"].endswith(".onnx.json"))
        # The conversation so far, for Aion: a few turns, in memory only.
        self.history = deque(maxlen=16)
        self.gate = SpeechGate()
        # What Citron said lately, to catch it hearing itself through the speakers.
        self.said = deque(maxlen=6)
        self.echo_tail = 0.35
        self.muted = False
        self.running = True
        self.mic_allowed = asyncio.Event()
        self.mic_allowed.set()
        self.mic_proc = None
        self.out_proc = None
        self.play_queue = asyncio.Queue()
        self.play_lock = asyncio.Lock()
        self.last_status = ""
        self.audio_epoch = 0
        self.turn_has_audio = False
        self.speaker_active = False
        # If PipeWire/WebRTC AEC is unavailable, protect speaker users with
        # half-duplex capture: the microphone rests while Citron talks.
        self.half_duplex = True
        self.echo_module = None
        self.mic_target = ""
        self.play_target = ""
        self.mic_stopped = asyncio.Event()
        self.mic_stopped.set()
        self.utterance = bytearray()
        self.turn_task = None
        self.utterance_ended_at = 0.0
        # Where an utterance waits for whisper-cpp: private, in memory where
        # the runtime directory is (tmpfs), emptied after each one.
        base = os.environ.get("XDG_RUNTIME_DIR")
        self.private = Path(tempfile.mkdtemp(prefix="citron-voice-", dir=base if base and os.path.isdir(base) else None))

    def status(self, mode: str) -> None:
        if mode != self.last_status:
            self.last_status = mode
            emit("status", mode=mode)

    def idle(self) -> None:
        self.status("muted" if self.muted else "listening")

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
            "--rate", str(self.voice_rate), "--channels", "1", *target, "-",
            stdin=asyncio.subprocess.PIPE,
        )
        await asyncio.sleep(0)
        if self.out_proc.returncode is not None:
            raise RuntimeError("Audio playback couldn't start. Check the PipeWire service.")

    async def reset_audio(self) -> None:
        # An interruption discards only the superseded reply. The epoch also
        # stops an already-dequeued stale chunk from playing.
        self.audio_epoch += 1
        async with self.play_lock:
            while not self.play_queue.empty():
                self.play_queue.get_nowait()
                self.play_queue.task_done()
            await self.stop_proc(self.out_proc)
            self.out_proc = None
        self.turn_has_audio = False
        self.speaker_active = False
        self.utterance_ended_at = 0.0
        if not self.muted:
            self.mic_allowed.set()

    async def interrupt(self) -> None:
        """The person spoke over Citron, or started again: drop the reply."""
        task, self.turn_task = self.turn_task, None
        if task and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
        emit("output_level", value=0)
        await self.reset_audio()

    def start_turn(self, pcm: bytes = b"", typed: str = "") -> None:
        previous = self.turn_task

        async def run():
            if previous and not previous.done():
                previous.cancel()
                await asyncio.gather(previous, return_exceptions=True)
                await self.reset_audio()
            await self.turn(pcm, typed)
        self.turn_task = asyncio.create_task(run())

    async def listen(self) -> None:
        while self.running:
            await self.mic_allowed.wait()
            if not self.running:
                break
            target = ["--target", self.mic_target] if self.mic_target else []
            # Named, so the menu bar's microphone indicator says who's listening.
            self.mic_stopped.clear()
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
                        # Pausing capture for playback or a mute closes the
                        # recorder on purpose; anything else is the hardware.
                        if self.muted or not self.running or not self.mic_allowed.is_set():
                            break
                        raise RuntimeError("Microphone disconnected. Check input permissions and PipeWire.")
                    if self.muted or not self.running or not self.mic_allowed.is_set():
                        break
                    was_open = self.gate.open
                    keep, ended = self.gate.feed(chunk, talking_over=self.speaker_active)
                    if self.gate.open and not was_open:
                        if self.speaker_active and not self.half_duplex:
                            await self.interrupt()      # talking over Citron stops it
                        self.status("listening")
                    for piece in keep:
                        if len(self.utterance) < MAX_UTTERANCE:
                            self.utterance += piece
                    if self.gate.open and len(self.utterance) >= MAX_UTTERANCE:
                        ended = True
                        self.gate.reset()
                    if ended:
                        pcm, self.utterance = bytes(self.utterance), bytearray()
                        if len(pcm) >= MIN_UTTERANCE:
                            self.utterance_ended_at = time.monotonic()
                            self.start_turn(pcm=pcm)
                    emit("level", value=pcm_level(chunk) if self.gate.open else 0)
            finally:
                await self.stop_proc(self.mic_proc)
                self.mic_proc = None
                self.gate.reset()
                self.utterance = bytearray()
                self.mic_stopped.set()

    async def transcribe(self, pcm: bytes) -> str:
        """What was said, by whisper-cpp on this computer, in Citron's language."""
        clip = self.private / "utterance.wav"
        try:
            fd = os.open(clip, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as raw, wave.open(raw, "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(2)
                out.setframerate(INPUT_RATE)
                out.writeframes(pcm)
            proc = await self.process(
                self.whisper, "-m", str(self.speech_model), "-f", str(clip),
                "-l", self.whisper_language, "-nt", "-np", "-t", str(min(8, max(2, os.cpu_count() or 4))),
                stdout=asyncio.subprocess.PIPE,
            )
            try:
                out, _ = await asyncio.wait_for(proc.communicate(), timeout=60)
            except asyncio.TimeoutError:
                await self.stop_proc(proc)
                raise RuntimeError("Speech recognition took too long. Try the Fast model in Settings.")
            if proc.returncode:
                raise RuntimeError("Speech recognition failed. Reinstall whisper-cpp with Software Update.")
            return clean(out.decode("utf-8", errors="replace"))
        finally:
            clip.unlink(missing_ok=True)

    async def start_piper(self):
        return await self.process(
            self.piper, "-m", str(self.voice_model), "-c", str(self.voice_config), "--output_raw",
            stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        )

    def queue_audio(self, data: bytes) -> None:
        if self.half_duplex and not self.speaker_active:
            # The microphone closes before Citron speaks; the listen() task
            # reaps the recorder (mic_stopped) while this keeps going.
            self.mic_allowed.clear()
            if self.mic_proc is not None and self.mic_proc.returncode is None:
                try:
                    self.mic_proc.terminate()
                except ProcessLookupError:
                    pass
            emit("level", value=0)
        if not self.speaker_active and self.utterance_ended_at:
            emit("timing", stage="first_audio", ms=round((time.monotonic() - self.utterance_ended_at) * 1000))
            self.utterance_ended_at = 0.0
        self.speaker_active = True
        self.turn_has_audio = True
        # Normalized amplitude only, for the orb; no audio crosses to the UI.
        emit("output_level", value=pcm_level(data))
        self.play_queue.put_nowait((self.audio_epoch, data))
        self.status("speaking")

    async def speak_out(self, piper) -> None:
        """Piper's speech, into the player as it comes."""
        while True:
            data = await piper.stdout.read(4800)
            if not data:
                break
            self.queue_audio(data)

    async def turn(self, pcm: bytes, typed: str = "") -> None:
        self.status("thinking")
        # Piper loads its voice while the words are worked out.
        piper = await self.start_piper() if self.piper else None
        speaking = asyncio.create_task(self.speak_out(piper)) if piper else None
        try:
            heard = typed or await self.transcribe(pcm)
            if not heard:
                return
            if not typed and echoes(heard, " ".join(self.said)):
                await self.heard_itself()
                return
            if not typed:
                emit("transcript", role="user", text=heard[:1200])
            reply = await self.reply(heard, piper)
            if reply:
                self.history.append({"role": "user", "content": heard})
                self.history.append({"role": "assistant", "content": reply})
                self.said.append(reply[-400:])
            if piper:
                piper.stdin.close()
                await speaking
                speaking = None
            if self.turn_has_audio:
                self.play_queue.put_nowait((self.audio_epoch, None))
                self.turn_has_audio = False
        finally:
            if speaking and not speaking.done():
                speaking.cancel()
                await asyncio.gather(speaking, return_exceptions=True)
            await self.stop_proc(piper)
            if not self.speaker_active:
                self.idle()

    async def reply(self, heard: str, piper) -> str:
        """Aion's answer, streamed: shown as it grows, each sentence spoken
        as soon as it's whole."""
        loop = asyncio.get_running_loop()
        pieces: asyncio.Queue = asyncio.Queue()
        stop = threading.Event()
        messages = [{"role": "system", "content": instructions(self.language)}, *self.history,
                    {"role": "user", "content": heard}]

        def produce():
            try:
                for piece in stream_chat(self.cfg["textModel"], messages, self.key):
                    if stop.is_set():
                        break
                    loop.call_soon_threadsafe(pieces.put_nowait, piece)
                loop.call_soon_threadsafe(pieces.put_nowait, None)
            except IntelligenceError as exc:
                loop.call_soon_threadsafe(pieces.put_nowait, exc)
            except Exception:
                loop.call_soon_threadsafe(pieces.put_nowait, IntelligenceError("Aion Labs' reply was cut off. Try again.", "network"))

        worker = threading.Thread(target=produce, daemon=True)
        worker.start()
        text, pending = "", ""
        try:
            while True:
                piece = await pieces.get()
                if piece is None:
                    break
                if isinstance(piece, IntelligenceError):
                    if piece.code in ("http_401", "http_403", "missing_key", "invalid_key"):
                        raise piece
                    emit("notice", text=str(piece))
                    return ""
                text += piece
                emit("transcript", role="assistant", text=text.strip()[-1500:])
                if piper:
                    pending += piece
                    ready, pending = sentences(pending)
                    for line in ready:
                        piper.stdin.write((" ".join(line.split()) + "\n").encode("utf-8"))
                    if ready:
                        await piper.stdin.drain()
            if piper and pending.strip():
                piper.stdin.write((" ".join(pending.split()) + "\n").encode("utf-8"))
                await piper.stdin.drain()
            return text.strip()
        finally:
            stop.set()

    async def playback(self) -> None:
        # A None item marks the end of a turn. Closing pw-play's stdin and
        # waiting for it ensures the speaker, not just this queue, has
        # finished before a half-duplex microphone opens again.
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
                                await asyncio.wait_for(self.out_proc.wait(), timeout=60)
                            except asyncio.TimeoutError:
                                await self.stop_proc(self.out_proc)
                            finally:
                                self.out_proc = None
                    # Let the room's echo die away.
                    if self.half_duplex:
                        await asyncio.sleep(self.echo_tail)
                    if epoch == self.audio_epoch:
                        self.speaker_active = False
                        emit("output_level", value=0)
                        if self.half_duplex and not self.muted:
                            self.mic_allowed.set()
                        self.idle()
                    continue
                async with self.play_lock:
                    if epoch != self.audio_epoch:
                        continue
                    if self.half_duplex:
                        # Playback waits until the microphone is really closed.
                        await self.mic_stopped.wait()
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

    async def heard_itself(self) -> None:
        """Citron heard its own voice (speakers into the microphone, an echo
        canceller that let it through). From now on the microphone rests while
        Citron talks, and a little longer after, for the echo to die away."""
        if self.half_duplex and self.echo_tail >= 0.8:
            return
        self.half_duplex = True
        self.echo_tail = 0.8
        emit("notice", text="Citron heard itself through the speakers, so it will listen once it has finished talking. Headphones let you interrupt it.")

    async def controls(self) -> None:
        stream = asyncio.StreamReader()
        loop = asyncio.get_running_loop()
        protocol = asyncio.StreamReaderProtocol(stream)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin.buffer)
        while self.running:
            data = await stream.readline()
            if not data:
                self.running = False
                return
            try:
                msg = json.loads(data)
            except (ValueError, UnicodeDecodeError):
                continue
            action = msg.get("action")
            if action == "stop":
                self.running = False
                return
            if action == "mute":
                self.muted = bool(msg.get("enabled", False))
                if self.muted:
                    self.mic_allowed.clear()
                    await self.stop_proc(self.mic_proc)
                    emit("level", value=0)
                    self.status("muted")
                else:
                    if not self.half_duplex or not self.speaker_active:
                        self.mic_allowed.set()
                    self.status("speaking" if self.speaker_active else "listening")
            if action == "text" and isinstance(msg.get("text"), str):
                txt = msg["text"].strip()[:3000]
                if txt:
                    emit("transcript", role="user", text=txt)
                    self.start_turn(typed=txt)

    async def prepare(self) -> None:
        """Fetch the voice files on first use, with progress for the overlay."""
        missing = needed(self.cfg)
        if not missing:
            return
        total = sum(e["size"] for _, e, _ in missing)
        done = 0
        last = -1
        self.status("downloading")

        def progress(n):
            nonlocal done, last
            done += n
            step = int(done * 100 / total)
            if step != last:
                last = step
                emit("download", done=done, total=total)
        loop = asyncio.get_running_loop()
        for url, entry, path in missing:
            await loop.run_in_executor(None, fetch, url, entry, path, progress)

    async def shutdown(self):
        self.running = False
        self.mic_allowed.set()

    async def run(self) -> None:
        # Quickshell stops the helper on Close. Intercept TERM so mic/speaker
        # subprocesses are torn down rather than left capturing audio.
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            loop.add_signal_handler(sig, lambda: asyncio.create_task(self.shutdown()))
        self.status("connecting")
        try:
            await self.prepare()
            self.status("connecting")
            await self.setup_echo_cancel()
            self.status("listening")
            tasks = [
                asyncio.create_task(self.controls()),
                asyncio.create_task(self.listen()),
                asyncio.create_task(self.playback()),
                asyncio.create_task(self.until_stopped()),
            ]
            done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            for t in done:
                if not t.cancelled() and t.exception():
                    raise t.exception()
            if self.turn_task and self.turn_task.done() and not self.turn_task.cancelled() and self.turn_task.exception():
                raise self.turn_task.exception()
        finally:
            self.running = False
            self.mic_allowed.set()
            if self.turn_task and not self.turn_task.done():
                self.turn_task.cancel()
                await asyncio.gather(self.turn_task, return_exceptions=True)
            await self.stop_proc(self.mic_proc)
            await self.stop_proc(self.out_proc)
            await self.remove_echo_cancel()
            shutil.rmtree(self.private, ignore_errors=True)
            self.key = ""

    async def until_stopped(self) -> None:
        # Ends the session when asked to stop, or when a turn fails for good
        # (the key was refused): its error is raised by run().
        while self.running:
            task = self.turn_task
            if task and task.done() and not task.cancelled() and task.exception():
                return
            await asyncio.sleep(0.2)


async def main() -> int:
    try:
        cfg = config()
        if not cfg["enabled"]:
            raise IntelligenceError("Enable Citron Intelligence in Settings first.", "disabled")
        if not shutil.which("pw-record") or not shutil.which("pw-play"):
            raise RuntimeError("PipeWire audio tools are missing (pw-record / pw-play).")
        if not tool(WHISPER):
            raise RuntimeError("Voice needs speech recognition (whisper-cpp). Install it with Software Update.")
        if cfg["speak"] and not tool(PIPER):
            raise RuntimeError("Spoken replies need Piper (piper-tts). Install it with Software Update, or turn off Speak Replies in Settings.")
        voice = VoiceSession(cfg, api_key())
        await voice.run()
        emit("status", mode="stopped")
        return 0
    except IntelligenceError as e:
        emit("error", text=str(e))
    except Exception as e:
        # Never print request headers or an API key.
        kind = type(e).__name__
        text = str(e)[:180] if kind == "RuntimeError" else \
            "Voice couldn't start (" + kind + "). Check your microphone, speakers and network."
        emit("error", text=text)
    return 1


if __name__ == "__main__":
    try:
        raise SystemExit(asyncio.run(main()))
    except KeyboardInterrupt:
        pass
