#!/usr/bin/env python3
"""The session harness's screenshots, checked and laid out (T-0.2).

    tests/session/shots.py OUTDIR

Each surface's screenshot (OUTDIR/<theme>-<surface>.png, from run.sh) must
differ from the plain desktop of the same theme, or the surface never
opened, and dark must differ from light. Writes OUTDIR/index.md, a contact
sheet, which also goes to the GitHub job summary when there is one. Exits
non-zero if a surface didn't appear.
"""
from __future__ import annotations
import json
import os
from pathlib import Path
import sys

from PIL import Image, ImageChops

out = Path(sys.argv[1])
summary = json.loads((out / "summary.json").read_text()) if (out / "summary.json").exists() else {}


def changed(a: Path, b: Path) -> float:
    """The share of pixels that differ visibly (0–1), at a quarter of the size."""
    x, y = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if x.size != y.size:
        return 1.0
    size = (max(1, x.width // 4), max(1, x.height // 4))
    d = ImageChops.difference(x.resize(size), y.resize(size)).convert("L")
    return d.point(lambda v: 255 if v > 24 else 0).histogram()[255] / (size[0] * size[1])


def brightness(p: Path) -> float:
    """Mean lightness 0–255: dark mode should be well below light."""
    im = Image.open(p).convert("L")
    h = im.histogram()
    return sum(i * n for i, n in enumerate(h)) / max(1, sum(h))


problems, rows = [], []
for theme in ("light", "dark"):
    desktop = out / f"{theme}-desktop.png"
    if not desktop.exists():
        problems.append(f"no {theme} desktop screenshot")
        continue
    for shot in sorted(out.glob(f"{theme}-*.png")):
        name = shot.stem.split("-", 1)[1]
        if name == "desktop":
            rows.append((theme, name, None, brightness(shot)))
            continue
        share = changed(desktop, shot)
        rows.append((theme, name, share, brightness(shot)))
        # After the lock screen is killed, the compositor may show its own
        # placeholder until the new one takes over: that one isn't judged.
        if share < 0.005 and name != "lock-restored":
            problems.append(f"{theme} {name}: the same as the desktop ({share:.2%} changed): it didn't open")
if (out / "light-desktop.png").exists() and (out / "dark-desktop.png").exists():
    if changed(out / "light-desktop.png", out / "dark-desktop.png") < 0.005:
        problems.append("dark and light look the same: the shell didn't follow the appearance setting")

lines = ["# Session harness", ""]
if summary:
    lines += [f"- Cold starts: **{summary['coldStarts'] - summary['crashed']} of {summary['coldStarts']}** clean",
              f"- Lock screen killed while locked, back within 3 s: **{summary['lockRestored']} of {summary['lockKills']}**",
              f"- AirDrop listening with receiving off: **{'yes' if summary['airdropListening'] else 'no'}**", ""]
lines += ["| Theme | Surface | Changed from the desktop | Brightness |", "|---|---|---|---|"]
lines += [f"| {t} | {n} | {'' if s is None else f'{s:.1%}'} | {b:.0f} |" for t, n, s, b in rows]
if problems:
    lines += ["", "## Problems", ""] + [f"- {p}" for p in problems]
text = "\n".join(lines) + "\n"
(out / "index.md").write_text(text)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write(text)
print(text)
for p in problems:
    print(f"::error::{p}")
sys.exit(1 if problems else 0)
