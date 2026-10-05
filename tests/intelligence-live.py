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
from helper import DEFAULTS, VOICES, config, model_name


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
        self.assertIn("ipc call citron toggle", opener)
        self.assertIn("gg-intelligence --voice", bindings)



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

    async def test_queue_backpressure_preserves_every_audio_chunk(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        session.half_duplex = False
        chunks = [bytes([i]) * 64 for i in range(70)]
        session.ws = self.Feed([self.packet(c) for c in chunks] + [{"turnComplete": True}])
        session.running = False
        received = []

        async def consume():
            while True:
                _, chunk = await session.play_queue.get()
                session.play_queue.task_done()
                if chunk is None:
                    return
                received.append(chunk)

        consumer = __import__("asyncio").create_task(consume())
        await __import__("asyncio").wait_for(session.receive(), timeout=3)
        await __import__("asyncio").wait_for(consumer, timeout=3)
        self.assertEqual(received, chunks)

    async def test_missing_aec_uses_safe_half_duplex(self):
        session = voice.VoiceSession("gemini-test", "Aoede", "not-a-key")
        with patch.object(voice.shutil, "which", return_value=None):
            await session.setup_echo_cancel()
        self.assertTrue(session.half_duplex)
        self.assertIsNone(session.echo_module)

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
