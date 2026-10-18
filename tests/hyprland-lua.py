#!/usr/bin/env python3
"""CitronOS's Hyprland Lua config, run against Hyprland 0.56's API.

compositor/hyprland/hyprland.lua and every golden-gate/*.lua part CitronOS
writes (motion, glass in each of its forms, input, accessibility, windows,
machine, displays, and what gg-hyprset and migrate-fragments.py produce) are
executed in Lua 5.4 with a stand-in `hl` that knows Hyprland 0.56.2's real
config keys, dispatchers, bind options and rule fields
(tests/data/hyprland-0.56-api.json, generated from Hyprland's own stubs and
wiki). An unknown option, dispatcher, rule field, animation or curve fails
here, before Hyprland's own --verify-config (CI, .github/workflows/shell.yml).

Needs lupa (pip install lupa)."""
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

try:
    import lupa.lua54 as lupa
except ImportError:                                   # older lupa: one Lua, usually 5.4
    import lupa                                        # type: ignore

ROOT = pathlib.Path(__file__).resolve().parents[1]
API = json.loads((ROOT / "tests/data/hyprland-0.56-api.json").read_text())
HYPR = ROOT / "compositor/hyprland"

MODS = {"SUPER", "SHIFT", "CTRL", "CONTROL", "ALT", "MOD2", "MOD3", "MOD5", "META", "WIN", "LOGO"}
DSP_ARGS = {
    "window.move": {"workspace", "follow", "window", "x", "y", "relative", "direction", "monitor", "group_aware"},
    "window.resize": {"x", "y", "relative", "window", "keep_aspect_ratio"},
    "window.fullscreen": {"mode", "action", "layout_aware", "window"},
    "window.float": {"action", "window"},
    "window.close": {"window"},
    "window.kill": {"window"},
    "focus": {"direction", "monitor", "workspace", "window", "urgent_or_last", "last", "on_current_monitor"},
    "dpms": {"action", "monitor"},
}


