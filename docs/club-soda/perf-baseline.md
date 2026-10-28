# Performance baseline (T-0.3)

Measured by `tests/session/perf.py` in the session harness (`.github/workflows/session.yml`):
the installed shell, in a clean account, under headless Sway. Each Session run prints the
same table in its job summary and compares it with `perf-baseline.json`: a number more than
25 % worse than the baseline (and by a margin that matters: 50 ms, 10 MB, 0.5 % of a core) is
a warning, not a failure, because CI machines vary.

## CI (4 cores, AMD EPYC 7763; headless Sway, software rendering)

Recorded 2026-10-28, Session run 34 (`e00ad14`).

| | Shell | Helpers (its D-Bus bridges) | Services (settingsd, notifyd) |
|---|---|---|---|
| Starting to "desktop ready" | 752 ms median, 773 ms p90 (5 starts) | | |
| Resident memory, a minute and more in | 673 MB | 87 MB | 54 MB |
| CPU, 60 s idle, a window behind the Dock, glass windows on | 15.9 % of a core | 0.45 % | 0.32 % |
| The same, glass windows off | 15.4 % | 0.58 % | 0.30 % |

## What it says

- **The idle shell costs about 16 % of a core here, glass windows on or off.** So the live
  window captures (CS2-007) aren't what costs here. Under Sway they don't run at all: the
  shell finds windows to capture through Hyprland. Either the shell keeps drawing while
  nothing happens, or each of its occasional frames is very expensive in software rendering.
  From the next run the table has the shell's **frames per second** while idle (Qt's
  `qt.scenegraph.time.renderloop` log), which tells the two apart. An idle shell should draw
  no frames.
- **673 MB resident** is a lot for a shell. Some of it is software rendering's surfaces kept
  in memory. How much is the shell's own (Launchpad's grid, Tablet Home, every screen's
  surfaces built at start, CS2-025) needs the laptop's number, with a GPU, beside this one.
- **The services are cheap.** citronos-settingsd and citronos-notifyd together: 54 MB and
  0.3 % of a core while idle. The shell's two bridges: 87 MB, under 0.6 %.
- **Start-up is steady.** 752 ms median and 773 ms p90 to the shell's "desktop ready" line.

T-3.3 (the glass lens opt-in, capture on damage) and T-3.4 (lazy Launchpad and Tablet Home)
are measured against these numbers.

## The laptop run (manual)

The plan asks for one Intel laptop beside CI. With a CitronOS session running on it:

```sh
# The same measurements, in the running session (stop the session's own shell first,
# so the script's is the only one):
systemctl --user stop citronos-shell.service
python3 ~/.local/share/golden-gate/src/tests/session/perf.py ~/perf   # or from a checkout
systemctl --user start citronos-shell.service
```

Then put `~/perf/perf.json`'s numbers under `"laptop"` in `perf-baseline.json`, with the
machine (model, CPU, GPU, screen), and add a row here.

**Spotlight, keypress to frame**, needs a real compositor's frame timing, so it's measured
only on the laptop:

```sh
QT_LOGGING_RULES="qt.scenegraph.time.renderloop=true" qs -c golden-gate 2>&1 | ts '%.s' > ~/spotlight.log &
# press ⌘Space ten times, a few seconds apart, then
pkill -x qs
```

Each keypress is followed by a burst of "Frame rendered" lines: the time from the keypress
to the first of them is the latency. `ts` comes with moreutils. A screen recording at
120 fps is a cross-check.
