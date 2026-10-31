#!/usr/bin/env python3
"""Offline contract/privacy checks for Citron's voice (whisper-cpp, then Aion
Labs, then Piper: all but the words stay on this computer) and its launch."""
from __future__ import annotations
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/lib/intelligence"))
spec = importlib.util.spec_from_file_location("citron_voice", ROOT / "apps/lib/intelligence/voice.py")
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)
import asyncio
import os
import tempfile
from helper import CATALOG, DEFAULTS, LANGUAGES, system_language, voice_language
import math
import random
from array import array


def pcm(fn, seconds):
    """16 kHz mono PCM of fn(t) in -1…1, as the microphone's 100 ms chunks."""
    data = array("h", (max(-32767, min(32767, int(fn(i / 16000) * 32767))) for i in range(int(seconds * 16000)))).tobytes()
    return [data[i:i + 3200] for i in range(0, len(data), 3200)]


NOISE = random.Random(7)


def white(a):
    return lambda t: a * (NOISE.random() * 2 - 1)


def fan(a):
    state = [0.0]
    def f(t):
        state[0] = 0.98 * state[0] + 0.02 * (NOISE.random() * 2 - 1)
        return a * state[0] * 8
    return f


def tone(a, hz):
    return lambda t: a * math.sin(2 * math.pi * hz * t)


def chord(a):
    return lambda t: a * sum(math.sin(2 * math.pi * f * t) for f in (262, 330, 392)) / 3


def speech(a, f0=150):
    # A voiced sound with harmonics, in syllables three and a half times a second.
    def f(t):
        env = max(0.0, math.sin(2 * math.pi * 3.5 * t)) ** 1.5
        return a * env * sum(math.sin(2 * math.pi * f0 * k * t) / k * (1.6 if 3 <= k <= 5 else 1) for k in range(1, 20)) / 3
    return f


def mix(*fs):
    return lambda t: sum(f(t) for f in fs)


CFG = {**DEFAULTS, "enabled": True, "voiceLanguage": "en-US", "voice": "en_US-amy-medium"}


class Launch(unittest.TestCase):
    def test_shell_route_and_global_shortcut(self):
        qml = (ROOT / "shell/VoiceAssistant.qml").read_text()
        shell = (ROOT / "shell/shell.qml").read_text()
        opener = (ROOT / "apps/intelligence/open.sh").read_text()
        bindings = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        self.assertIn('target: "citron"', qml)
        self.assertIn("objectName: \"citronSystemOverlay\"", qml)
        self.assertIn("voiceProc.running = false", qml)
        self.assertIn("source: \"VoiceAssistant.qml\"", shell)
        self.assertIn('ipc call citron "$mode"', opener)
        self.assertIn("ipc call citron toggle", bindings)



    def test_voice_is_local_and_only_words_go_out(self):
        src = (ROOT / "apps/lib/intelligence/voice.py").read_text()
        self.assertNotIn("websocket", src.lower())
        self.assertNotIn("generativelanguage", src)
        self.assertIn('WHISPER = ("whisper-cli", "whisper-cpp")', src)
        self.assertIn("stream_chat(", src)
        self.assertFalse((ROOT / "apps/lib/intelligence/live.py").exists())


class Language(unittest.TestCase):
    def test_system_language(self):
        self.assertEqual(system_language({"LANG": "de_DE.UTF-8"}), "de-DE")
        self.assertEqual(system_language({"LANG": "de_AT.UTF-8"}), "de-DE")
        self.assertEqual(system_language({"LANG": "zh_CN.UTF-8"}), "zh-CN")
        self.assertEqual(system_language({"LC_ALL": "C", "LANG": "fr_FR.UTF-8"}), "fr-FR")
        self.assertEqual(system_language({"LANG": "C.UTF-8"}), "en-US")
        self.assertEqual(system_language({}), "en-US")
        self.assertEqual(voice_language("ja-JP", {"LANG": "de_DE"}), "ja-JP")
        self.assertEqual(voice_language("auto", {"LANG": "it_IT.UTF-8"}), "it-IT")
        self.assertEqual(voice_language("klingon", {"LANG": "it_IT"}), "it-IT")
        self.assertEqual(DEFAULTS["voiceLanguage"], "auto")
        self.assertIn("en-US", LANGUAGES)


    def test_each_language_hears_and_speaks(self):
        for code, entry in CATALOG["languages"].items():
            with self.subTest(code):
                self.assertRegex(entry["whisper"], r"^[a-z]{2}$")
                self.assertTrue(entry["voices"])
                for v in entry["voices"]:
                    self.assertEqual({f["path"].rsplit(".", 1)[-1] for f in v["files"]}, {"onnx", "json"})

    def test_instructions_pin_the_language_and_suit_speech(self):
        text = voice.instructions("fr-FR")
        self.assertIn("Always answer in French", text)
        self.assertIn("read aloud", text)


