#!/usr/bin/env python3
"""No passwordless path to root through Software Update (CS2-001).

An administrator may install updates without typing a password: a polkit
rule grants org.goldengate.update for local, active wheel members. So nothing
reachable through that action may decide *what* gets installed: the update
source has its own action, which always asks and which no rule grants.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OVERLAY = ROOT / "distro/archiso/overlay"
INSTALLED = "/usr/share/golden-gate/"


def actions():
    out = {}
    for policy in (OVERLAY / "usr/share/polkit-1/actions").glob("*.policy"):
        for action in ET.parse(policy).getroot().iter("action"):
            d = action.find("defaults")
            exec_path = next((a.text for a in action.iter("annotate")
                              if a.get("key") == "org.freedesktop.policykit.exec.path"), None)
            out[action.get("id")] = {
                "defaults": {k: d.find(k).text for k in ("allow_any", "allow_inactive", "allow_active")},
                "helper": ROOT / exec_path[len(INSTALLED):] if exec_path and exec_path.startswith(INSTALLED) else None,
            }
    return out


def passwordless():
    """Action IDs some rule answers with polkit.Result.YES."""
    ids = set()
    for rule in (OVERLAY / "etc/polkit-1/rules.d").glob("*.rules"):
        text = rule.read_text()
        if "polkit.Result.YES" in text:
            ids |= set(re.findall(r'action\.id\s*===?\s*"([^"]+)"', text))
    return ids


class UpdatePrivileges(unittest.TestCase):
    def test_passwordless_helpers_cant_change_the_source(self):
        acts = actions()
        granted = passwordless()
        self.assertIn("org.goldengate.update", granted, "one-click updates stay one click")
        for action_id in granted:
            helper = acts[action_id]["helper"]
            self.assertIsNotNone(helper, action_id + " must name its helper")
            text = helper.read_text()
            for marker in ("set_source(", '"set-source"'):
                self.assertFalse(marker in text, f"{helper.name} ({action_id}, passwordless) can change the update source")
            proc = subprocess.run([sys.executable, str(helper), "set-source"], input="{}\n",
                                  capture_output=True, text=True, timeout=30)
            self.assertEqual(proc.returncode, 2, "set-source is not a command of the passwordless helper")

    def test_changing_the_source_always_asks(self):
        acts = actions()
        source = acts.get("org.goldengate.update.source")
        self.assertIsNotNone(source, "the update source has its own polkit action")
        self.assertEqual(set(source["defaults"].values()), {"auth_admin"}, "no auth_admin_keep, never yes")
        self.assertNotIn("org.goldengate.update.source", passwordless())
        self.assertEqual(source["helper"], ROOT / "apps/settings/update-source-helper.py")
        self.assertTrue(os.access(source["helper"], os.X_OK), "pkexec runs the helper itself")
        pane = (ROOT / "apps/settings/panes/UpdatePane.qml").read_text()
        save = pane[pane.index("id: sourceSave"):]
        save = save[:save.index("stdinEnabled")]
        self.assertIn("pane.sourceHelper", save, "Settings saves the source through the asking helper")
        self.assertIn("/run/archiso", save, "only the live USB skips the prompt")

    def test_every_helper_is_executable(self):
        for action_id, act in actions().items():
            if act["helper"]:
                self.assertTrue(os.access(act["helper"], os.X_OK), f"{act['helper']} ({action_id})")

    @unittest.skipIf(os.geteuid() == 0, "checks the refusal an unprivileged user gets")
    def test_source_helper_refuses_without_root(self):
        proc = subprocess.run([sys.executable, str(ROOT / "apps/settings/update-source-helper.py"), "set-source"],
                              input=json.dumps({"repo": "a/b", "branch": "main"}) + "\n",
                              capture_output=True, text=True, timeout=30)
        self.assertEqual(proc.returncode, 77)


if __name__ == "__main__":
    unittest.main()
