#!/usr/bin/env python3
"""The performance baseline (T-0.3), in the session harness's real session:
the installed shell (`qs -c golden-gate`) under the compositor run.sh started.

    tests/session/perf.py OUTDIR [--starts 5] [--idle 60]

Measured:
  ready   ms from starting the shell to its "CitronOS: desktop ready" line,
          over several starts (median and p90)
  rss     the shell's resident memory once it has run a minute and more, its
          helpers' (its child processes: the D-Bus bridges) and the session
          services' (citronos-settingsd, citronos-notifyd)
  cpu     % of one core over `--idle` seconds with nothing happening and a
          window behind the Dock, first with glass windows on (the default),
          then off; helpers and services alongside
  frames  the shell's frames rendered per second over those same seconds
          (Qt's qt.scenegraph.time.renderloop log): an idle shell that keeps
          drawing shows here, whatever its CPU

Spotlight's keypress-to-frame needs a compositor's frame timing and a real
GPU: it's measured on the laptop (perf-baseline.md says how), not here.

Writes OUTDIR/perf.json and OUTDIR/perf.md (also to the job summary). With
docs/club-soda/perf-baseline.json there, a number more than 25 % worse than
its baseline is a warning (not a failure: CI machines vary).
"""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
BASELINE = REPO / "docs/club-soda/perf-baseline.json"
TICK = os.sysconf("SC_CLK_TCK")
READY = "CitronOS: desktop ready"
SERVICES = ("settingsd.py", "notifyd.py")
WINDOW = """import Quickshell
import QtQuick
ShellRoot {
    FloatingWindow {
        implicitWidth: 1200; implicitHeight: 760
        color: "#2f6fbf"
        Text { anchors.centerIn: parent; text: "A window behind the Dock"; color: "white"; font.pixelSize: 28 }
    }
}
"""


def children() -> dict[int, list[int]]:
    tree: dict[int, list[int]] = {}
    for d in Path("/proc").iterdir():
        if d.name.isdigit():
            try:
                ppid = int((d / "stat").read_text().rsplit(")", 1)[1].split()[1])
            except (OSError, IndexError, ValueError):
                continue
            tree.setdefault(ppid, []).append(int(d.name))
    return tree


def descendants(pid: int) -> list[int]:
    tree, out, todo = children(), [], [pid]
    while todo:
        for c in tree.get(todo.pop(), []):
            out.append(c)
            todo.append(c)
    return out


def services() -> list[int]:
    found = []
    for d in Path("/proc").iterdir():
        if d.name.isdigit():
            try:
                cmd = (d / "cmdline").read_bytes().decode(errors="replace")
            except OSError:
                continue
            if any(s in cmd for s in SERVICES) and "perf.py" not in cmd:
                found.append(int(d.name))
    return found


def ticks(pid: int) -> int | None:
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])           # utime + stime
    except (OSError, IndexError, ValueError):
        return None


def rss_mb(pids) -> float:
    total = 0
    for pid in pids:
        try:
            for line in Path(f"/proc/{pid}/status").read_text().splitlines():
                if line.startswith("VmRSS:"):
                    total += int(line.split()[1])
        except OSError:
            continue
    return round(total / 1024, 1)


def cpu(groups: dict[str, list[int]], seconds: float) -> dict[str, float]:
    """% of one core each group used over `seconds` (processes alive throughout)."""
    before = {name: {p: ticks(p) for p in pids} for name, pids in groups.items()}
    time.sleep(seconds)
    out = {}
    for name, pids in groups.items():
        used = 0
        for p in pids:
            a, b = before[name].get(p), ticks(p)
            if a is not None and b is not None:
                used += b - a
        out[name] = round(100 * used / TICK / seconds, 2)
    return out


def frames(log: Path) -> int:
    try:
        return log.read_text(errors="replace").count("Frame rendered")
    except OSError:
        return 0


def start(log: Path, count_frames: bool = False) -> tuple[subprocess.Popen, float]:
    """The shell, and ms until it said it was ready."""
    env = dict(os.environ)
    if count_frames:
        rules = env.get("QT_LOGGING_RULES", "")
        env["QT_LOGGING_RULES"] = (rules + ";" if rules else "") + "qt.scenegraph.time.renderloop=true"
    started = time.monotonic()
    shell = subprocess.Popen(["qs", "-c", "golden-gate"], stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env)
    while time.monotonic() - started < 60:
        if READY in log.read_text(errors="replace"):
            return shell, round((time.monotonic() - started) * 1000)
        if shell.poll() is not None:
            break
        time.sleep(0.01)
    stop(shell)
    raise RuntimeError(f"the shell never said it was ready (see {log})")