class SpeechGateTests(unittest.TestCase):
    """Only speech is transcribed: the room's sounds can't start a reply."""

    def run_gate(self, before, during, seconds=3, talking_over=False):
        gate = voice.SpeechGate()
        for chunk in pcm(before, 2):
            gate.feed(chunk)
        sent = 0
        for chunk in pcm(during, seconds):
            sent += len(gate.feed(chunk, talking_over=talking_over)[0])
        return sent

    def test_room_sounds_are_never_sent(self):
        quiet = white(0.0005)
        for name, sound in [("silence", lambda t: 0.0), ("a quiet room", quiet), ("mains hum", tone(0.1, 60)),
                            ("hiss", white(0.05)), ("a held chord", chord(0.2))]:
            with self.subTest(name):
                self.assertEqual(self.run_gate(quiet, sound), 0)
        click = lambda t: 0.8 * (NOISE.random() * 2 - 1) if 0.5 < t < 0.53 else 0.0
        self.assertEqual(self.run_gate(quiet, click, 2), 0, "a click")

    def test_a_running_fan_is_part_of_the_room(self):
        f = fan(0.05)
        self.assertEqual(self.run_gate(f, f, 4), 0)

    def test_a_fan_switched_on_is_let_through_for_a_moment_at_most(self):
        gate = voice.SpeechGate()
        for chunk in pcm(white(0.0005), 1):
            gate.feed(chunk)
        open_for = 0
        for chunk in pcm(fan(0.05), 8):
            gate.feed(chunk)
            open_for += gate.open
        self.assertLessEqual(open_for, 13, "under 1.3 s, then it's the room")

    def test_speech_is_sent_whole(self):
        quiet = white(0.0005)
        chunks = len(pcm(speech(0.15), 2))
        self.assertGreaterEqual(self.run_gate(quiet, speech(0.15), 2), chunks, "with the moment before it")
        self.assertGreaterEqual(self.run_gate(quiet, speech(0.03), 2), chunks - 2, "even softly")
        self.assertGreaterEqual(self.run_gate(fan(0.05), mix(fan(0.05), speech(0.6)), 2), chunks - 4, "over a fan")
        self.assertGreaterEqual(self.run_gate(chord(0.05), mix(chord(0.05), speech(0.6)), 2), chunks - 4, "over music")
        gate = voice.SpeechGate()
        for chunk in pcm(quiet, 1):
            gate.feed(chunk)
        self.assertGreaterEqual(sum(len(gate.feed(c)[0]) for c in pcm(speech(0.3), 10)), 100, "a long talk stays open")

    def test_end_of_speech_is_announced(self):
        gate = voice.SpeechGate()
        ended = []
        for chunk in pcm(white(0.0005), 1) + pcm(speech(0.15), 1) + pcm(white(0.0005), 2):
            ended.append(gate.feed(chunk)[1])
        self.assertEqual(ended.count(True), 1)
        self.assertFalse(gate.open)

    def test_turn_ends_promptly_without_cutting_short_word_gaps(self):
        gate = voice.SpeechGate()
        quiet = white(0.0005)
        for chunk in pcm(quiet, 1):
            gate.feed(chunk)
        ended = []
        for chunk in pcm(speech(0.15), 1.5):
            ended.append(gate.feed(chunk)[1])
        self.assertTrue(gate.open)
        for chunk in pcm(quiet, 0.3):
            ended.append(gate.feed(chunk)[1])
        self.assertTrue(gate.open, "a 300ms thinking pause is not a new turn")
        for chunk in pcm(speech(0.15), 0.7):
            ended.append(gate.feed(chunk)[1])
        self.assertTrue(gate.open)
        for chunk in pcm(quiet, 1):
            ended.append(gate.feed(chunk)[1])
        self.assertEqual(ended.count(True), 1)
        self.assertFalse(gate.open)

    def test_talking_over_citron_takes_a_real_voice(self):
        quiet = white(0.0005)
        self.assertEqual(self.run_gate(quiet, speech(0.006), 2, talking_over=True), 0, "its own faint echo")
        self.assertGreater(self.run_gate(quiet, speech(0.15), 2, talking_over=True), 15, "someone interrupting")


