#!/usr/bin/env python3
"""Golden Gate's ambient Citron and accessible cross-toolkit visual contracts."""
from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def contrast(fg, bg):
    def srgb(rgb):
        vals = []
        for n in rgb:
            s = n / 255
            vals.append(s / 12.92 if s <= 0.04045 else ((s + .055) / 1.055) ** 2.4)
        return .2126 * vals[0] + .7152 * vals[1] + .0722 * vals[2]
    a, b = srgb(fg), srgb(bg)
    return (max(a, b) + .05) / (min(a, b) + .05)


def rgba(expr):
    m = re.fullmatch(r"rgba\((\d+), (\d+), (\d+), ([\d.]+)\)", expr)
    if not m:
        raise ValueError("Not RGBA: " + expr)
    return tuple(map(int, m.group(1, 2, 3))), float(m.group(4))


def blend(value, background):
    rgb, alpha = rgba(value)
    return tuple(round(rgb[i] * alpha + background[i] * (1 - alpha)) for i in range(3))


class SystemIntelligence(unittest.TestCase):
    def test_no_standalone_app_identity_or_ghost_shortcuts(self):
        self.assertFalse((ROOT / "apps/intelligence.qml").exists())
        self.assertFalse((ROOT / "apps/desktop/org.goldengate.Intelligence.desktop").exists())
        installer = (ROOT / "scripts/install.sh").read_text()
        self.assertIn('rm -f "$DATA/applications/org.goldengate.Intelligence.desktop"', installer)
        self.assertIn('rm -f "$R/usr/share/applications/org.goldengate.Intelligence.desktop"', installer)
        launchpad = (ROOT / "shell/Applications.qml").read_text()
        self.assertNotIn('"org.goldengate.Intelligence"', launchpad)
        self.assertIn("hasApprovedIcon(e)", launchpad)

    def test_overlay_keeps_all_working_backend_routes(self):
        qml = (ROOT / "shell/VoiceAssistant.qml").read_text()
        opener = (ROOT / "apps/intelligence/open.sh").read_text()
        menu = (ROOT / "shell/MenuBar.qml").read_text()
        prefs = (ROOT / "apps/settings/panes/IntelligencePane.qml").read_text()
        self.assertIn("Shared.PrismOrb {", qml)
        self.assertIn('objectName: "citronSystemOverlay"', qml)
        self.assertIn('objectName: "citronSystemPrompt"', qml)
        self.assertIn('import "ui/intelligence" as AI', qml)
        self.assertIn("AI.Service {", qml)
        self.assertIn('command: ["python3", citron.helper]', qml)
        for action in ("ask", "writing", "image", "edit", "voice", "photo"):
            self.assertIn(f"function {action}(", qml, action)
        self.assertIn("selectedPhoto = \"\"", qml)
        self.assertIn("history = []", qml)
        self.assertIn('action:"discard"', qml)
        self.assertNotIn('exec qs -n -p "$here/intelligence.qml"', opener)
        self.assertIn('ipc call citron "$mode"', opener)
        self.assertIn('ipc call citron photo "$photo"', opener)
        self.assertIn('["qs", "-c", "golden-gate", "ipc", "call", "citron", "ask"]', menu)
        self.assertIn('text: "Summon Citron"', prefs)
        self.assertIn("gg-settings intelligence", opener)

    def test_optical_orb_has_no_per_frame_network_or_voice_capture(self):
        orb = (ROOT / "apps/lib/PrismOrb.qml").read_text()
        self.assertIn("readonly property bool reduceMotion: Theme.reduceMotion", orb)
        self.assertIn("running: orb.running && !orb.reduceMotion", orb)
        self.assertIn("GradientStop { position: 0.51; color: \"#ffeecb\" }", orb)
        self.assertIn("GradientStop { position: 0.64; color: \"#ffa9b2\" }", orb)
        self.assertNotIn("Process {", orb)
        self.assertNotIn("request(", orb)

    def test_labels_meet_body_contrast_floor(self):
        tokens = json.loads((ROOT / "design/tokens.json").read_text())
        for scheme, surface in (("light", (255, 255, 255)), ("dark", (26, 26, 26))):
            for label in ("label", "secondaryLabel", "tertiaryLabel"):
                value = tokens["color"][scheme][label]
                with self.subTest(scheme=scheme, label=label):
                    self.assertGreaterEqual(contrast(blend(value, surface), surface), 4.5)

    def test_soft_shadow_design_tokens_are_shared_with_consumers(self):
        tokens = json.loads((ROOT / "design/tokens.json").read_text())
        glass = (ROOT / "apps/lib/Glass.qml").read_text()
        qml = (ROOT / "apps/lib/theme/Theme.qml").read_text()
        css = (ROOT / "design/dist/tokens.css").read_text()
        gtk = (ROOT / "design/dist/gtk.css").read_text()
        motion = (ROOT / "design/dist/hyprland-motion.conf").read_text()
        self.assertIn('root.role === "menu" ? 20 :', glass)
        self.assertIn("Math.max(0, (root.material?.shadowOpacity ?? 0)", glass)
        self.assertIn("range = 46", motion)
        self.assertIn("render_power = 2", motion)
        self.assertIn("offset = 0 9", motion)
        self.assertIn("--dim-opacity: 78%", gtk)
        self.assertIn("Math.max(12, n)", qml)
        for role in ("glassClear", "glassRegular", "menu", "glassControl", "glassSidebar", "glassDock"):
            material = tokens["material"][role]
            self.assertLessEqual(material["shadowOpacity"], .20, role)
            self.assertIn(material["shadow"], css)
            index = qml.index("readonly property QtObject " + role + ":")
            obj = qml[index: qml.index("\n    }", index)]
            self.assertIn("shadowY: " + str(material["shadowY"]), obj)
            self.assertIn("shadowOpacity: " + str(material["shadowOpacity"]), obj)


class CitronReliabilityRegression(unittest.TestCase):
    def test_timeout_finishes_with_error(self):
        service = (ROOT / "apps/lib/intelligence/Service.qml").read_text()
        self.assertIn('service.cancel("The request timed out. Try again.")', service)
        self.assertIn('terminalError ? {ok: false', service)
        self.assertIn('cancelled = !terminalError', service)

    def test_voice_retry_and_prompt_capture(self):
        qml = (ROOT / "shell/VoiceAssistant.qml").read_text()
        self.assertIn("if (!citron.open || citron.restartingVoice) return", qml)
        self.assertIn("id: voiceWatchdog", qml)
        self.assertIn('Voice is still connecting. Your message has been kept.', qml)
        self.assertIn("citron.pendingPrompt", qml)


if __name__ == "__main__":
    unittest.main(verbosity=2)
