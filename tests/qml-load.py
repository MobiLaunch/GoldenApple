#!/usr/bin/env python3
"""The shell and every app load without QML errors.

check-qml.py parses each file on its own; this loads them for real, through
the preview harness (tools/preview), so a type that doesn't resolve (Notes'
editor used the shared TextArea without importing it, so no note could be
opened), a property that newer Qt marks final, or a component that fails to
build is caught. Each target is loaded and drawn once; any such error fails."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "tools/preview/preview.py"
APPS = ["settings", "files", "notes", "music", "photos", "weather", "calculator", "textedit", "messages",
        "maps", "calendar", "software", "airdrop", "lcode", "mail", "clock", "intelligence", "diskutility"]
ERRORS = re.compile(r"is not a type|Type \w+ unavailable|Cannot override FINAL|Cannot assign to non-existent property|"
                    r"module \"[^\"]+\" is not installed|Syntax error|failed to load component|could not create")

failures = []
with tempfile.TemporaryDirectory() as tmp:
    targets = [("shell", ["shell"])] + [(app, ["app", f"apps/{app}.qml"]) for app in APPS]
    # The default Appearance pane used to pass even when Intelligence was
    # unresolvable: Loader errors only happen on the selected pane.
    targets += [
        # Summoning the floating Citron orb must compile independently of
        # the full assistant and without contacting Gemini in preview.
        ("citron-voice-bubble", ["shell", "--do", "citron.toggle",
                                 "--require-object", "citronVoiceBubble"]),
        ("settings-intelligence-start", ["app", "apps/settings.qml", "--env",
                                         "GG_SETTINGS_PANE=intelligence", "--require-object", "citronSettingsPanel"]),
        ("settings-intelligence-navigation", ["app", "apps/settings.qml",
                                              "--do", "settings.open:intelligence",
                                              "--require-object", "citronSettingsPanel"]),
        ("intelligence-preferences", ["app", "apps/intelligence.qml",
                                      "--env", "GG_INTELLIGENCE_MODE=settings",
                                      "--require-object", "citronSettingsPanel"]),
    ]
    for name, args in targets:
        proc = subprocess.run([sys.executable, str(PREVIEW), *args, "--wait", "300", "-o", f"{tmp}/{name}.png"],
                              capture_output=True, text=True, timeout=180, cwd=ROOT)
        bad = [line for line in (proc.stdout + proc.stderr).splitlines() if ERRORS.search(line)]
        if proc.returncode != 0 or bad or not Path(f"{tmp}/{name}.png").exists():
            failures.append(f"{name}: exit {proc.returncode}\n  " + "\n  ".join(bad[:6] or (proc.stderr.strip().splitlines()[-3:])))

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
print(f"QML load: the shell and {len(APPS)} apps load and draw without QML errors")
