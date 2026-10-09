#!/usr/bin/env python3
"""Offline contract/privacy checks for Citron Live audio and desktop launch."""
from __future__ import annotations
import importlib.util
import base64
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/lib/intelligence"))
spec = importlib.util.spec_from_file_location("citron_live", ROOT / "apps/lib/intelligence/live.py")
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)
from helper import DEFAULTS, LANGUAGES, VOICES, config, model_name, system_language, voice_language
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


class LiveProtocol(unittest.TestCase):
    def test_audio_setup_and_transcripts_are_native(self):
        setup = voice.setup_message("gemini-3.8-live", "Aoede")["setup"]
        self.assertEqual(setup["model"], "models/gemini-3.8-live")
        self.assertEqual(setup["generationConfig"]["responseModalities"], ["AUDIO"])
        self.assertEqual(setup["generationConfig"]["speechConfig"]["voiceConfig"]
                         ["prebuiltVoiceConfig"]["voiceName"], "Aoede")
        self.assertEqual(setup["inputAudioTranscription"], {})
        self.assertEqual(setup["outputAudioTranscription"], {})
        self.assertNotIn("key", json.dumps(setup).lower())

    def test_audio_chunks_are_pcm_not_saved_or_logged(self):
        pcm = b"\x00\x00\x10\x00" * 800  # 100 ms of 16 kHz mono
        packet = voice.audio_packet(pcm)["realtimeInput"]["audio"]
        self.assertEqual(packet["mimeType"], "audio/pcm;rate=16000")
        self.assertEqual(base64.b64decode(packet["data"]), pcm)
        self.assertGreater(voice.pcm_level(pcm), 0)
        self.assertEqual(voice.pcm_level(b"\x00\x00" * 300), 0.0)
        self.assertEqual(voice.INPUT_RATE, 16000)
        self.assertEqual(voice.OUTPUT_RATE, 24000)
        self.assertEqual(voice.CHUNK_BYTES, 3200)

    def test_native_dependency_and_keyring_are_required(self):
        self.assertEqual(DEFAULTS["voiceModel"], "gemini-3.8-live")
        self.assertIn(DEFAULTS["voiceName"], VOICES)
        self.assertEqual(model_name("models/gemini-3.8-live"), "gemini-3.8-live")
        src = (ROOT / "apps/lib/intelligence/live.py").read_text()
        self.assertIn("api_key()", src)
        self.assertIn('shutil.which("pw-record")', src)
        self.assertIn('shutil.which("pw-play")', src)
        self.assertIn("websockets.asyncio.client", src)
        self.assertNotIn("subprocess.run(", src)
        self.assertIn("python-websockets", (ROOT / "distro/archiso/packages.x86_64").read_text())

    def test_shell_route_and_global_shortcut(self):
        qml = (ROOT / "shell/VoiceAssistant.qml").read_text()
        shell = (ROOT / "shell/shell.qml").read_text()
        opener = (ROOT / "apps/intelligence/open.sh").read_text()
        bindings = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        self.assertIn('target: "citron"', qml)
        self.assertIn("objectName: \"citronVoiceBubble\"", qml)
        self.assertIn("voiceProc.running = false", qml)
        self.assertIn("source: \"VoiceAssistant.qml\"", shell)
        self.assertIn('ipc call citron "$mode"', opener)
        self.assertIn("ipc call citron toggle", bindings)



class Language(unittest.TestCase):
    """Citron keeps to one language instead of following noise and echoes."""

    def test_setup_pins_the_language(self):
        setup = voice.setup_message("gemini-3.8-live", "Aoede", "de-DE")["setup"]
        self.assertEqual(setup["generationConfig"]["speechConfig"]["languageCode"], "de-DE")
        rules = setup["systemInstruction"]["parts"][0]["text"]
        self.assertIn("Always speak in German (de-DE)", rules)
        self.assertIn("Never change language because of background noise", rules)
        self.assertIn("say nothing", rules)
        # A model that refuses languageCode is asked again without it, still pinned by instruction.
        bare = voice.setup_message("gemini-3.8-live", "Aoede", "de-DE", language_code=False)["setup"]
        self.assertNotIn("languageCode", bare["generationConfig"]["speechConfig"])
        self.assertIn("German", bare["systemInstruction"]["parts"][0]["text"])

    def test_server_is_slow_to_start_a_reply(self):
        vad = voice.setup_message("m", "Aoede")["setup"]["realtimeInputConfig"]["automaticActivityDetection"]
        self.assertEqual(vad["startOfSpeechSensitivity"], "START_SENSITIVITY_LOW")
        self.assertGreaterEqual(vad["silenceDurationMs"], 600)

    def test_system_language(self):
        self.assertEqual(system_language({"LANG": "de_DE.UTF-8"}), "de-DE")
        self.assertEqual(system_language({"LANG": "de_AT.UTF-8"}), "de-DE")
        self.assertEqual(system_language({"LANG": "zh_CN.UTF-8"}), "cmn-CN")
        self.assertEqual(system_language({"LC_ALL": "C", "LANG": "fr_FR.UTF-8"}), "fr-FR")
        self.assertEqual(system_language({"LANG": "C.UTF-8"}), "en-US")
        self.assertEqual(system_language({}), "en-US")
        self.assertEqual(voice_language("ja-JP", {"LANG": "de_DE"}), "ja-JP")
        self.assertEqual(voice_language("auto", {"LANG": "it_IT.UTF-8"}), "it-IT")
        self.assertEqual(voice_language("klingon", {"LANG": "it_IT"}), "it-IT")
        self.assertEqual(DEFAULTS["voiceLanguage"], "auto")
        self.assertIn("en-US", LANGUAGES)