class Echo(unittest.TestCase):
    def test_hearing_itself(self):
        said = "Sure, the ferry to Sausalito leaves every forty minutes from Pier 41."
        self.assertTrue(voice.echoes("the ferry to Sausalito leaves every forty minutes", said))
        self.assertFalse(voice.echoes("when does the ferry to Sausalito leave on Sunday", said),
                         "a follow-up with some of the answer's words is the person talking")
        self.assertFalse(voice.echoes("when does the next ferry leave", said))
        self.assertFalse(voice.echoes("the ferry", said), "too short to tell")
        self.assertFalse(voice.echoes("anything at all here", ""))


class Words(unittest.TestCase):
    def test_sounds_that_arent_words_are_dropped(self):
        self.assertEqual(voice.clean(" [BLANK_AUDIO]\n"), "")
        self.assertEqual(voice.clean(" Thank you."), "", "what Whisper imagines from silence")
        self.assertEqual(voice.clean(" (music) What time is it? [noise]"), "What time is it?")

    def test_whole_sentences_are_spoken_as_they_come(self):
        self.assertEqual(voice.sentences("The capital is Lisbon. It sits on"), (["The capital is Lisbon."], "It sits on"))
        self.assertEqual(voice.sentences("Yes! Really? Of course…"), (["Yes!", "Really?", "Of course…"], ""))
        self.assertEqual(voice.sentences("No full stop yet"), ([], "No full stop yet"))


class Proc:
    """A stand-in for a child process: whisper-cpp, Piper, pactl."""
    def __init__(self, out=b"", chunks=()):
        self.returncode = None
        self.out = out
        self.written = []
        self.stdin = self
        self.stdout = self
        self.chunks = list(chunks)
        self.closed = False

    async def communicate(self):
        self.returncode = 0
        return self.out, b""

    def write(self, data): self.written.append(data)
    async def drain(self): pass
    def close(self): self.closed = True

    async def read(self, n):
        # Like Piper: no speech until it has been given words.
        while not self.closed and not (self.chunks and self.written):
            await asyncio.sleep(0.01)
        return self.chunks.pop(0) if self.chunks and self.written else b""

    def terminate(self): self.returncode = 0
    def kill(self): self.returncode = -9
    async def wait(self): return 0


