#!/usr/bin/env python3
"""Offline contract tests for Golden Gate Window > Move & Resize.
No compositor, monitor, user windows or external process is required.
"""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("gg_tile", ROOT / "compositor/hyprland/tile.py")
tile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tile)


class WindowTileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gg-tile-test-")
        self.addCleanup(self.temp.cleanup)
        self.saved = Path(self.temp.name) / "geometry.json"
        self.monitors = [{
            "id": 1, "x": 0, "y": 0, "width": 1440, "height": 900, "scale": 1,
            "reserved": [0, 30, 0, 76],
        }]
        self.window = {"address": "0xabc", "at": [180, 120], "size": [850, 660],
                       "monitor": 1, "floating": True, "fullscreen": 0}

    def fake_compositor(self, explicit=None):
        commands = []
        windows = [self.window] if explicit is None else explicit

        def fake(*args):
            if args == ("-j", "activewindow"):
                return json.dumps(self.window)
            if args == ("-j", "clients"):
                return json.dumps(windows)
            if args == ("-j", "monitors"):
                return json.dumps(self.monitors)
            commands.append(args)
            return "ok"

        return fake, commands

    def test_geometry_and_gap(self):
        monitor = {"x": 0, "y": 0, "width": 1920, "height": 1080,
                   "scale": 1, "reserved": [0, 30, 0, 78]}
        ar = tile.area(monitor)
        self.assertEqual(ar, (8, 38, 1904, 956))
        left = tile.rect("left", self.window, ar)
        right = tile.rect("right", self.window, ar)
        self.assertEqual(right[0] - (left[0] + left[2]), tile.GAP)
        self.assertGreaterEqual(left[1], 30)
        self.assertLessEqual(right[0] + right[2], 1920)
        self.assertLessEqual(left[1] + left[3], 1080 - 78)

    def test_restored_window_keeps_traffic_lights_on_current_screen(self):
        ar = (8, 38, 784, 482)
        for prior in ((-1500, -200, 1350, 800), (1500, 1000, 880, 620),
                      (120, 90, 640, 400)):
            x, y, w, h = tile.restored_rect(prior, ar)
            self.assertGreaterEqual(x, ar[0])
            self.assertGreaterEqual(y, ar[1])
            self.assertLessEqual(x + w, ar[0] + ar[2])
            self.assertLessEqual(y + h, ar[1] + ar[3])

    def test_restore_uses_saved_geometry_and_consumes_history(self):
        fake, commands = self.fake_compositor()
        with patch.object(tile, "hyprctl", side_effect=fake), patch.object(tile, "state_file", return_value=self.saved):
            self.assertEqual(tile.main(["right"]), 0)
            self.assertEqual(json.loads(self.saved.read_text())["0xabc"], [180, 120, 850, 660])
            self.window["at"] = [650, 45]
            self.window["size"] = [700, 720]
            self.assertEqual(tile.main(["restore"]), 0)
            self.assertNotIn("0xabc", json.loads(self.saved.read_text()))
            self.assertTrue(any("movewindowpixel exact 180 120" in args[-1] for args in commands))

    def test_stale_address_does_not_resize_unrelated_focused_app(self):
        fake, commands = self.fake_compositor()
        with patch.object(tile, "hyprctl", side_effect=fake), patch.object(tile, "state_file", return_value=self.saved):
            self.assertEqual(tile.main(["left", "0xdead"]), 1)
            self.assertFalse(commands, "should never mutate a different active window")
            self.assertFalse(self.saved.exists())
            self.assertEqual(tile.main(["left", "0xabc"]), 0)
            self.assertTrue(any("address:0xabc" in args[-1] for args in commands))

    def test_reject_batch_injection_and_extra_arguments(self):
        fake, commands = self.fake_compositor()
        with patch.object(tile, "hyprctl", side_effect=fake):
            for argv in (["left", "0xabc;dispatch", "evil"],
                         ["left", "0xabc;dispatch"],
                         ["right", "address:0xabc"],
                         ["center", "0xabc 0xdef"]):
                self.assertEqual(tile.main(argv), 2)
            self.assertFalse(commands)

    def test_scaled_display_geometry(self):
        mon = {"x": 1920, "y": 0, "width": 2560, "height": 1440, "scale": 2,
               "reserved": [0, 30, 0, 90]}
        ar = tile.area(mon)
        self.assertEqual(ar, (1928, 38, 1264, 584))
        for name in tile.LAYOUTS:
            x, y, w, h = tile.rect(name, self.window, ar)
            self.assertGreaterEqual(x, ar[0])
            self.assertGreaterEqual(y, ar[1])
            self.assertLessEqual(x+w, ar[0]+ar[2])
            self.assertLessEqual(y+h, ar[1]+ar[3])


if __name__ == "__main__":
    unittest.main()