def load(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Hyprland:
    """A Lua state with Hyprland 0.56's `hl` API, recording what's called and what's wrong."""

    def __init__(self, confdir: pathlib.Path, plugins: tuple[str, ...] = ()):
        self.errors: list[str] = []
        self.binds: list[str] = []
        self.calls: list[tuple] = []
        self.curves = {"default", "linear"}
        self.parts: list[str] = []
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.package.path = f"{confdir}/?.lua;{confdir}/?/init.lua"
        self.lua.execute("table.unpack = table.unpack or unpack")
        py = self
        printed = []
        g.print = lambda *a: printed.append(" ".join(str(x) for x in a))
        self.printed = printed

        def err(msg):
            py.errors.append(msg)

        def keys(t):
            return [k for k in t.keys()] if t is not None and lupa.lua_type(t) == "table" else []

        def check_value(key, value, typ):
            lt = lupa.lua_type(value)
            ok = True
            if typ == "boolean":
                ok = isinstance(value, bool)
            elif typ in ("integer|boolean", "number|boolean"):
                ok = isinstance(value, (bool, int, float))
            elif typ == "string":
                ok = isinstance(value, str)
            elif "HL.Gradient" in typ or "HL.Vec2Like" in typ or "HL.CssGap" in typ:
                ok = isinstance(value, (str, int, float)) or lt == "table"
            if not ok:
                err(f"hl.config: {key} wants {typ}, got {lt or type(value).__name__} {value!r}")

        def config(t):
            def walk(prefix, tbl):
                for k in keys(tbl):
                    v = tbl[k]
                    full = f"{prefix}.{k}" if prefix else str(k)
                    if full in API["config"]:
                        check_value(full, v, API["config"][full])
                    elif lupa.lua_type(v) == "table":
                        walk(full, v)
                    elif full.startswith("plugin."):
                        py.calls.append(("plugin-config", full, v))
                    else:
                        err(f"hl.config: unknown config key '{full}'")
            if lupa.lua_type(t) != "table":
                err("hl.config: argument must be a table")
            else:
                walk("", t)

        def dispatcher(name):
            def make(*args):
                allowed = DSP_ARGS.get(name)
                if args and lupa.lua_type(args[0]) == "table" and allowed is not None:
                    for k in keys(args[0]):
                        if k not in allowed:
                            err(f"hl.dsp.{name}: unknown argument '{k}'")
                if name == "window.fullscreen" and args and lupa.lua_type(args[0]) == "table":
                    m = args[0]["mode"]
                    if m is not None and m not in ("fullscreen", "maximized", "0", "1"):
                        err(f"hl.dsp.window.fullscreen: mode {m!r}")
                if name == "exec_cmd" and (not args or not isinstance(args[0], str) or not args[0]):
                    err("hl.dsp.exec_cmd: needs a command")
                if name == "workspace.toggle_special" and (not args or not isinstance(args[0], str) or args[0].startswith("special:")):
                    err("hl.dsp.workspace.toggle_special: needs the name without special:")
                t = py.lua.table()
                t["__dispatcher"] = name
                return t
            return make

        dsp = self.lua.table()
        for ns, fns in API["dispatchers"].items():
            target = dsp
            if ns:
                target = self.lua.table()
                dsp[ns] = target
            for f in fns:
                target[f] = dispatcher(f"{ns}.{f}" if ns else f)

        def bind(key, d, opts=None):
            if not isinstance(key, str) or not key.strip():
                err(f"hl.bind: bad keys {key!r}")
                return
            parts = [p.strip() for p in key.split("+")]
            for p in parts[:-1]:
                if p.upper() not in MODS:
                    err(f"hl.bind {key!r}: {p!r} is not a modifier")
            if not parts[-1]:
                err(f"hl.bind {key!r}: no key")
            norm = " + ".join(sorted(p.upper() for p in parts[:-1]) + [parts[-1].upper()])
            if norm in py.binds:
                err(f"hl.bind: {key} bound twice")
            py.binds.append(norm)
            if not (lupa.lua_type(d) == "function" or (lupa.lua_type(d) == "table" and d["__dispatcher"])):
                err(f"hl.bind {key}: not a dispatcher or function")
            for k in keys(opts):
                if k not in API["bind_options"] and k != "mouse":
                    err(f"hl.bind {key}: unknown option '{k}'")

        def rule(kind, allowed_match, allowed_effects):
            def make(spec):
                if lupa.lua_type(spec) != "table":
                    err(f"hl.{kind}: expects a table")
                    return
                for k in keys(spec):
                    if k in ("name", "enabled"):
                        continue
                    if k == "match":
                        for m in keys(spec["match"]):
                            if m not in allowed_match:
                                err(f"hl.{kind}: unknown match '{m}'")
                    elif k not in allowed_effects:
                        err(f"hl.{kind}: unknown effect '{k}'")
                py.calls.append((kind, dict(spec)))
            return make

        def simple(kind, allowed, required=()):
            def make(spec):
                if lupa.lua_type(spec) != "table":
                    err(f"hl.{kind}: expects a table")
                    return
                for k in keys(spec):
                    if k not in allowed:
                        err(f"hl.{kind}: unknown field '{k}'")
                for r in required:
                    if spec[r] is None:
                        err(f"hl.{kind}: '{r}' is required")
                py.calls.append((kind, dict(spec)))
            return make

        def gesture(spec):
            simple("gesture", set(API["gesture"]), ("fingers", "direction", "action"))(spec)
            if spec["fingers"] is not None and not (2 <= spec["fingers"] <= 9):
                err("hl.gesture: fingers 2-9")
            if spec["direction"] not in ("swipe", "horizontal", "vertical", "left", "right", "up", "down", "pinch", "pinchin", "pinchout"):
                err(f"hl.gesture: direction {spec['direction']!r}")
            a = spec["action"]
            if lupa.lua_type(a) != "function" and a not in ("close", "cursor_zoom", "float", "fullscreen", "move", "resize",
                                                            "scroll_move", "special", "workspace", "unset"):
                err(f"hl.gesture: action {a!r}")

        def curve(name, spec):
            if spec["type"] == "bezier":
                pts = spec["points"]
                if lupa.lua_type(pts) != "table" or len(list(pts.values())) != 2:
                    err(f"hl.curve {name}: bezier needs two points")
            elif spec["type"] != "spring":
                err(f"hl.curve {name}: type {spec['type']!r}")
            py.curves.add(name)

        def animation(spec):
            simple("animation", {"leaf", "enabled", "speed", "bezier", "spring", "style"}, ("leaf",))(spec)
            if spec["leaf"] not in API["animation_leaves"]:
                err(f"hl.animation: unknown leaf {spec['leaf']!r}")
            c = spec["bezier"] or spec["spring"]
            if c is not None and c not in py.curves:
                err(f"hl.animation {spec['leaf']}: curve {c!r} isn't defined (yet)")

        def env(name, value):
            if not isinstance(name, str) or not isinstance(value, str):
                err(f"hl.env: {name!r}={value!r} must be strings")

        def on(event, fn):
            if event not in ("hyprland.start", "hyprland.shutdown", "config.reloaded"):
                err(f"hl.on: unexpected event {event!r}")
            py.calls.append(("on", event))
            if event == "hyprland.start":
                py.start = fn

        def exec_cmd(cmd, rules=None):
            if not isinstance(cmd, str) or not cmd:
                err("hl.exec_cmd: needs a command")
            py.calls.append(("exec", cmd))

        hl = self.lua.table()
        hl.config = config
        hl.bind = bind
        hl.dsp = dsp
        hl.window_rule = rule("window_rule", set(API["window_rule_match"]), set(API["window_rule_effects"]))
        hl.layer_rule = rule("layer_rule", {"namespace"}, set(API["layer_rule"]) - {"match", "name", "enabled"})
        hl.workspace_rule = simple("workspace_rule", set(API["workspace_rule"]), ("workspace",))
        hl.monitor = simple("monitor", set(API["monitor"]), ("output",))
        hl.gesture = gesture
        hl.curve = curve
        hl.animation = animation
        hl.env = env
        hl.on = on
        hl.exec_cmd = exec_cmd
        hl.dispatch = lambda d: py.calls.append(("dispatch", d["__dispatcher"]))
        plugin = self.lua.table()
        plugin.load = lambda path: py.calls.append(("plugin-load", path)) if isinstance(path, str) and path else err("hl.plugin.load: path")
        for name in plugins:
            plugin[name] = self.plugin(name)
        hl.plugin = plugin
        for f in API["api"]:
            if hl[f] is None and f not in ("layout", "notification"):
                hl[f] = lambda *a: None
        g.hl = hl
        self.start = None

    def plugin(self, name):
        t = self.lua.table()
        py = self
        if name == "hyprglass":
            t.config = lambda spec: py.calls.append(("hyprglass", dict(spec)))
            t.layer = lambda ns, opts=None: py.calls.append(("hyprglass-layer", ns))
            t.preset = lambda *a: None
        if name == "hyprbars":
            def add_button(spec):
                for k in ("bg_color", "fg_color", "size", "icon", "action"):
                    if spec[k] is None:
                        py.errors.append(f"hyprbars.add_button: {k} missing")
                py.calls.append(("hyprbars-button", spec["action"]))
            t.add_button = add_button
        return t

    def run(self, path: pathlib.Path, start: bool = True):
        try:
            self.lua.execute(path.read_text(encoding="utf-8"))
            if start and self.start is not None:
                self.start()
        except lupa.LuaError as exc:
            self.errors.append(f"{path.name}: {exc}")


def sh(*cmd, env=None):
    return subprocess.run(cmd, capture_output=True, text=True, env={**os.environ, **(env or {})}, check=True).stdout


class LuaConfig(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.conf = self.tmp / "hypr"
        (self.conf / "golden-gate").mkdir(parents=True)
        text = (HYPR / "hyprland.lua").read_text()
        text = text.replace("__GG_APPS__", "/usr/share/golden-gate/apps").replace("__GG_WALLPAPER__", "/usr/share/backgrounds/golden-gate/tide.png")
        (self.conf / "hyprland.lua").write_text(text)
        shutil.copy(ROOT / "design/dist/hyprland-motion.lua", self.conf / "golden-gate/motion.lua")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def hypr(self, plugins=()):
        return Hyprland(self.conf, plugins)

    def run_main(self, plugins=()):
        h = self.hypr(plugins)
        h.run(self.conf / "hyprland.lua")
        return h

    def part(self, name, text):
        (self.conf / "golden-gate" / f"{name}.lua").write_text(text)

    def glass(self, theme="light", desktop=None, plugins=True, bars=True):
        d = self.tmp / "gl"
        d.mkdir(exist_ok=True)
        cfg = self.tmp / "xdg"
        (cfg / "golden-gate").mkdir(parents=True, exist_ok=True)
        (cfg / "golden-gate/desktop.json").write_text(json.dumps(desktop or {}))
        hg, hb = d / "hyprglass.so", d / "hyprbars.so"
        for f in (hg, hb):
            f.write_bytes(b"")
        (d / "hyprglass.so.hyprland").write_text("0.56.2\n")
        out = self.conf / "golden-gate/glass.lua"
        out.unlink(missing_ok=True)
        sh("bash", str(HYPR / "hyprglass-sync.sh"), theme, env={
            "GG_GLASS_LUA": str(out), "XDG_CONFIG_HOME": str(cfg),
            "GG_HYPRGLASS_PLUGIN": str(hg if plugins else d / "none.so"),
            "GG_HYPRBARS_PLUGIN": str(hb if bars else d / "none.so"), "PATH": os.environ["PATH"]})
        return out.read_text()

    def test_main_config_alone(self):
        h = self.run_main()
        self.assertEqual(h.errors, [])
        self.assertTrue(any(c == ("on", "hyprland.start") for c in h.calls))
        # the shell, its lock screen and the session's helpers start once Hyprland has
        execs = [c[1] for c in h.calls if c[0] == "exec"]
        self.assertTrue(any("qs -c golden-gate >>" in e for e in execs), execs)
        self.assertTrue(any("qs -c golden-gate-lock" in e for e in execs))
        self.assertTrue(any(e == "gg-hyprglass-sync" for e in execs))
        self.assertTrue(any("session started" in e for e in execs))
        # every part missing is reported, none stops the config
        self.assertEqual(len([p for p in h.printed if "not loaded" in p]), 6)

    def test_macos_keys(self):
        h = self.run_main()
        b = set(h.binds)
        for want in ("SUPER + SPACE", "SUPER + TAB", "SHIFT + SUPER + 3", "SHIFT + SUPER + 4", "CTRL + SUPER + Q",
                     "ALT + CTRL + LEFT", "CTRL + UP", "F4", "SUPER + MOUSE:272", "XF86AUDIORAISEVOLUME"):
            self.assertIn(want, b)
        # ⌘C/⌘V/⌘W stay with the apps (keyd turns them into Ctrl): Hyprland must not take them
        for taken in ("SUPER + C", "SUPER + V", "SUPER + W", "SUPER + Q"):
            self.assertNotIn(taken, b)

    def test_every_part(self):
        self.part("glass", self.glass("dark"))
        sp = load("set_prefs", ROOT / "apps/settings/set-prefs.py")
        self.part("input", sp.input_conf({"layout": "de", "variant": "nodeadkeys", "sensitivity": -0.3, "tapToClick": False}))
        self.part("accessibility", sp.accessibility_conf({"reduceMotion": True}))
        self.part("windows", sp.windows_conf({"snapEnabled": False, "windowGap": 20}))
        machine = self.conf / "golden-gate/machine.lua"
        sh("sh", str(HYPR / "machine-conf.sh"), str(machine), env={"LIBGL_ALWAYS_SOFTWARE": "1"})
        self.part("displays", 'hl.monitor({ output = "eDP-1", mode = "2560x1600@60.000", position = "0x0", scale = 1.6 }) -- display eDP-1\n')
        h = self.run_main(plugins=("hyprglass", "hyprbars"))
        self.assertEqual(h.errors, [])
        self.assertEqual([p for p in h.printed if "not loaded" in p], [])
        kinds = [c[0] for c in h.calls]
        self.assertIn("hyprglass", kinds)
        self.assertEqual(kinds.count("hyprbars-button"), 3)
        self.assertIn(("plugin-config", "plugin.hyprbars.bar_buttons_alignment", "left"), h.calls)

    def test_glass_forms(self):
        for theme in ("light", "dark"):
            for desktop in ({}, {"glass": "tinted"}, {"reduceTransparency": True}, {"glassSolidity": 0.5}):
                for plugins, bars in ((True, True), (False, False), (True, False)):
                    with self.subTest(theme=theme, desktop=desktop, plugins=plugins, bars=bars):
                        self.part("glass", self.glass(theme, desktop, plugins, bars))
                        h = self.run_main(plugins=("hyprglass", "hyprbars"))
                        self.assertEqual(h.errors, [])
                        glass = [c for c in h.calls if c[0] == "hyprglass"]
                        self.assertEqual(len(glass), 1 if plugins else 0)
                        solid = any(c[0] == "window_rule" and c[1].get("name") == "gg-reduce-transparency" for c in h.calls)
                        self.assertEqual(solid, bool(desktop.get("reduceTransparency")))

    def test_glass_without_loaded_plugins(self):
        # The first load, before Hyprland has loaded the plugins: the guards skip their parts.
        self.part("glass", self.glass("light"))
        h = self.run_main()
        self.assertEqual(h.errors, [])
        self.assertIn(("plugin-load", str(self.tmp / "gl/hyprglass.so")), h.calls)

    def test_glass_unchanged_is_not_rewritten(self):
        self.glass("light")
        out = self.conf / "golden-gate/glass.lua"
        stamp = out.stat().st_mtime_ns
        cfg = self.tmp / "xdg"
        sh("bash", str(HYPR / "hyprglass-sync.sh"), "light", env={
            "GG_GLASS_LUA": str(out), "XDG_CONFIG_HOME": str(cfg),
            "GG_HYPRGLASS_PLUGIN": str(self.tmp / "gl/hyprglass.so"), "GG_HYPRBARS_PLUGIN": str(self.tmp / "gl/hyprbars.so")})
        self.assertEqual(out.stat().st_mtime_ns, stamp)

    def test_live_changes(self):
        hs = load("hyprset", HYPR / "hyprset.py")
        code = hs.build(["input:kb_layout", "us", "input:touchpad:tap-to-click", "true", "general:snap:window_gap", "16",
                         "animations:enabled", "false", "input:sensitivity", "-0.25"])
        code += "\n" + hs.build(["--monitor", "eDP-1, 2560x1600@60.000, 0x0, 1.6", "HDMI-A-1,preferred,auto,auto", "DP-2,disable"])
        f = self.tmp / "live.lua"
        f.write_text(code)
        h = self.hypr()
        h.run(f)
        self.assertEqual(h.errors, [])
        self.assertEqual(len([c for c in h.calls if c[0] == "monitor"]), 3)

    def test_migrated_parts(self):
        mf = load("migrate", HYPR / "migrate-fragments.py")
        d = self.conf / "golden-gate"
        (d / "input.conf").write_text("input {\n    kb_layout = fr\n    touchpad {\n        tap-to-click = false\n        scroll_factor = 0.80\n    }\n}\n")
        (d / "accessibility.conf").write_text("animations {\n    enabled = false\n}\n")
        (d / "windows.conf").write_text("# Generated by Golden Gate Settings.\ngeneral {\n    resize_on_border = true\n    snap {\n        enabled = false\n    }\n}\n")
        (d / "displays.conf").write_text("monitor = eDP-1, 1920x1080@60.000, 0x0, 1.25\n")
        self.assertEqual(sorted(mf.migrate(d)), ["accessibility", "displays", "input", "windows"])
        self.assertEqual(mf.migrate(d), [])
        h = self.run_main()
        self.assertEqual(h.errors, [])
        self.assertIn('kb_layout = "fr"', (d / "input.lua").read_text())

    def test_setup_assistant_keyboard(self):
        sp = load("save_prefs", ROOT / "apps/setup/save-preferences.py")
        cfg = self.tmp / "cfg"
        sp.save({"layout": "de", "variant": "nodeadkeys", "look": "dark"}, cfg)
        text = (cfg / "hypr/golden-gate/input.lua").read_text()
        self.part("input", text)
        h = self.run_main()
        self.assertEqual(h.errors, [])
        self.assertIn('kb_layout = "de"', text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
