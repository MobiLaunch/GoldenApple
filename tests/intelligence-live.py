#!/usr/bin/env python3
"""Offline contract/privacy checks for Citron Live audio and desktop launch."""
from __future__ import annotations
import importlib.util
import base64
import json
from pathlib import Path
import sys
import unittest

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
