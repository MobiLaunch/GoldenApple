#!/usr/bin/env python3
"""Title bars with traffic lights for apps that leave theirs to the compositor.

The hyprbars patcher (distro/hyprbars/patch.py) is run on a copy of the plugin
source's shape: it must swap hyprbars' "every window" test for Golden Gate's
(xdg-decoration clients and X11 windows only, never Golden Gate's own), keep
one of each button, leave a patched file alone, and refuse when upstream moved
its anchors. Then gg-hyprglass-sync runs against a stand-in hyprctl: it loads
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
    def run_sync(self, theme: str, with_plugin: bool) -> list[str]:
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            log = d / "hyprctl.log"
            (d / "bin").mkdir()
            hyprctl = d / "bin/hyprctl"
            hyprctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$HYPRCTL_LOG"\n'
                               '[ "$1 $2" = "plugin list" ] && exit 0\nexit 0\n')
            hyprctl.chmod(0o755)
            for tool in ("logger", "systemd-detect-virt", "gsettings"):
                (d / "bin" / tool).write_text("#!/bin/sh\nexit 0\n")
                (d / "bin" / tool).chmod(0o755)
            plugin = d / "hyprbars.so"
            if with_plugin:
                plugin.write_bytes(b"\x7fELF")
            env = {**os.environ, "PATH": f"{d / 'bin'}:{os.environ['PATH']}", "HYPRCTL_LOG": str(log),
                   "GG_HYPRBARS_PLUGIN": str(plugin), "GG_HYPRGLASS_PLUGIN": str(d / "missing.so"),
                   "HOME": str(d), "XDG_CONFIG_HOME": str(d / "config")}
            subprocess.run(["bash", str(SYNC), theme], env=env, check=True, timeout=30)
            return log.read_text().splitlines() if log.exists() else []

    def test_traffic_lights_on_the_left(self):
        calls = self.run_sync("light", True)
        self.assertTrue(any(c.startswith("plugin load ") and c.endswith("hyprbars.so") for c in calls), calls)
        self.assertIn("keyword plugin:hyprbars:bar_buttons_alignment left", calls)
        buttons = [c for c in calls if c.startswith("keyword plugin:hyprbars:hyprbars-button ")]
        self.assertEqual(len(buttons), 3, calls)
        # Close, minimise, zoom: left to right, in the traffic-light colours.
        for button, colour, action in zip(buttons, ("ff5f57", "febc2e", "28c840"),
                                          ("killactive", "special:minimized", "fullscreen 1")):
            self.assertIn(f"rgb({colour}), 13,", button)
            self.assertIn(action, button)
        self.assertIn("keyword plugin:hyprbars:bar_color rgb(ececec)", calls)

    def test_dark_bar_in_dark_mode(self):
        calls = self.run_sync("dark", True)
        self.assertIn("keyword plugin:hyprbars:bar_color rgb(2c2c2e)", calls)
        self.assertIn("keyword plugin:hyprbars:inactive_button_color rgb(4a4a4d)", calls)

    def test_nothing_without_the_plugin(self):
        calls = self.run_sync("light", False)
        self.assertFalse([c for c in calls if "hyprbars" in c], calls)

    def test_reloads_run_it_again(self):
        conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        self.assertIn("\nexec = gg-hyprglass-sync\n", conf)


if __name__ == "__main__":
    unittest.main(verbosity=2)