class SpeechGateTests(unittest.TestCase):
    """Only speech leaves the computer: the room's sounds can't start a reply."""

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

    def test_talking_over_citron_takes_a_real_voice(self):
        quiet = white(0.0005)
        self.assertEqual(self.run_gate(quiet, speech(0.006), 2, talking_over=True), 0, "its own faint echo")
        self.assertGreater(self.run_gate(quiet, speech(0.15), 2, talking_over=True), 15, "someone interrupting")


class Echo(unittest.TestCase):
    def test_hearing_itself(self):
        said = "Sure, the ferry to Sausalito leaves every forty minutes from Pier 41."
        self.assertTrue(voice.echoes("the ferry to Sausalito leaves every forty minutes", said))
        self.assertFalse(voice.echoes("when does the next ferry leave", said))
        self.assertFalse(voice.echoes("the ferry", said), "too short to tell")
        self.assertFalse(voice.echoes("anything at all here", ""))


class LiveAudioHandling(unittest.IsolatedAsyncioTestCase):
    """No microphone, API key or PipeWire server is needed for these tests."""

    class Feed:
        def __init__(self, chunks):
            self.chunks = chunks

        async def __aiter__(self):
            for chunk in self.chunks:
                yield json.dumps({"serverContent": chunk})

    @staticmethod
    def packet(data):
        return {"modelTurn": {"parts": [{
            "inlineData": {"mimeType": "audio/pcm", "data": base64.b64encode(data).decode()}
        }]}}

    async def test_speaker_mode_pauses_microphone_before_output(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        self.assertTrue(session.half_duplex)
        session.ws = self.Feed([self.packet(b"\\0\\0" * 100), {"turnComplete": True}])
        # Skip the normal disconnect exception; we're injecting a finite feed.
        session.running = False
        await session.receive()
        self.assertFalse(session.mic_allowed.is_set())
        self.assertTrue(session.speaker_active)
        queued = [session.play_queue.get_nowait()[1] for _ in range(2)]
        self.assertEqual(queued, [b"\\0\\0" * 100, None])

    async def test_echo_cancellation_keeps_mic_open_for_barge_in(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        session.half_duplex = False
        session.ws = self.Feed([self.packet(b"\\0\\0" * 100), {"turnComplete": True}])
        session.running = False
        await session.receive()
        self.assertTrue(session.mic_allowed.is_set())

    async def test_reading_never_waits_for_playback(self):
        # A long reply arrives far faster than it plays. The WebSocket must be
        # read throughout (keepalive pongs, "interrupted"): with nothing
        # playing, the whole reply is still read at once and every chunk kept.
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        session.half_duplex = False
        chunks = [bytes([i % 256]) * 64 for i in range(600)]
        session.ws = self.Feed([self.packet(c) for c in chunks] + [{"turnComplete": True}])
        session.running = False
        await __import__("asyncio").wait_for(session.receive(), timeout=2)
        queued = [session.play_queue.get_nowait()[1] for _ in range(session.play_queue.qsize())]
        self.assertEqual(queued, chunks + [None])

    async def test_stale_echo_cancellers_are_unloaded(self):
        # A session killed outright leaves its module loaded (and the real
        # microphone open); the next session removes it, and only it.
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        listing = ("7\tmodule-echo-cancel\tsource_name=citron_aec_mic_999999 sink_name=citron_aec_speaker_999999 aec_method=webrtc\t\n"
                   "8\tmodule-echo-cancel\tsource_name=citron_aec_mic_%d sink_name=x aec_method=webrtc\t\n"
                   "9\tmodule-echo-cancel\tsource_name=someone_elses\t\n" % __import__("os").getpid())
        calls = []

        class Proc:
            returncode = 0
            def __init__(self, args): self.args = args
            async def communicate(self): return listing.encode(), b""
            async def wait(self): return 0

        async def process(*args, **kw):
            calls.append(args)
            return Proc(args)

        session.process = process
        with patch.object(voice, "alive", side_effect=lambda pid: pid != 999999):
            await session.remove_stale_echo_cancel()
        self.assertEqual([c for c in calls if c[1] == "unload-module"], [("pactl", "unload-module", "7")])

    async def test_missing_aec_uses_safe_half_duplex(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        with patch.object(voice.shutil, "which", return_value=None):
            await session.setup_echo_cancel()
        self.assertTrue(session.half_duplex)
        self.assertIsNone(session.echo_module)

    async def test_hearing_itself_turns_on_speaker_safe_mode(self):
        # Gemini transcribes Citron's own words from the microphone: they aren't
        # shown as yours, and from then on it listens only once it's finished.
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        session.half_duplex = False
        notices = []
        with patch.object(voice, "emit", side_effect=lambda event, **v: notices.append((event, v))):
            session.ws = self.Feed([
                {"outputTranscription": {"text": "The ferry to Sausalito leaves every forty minutes from Pier 41."}},
                self.packet(b"\\0\\0" * 100),
                {"inputTranscription": {"text": "ferry to Sausalito leaves every forty minutes"}},
            ])
            session.running = False
            await session.receive()
        self.assertTrue(session.half_duplex)
        self.assertGreaterEqual(session.echo_tail, 0.8)
        self.assertFalse(session.mic_allowed.is_set(), "the microphone rests while Citron talks")
        users = [v["text"] for e, v in notices if e == "transcript" and v["role"] == "user"]
        self.assertEqual(users, [])
        self.assertTrue(any(e == "notice" and "heard itself" in v["text"] for e, v in notices))

    async def test_gated_microphone_sends_only_speech(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        sent = []

        class Ws:
            async def send(self, text): sent.append(json.loads(text))

        class Stdout:
            def __init__(self, chunks): self.chunks = list(chunks)
            async def readexactly(self, n):
                if not self.chunks:
                    session.running = False
                    raise __import__("asyncio").IncompleteReadError(b"", n)
                return self.chunks.pop(0)

        class Proc:
            returncode = None
            def __init__(self, chunks): self.stdout = Stdout(chunks)
            def terminate(self): self.returncode = 0
            async def wait(self): return 0

        chunks = pcm(white(0.0005), 1) + pcm(tone(0.1, 60), 2) + pcm(speech(0.15), 1) + pcm(white(0.0005), 2)

        async def process(*args, **kw):
            return Proc(chunks)

        session.ws = Ws()
        session.process = process
        with patch.object(voice, "emit"):
            await session.listen()
        audio = [m for m in sent if "audio" in m["realtimeInput"]]
        ends = [m for m in sent if m["realtimeInput"].get("audioStreamEnd")]
        self.assertGreaterEqual(len(audio), 10, "the speech, with the moment before it")
        self.assertLessEqual(len(audio), 22, "and not the hum or the quiet")
        self.assertEqual(len(ends), 1, "then the end of the speech")

    async def test_a_model_refusing_language_code_is_asked_again_without(self):
        import types
        setups = []

        class Fake:
            def __init__(self): self.sent = []
            async def send(self, text):
                self.sent.append(json.loads(text))
                if "setup" in self.sent[-1]:
                    setups.append(self.sent[-1]["setup"])
            async def recv(self):
                if "languageCode" in setups[-1]["generationConfig"]["speechConfig"]:
                    raise ConnectionError("1007 invalid argument")
                return json.dumps({"setupComplete": {}})
            async def close(self): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *a): pass

        async def connect(*a, **kw): return Fake()

        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key", "fr-FR")
        async def no_aec(): session.half_duplex = True
        session.setup_echo_cancel = no_aec
        async def done(): return None
        for name in ("controls", "listen", "playback", "receive"):
            setattr(session, name, done)
        # A stand-in for websockets (not needed installed): run() imports connect from it.
        client = types.ModuleType("websockets.asyncio.client")
        client.connect = connect
        package = types.ModuleType("websockets")
        package.asyncio = types.ModuleType("websockets.asyncio")
        package.asyncio.client = client
        modules = {"websockets": package, "websockets.asyncio": package.asyncio, "websockets.asyncio.client": client}
        with patch.dict(sys.modules, modules), patch.object(voice, "emit"):
            await session.run()
        self.assertEqual(len(setups), 2)
        self.assertIn("languageCode", setups[0]["generationConfig"]["speechConfig"])
        self.assertNotIn("languageCode", setups[1]["generationConfig"]["speechConfig"])
        self.assertIn("French", setups[1]["systemInstruction"]["parts"][0]["text"])

    async def test_interruption_discards_old_turn(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        session.speaker_active = True
        session.mic_allowed.clear()
        await session.play_queue.put((session.audio_epoch, b"old audio"))
        await session.reset_audio()
        self.assertEqual(session.play_queue.qsize(), 0)
        self.assertFalse(session.speaker_active)
        self.assertTrue(session.mic_allowed.is_set())


if __name__ == "__main__":
    unittest.main(verbosity=2)
