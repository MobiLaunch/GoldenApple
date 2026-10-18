#!/usr/bin/env python3
"""Title bars with traffic lights for apps that leave theirs to the compositor.

The hyprbars patcher (distro/hyprbars/patch.py) is run on a copy of the plugin
source's shape: it must swap hyprbars' "every window" test for CitronOS's
(xdg-decoration clients and X11 windows only, never CitronOS's own), keep
one of each button, leave a patched file alone, and refuse when upstream moved
its anchors. Then gg-hyprglass-sync writes golden-gate/glass.lua: it loads
the plugin and sets the macOS look (left traffic lights in their colours,
theme-matched bar), and does nothing for title bars when the plugin is absent."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATCHER = ROOT / "distro/hyprbars/patch.py"
SYNC = ROOT / "compositor/hyprland/hyprglass-sync.sh"

# The parts of hyprland-plugins' hyprbars/main.cpp (the commit pinned for
# Hyprland 0.56.2) that the patcher works on.
MAIN_CPP = """#define WLR_USE_UNSTABLE
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <hyprutils/string/VarList.hpp>

static void onNewWindow(PHLWINDOW window) {
    if (!window->m_X11DoesntWantBorders) {
        if (std::ranges::any_of(window->m_windowDecorations, [](const auto& d) { return d->getDisplayName() == "Hyprbar"; }))
            return;
    }
}

Hyprlang::CParseResult onNewButton(const char* K, const char* V) {
    g_pGlobalState->buttons.push_back(SHyprButton{vars[3], userfg, *fgcolor, *bgcolor, size, vars[2]});
    return result;
}
"""


class Patcher(unittest.TestCase):
    def patch(self, text: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "main.cpp"
            f.write_text(text)
            code = subprocess.run([sys.executable, str(PATCHER), str(f)], capture_output=True).returncode
            return code, f.read_text()

    def test_bars_only_for_server_side_windows(self):
        code, out = self.patch(MAIN_CPP)
        self.assertEqual(code, 0)
        self.assertIn("if (ggWantsBar(window)) {", out)
        self.assertNotIn("if (!window->m_X11DoesntWantBorders) {", out)
        self.assertIn('cls.starts_with("org.goldengate.")', out)
        self.assertIn("CXDGToplevelResource::fromResource(resource) == TOPLEVEL", out)
        self.assertIn("#include <hyprland/src/protocols/XDGDecoration.hpp>", out)
        # The includes come after Hyprland's own and before first use.
        self.assertLess(out.index("XDGDecoration.hpp"), out.index("ggWantsBar"))
        self.assertLess(out.index("static bool ggWantsBar"), out.index("static void onNewWindow"))
        # One of each button.
        self.assertLess(out.index("keep one of each"), out.index("buttons.push_back"))

    def test_patching_twice_changes_nothing(self):
        _, once = self.patch(MAIN_CPP)
        code, twice = self.patch(once)
        self.assertEqual(code, 0)
        self.assertEqual(once, twice)

    def test_refuses_when_upstream_moved(self):
        code, out = self.patch(MAIN_CPP.replace("if (!window->m_X11DoesntWantBorders) {", "if (true) {"))
        self.assertNotEqual(code, 0)
        self.assertNotIn("ggWantsBar", out)


class Sync(unittest.TestCase):
    def run_sync(self, theme: str, with_plugin: bool) -> str:
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "bin").mkdir()
            for tool in ("logger", "systemd-detect-virt", "gsettings"):
                (d / "bin" / tool).write_text("#!/bin/sh\nexit 0\n")
                (d / "bin" / tool).chmod(0o755)
            plugin = d / "hyprbars.so"
            if with_plugin:
                plugin.write_bytes(b"\x7fELF")
            out = d / "glass.lua"
            env = {**os.environ, "PATH": f"{d / 'bin'}:{os.environ['PATH']}", "GG_GLASS_LUA": str(out),
                   "GG_HYPRBARS_PLUGIN": str(plugin), "GG_HYPRGLASS_PLUGIN": str(d / "missing.so"),
                   "HOME": str(d), "XDG_CONFIG_HOME": str(d / "config")}
            env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
            subprocess.run(["bash", str(SYNC), theme], env=env, check=True, timeout=30)
            return out.read_text()

    def test_traffic_lights_on_the_left(self):
        lua = self.run_sync("light", True)
        self.assertRegex(lua, r'hl\.plugin\.load\("[^"]*hyprbars\.so"\)')
        self.assertIn("if hl.plugin.hyprbars then", lua)
        self.assertIn('bar_buttons_alignment = "left"', lua)
        buttons = [l for l in lua.splitlines() if "hl.plugin.hyprbars.add_button" in l]
        actions = [l for l in lua.splitlines() if l.strip().startswith("action = ")]
        self.assertEqual(len(buttons), 3, lua)
        # Close, minimise, zoom: left to right, in the traffic-light colours.
        for button, action, colour, does in zip(buttons, actions, ("ff5f57", "febc2e", "28c840"),
                                                ("hl.dsp.window.close()", "special:minimized", 'mode = "maximized"')):
            self.assertIn(f'bg_color = "rgb({colour})", fg_color = ', button)
            self.assertIn("size = 13", button)
            self.assertIn(does, action)
        self.assertIn('bar_color = "rgb(ececec)"', lua)

    def test_dark_bar_in_dark_mode(self):
        lua = self.run_sync("dark", True)
        self.assertIn('bar_color = "rgb(2c2c2e)"', lua)
        self.assertIn('inactive_button_color = "rgb(4a4a4d)"', lua)

    def test_nothing_without_the_plugin(self):
        lua = self.run_sync("light", False)
        self.assertNotIn("hyprbars", lua)

    def test_reloads_keep_them(self):
        # glass.lua is part of the config: every reload runs it again.
        conf = (ROOT / "compositor/hyprland/hyprland.lua").read_text()
        self.assertIn('part("glass")', conf)
        self.assertIn('hl.exec_cmd("gg-hyprglass-sync")', conf)


if __name__ == "__main__":
    unittest.main(verbosity=2)