def stop(p: subprocess.Popen) -> None:
    if p.poll() is None:
        p.terminate()
        try:
            p.wait(10)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()


def pref(key: str, value: str) -> None:
    subprocess.run(["gg-pref", key, value], check=False, capture_output=True, timeout=20)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--starts", type=int, default=5)
    ap.add_argument("--idle", type=float, default=60)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    ready = []
    for i in range(args.starts):
        shell, ms = start(out / f"perf-start-{i + 1}.log")
        ready.append(ms)
        stop(shell)
        time.sleep(1)

    # One window behind the Dock, then the shell left alone.
    window_qml = Path(tempfile.mkdtemp()) / "window.qml"
    window_qml.write_text(WINDOW)
    window = subprocess.Popen(["qs", "-p", str(window_qml)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pref("glassWindows", "true")
    idle_log = out / "perf-idle.log"
    shell, _ = start(idle_log, count_frames=True)
    time.sleep(20)                                   # past its opening animations
    groups = lambda: {"shell": [shell.pid], "helpers": descendants(shell.pid), "services": services()}

    def measure():
        f0 = frames(idle_log)
        used = cpu(groups(), args.idle)
        used["fps"] = round((frames(idle_log) - f0) / args.idle, 2)
        return used
    on = measure()
    g = groups()
    rss = {"shell": rss_mb(g["shell"]), "helpers": rss_mb(g["helpers"]), "services": rss_mb(g["services"])}
    pref("glassWindows", "false")
    time.sleep(5)
    off = measure()
    pref("glassWindows", "true")
    stop(shell)
    stop(window)

    result = {
        "machine": {"cpu": cpu_model(), "cores": os.cpu_count(), "kernel": platform.release(),
                    "compositor": "headless Sway, pixman (software) rendering"},
        "readyMs": {"each": ready, "median": statistics.median(ready),
                    "p90": sorted(ready)[max(0, int(round(0.9 * len(ready))) - 1)]},
        "rssMb": rss,
        "idleCpuPercent": {"glassWindowsOn": on, "glassWindowsOff": off, "seconds": args.idle},
        "spotlightKeypressToFrame": "measured on the laptop (needs a compositor's frame timing)",
    }
    (out / "perf.json").write_text(json.dumps(result, indent=2) + "\n")

    warnings = compare(result)
    md = ["## Performance (T-0.3)", "",
          f"Headless Sway (software rendering), {result['machine']['cores']} cores, {result['machine']['cpu']}.", "",
          "| | shell | helpers | services | shell frames/s |", "|---|---|---|---|---|",
          f"| Ready (ms), median of {len(ready)} · p90 | {result['readyMs']['median']:.0f} · {result['readyMs']['p90']:.0f} | | | |",
          f"| RSS (MB) | {rss['shell']} | {rss['helpers']} | {rss['services']} | |",
          f"| Idle CPU %, glass windows on | {on['shell']} | {on['helpers']} | {on['services']} | {on['fps']} |",
          f"| Idle CPU %, glass windows off | {off['shell']} | {off['helpers']} | {off['services']} | {off['fps']} |", ""]
    md += [f"- ⚠ {w}" for w in warnings] + ([""] if warnings else [])
    (out / "perf.md").write_text("\n".join(md) + "\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write("\n".join(md) + "\n")
    print("\n".join(md))
    for w in warnings:
        print(f"::warning::{w}")
    return 0


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def compare(result: dict) -> list[str]:
    """What's more than 25 % worse than the committed baseline (and worse by
    enough to matter: 50 ms, 10 MB, 0.5 % of a core)."""
    try:
        base = json.loads(BASELINE.read_text())["ci"]
    except (OSError, ValueError, KeyError):
        return []
    checks = [("time to desktop ready (median ms)", result["readyMs"]["median"], base["readyMs"]["median"], 50),
              ("shell RSS (MB)", result["rssMb"]["shell"], base["rssMb"]["shell"], 10),
              ("shell idle CPU %, glass windows on", result["idleCpuPercent"]["glassWindowsOn"]["shell"],
               base["idleCpuPercent"]["glassWindowsOn"]["shell"], 0.5),
              ("shell idle CPU %, glass windows off", result["idleCpuPercent"]["glassWindowsOff"]["shell"],
               base["idleCpuPercent"]["glassWindowsOff"]["shell"], 0.5)]
    return [f"{name}: {now} against a baseline of {was}" for name, now, was, floor in checks
            if now > was * 1.25 and now - was > floor]


if __name__ == "__main__":
    sys.exit(main())
