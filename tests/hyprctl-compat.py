#!/usr/bin/env python3
"""What CitronOS sends Hyprland while the desktop is up works on Hyprland
0.56 (hyprland.conf) and 0.57 (Lua only), T-2.3:

- gg-hyprctl (compositor/hyprland/hyprctl.py) asks Hyprland once which it
  is, passes dispatch, keyword and --batch to hyprctl as they are with
  hyprland.conf, and in Lua mode sends them to CitronOS's reader with
  hyprctl eval (citronos.dispatch / citronos.keyword);
- what's dispatched can't get out of its Lua string, from gg-hyprctl or
  from the shell's Hypr.dispatch (apps/lib/hypr/Hypr.qml);
- every dispatcher CitronOS sends has a Lua form in the reader, and nothing
  sends hyprctl dispatch or keyword, or Hyprland.dispatch, another way.
packaging/hyprland-lua-check.sh checks each Lua form on Hyprland 0.57."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("gg_hyprctl", ROOT / "compositor/hyprland/hyprctl.py")
hc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hc)
READER = (ROOT / "compositor/hyprland/hyprlang.lua").read_text()


class FakeHyprland:
    """A hyprctl that records what it's asked, and answers eval as a
    Hyprland in Lua mode or not (or no Hyprland at all)."""

    def __init__(self, mode: str):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.log = base / "calls.jsonl"
        bin_dir = base / "bin"
        bin_dir.mkdir()
        answer = {"lua": "ok", "hyprlang": "eval is only supported with the lua config manager"}.get(mode, "")
        fake = bin_dir / "hyprctl"
        fake.write_text(f"""#!{sys.executable}