class Session(unittest.IsolatedAsyncioTestCase):
    """No microphone, API key, PipeWire, whisper-cpp or Piper needed."""

    def session(self):
        s = voice.VoiceSession(CFG, "not-a-key")
        self.addCleanup(lambda: __import__("shutil").rmtree(s.private, ignore_errors=True))
        s.whisper, s.piper = "whisper-cli", "piper"
        return s

    def fake(self, s, heard=" What is the capital of Portugal?\n", spoken=(b"\1\0" * 200,)):
        procs = {}

        async def process(cmd, *args, **kw):
            if cmd == "whisper-cli":
                clip = Path(args[args.index("-f") + 1])
                procs["clip"] = (clip.exists(), clip.stat().st_mode & 0o777, clip.parent == s.private)
                procs["whisper"] = (cmd,) + args
                return Proc(out=heard.encode())
            procs["piper"] = Proc(chunks=spoken)
            procs["piper_args"] = args
            return procs["piper"]
        s.process = process
        return procs

    async def test_a_turn_hears_asks_and_speaks(self):
        s = self.session()
        procs = self.fake(s)
        events = []
        asked = []

        def chat(model, messages, key):
            asked.append((model, messages, key))
            yield from ["The capital of Portugal ", "is Lisbon. It sits on", " the Tagus."]
        with patch.object(voice, "stream_chat", chat), patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await s.turn(b"\0\0" * 16000)
        # whisper-cpp read a private, owner-only clip in Citron's language; the clip is gone.
        self.assertEqual(procs["clip"], (True, 0o600, True))
        self.assertEqual(list(s.private.iterdir()), [])
        self.assertEqual(procs["whisper"][procs["whisper"].index("-l") + 1], "en")
        # Aion got the words and the conversation's instructions, nothing else.
        model, messages, key = asked[0]
        self.assertEqual((model, key), (DEFAULTS["textModel"], "not-a-key"))
        self.assertEqual(messages[-1], {"role": "user", "content": "What is the capital of Portugal?"})
        self.assertEqual(messages[0]["role"], "system")
        # Piper got whole sentences, as they came, in the chosen voice.
        self.assertEqual(b"".join(procs["piper"].written).decode(),
                         "The capital of Portugal is Lisbon.\nIt sits on the Tagus.\n")
        self.assertIn(str(s.voice_model), procs["piper_args"])
        users = [v["text"] for e, v in events if e == "transcript" and v["role"] == "user"]
        said = [v["text"] for e, v in events if e == "transcript" and v["role"] == "assistant"]
        self.assertEqual(users, ["What is the capital of Portugal?"])
        self.assertEqual(said[-1], "The capital of Portugal is Lisbon. It sits on the Tagus.")
        self.assertEqual([c for _, c in [s.play_queue.get_nowait() for _ in range(s.play_queue.qsize())]],
                         [b"\1\0" * 200, None])
        self.assertEqual([m["role"] for m in s.history], ["user", "assistant"])

    async def test_nothing_heard_asks_nothing(self):
        s = self.session()
        self.fake(s, heard=" [BLANK_AUDIO]\n")
        with patch.object(voice, "stream_chat", side_effect=AssertionError("nothing to ask")), patch.object(voice, "emit"):
            await s.turn(b"\0\0" * 16000)
        self.assertEqual(s.play_queue.qsize(), 0)

    async def test_hearing_itself_turns_on_speaker_safe_mode(self):
        s = self.session()
        s.half_duplex = False
        s.said.append("The ferry to Sausalito leaves every forty minutes from Pier 41.")
        self.fake(s, heard=" ferry to Sausalito leaves every forty minutes\n")
        events = []
        with patch.object(voice, "stream_chat", side_effect=AssertionError("not asked")), \
                patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await s.turn(b"\0\0" * 16000)
        self.assertTrue(s.half_duplex)
        self.assertGreaterEqual(s.echo_tail, 0.8)
        self.assertFalse([v for e, v in events if e == "transcript"])
        self.assertTrue(any(e == "notice" and "heard itself" in v["text"] for e, v in events))

    async def test_typed_words_skip_speech_recognition(self):
        s = self.session()
        procs = self.fake(s)
        with patch.object(voice, "stream_chat", lambda *a: iter(["Sure."])), patch.object(voice, "emit"):
            await s.turn(b"", typed="Tell me a joke")
        self.assertNotIn("whisper", procs)
        self.assertEqual(s.history[0], {"role": "user", "content": "Tell me a joke"})

    async def test_an_aion_failure_is_said_and_listening_goes_on(self):
        s = self.session()
        self.fake(s)

        def chat(*a):
            raise voice.IntelligenceError("Aion Labs' usage limit was reached.", "http_429")
            yield
        events = []
        with patch.object(voice, "stream_chat", chat), patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await s.turn(b"\0\0" * 16000)
        self.assertIn(("notice", {"text": "Aion Labs' usage limit was reached."}), events)
        self.assertEqual(events[-1], ("status", {"mode": "listening"}))

    async def test_a_refused_key_ends_the_session(self):
        s = self.session()
        self.fake(s)

        def chat(*a):
            raise voice.IntelligenceError("Aion Labs did not accept the API key.", "http_401")
            yield
        with patch.object(voice, "stream_chat", chat), patch.object(voice, "emit"):
            with self.assertRaises(voice.IntelligenceError):
                await s.turn(b"\0\0" * 16000)

    async def test_speaker_mode_pauses_microphone_before_output(self):
        s = self.session()
        self.assertTrue(s.half_duplex)
        stopped = []

        class Mic:
            returncode = None
            def terminate(self): stopped.append("terminated")
        s.mic_proc = Mic()
        s.utterance_ended_at = voice.time.monotonic() - 0.9
        events = []
        with patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            s.queue_audio(b"\0\0" * 100)
        self.assertEqual(stopped, ["terminated"])
        self.assertFalse(s.mic_allowed.is_set())
        self.assertTrue(s.speaker_active)
        self.assertTrue(any(e == "timing" and v["ms"] >= 850 for e, v in events))

    async def test_echo_cancellation_keeps_mic_open_for_barge_in(self):
        s = self.session()
        s.half_duplex = False
        with patch.object(voice, "emit"):
            s.queue_audio(b"\0\0" * 100)
        self.assertTrue(s.mic_allowed.is_set())

    async def test_interruption_discards_the_reply(self):
        s = self.session()

        async def long_turn():
            await asyncio.sleep(10)
        s.turn_task = asyncio.create_task(long_turn())
        s.speaker_active = True
        s.mic_allowed.clear()
        await s.play_queue.put((s.audio_epoch, b"old audio"))
        with patch.object(voice, "emit"):
            await s.interrupt()
        self.assertIsNone(s.turn_task)
        self.assertEqual(s.play_queue.qsize(), 0)
        self.assertFalse(s.speaker_active)
        self.assertTrue(s.mic_allowed.is_set())

    async def test_gated_microphone_transcribes_only_speech(self):
        s = self.session()
        turns = []
        s.start_turn = lambda pcm=b"", typed="": turns.append(len(pcm))

        class Stdout:
            def __init__(self, chunks): self.chunks = list(chunks)
            async def readexactly(self, n):
                if not self.chunks:
                    s.running = False
                    raise asyncio.IncompleteReadError(b"", n)
                return self.chunks.pop(0)

        class Mic(Proc):
            def __init__(self, chunks):
                super().__init__()
                self.stdout = Stdout(chunks)

        chunks = pcm(white(0.0005), 1) + pcm(tone(0.1, 60), 2) + pcm(speech(0.15), 1) + pcm(white(0.0005), 2)

        async def process(*args, **kw):
            return Mic(chunks)
        s.process = process
        with patch.object(voice, "emit"):
            await s.listen()
        self.assertEqual(len(turns), 1, "one utterance, when the speech ended")
        self.assertGreaterEqual(turns[0], 10 * 3200, "the speech, with the moment before it")
        self.assertLessEqual(turns[0], 22 * 3200, "and not the hum or the quiet")

    async def test_stale_echo_cancellers_are_unloaded(self):
        s = self.session()
        listing = ("7\tmodule-echo-cancel\tsource_name=citron_aec_mic_999999 sink_name=citron_aec_speaker_999999 aec_method=webrtc\t\n"
                   "8\tmodule-echo-cancel\tsource_name=citron_aec_mic_%d sink_name=x aec_method=webrtc\t\n"
                   "9\tmodule-echo-cancel\tsource_name=someone_elses\t\n" % os.getpid())
        calls = []

        async def process(*args, **kw):
            calls.append(args)
            return Proc(out=listing.encode())
        s.process = process
        with patch.object(voice, "alive", side_effect=lambda pid: pid != 999999):
            await s.remove_stale_echo_cancel()
        self.assertEqual([c for c in calls if c[1] == "unload-module"], [("pactl", "unload-module", "7")])

    async def test_missing_aec_uses_safe_half_duplex(self):
        s = self.session()
        with patch.object(voice.shutil, "which", return_value=None), patch.object(voice, "emit"):
            await s.setup_echo_cancel()
        self.assertTrue(s.half_duplex)
        self.assertIsNone(s.echo_module)

    async def test_missing_tools_are_named(self):
        events = []
        with patch.object(voice, "config", return_value=CFG), \
                patch.object(voice.shutil, "which", side_effect=lambda n: "/usr/bin/" + n if n.startswith("pw-") else None), \
                patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await voice.main()
        self.assertTrue(any(e == "error" and "whisper-cpp" in v["text"] for e, v in events))
        events.clear()
        with patch.object(voice, "config", return_value=CFG), \
                patch.object(voice.shutil, "which", side_effect=lambda n: None if n.startswith("piper") else "/usr/bin/" + n), \
                patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await voice.main()
        self.assertTrue(any(e == "error" and "Piper" in v["text"] for e, v in events))

    async def test_voice_files_are_fetched_first_with_progress(self):
        s = self.session()
        fetched = []

        def fetch(url, entry, path, progress):
            fetched.append(url)
            progress(entry["size"])
        events = []
        missing = [("https://huggingface.co/a", {"size": 10}, Path("/x/a")), ("https://huggingface.co/b", {"size": 30}, Path("/x/b"))]
        with patch.object(voice, "needed", return_value=missing), patch.object(voice, "fetch", fetch), \
                patch.object(voice, "emit", side_effect=lambda e, **v: events.append((e, v))):
            await s.prepare()
        self.assertEqual(fetched, ["https://huggingface.co/a", "https://huggingface.co/b"])
        self.assertEqual(events[0], ("status", {"mode": "downloading"}))
        self.assertEqual(events[-1], ("download", {"done": 40, "total": 40}))


if __name__ == "__main__":
    unittest.main(verbosity=2)
