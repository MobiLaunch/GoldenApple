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

- **The idle shell cost about 16 % of a core here, glass windows on or off: the Clock
  widget.** So the live window captures (CS2-007) weren't what cost: under Sway they don't
  run at all, since the shell finds windows to capture through Hyprland. Run 36 (`9316376`)
  broke the shell's idle CPU down by thread: the render thread at 3.7 % and each of
  llvmpipe's four rasterizing threads at 3.5-3.7 %, the main thread under that. The shell
  kept drawing. A new account's desktop has the Clock widget, and its hands sprang to each
  new place (a 140 ms spring): the second hand every second, and the minute hand too, since
  it creeps each second. That drew the whole widget layer, glass and all, about nine times
  a second. The preview harness, its clocks let run (`--idle-frames`), counted 54 frames in
  6 s at rest. Now the minute and second hands step, as a quartz watch's do, and only the
  hour hand springs, once a minute: 7 frames in 6 s, the second hand's step.
  `tests/idle-frames.py` keeps it there. The clock face also keeps its own seconds, so the
  shared feed every other widget reads goes by the minute. The next Session run gives the
  new idle number.
- **673 MB resident** is a lot for a shell. Some of it is software rendering's surfaces kept
  in memory. How much is the shell's own (Launchpad's grid, Tablet Home, every screen's
  surfaces built at start, CS2-025) needs the laptop's number, with a GPU, beside this one.
- **The services are cheap.** citronos-settingsd and citronos-notifyd together: 54 MB and
  0.3 % of a core while idle. The shell's two bridges: 87 MB, under 0.6 %.
- **Start-up is steady.** 752 ms median and 773 ms p90 to the shell's "desktop ready" line.

T-3.3 (the glass lens opt-in, capture on damage) and T-3.4 (lazy Launchpad and Tablet Home)
are measured against these numbers.

## The lock screen coming back

The harness kills the lock screen five times while locked. In run 35, each restart broke
down as follows:

- the new process was up after about 1.2–1.3 s, of which 1 s was the unit's restart delay;
- its configuration had loaded by about 1.5 s;
- it held the lock again by 2.9–3.2 s.

The delay is now 200 ms (`citronos-lock.service`), with systemd backing off to every 5 s
for a lock screen that keeps failing, so it can't spin. The compositor keeps the session
locked throughout. In run 36 (`9316376`) the process was up after 0.41-0.47 s, its
configuration loaded by 0.66-0.75 s, and the lock held again by 1.9-2.6 s: 5 of 5 within
the 3 s goal, with about 0.4 s to spare.

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
