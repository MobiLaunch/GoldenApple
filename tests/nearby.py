#!/usr/bin/env python3
"""Nearby pairing cards: the helper tells headphones and iPhones apart from
other devices in `bluetoothctl info` output, names AirPods from Apple's
proximity-pairing advertisement, and drops devices that are too far away."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "shell/nearby/nearby.py"
sys.path.insert(0, str(HELPER.parent))
import nearby  # noqa: E402

AIRPODS_PRO = """Device 4C:11:AE:20:9B:01 (random)
\tName: AirPods Pro
\tAlias: AirPods Pro
\tClass: 0x00240418
\tIcon: audio-headset
\tPaired: no
\tConnected: no
\tRSSI: 0xffffffcf (-49)
\tManufacturerData.Key: 0x004c (76)
\tManufacturerData.Value:
  07 19 01 0e 20 2b 99 8f 01 00 05 7d 7c 1e 2d 3e  ....+.....}|.->
  11 22 33 44 55 66 77 88 99                       ."3DUfw..
"""
CASE_ONLY = """Device 6A:11:AE:20:9B:02 (random)
\tAlias: 6A-11-AE-20-9B-02
\tPaired: no
\tRSSI: -52
\tManufacturerData.Key: 0x004c (76)
\tManufacturerData.Value:
  07 19 01 14 20 2b 99 8f 01 00 05 7d 7c 1e 2d 3e  ....+.....}|.->
"""
SONY = """Device 00:1B:66:AA:BB:CC (public)
\tName: WH-1000XM5
\tIcon: audio-headphones
\tPaired: yes
\tConnected: no
\tRSSI: -58
"""
IPHONE = """Device 5D:44:12:9A:00:10 (random)
\tAlias: 5D-44-12-9A-00-10
\tPaired: no
\tRSSI: -45
\tManufacturerData.Key: 0x004c (76)
\tManufacturerData.Value:
  10 06 1d 1d 4c 21 a8 78                          ....L!.x
"""
KEYBOARD = """Device 11:22:33:44:55:66 (public)
\tName: MX Keys
\tIcon: input-keyboard
\tRSSI: -40
"""
FAR = SONY.replace("RSSI: -58", "RSSI: -84").replace("00:1B:66:AA:BB:CC", "00:1B:66:AA:BB:DD")


class Classify(unittest.TestCase):
    def test_airpods_are_named_from_the_advertisement(self):
        info = nearby.parse_info(AIRPODS_PRO)
        self.assertEqual(info["rssi"], -49)
        self.assertEqual(nearby.classify(info)["kind"], "headphones")
        self.assertEqual(nearby.classify(info)["model"], "AirPods Pro")
        self.assertEqual(nearby.classify(nearby.parse_info(CASE_ONLY))["model"], "AirPods Pro")

    def test_headphones_by_class_iphone_by_nearby_info(self):
        self.assertEqual(nearby.classify(nearby.parse_info(SONY))["kind"], "headphones")
        phone = nearby.classify(nearby.parse_info(IPHONE))
        self.assertEqual((phone["kind"], phone["model"]), ("phone", "iPhone"))
        self.assertIsNone(nearby.classify(nearby.parse_info(KEYBOARD)))


class Helper(unittest.TestCase):
    def test_reports_close_devices_worth_a_card(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"4C:11:AE:20:9B:01": AIRPODS_PRO, "00:1B:66:AA:BB:CC": SONY,
                       "5D:44:12:9A:00:10": IPHONE, "11:22:33:44:55:66": KEYBOARD,
                       "00:1B:66:AA:BB:DD": FAR}, f)
        env = dict(os.environ, GG_NEARBY_FAKE=f.name)
        out = subprocess.run([sys.executable, str(HELPER)], env=env, capture_output=True, text=True, timeout=20)
        os.unlink(f.name)
        rows = [json.loads(l) for l in out.stdout.splitlines()]
        self.assertEqual([r["mac"] for r in rows], ["4C:11:AE:20:9B:01", "00:1B:66:AA:BB:CC", "5D:44:12:9A:00:10"])
        self.assertEqual(rows[0]["name"], "AirPods Pro")
        self.assertTrue(rows[1]["paired"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