import json, sys
with open({str(self.log)!r}, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if {mode!r} == "none":
    print("HYPRLAND_INSTANCE_SIGNATURE not set (is hyprland running?)", file=sys.stderr)
    sys.exit(1)
if sys.argv[1:2] == ["eval"]:
    print({answer!r} if sys.argv[2] == "return 1" else "ok")
else:
    print("ok")
""")
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        self.runtime = base / "run"
        self.runtime.mkdir()
        self.env = {**os.environ, "PATH": f"{bin_dir}:/usr/bin:/bin", "XDG_RUNTIME_DIR": str(self.runtime),
                    "HYPRLAND_INSTANCE_SIGNATURE": "abc_123"}

    def run(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(ROOT / "compositor/hyprland/hyprctl.py"), *args],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def calls(self) -> list[list[str]]:
        return [json.loads(l) for l in self.log.read_text().splitlines()] if self.log.exists() else []

    def close(self):
        self.tmp.cleanup()


class GgHyprctl(unittest.TestCase):
    def fake(self, mode):
        f = FakeHyprland(mode)
        self.addCleanup(f.close)
        return f

    def test_with_hyprland_conf_it_is_hyprctl(self):
        f = self.fake("hyprlang")
        self.assertEqual(f.run("mode").stdout.strip(), "hyprlang")
        f.run("dispatch", "workspace", "2")
        f.run("keyword", "input:kb_layout", "de")
        f.run("--batch", "keyword monitor DP-1, preferred, auto, 1 ; dispatch fullscreen 1")
        sent = [c for c in f.calls() if c[:1] != ["eval"]]
        self.assertEqual(sent, [["dispatch", "workspace", "2"], ["keyword", "input:kb_layout", "de"],
                                ["--batch", "keyword monitor DP-1, preferred, auto, 1 ; dispatch fullscreen 1"]])

    def test_in_lua_mode_the_reader_does_it(self):
        f = self.fake("lua")
        self.assertEqual(f.run("mode").stdout.strip(), "lua")
        self.assertEqual(f.run("dispatch", "movetoworkspacesilent", "special:hidden,address:0x5f").returncode, 0)
        f.run("keyword", "input:kb_layout", "de")
        evals = [c[1] for c in f.calls() if c[:1] == ["eval"] and c[1] != "return 1"]
        self.assertEqual(evals, ['citronos.dispatch([[movetoworkspacesilent special:hidden,address:0x5f]])',
                                 'citronos.keyword([[input:kb_layout]], [[de]])'])

    def test_a_batch_is_one_eval(self):
        f = self.fake("lua")
        f.run("--batch", "keyword monitor DP-1, preferred, auto, 1 ; dispatch fullscreen 1 ; reload")
        calls = [c for c in f.calls() if c != ["eval", "return 1"]]
        self.assertIn(["reload"], calls, "what isn't dispatch or keyword goes to hyprctl as it is")
        self.assertIn(["eval", "citronos.keyword([[monitor]], [[DP-1, preferred, auto, 1]]); "
                               "citronos.dispatch([[fullscreen 1]])"], calls)

    def test_the_mode_is_asked_once_a_session(self):
        f = self.fake("lua")
        for _ in range(3):
            f.run("dispatch", "workspace", "1")
        self.assertEqual(sum(1 for c in f.calls() if c == ["eval", "return 1"]), 1)
        self.assertEqual((f.runtime / "gg-hyprctl-mode-abc_123").read_text().strip(), "lua")

    def test_no_hyprland_is_not_remembered(self):
        f = self.fake("none")
        self.assertEqual(f.run("mode").stdout.strip(), "hyprlang")
        self.assertFalse((f.runtime / "gg-hyprctl-mode-abc_123").exists())

    def test_other_commands_are_hyprctl(self):
        f = self.fake("lua")
        f.run("clients", "-j")
        self.assertEqual(f.calls(), [["clients", "-j"]])

    def test_a_lua_string_holds_anything(self):
        for s in ("plain", "a]]b", "]]", "x]", "x]=", "]=]]==]", "[[nested]]", 'quote " and \\ and \n'):
            lua = hc.lua_string(s)
            eq = re.match(r"^\[(=*)\[", lua).group(1)
            self.assertTrue(lua.endswith("]" + eq + "]"))
            body = lua[len(eq) + 2:-(len(eq) + 2)]
            self.assertEqual(body, s)
            self.assertNotIn("]" + eq + "]", s, f"{s!r} would close its string early")


class HyprQml(unittest.TestCase):
    """The shell's Hypr.dispatch, run as QML runs it."""

    def test_its_lua_string_matches_gg_hyprctls(self):
        from PySide6.QtCore import QCoreApplication
        from PySide6.QtQml import QJSEngine
        self.app = QCoreApplication.instance() or QCoreApplication([])
        qml = (ROOT / "apps/lib/hypr/Hypr.qml").read_text()
        fn = re.search(r"function luaString\(s\) \{.*?\n    \}", qml, re.S).group(0)
        engine = QJSEngine()
        engine.evaluate(fn)
        for s in ("workspace 2", "exec a]]b", "x]", "]=]]==]", "focuswindow class:^(a)$"):
            self.assertEqual(engine.evaluate(f"luaString({json.dumps(s)})").toString(), hc.lua_string(s), s)

    def test_dispatch_says_lua_only_in_lua_mode(self):
        qml = (ROOT / "apps/lib/hypr/Hypr.qml").read_text()
        self.assertIn('lua ? "citronos.dsp(" + luaString(text) + ")" : text', qml)
        self.assertIn('command: ["gg-hyprctl", "mode"]', qml)


def sources():
    for d in ("shell", "apps", "compositor", "services"):
        for p in (ROOT / d).rglob("*"):
            if p.suffix in (".qml", ".js", ".py", ".sh") and "__pycache__" not in p.parts and p.is_file() \
                    and not p.is_symlink() and "ui" not in p.relative_to(ROOT).parts[:2]:
                yield p


class EveryDispatch(unittest.TestCase):
    def test_nothing_goes_around(self):
        allowed = {ROOT / "apps/lib/hypr/Hypr.qml", ROOT / "compositor/hyprland/hyprctl.py"}
        for p in sources():
            if p in allowed:
                continue
            text = p.read_text(errors="replace")
            for pattern in (r"Hyprland\.dispatch\(", r"(?<![\w-])hyprctl\"?,?\s*\"?(dispatch|keyword|--batch)\b"):
                m = re.search(pattern, text)
                self.assertIsNone(m, f"{p.relative_to(ROOT)} sends {m and m.group(0)!r} around gg-hyprctl/Hypr.dispatch")

    def test_every_dispatcher_has_a_lua_form(self):
        table = READER[READER.index("local DISPATCHERS = {"):READER.index("\n}\n", READER.index("local DISPATCHERS = {"))]
        known = set(re.findall(r"^  (\w+) = function", table, re.M))
        used = set()
        for p in sources():
            text = p.read_text(errors="replace")
            used |= set(re.findall(r"Hypr\.dispatch\(\s*[\"'`](\w+)", text))
            used |= set(re.findall(r"gg-hyprctl\"?,?\s*\"?dispatch\"?,?\s*\"?(\w+)", text))
            used |= set(re.findall(r"\"dispatch (\w+)", text))
        conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        used |= set(re.findall(r"^\s*bind\w*\s*=\s*[^,]*,[^,]*,\s*(\w+)", conf, re.M))
        used |= set(re.findall(r"gesture\s*=.*?dispatcher,\s*(\w+)", conf))
        self.assertGreater(len(used), 10, used)
        self.assertEqual(sorted(used - known), [], "dispatchers without a Lua form in hyprlang.lua")


if __name__ == "__main__":
    unittest.main(verbosity=2)
