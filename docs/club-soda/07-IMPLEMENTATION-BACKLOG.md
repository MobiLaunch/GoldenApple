# CitronOS 2 "Club Soda": Implementation Backlog

These tasks are meant for another developer or a coding agent to pick up as-is. IDs are
`T-<milestone>.<n>`. Findings (`CS2-…`) are in [02](02-UI-UX-AUDIT.md) and
[03](03-BACKEND-AUDIT.md). M0 and M1 are written in full detail. Later milestones use the
same fields, more briefly, and should be expanded when their milestone starts.

**Rules for every task:**
- Use argv, never shell strings built from data.
- Report each change's success or failure in the UI.
- Never block the UI thread.
- Keep Reduce Motion and Reduce Transparency working.
- Add or extend a behaviour test, not a `grep` guard.
- Keep the internal identifiers (`org.goldengate.*`, `gg-*`, `~/.config/golden-gate`).
- Run `python tests/check-qml.py`, `python tests/qml-regressions.py` and the affected tests
  before pushing.

---

## M0: Baseline

### T-0.1: Record the test baseline · **done**
- **Scope:** run every test once and record the results.
- **Result:** 125 pass, 10 environmental (Darling source not supplied, run as root,
  generated symbols not built), 0 real failures. See
  [03 → Test baseline](03-BACKEND-AUDIT.md#test-baseline).

### T-0.2: Real-session harness · **done**
- **As built:** `tests/session/run.sh` makes a clean account in an Arch container, installs
  CitronOS into it with `scripts/install.sh`, checks `Hyprland --verify-config` accepts the
  hyprland.conf it wrote, and runs the real shell (`qs -c golden-gate`) under headless Sway
  (pixman), with hyprland.conf's `env =` lines and a session bus started after
  `XDG_RUNTIME_DIR` (dconf tells readers about changes there). Hyprland itself needs a GPU
  render node; the ISO's boot test runs it in QEMU. In order:
  - `--self-test`: a shell killed with SIGSEGV and a configuration that doesn't load must
    both be caught (the job runs this first);
  - 20 cold starts. A start fails if the shell died, left a Quickshell crash report,
    printed "pure virtual" or a QML error in CitronOS's files;
  - the desktop, Control Center, Spotlight, Launchpad, Notification Center and Mission
    Control, opened over IPC and screenshotted in light and in dark;
  - the lock screen as its own process (a loop standing in for `citronos-lock.service`),
    locked with gg-lock, then killed with SIGSEGV 5 times. Each must hold the lock again
    within 3 s, asked over IPC (`lock.isLocked`, the compositor's confirmation);
  - `gg-airdrop --serve` running with a new account's default (receiving off): nothing may
    listen on 53317 (`ss`).

  `tests/session/shots.py` fails a surface whose screenshot matches the desktop (it didn't
  open) and dark that looks like light, and writes a contact sheet to the job summary.
  `.github/workflows/session.yml` runs on changes to the shell, compositor, units and
  installer, and uploads the screenshots and logs. Its first runs found two bugs in the
  harness (light and dark identical: the bus started before `XDG_RUNTIME_DIR`; missing
  icons: the session's env) and one in CitronOS: a lock screen refused after a crash
  (T-1.5).
- **Scope:** a CI job that boots headless Hyprland (or Sway with Quickshell, as before) and
  runs the real shell.
- **Files:** new `tests/session/run.sh` and `tests/session/shots.py`; new
  `.github/workflows/session.yml`; reuse the reverted `tests/shell-shots.sh` from history
  (`git show 9d9f1fb:tests/shell-shots.sh`).
- **Changes:**
  - Start the compositor with `WLR_BACKENDS=headless`, then `qs -c golden-gate`.
  - Detect crashes three ways: the process is alive, no report exists under
    `~/.cache/quickshell/crashes`, and no "pure virtual" text appears in the log.
  - Repeat cold starts N times (default 10).
  - Screenshot each surface through `qs ipc` (Control Center, Spotlight, Launchpad,
    Notification Center, Mission Control, lock), in light and dark.
  - Upload the screenshots as artifacts.
- **Depends on:** nothing.
- **Expected:** a red job if any cold start crashes. Screenshots of every surface.
- **Tests:** the job itself. Seed it with a deliberately crashing QML file once, to prove
  detection works.
- **Done when:** the job is green on the branch and a crash makes it red.

### T-0.3: Performance baseline
- **Scope:** measure, don't guess (CS2-007, CS2-021, CS2-025).
- **Files:** `tests/session/perf.py`; `docs/club-soda/perf-baseline.md` (results).
- **Changes:** record time to the "desktop ready" log line, shell RSS after 60 s, shell
  CPU % over 60 s idle with one window behind the Dock (glass windows on and off), and
  Spotlight keypress-to-frame where measurable. Run in CI (VM) and on one Intel laptop
  (manual).
- **Depends on:** T-0.2.
- **Done when:** the baseline numbers are committed and the job tracks them over time.

---

## M1: Trust and stability

### T-1.1: Remove shell-string injection from Control Center (CS2-002) · **P0** · S · **done**
- **As built:** every Control Center, menu bar and Move & Resize command is an argv
  `execDetached`; a network's name is only `$1` to a fixed script.
  `tests/control-center-join.py` runs the requested command against stub `nmcli` with
  SSIDs containing `$()`, backticks, quotes and newlines (and fails on the old code).
- **Files:** `shell/ControlCenter.qml` (lines 56, 104-128, 252, 265, 1056, 1071);
  `apps/lib/ZoomMenu.qml:26`; new `apps/settings/wifi-join.sh` or a function in a new
  `citronos` Python module.
- **Changes:**
  1. Delete `function run(cmd)`.
  2. Make `joinNetwork(ssid)` call
     `Quickshell.execDetached(["gg-wifi-join", ssid])`. `gg-wifi-join` runs
     `nmcli -w 15 connection up id "$1" || nmcli -w 15 device wifi connect "$1" || exec gg-settings wifi`,
     with `"$1"` used only as argv.
  3. Convert every other `cc.run("…")` to an argv `execDetached`.
  4. Make ZoomMenu call `execDetached(["gg-tile", layout])`.
- **Expected:** behaviour is unchanged for normal SSIDs. SSIDs containing `$()`, backticks,
  quotes or newlines are passed literally.
- **Tests:** a new `tests/control-center-join.py`. Load ControlCenter through the preview
  harness with a stub `gg-wifi-join` that records its argv, call
  `joinNetwork('$(touch /tmp/x)')`, and assert the recorded argv equals the literal and
  `/tmp/x` doesn't exist. Also add `tests/security-lint.py` (T-1.10).
- **Done when:** both tests pass and `git grep 'dispatch("exec " +'` is empty.

### T-1.2: Split the privileged update actions (CS2-001) · **P0** · S · **done**
- **As built:** `set-source` moved to `apps/settings/update-source-helper.py` under the
  new action `org.goldengate.update.source` (`auth_admin`, never kept, in no rule).
  The passwordless helper can't change the source. `tests/update-privileges.py` checks
  every rule-granted action's helper.
- **Files:** `apps/settings/update-helper.py`, new `apps/settings/update-source-helper.py`;
  `distro/archiso/overlay/usr/share/polkit-1/actions/org.goldengate.update.policy` (add
  `org.goldengate.update.source`); `…/rules.d/49-golden-gate-update.rules`;
  `apps/settings/panes/UpdatePane.qml:146,171`; `golden_update.py` (`LIVE_ONLY` unchanged);
  `scripts/install.sh` (install the new helper).
- **Changes:**
  1. Move `set-source` into `update-source-helper.py` under a new action
     `org.goldengate.update.source` with `auth_admin` in all three defaults and no rule.
  2. Remove `set-source` from `update-helper.py`.
  3. Narrow the passwordless rule's comment and behaviour: it still covers `apply`, but
     `apply` must refuse (exit 77) unless the configured source equals the release
     default *or* was set through the source helper in this boot. Record a root-owned
     marker with the source's hash.
  4. In the UI, the source sheet calls `pkexec update-source-helper.py`.
- **Expected:** changing the source always asks for an admin password, and one-click
  updates keep working.
- **Tests:** a new `tests/update-privileges.py`:
  - parse the policy and the rules;
  - assert no passwordless action's `exec.path` can change the source;
  - run the helper as a non-root user and get 77;
  - with `GG_UPDATE_ROOT` staging, check that `apply` refuses an unrecognised source.
- **Done when:** the tests pass and the manual VM check prompts for a password.

### T-1.3: Signed update bundles and a release channel (CS2-003) · **P0** · M · **done**
- **As built:** Ed25519 via `openssl` (no new dependency) rather than minisign. Channels
  stable (default), beta and dev; an `update.json` from before channels counts as
  stable. A release is three assets: `citronos-V.tar.gz`, `.manifest.json` (format,
  version, tag, channel, file, SHA-256, commit) and `.manifest.json.sig`. The manifest
  is verified before the bundle is downloaded. The bundle must match its SHA-256, the
  tag must match, the channel must be allowed, and the version must be newer. The token
  is dropped on redirects to GitHub's storage host. `scripts/release-key.sh`,
  `scripts/make-release.sh` and `.github/workflows/release.yml` build and publish
  releases. `install-local --from BUNDLE` wants a signed bundle unless `--unsigned`.
  `tests/golden-update-signed.py`.
- **Still to do (owner):** run `scripts/release-key.sh`, commit the public key, add
  `CITRONOS_RELEASE_KEY` as an Actions secret, then tag `v4.0.0`. Until then, stable
  machines report "No CitronOS release has been published yet" and install nothing
  from GitHub.
- **Files:** `apps/settings/golden_update.py` (`check`, `download`, `install_local`),
  `scripts/make-update-bundle.sh`, new `distro/release.pub`, `.github/workflows/release.yml`
  (new), `tests/golden-update.py`.
- **Changes:**
  1. Releases are tags `vX.Y.Z`. CI builds `citronos-X.Y.Z.tar.gz` and a `minisign`
     signature with a key held in CI secrets, and publishes both as GitHub release assets.
  2. `check()` queries `/repos/{repo}/releases/latest` (stable) or the newest prerelease
     (beta), not a branch HEAD. `DEFAULT_BRANCH` is used only when
     `/etc/golden-gate/update.json` says `"channel": "dev"`.
  3. `download()` fetches the asset and its `.minisig` and verifies them with the pinned
     public key before `unpack`. A missing or bad signature raises `UpdateFailed` with
     "This update isn't signed by CitronOS".
  4. `install-local` verifies bundles the same way. `--allow-unsigned` exists only for
     developers and needs a root-owned `/etc/golden-gate/allow-unsigned`.
- **Depends on:** T-1.2.
- **Expected:** stable machines install only signed, tagged releases.
- **Tests:** extend `tests/golden-update.py` with a stand-in API serving three cases: a
  signed bundle (installs), an unsigned one (refused), and one signed by the wrong key
  (refused).
- **Done when:** the tests pass, the first signed release is published, and the README's
  update section is updated.

### T-1.4: Theme-icon crash fix and `AppIcon` (CS2-004) · **P1** · S · **done**
- **As built:** `apps/lib/AppIcon.qml` (the shell's `ui/AppIcon.qml`) is an `Image` with
  `asynchronous: !String(source).startsWith("image://")` (theme icons on the GUI thread,
  files in the background), `sourceSize` at 2× its size, mipmaps, aspect kept and
  `Accessible.ignored`. Being an Image, callers keep `status`, `scale`, `layer` and ids, and
  callers pass the source (the shell's approved-artwork lookups stay where they are) rather
  than an `icon`/`fallback` pair. Every app and theme icon in the shell uses it: the Dock
  (apps and places), Launchpad (cells, folder previews, open folders), Tablet Home,
  Mission Control (both), the launch card (its `sourceSize` fixed, as it grows), Spotlight,
  the app switcher, the widget gallery and the Notes widget. `tests/qml-regressions.py`
  now fails any `Image` in `shell/` whose source is an app or theme icon, as well as an
  asynchronous one; on the old shell it finds all 13. The Dock and Launchpad render
  pixel-identically in the preview. Still to do: the 20-cold-start session-harness check.
- **Files:** new `apps/lib/AppIcon.qml`; `shell/Applications.qml:480-494`,
  `shell/TabletHome.qml:412-421`, `shell/Dock.qml`, `shell/MissionControl.qml:205-212`,
  `shell/AppLaunch.qml:299`, `shell/DesktopWidgets.qml:358`; `tests/qml-regressions.py`.
- **Changes:**
  - `AppIcon { icon: entry.icon; fallback: "application-x-executable"; size: … }` wraps
    `Image` with `asynchronous: !String(source).startsWith("image://")`, `sourceSize` at
    2×, mipmap on, and an `Accessible.ignored` default.
  - Replace the direct Images listed above.
  - Port the regex guard from commit `24db0a5` (async plus an `iconPath` source in the
    same Image is an error).
- **Expected:** no start-up crash from icon loading.
- **Tests:** `qml-regressions.py` guard; T-0.2 with 20 cold starts.
- **Done when:** 20 of 20 clean starts in the session harness.

### T-1.5: Separate lock-screen process with restore (CS2-005) · **P1** · M · **done**
- **As built:** `shell/lock-shell.qml` (in the shell's own folder, so imports and the OTA
  refresh of the shell carry it; `qs -p` on a file) runs `LockScreen` alone, as
  `citronos-lock.service` (`gg-lock serve`, `Restart=always`, no start limit) under
  `citronos-session.target`. The shell no longer holds the lock; its `lock` IPC forwards to
  `gg-lock` (`compositor/hyprland/lock.sh`), which hypridle's `lock_cmd`, ⌃⌘Q and the
  menus all reach. gg-lock writes `$XDG_RUNTIME_DIR/citronos-locked`, then asks the lock
  process over IPC, or starts the unit, or the process itself without systemd. A lock
  process that starts while the mark is there locks at once, and unlocking removes it. The
  mark stands in for logind's `LockedHint`, which nothing sets today and a user service
  can't easily address. hyprland.conf sets `misc:allow_session_lock_restore = true`, so a
  crashed lock leaves the session locked until the new one takes over. Without a systemd
  user manager, gg-session-start keeps a lock process running too.
  `tests/lock-process.py` runs the real lock-shell.qml in the preview (idle without the
  mark, locked at once with it, mark and clear on lock/unlock; it fails on the old
  LockScreen) and gg-lock against stub qs/systemctl.
  **Found by the session harness (T-0.2):** a lock screen restarted straight after a crash
  could be refused. Quickshell's crash handler forks to write the core dump, and the fork
  keeps the dead lock screen's Wayland connection open for about half a second, so the
  compositor still counts its lock ("Cannot lock an already locked session"). Quickshell
  reports the refusal as an unlock, without `lockedChanged`, and the old LockScreen removed
  the mark as if someone had signed in. Now the lock screen holds the lock from being asked
  (IPC or the mark) until someone signs in, and checks every 300 ms that it still has it,
  asking again if not. Signing in removes the mark first, then lets go. The harness kills
  it 5 times while locked: each time a lock screen holds the lock again in about 2 s. Then
  it signs in, typed with a virtual keyboard (wtype): a wrong password must be checked and
  refused, and the account's own must unlock it and clear the mark (`lock.status`, IPC,
  reports the sign-in's state, never the password). A PAM error, not only a wrong
  password, now lets the person try again; before, it left the field disabled.
- **Files:** new `shell-lock/shell.qml` (imports `../shell/components/LockSurface.qml`
  through `ui/`); `shell/shell.qml:189` (remove the in-process LockScreen, keep the IPC
  name by forwarding); `compositor/hyprland/hypridle.conf` (`lock_cmd`);
  `compositor/hyprland/hyprland.conf` (`misc { allow_session_lock_restore = true }`); new
  unit `citronos-lock.service`; `scripts/install.sh`.
- **Changes:**
  - `loginctl lock-session`, `hypridle` and ⌃⌘Q all start or poke `qs -c golden-gate-lock`.
  - The unit restarts on failure. On start, if logind's `LockedHint` is true, it locks
    immediately.
- **Expected:** a lock-client crash recovers to a working lock screen within 3 s.
- **Tests:** a session-harness case: lock, `kill -SEGV` the lock process, assert a new lock
  surface within 3 s, type the password through `wtype`, and assert the session unlocks.
- **Done when:** 5 of 5 runs pass.

### T-1.6: systemd user units for the session (CS2-006) · **P1** · M · **done**
- **As built:** `distro/systemd/user/` has `citronos-session.target` (bound to
  `graphical-session.target`) wanting `citronos-shell`, `citronos-airdrop` and
  `citronos-icon-resolver`, plus `citronos-shell-safe`. The shell restarts after 1 s
  (`Restart=always`, so a clean exit is restarted too; `RestartMode=direct`); the fifth stop
  in 60 s (`StartLimitBurst=4`) fails it into `OnFailure=citronos-shell-safe.service`, which runs the same shell with `GG_SAFE=1` (no
  desktop widgets, no Citron, no live window captures in the glass) and says so in a
  notification. Output goes to the journal; the home-made log rotation is gone, except in
  the fallback below. hyprland.conf's three loops became `exec-once = gg-session-start`
  (`compositor/hyprland/session-start.sh`, a system-installed command rather than a file
  in `~/.config/hypr`, so an update that refreshes hyprland.conf can't point at something
  missing). It imports the session's display into the user manager, resets failed units
  and restarts the target; without a systemd user manager it supervises the shell itself
  as before. `gg-session` stops the target and unsets the display when Hyprland exits.
  AirDrop's unit runs `gg-airdrop --serve` with `Restart=on-failure`, so "already running"
  isn't restarted. Diagnostics read the journal. `tests/shell-supervisor.py` covers the
  unit policy, the start order, the fallback (new account, big log), logout, and safe mode
  in the preview (it fails on the old shell).
  **Found by the boot test's self-test** (`distro/archiso/selftest/`, the units for real on
  the ISO): one crash started safe mode. With systemd's default `RestartMode=normal` a
  service passes through "failed" on each death, and each pass fires `OnFailure=`.
  `RestartMode=direct` (systemd 254+) restarts without it, so only giving up does. And
  systemd refuses a start once there have been *more* than `StartLimitBurst`, so 5 took a
  sixth stop; 4 makes the fifth the one that gives up. The same run found NetworkManager's
  dispatcher disabled (T-1.8).
- **Files:** new `distro/systemd/user/citronos-session.target`, `citronos-shell.service`,
  `citronos-shell-safe.service`, `citronos-airdrop.service`, `citronos-icon-resolver.service`;
  `compositor/hyprland/hyprland.conf:41-56` (replace the loops with
  `exec-once = systemctl --user start citronos-session.target`);
  `distro/archiso/overlay/usr/local/bin/gg-session` (import the environment); `shell/shell.qml`
  (honour `GG_SAFE=1`: no `DesktopBackdrop` windows, no widgets, no Citron).
- **Changes:**
  - `Restart=on-failure`, `RestartSec=1`, `StartLimitIntervalSec=60`, `StartLimitBurst=5`
    (as built: `Restart=always`, `RestartMode=direct`, `StartLimitBurst=4`),
    `OnFailure=citronos-shell-safe.service`.
  - `StandardOutput=journal`.
  - Remove the home-made log rotation.
- **Tests:** extend `tests/shell-supervisor.py` to parse the units and assert the
  restart policy. Add a session-harness case where five kills lead to safe mode and a
  notification.
- **Done when:** `systemctl --user list-units 'citronos-*'` shows them active on the ISO.

### T-1.7: Keep Wi-Fi passwords off argv (CS2-016, interim) · **P2** · S · **done**
- **As built:** no new helper. Settings › Wi-Fi and Setup Assistant run
  `nmcli --ask … device wifi connect <ssid>` and write the password to its stdin
  (`Sys.runWithInput`, and the Setup step's own Process). `tests/wifi-password.py` records
  every argv and every stdin write in the preview harness: the password is only ever on
  stdin, once (and the test fails on the old code). The `ps` check on a real join is
  still to do.
- **Files:** `apps/settings/panes/WifiPane.qml:44-51`; a new `gg-wifi-join` mode
  `--password-stdin`.
- **Changes:** Settings runs `["gg-wifi-join", "--password-stdin", ssid]` and writes the
  password to stdin. The helper uses `nmcli … passwd-file /dev/stdin`, or builds a
  connection with `nmcli connection add … wifi-sec.psk` read from stdin through Python's
  `subprocess` input.
- **Tests:** a stub `nmcli` that records argv and stdin. Assert the password never appears
  in argv.
- **Done when:** the test passes, and a `ps` loop during a real join shows no password.

### T-1.8: AirDrop off by default, and a firewall (CS2-017) · **P2** · S · **done**
- **As built:** receiving is off on a fresh settings file, and while it's off `airdropd`
  holds no network socket at all (no HTTPS, no UDP discovery port). Sending and the /24
  sweep still work, since they only connect out. The choices are Receiving Off,
  Everyone for 10 Minutes (it stores an expiry time and turns itself off; Control Center's
  toggle uses this, as on a Mac) and Everyone. Only HTTPS is used: without openssl the
  computer can't receive, and plain-HTTP devices are neither listed nor called.
  Firewall: `firewalld` is installed and enabled (ISO and installer); the default zone
  `public` allows only DHCPv6 and mDNS; `home` adds `citronos-airdrop` (53317 tcp/udp) and
  `citronos-airplay` (UxPlay, now run with `-p` for its fixed ports). Which networks are
  private is decided by a NetworkManager dispatcher script (`50-citronos-zone`, root), not
  `apply-preferences.sh` (the user session can't change zones): wired networks and Wi-Fi
  with a password (WPA/WPA3 Personal) are `home`; open Wi-Fi, WPA Enterprise, this
  computer's hotspot and everything else stay `public`; a zone the connection names
  always wins, and only the running firewall changes. Choosing per network in Settings is
  T-4.8. Tests: `tests/airdrop.py` (off by default with no listener, 10-minute expiry with
  a short window and an injected clock, a sender with receiving off, plain HTTP never used;
  it fails on the old daemon) and `tests/firewall-zones.py`. The session harness (T-0.2)
  and the boot test's self-test check that nothing listens on 53317 after login; the
  self-test also checks the zones in the live session, and found the dispatcher script
  never ran: NetworkManager runs them only with `NetworkManager-dispatcher.service`
  enabled, which the ISO (its `dbus-org.freedesktop.nm-dispatcher.service` link) and the
  installer now do.
- **Files:** `apps/airdrop/airdropd.py:319-345` (default `"off"`, remove the HTTP
  fallback, add "everyone for 10 minutes" with an expiry); `apps/airdrop.qml` (UI for
  that); `distro/archiso/packages.x86_64` (+`firewalld`); new
  `distro/archiso/overlay/etc/firewalld/services/citronos-airdrop.xml`; `apply-preferences.sh`
  (map NM connections to zones: `home` for private, `public` for the rest).
- **Tests:** extend `tests/airdrop.py`. A fresh settings file means not discoverable and
  no listener. "Everyone for 10 minutes" turns it on and it expires (with an injected
  clock). Plain HTTP is never used.
- **Done when:** `ss -lntup` on a fresh login shows no 53317 listener.

### T-1.9: Report preference-write failures in the shell (CS2-023, interim) · **P2** · S · **done**
- **As built:** `Prefs.write(key, value, what)` is the one way the shell changes a
  preference (Dock, widgets, Home Screen, Control Center, Night Shift, brightness,
  screenshot options, battery percentage). It shows the change at once, runs gg-pref in a
  watched Process, and on failure puts the old value back (unless something changed it
  again meanwhile), sets `Prefs.saveError` and posts "Your Dock change wasn't saved" with
  gg-pref's reason. gg-pref keeps one `desktop.json.damaged-<time>` copy of a damaged file
  and names it. `tests/prefs-write-errors.py` covers success, failure, a damaged file and
  Control Center (and fails on the old code).
- **Files:** `shell/components/Prefs.qml:33-58` (`setTabletWidgets`, `setDockPinned`,
  `setWidgets`); `shell/Notifications.qml` (post a local notification);
  `apps/setup/pref-helper.py` (on a damaged file, also copy it to
  `desktop.json.damaged-<ts>` and say so).
- **Changes:** reuse the `focusWriter` pattern (`Prefs.qml:111-123`) for every writer. On a
  non-zero exit, roll back the in-memory change and post "Your Dock change couldn't be
  saved: …".
- **Tests:** a preview-harness test with a read-only config directory. Change the Dock and
  assert that both the rollback and the notification happen.
- **Done when:** the test passes.

### T-1.10: Security lints (CS2-001, CS2-002, CS2-016) · S · **done**
- **As built:** `tests/security-lint.py`, in the `generated` CI job, with an empty
  `tests/security-lint.baseline`. QML and JS go through a small lexer: an `sh -c`
  script, a `Sys.sh()` script or a `dispatch("exec …")` must be literal strings (joined
  with `+`, or a literal `readonly property string` of the same file); argv arrays may
  not carry `password`, `--token`, a `password`/`token`/`secret` variable and the like.
  Python is read with `ast`: no `shell=True`, `os.system`, `os.popen` or an `sh -c` script
  built from data. polkit: every action granted `YES` by a rule (or `yes` by a policy)
  must run a helper listed in the lint with its exact subcommands, read from the helper's
  `commands` table, and that helper may not call `set_source`, `install_local` or anything
  `unsigned`. A reviewed exception carries `security-lint: allow <why>` (two today: Settings'
  `Sys.sh` definition, whose callers are checked, and AirDrop's test hook). The lint tests
  itself on samples first, and catches the pre-T-1.1/T-1.7 code. Fixing what it found:
  Bluetooth pairing (a device's address in a shell string), Settings' keyboard read, Night
  Shift warmth, and the `os.system` calls in the preview and SDDM test.
- **Files:** new `tests/security-lint.py`; `.github/workflows/check.yml` (`generated`
  job).
- **Checks:**
  1. QML and JS: no `dispatch("exec " +`, no `["sh","-c", <expr containing +>]`, no
     `execDetached(["sh","-c", … + …])`.
  2. Python: no `shell=True`.
  3. polkit: for every action granted `YES` by a rule, its `exec.path` helper has no
     subcommand that writes `/etc/golden-gate/update.json` or runs downloaded code
     (checked against a list of allowed subcommands).
  4. No `password` and no `token` arguments in argv arrays built in QML.
- Existing violations are listed in `tests/security-lint.baseline` and may only shrink.
- **Done when:** it runs in CI, and the baseline is empty after T-1.1, T-1.2 and T-1.7.

---

## M2: Platform foundations and design system

| ID | Task | Findings | Files and subsystems | Key changes | Tests / done when |
|---|---|---|---|---|---|
| T-2.1 | PKGBUILDs and a signed `[citronos]` repository | CS2-011, CS2-003 | new `packaging/*/PKGBUILD`; `scripts/install.sh` → `make install DESTDIR=` used by the PKGBUILDs; `.github/workflows/packages.yml` | Package split per [05](05-ARCHITECTURE-PROPOSAL.md#packages-updates-and-releases); the shell moves to `/etc/xdg/quickshell/golden-gate`; bin wrappers to `/usr/bin` | `pacman -Qkk citronos-*` is clean on an ISO install; a new account has no `~/.config/quickshell` and the shell runs |
| T-2.2 | Reproducible ISO | CS2-010 | `distro/archiso/build.sh`, new `distro/archiso/archive-date` | Pinned Arch Linux Archive mirror; AUR inputs pinned by commit, or consumed from `[citronos]`; signed local repository; `build-manifest.json` | Two CI builds give an identical manifest |
| T-2.3 | Hyprland and HyprGlass in lock-step | CS2-009 | `packaging/citronos-hyprland`, `packaging/citronos-hyprglass` | Both built from source in CI against the same tag; `IgnorePkg`-style hold through package `conflicts`/`provides` | Simulated Hyprland bump: CI produces a matched pair or holds both back |
| T-2.4 | `citronos` Python package | CS2-020 | new `apps/lib/python/citronos/{files,secrets,jsonl,proc,paths}.py` | Atomic write, Secret Service over D-Bus, JSON lines, subprocess with timeout and `PDEATHSIG`; migrate Notes, Calendar and Files first | Unit tests for each module; the migrated helpers' tests pass |
| T-2.5 | `citronos-settingsd` | CS2-023 | new `services/settingsd/`; `shell/components/Prefs.qml`, `apps/settings/Sys.qml` move to the service singleton | Typed keys with defaults, per-domain files, `.bak` restore, `Changed` signal | Damage the file → restored with a notice; two writers don't lose updates (port `tests/settings-prefs.py`) |
| T-2.6 | `citronos-notifyd` + LauncherEntry | CS2-024 | new `services/notifyd/`; `shell/Notifications.qml` becomes a client | SQLite history, Focus rules, `com.canonical.Unity.LauncherEntry`; Mail badge through it | Kill the shell → history intact; an Electron badge shows (port `notification-*` tests) |
| T-2.7 | Role tokens | CS2-018, CS2-043 | `design/tokens.json`, `design/build.mjs`, `apps/lib/theme/Theme.qml` | `Theme.font.*`, `Theme.radius.*` (7), colour roles, `Theme.motion.*`; interim `fs()` floor at 10 and scaling above 24 | `appearance-contracts.mjs` extended; screenshot diff |
| T-2.8 | Design lint with baseline | CS2-018, CS2-013 | new `tests/design-lint.py` + baseline | Literal radius, duration and colour; pointer handlers without `Accessible` | Runs in CI; the baseline only shrinks |
| T-2.9 | New shared components | — | `apps/lib/{SearchField,ListRow,FormRow,FormSection,Popover,Alert,ConfirmSheet,Toast,InlineBanner,Spinner,Tooltip,NavigationSplitView,Badge}.qml` | Each with accessibility, Reduce Motion and keyboard support | `tests/shared-ui.py` extended; each component has a preview-harness test |
| T-2.10 | Migrate the six worst files | CS2-018 | `Browser.qml`, `settings.qml`, `maps.qml`, `VoiceAssistant.qml`, `calculator.qml`, `LockSurface.qml` | Literals → roles | Lint numbers drop; screenshots reviewed |
| T-2.11 | Accessible annotations in the shell | CS2-013 | `shell/Dock.qml`, `Spotlight.qml`, `Notifications.qml`, `DesktopWidgets.qml`, `CitronPodsPopup.qml`, `apps/maps.qml`, `apps/calculator.qml` | `Accessible.role`, `name`, `onPressAction` | The design lint's accessibility rule passes for `shell/` |

**As built (M2 so far):**
- **T-2.1, PKGBUILDs and a signed repository · in progress (part 1 of 3).** `make install
  DESTDIR=` (`scripts/stage.sh`, one part per package) lays CitronOS out as packaged:
  `citronos-runtime` (the apps and shared UI in `/usr/share/golden-gate`, helpers in
  `/usr/lib/golden-gate`, the `gg-*` commands in `/usr/bin`, units, D-Bus services, PAM,
  polkit, pacman hooks in `/usr/share/libalpm/hooks`), `citronos-shell` (the shell in
  `/etc/xdg/quickshell/golden-gate`, which Quickshell searches after `~/.config`),
  `citronos-hyprland-config` (`/usr/share/golden-gate/hypr`, and a new account's
  `hyprland.conf` is one `source` line) and `citronos-theme`, with the `citronos` meta
  package. `packaging/citronos/PKGBUILD` builds them; the Packages workflow
  (`packaging/check.sh`) installs them on a clean Arch system, where `pacman -Qkk` is clean
  and a new account runs the system's shell with no copy of its own. `gg-lock` finds the
  lock screen as Quickshell finds the shell; `gg-session` makes the per-account Hyprland
  files a packaged config sources. `tests/packaging.py` (in Check) stages each part: no file
  in two packages, nothing in `/usr/local` or a home folder, and every command, service,
  unit and desktop entry runs something installed. Next: the ISO and Software Update
  install these packages instead of `install.sh --system`, moving existing accounts off
  their copies of the shell (part 2); signing them and the `[citronos]` repository, with
  `citronos-keyring` (part 3).
- **T-0.3, performance baseline · CI done; the laptop run is manual.**
  `tests/session/perf.py`, in every Session run: time to "desktop ready", resident memory,
  idle CPU with a window behind the Dock (glass windows on and off) and the shell's busiest
  threads, for the shell, its bridges and the services. CI's baseline is in
  `perf-baseline.json` and `perf-baseline.md`: 751 ms to ready, 663 MB, 1.6 % of a core idle,
  the services 54 MB and 0.3 %. A run more than 25 % worse warns. Idle was 16 % until the
  threads showed the shell redrawing: the Clock widget's hands sprang to each new place,
  drawing the widget layer nine times a second; they now step (`tests/idle-frames.py` keeps
  the shell at about one frame a second at rest). On the way: the lock screen no longer
  starts a D-Bus bridge (it reads its preferences from the file, `GG_PREFS_READONLY`),
  comes back 200 ms after it stops, without Quickshell's crash handler (no dump of a
  password being typed, nothing holding its lock open), and the Session harness installs
  `python-dbus-next` as the ISO does, so it runs settingsd and notifyd for real.
- **T-2.9, new shared components · done.** `apps/lib/` gains `Alert`, `ConfirmSheet`,
  `Popover`, `SearchField`, `ListRow`, `FormRow`, `FormSection`, `InlineBanner`, `Toast`,
  `Spinner`, `Badge`, `Tooltip` and `NavigationSplitView` (`AppIcon` was already there). Each
  carries its accessible role and name, works from the keyboard and has a Reduce Motion
  behaviour, using the T-2.7 tokens (two new colour roles, `groupedCard` and
  `groupedCardBorder`). `tests/shared-components.py` (16, in CI) drives each in a scene of
  its own with real key and pointer events, and `tests/shared-ui.py` now guards the new
  names. Settings' "couldn't be saved" strip is now an `InlineBanner` (it also shows again
  for the next error after one is dismissed). LCode's own `Popover` and `FormRow` were
  renamed (`DesignPopover`, `PreferenceRow`): an unqualified `import "../../lib"` takes
  precedence over a component's own folder, so the new shared ones would have replaced
  them silently. Moving the apps' hand-made search fields, rows, popovers and
  confirmations onto these is per-app migration work, like T-2.10's.
- **T-2.6, `citronos-notifyd` + LauncherEntry · done.**
  `services/notifyd/notifyd.py` owns `org.freedesktop.Notifications` (spec 1.2: actions,
  body, static icons, persistence) and serves the shell as `org.citronos.Notifications1`
  (`List`, `Dismiss`, `DismissApp`, `Invoke`, `Badges`; `Added`, `Removed`,
  `BadgesChanged`). The history is SQLite (`~/.local/state/golden-gate/notifications.db`,
  0600, the newest 300; transient ones aren't kept), so it outlives the shell and the
  service itself. It applies each app's Settings choice (an app that isn't allowed is
  dropped but still listed in `notifiers.json`, so Settings can allow it again) and Focus
  decides as each one arrives (`quiet`: no banner, no sound). Focus's rules are a Python port
  of `FocusPolicy.js` (`citronos.focus`); a contract test runs 100+ cases, a DST change
  among them, through both, so they can't drift apart. An `image-data` hint becomes a
  private PNG, removed with its notification. Badges and progress come from
  `com.canonical.Unity.LauncherEntry`, which Electron, Qt and GTK apps already broadcast,
  and go when the app leaves the bus. Started with the session (`citronos-notifyd.service`,
  before the shell) and activatable under both names. `tests/notifyd.py` (13, in CI): a
  real app on a private bus sending, replacing, closing and hearing its actions; history
  across a killed service; Settings' allow and Focus; images; the limit; LauncherEntry
  badges coming and going.

  **The shell as its client.** `shell/Notifications.qml` reaches notifyd through the bridge
  (`DBusObject`): banners, Notification Center and the Dock's badges come from its records,
  wrapped to look like Quickshell's notifications, so the cards, actions, dismissing and
  grouping are unchanged. Focus's decision (`quiet`) is notifyd's, made as each arrives; the
  app's banner and sound choices stay the shell's. Only if the bridge can't reach notifyd at
  all (`DBusObject.unreachable`, not while it's restarting) does the shell become the server
  itself, as before; otherwise there'd be two. The Dock shows an app's own count when it
  keeps one (LauncherEntry) and its progress as a bar across the icon's foot. CitronOS's own
  apps, whose helpers come and go, use `SetBadge(app, count)`, kept in the database until
  changed: Mail's helper sends its unread count that way (with `gdbus`) and still writes
  `mail-badges.json` for a shell without notifyd. That is CS2-024's check: kill the shell and
  the history is intact; an Electron app's badge shows. `tests/notifyd.py` (20) adds the
  production `Notifications.qml` against the real service: banners and Notification Center,
  an action reaching the app, Focus keeping one out of the banners, the history across a
  shell restart, badges and progress for the Dock, Mail's badge across a service restart, and
  the shell standing in when there's no bus. The existing notification suites still run the
  stand-in path in the preview.
- **T-2.5, `citronos-settingsd` · done.** `citronos.settings` with
  `settings-schema.json`: every `desktop.json` key with a type (bool, number with a range,
  string with its choices, list, object, map) and a default. `gg-pref`, which every writer
  already goes through, now uses it: a value that doesn't fit is refused with the reason;
  writers take turns under the lock; the copy before each change is `desktop.json.bak`; a
  damaged file is put back from it (the damaged one kept aside) with a notification, and at
  login (`gg-pref --check` in `apply-preferences.sh`) before anything reads it. That is
  CS2-023's check: damage `desktop.json`, rearrange the Dock, restart, and the arrangement is
  kept and the user told. `tests/settings-store.py` (13, in CI) checks it, and that every key
  Settings and the shell write is in the schema.

  **The service and the bridge.** `services/settingsd/settingsd.py` is
  `org.citronos.Settings1` (`/org/citronos/Settings1`, values as JSON text): `Get`, `GetAll`,
  `Set` (checked against the schema; a refusal is a D-Bus error with the reason), and the
  signals `Changed(domain, key, value)` and `Restored(domain, message)`. It writes through
  the same store and lock as gg-pref, so neither loses the other's change, and it watches the
  folder (inotify), so a change made by gg-pref or an editor is sent as `Changed` too, key by
  key. Its own change is signalled before the reply. D-Bus activation starts it
  (`distro/dbus/org.citronos.Settings1.service`, the user unit `citronos-settingsd.service`).
  `apps/lib/dbus-bridge.py` is the plan's generic bridge: one object, JSON lines on
  stdin/stdout, arguments typed from introspection, and a service that stops is started
  again. **Measured** (the plan's condition for keeping it in Python): a `Set` through the
  bridge takes 4.3 ms median, 5.4 ms p90, against gg-pref's 43 ms, so no Qt plugin is
  needed. `tests/settingsd.py` (12, in CI) runs both on a private bus: activation, two
  clients hearing each other, refusals, outside edits, a damaged file put back and said,
  30 simultaneous writers through the service and gg-pref with nothing lost, a killed
  service coming back, and the timing.

  **The clients.** `apps/lib/DBusObject.qml` runs the bridge for one object (`ready`,
  `call(method, args, done)`, `signalled`), and `apps/lib/services/Preferences.qml` is one
  domain for any client: `data`, kept current by `Changed` key by key; `write()` (shown at
  once, put back with the reason if refused) and `save()` (shown once saved, for Focus).
  Without the service (before it answers, or if it can't start) it reads and watches the file
  and writes with gg-pref, same schema, same lock; a change cut off by the service stopping
  is made again with gg-pref. Changes not yet answered stay on screen whatever is read
  meanwhile, so neither an earlier change's signal nor the first `GetAll` flicks them back.
  The shell's `Prefs.qml` and Settings' `Sys.qml` (with Focus and Lock Screen) use it, so
  they no longer each start a gg-pref per change or re-read the whole file on every write.
  Lock Screen now applies the idle timers when the change is saved, rather than 0.3 s
  after it. `tests/settingsd.py` (16) adds the QML clients with the real bridge and service:
  the shell and Settings hearing each other and outside edits, no gg-pref while the service
  is there, a refusal put back with its reason, 20 quick changes without a flicker, and
  gg-pref saving it with no bus. The preview's `Process` can run the bridge for real when a
  test asks (`__spawner`); everywhere else it is a fixture, so the other suites exercise
  the gg-pref path. Left for later: `privacy`, `input`, `accessibility` and `windows`
  still have their own writer (`set-prefs.py`); they become domains of the same service
  when they get schemas.
- **T-2.4, the `citronos` Python package · done.** `apps/lib/python/citronos/` (installed
  with the shared UI, `/usr/share/golden-gate/ui/python`): `files` (atomic write that also
  syncs the folder and never leaves its temporary file; new files 0600, replaced ones keep
  their mode; JSON; `locked()`; `keep_aside()` for a damaged store; backups), `jsonl`
  (append-only logs, one synced write under a lock, a torn last line skipped and never glued
  to the next), `proc` (no shell, a timeout, `die_with_parent` so a child never outlives its
  helper), `secrets` (the keyring with "missing", "timeout" and "failed" errors; secrets on
  stdin only) and `paths` (XDG folders). Calendar, Notes' trash and Files' view preferences
  write through it (Notes' trash used to leave a temporary file behind on a failed write), and
  Mail's keyring calls go through `secrets`. `tests/citronos-python.py` (18 tests, in CI)
  checks each module, including a real child dying with its parent and a fake `secret-tool`
  that records its arguments (a secret is never one). Deviation: `secrets` drives
  `secret-tool` rather than speaking D-Bus itself, because secret-tool shows the keyring's
  unlock prompt, which a helper can't; a D-Bus backend can sit behind the same calls.
- **T-2.8, design lint · done.** `tests/design-lint.py` counts, per QML file in `shell/`,
  `apps/` and `themes/`: literal radii and durations (0 is fine), literal colours,
  `Theme.fs(n)` sizes, and pointer handlers that act (a MouseArea or TapHandler with
  `onClicked`, `onTapped` …) with no `Accessible.role` and `.name` on it or the item it sits
  in. The literal rules skip `theme/` folders. `tests/design-lint.baseline.json` holds the
  per-file counts: a file may not go over, and a count that went down must be lowered too
  (`--update`, which refuses a higher total), so the numbers only shrink. Exceptions say
  why: `// design-lint: allow <reason>`. In CI beside the security lint. First counts:
  radius 524, duration 208, colour 1,593, `fs()` 837, accessible 242. (The audit's 426 radii
  counted whole numbers only.)
- **T-2.11, accessibility in the shell · done.** All 45 handlers the lint found in
  `shell/` have a role, a name that says what they are or their state, and an
  `onPressAction` doing what the click does (shared through a function where the click was
  more than a line). The menu bar's `BarItem` takes a `label`. Click-away layers are
  `Accessible.ignored`; GlassSlider's drag area and Screenshot's area drawing are reviewed
  exceptions (the slider, and the toolbar's choices, are the accessible controls). `shell/`
  is at 0, and the baseline keeps it there; 197 remain in `apps/`.
- **T-2.7, role tokens · done (migration is T-2.10).** `design/tokens.json`'s `role`
  section generates `Theme.font.caption2 … largeTitle` (a whole font, scaled by Text Size),
  `Theme.radius.{control 6, field 8, card 12, menu 14, panel 18, window 22, capsule 999}`,
  `Theme.motion.{tap, snappy, panel, sheet, window, bouncy, ambient}` (each with `ms`, its
  duration or its Reduce Motion fade) plus the hover/fade/menu/minimize durations, and the
  colour roles `fillHover`, `fillPressed`, `destructive`, `success`, `warning`,
  `overlayScrim` and `shadow`. `fs()` gets CS2-043's interim fix: nothing under 10 px (it
  was 12, so 8 to 12 all looked the same), titles of 25–40 px scale at half the rate,
  display numerals over 40 stay; Text Size runs from 85 % to 150 %. `tests/text-size.py`
  checks it all at 85, 100 and 150 %.
- **T-2.10, the worst files on roles · done.** What each file became:
  - **Type.** The ramp is now macOS's (footnote 10, subheadline 11, callout 12, body 13,
    title3 15, title2 17, title1 22, largeTitle 26), and `tools/migrate-fs.py` moved the 750
    `Theme.fs(n)` calls on those sizes to `Theme.font.<role>.pixelSize`, in 139 QML files
    (a3d2753's message says 160; 145 files changed in all). 87 calls on sizes off the ramp
    (14, 16, 18, 20 …) wait for a decision on each.
  - **`LockSurface.qml`.** White over the wallpaper is `Theme.vibrant.*`, radii are roles or
    half the height, durations are `Theme.motion`, and the "no" shake is the shared
    `apps/lib/Shake.qml`. What stays is the lock screen's own (the dusk tint, the platter,
    the default picture), each a reviewed exception. Screenshots unchanged.
  - **`calculator.qml` and `CalcKey.qml`.** The Mac's Calculator is graphite in Light Mode
    too, so its palette is the app's own, in `apps/calculator/theme/CalcColors.qml`; the lint
    treats an app's `theme/` folder as it does `apps/lib/theme`. Its two hand-drawn menus
    (the mode menu, the unit lists) are now the system's `PopupMenu`, the pills take half
    their height, and every handler, the keys and bits included, has a role, a name and
    `onPressAction`. Screenshots in every mode are pixel-identical but for the unit
    buttons' corners (7 → 6); the menus look like every other menu, dark as the window.
  - **`settings.qml`.** Two colour roles join the tokens: `unemphasizedSelection` (a
    selected row in an inactive window) and `selectedText` (on the accent). The pane
    icons' tile colours are Settings' own, the same in both appearances, in
    `apps/settings/theme/PaneTints.qml`. The search suggestions are menu glass
    (`Glass { role: "menu" }`) instead of a near-opaque box with a drawn shadow, so the
    sidebar shows through them a little more, as through every menu. Durations are
    `Theme.motion`. All six pane shots, light and dark, are pixel-identical.
  - **`Browser.qml`.** Web draws its own chrome, as Safari does, so the window, toolbar,
    tab bar, Smart Search field, sidebar (each with its private-window tint) and the
    panels over the page are Web's own palette, `apps/browser/theme/WebColors.qml`;
    hovers, selections, list fills and labels are the system's. Its eight hand-built
    panels (Settings, Passwords, Website Permissions, Privacy Report, Profiles, Tab Groups
    and the group editor, a site's permission request) are one `BrowserSheet`, which
    grows in, fades, and now always fades out. The traffic lights take the new
    `Theme.trafficLight*` tokens, icon tiles the system's 0.26 corner ratio, and every
    tap target in Web and its Start Page has a role, a name and an action. Shots of 12
    states in light and dark (the real app, through a capture script run as a desktop
    user) differ only by a shade in hovers and selections and a tighter sheet shadow;
    `tests/native-browser.py` passes against real Chromium.
  - **`maps.qml`.** `Theme.system.*` joins the tokens: Apple's system colours in each
    appearance's tone (blue `#007aff` in Light, `#0a84ff` in Dark …), for what is that
    colour whatever the accent. The start of a route is system blue, the destination
    system red, favourites system yellow; the Directions button, the chosen travel mode
    and the chosen route follow the accent, as buttons do. What Maps lays over the map
    (the panel, the round controls, the toast) is `apps/maps/theme/MapsColors.qml`;
    hovers and selections are the system's, and every control has a role, a name and an
    action (the map buttons now say what they do). Screenshots of search, Find Nearby,
    a place and directions, light and dark, differ in hairlines (now `Theme.separator`),
    Light Mode's blue and a few corners. The map's own drawing (pins, routes, tiles in
    `apps/maps/`) keeps its palette; it is outside the six files.
  - **`VoiceAssistant.qml` (Citron).** Its text is the system's vibrant labels (white
    over dark glass, which `Theme.vibrant` was made for), its text shadows
    `Theme.vibrant.shadow`. Its own look, the smoky indigo glass, chips, round buttons,
    the deep blue of a live microphone and a ready Send, the pale link and error tints,
    is `apps/lib/intelligence/palette/CitronColors.qml` (named `palette`, not `theme`:
    `tests/shared-ui.py` keeps one Theme module per process). The composer's round
    buttons share one fill. Shots of Ask, Write, Create and the voice states: the labels
    a touch more translucent, nothing else.
  - **The six files are done:** colour, radius, duration and accessible are 0 in each,
    but for the lock screen's reviewed exceptions. What is left of `fs()` (87 calls on
    sizes off the ramp) waits on a decision per size.

## M3: Desktop refinement

| ID | Task | Findings | Files | Key changes | Tests / done when |
|---|---|---|---|---|---|
| T-3.1 | Fullscreen-aware menu bar and Dock | CS2-008 | `shell/Dock.qml`, `shell/MenuBar.qml` | Track `hasfullscreen` per monitor; slide out; hot-edge reveal; exclusive zone 0 | Session harness: `mpv --fs` screenshot has no shell pixels |
| T-3.2 | Dock auto-hide, position, displays | CS2-034 | `Dock.qml`, `Prefs.qml`/settingsd, `apps/settings/panes/DockPane.qml` | `dock.autohide`, `dock.position`, `dock.displays` | Screenshot tests for each option; windows use the freed space |
| T-3.3 | Glass lens opt-in, capture on damage | CS2-007 | `components/DesktopBackdrop.qml`, `Prefs.qml`, `AppearancePane.qml` | Default off for permanent surfaces; frame-event capture; off on battery with Low Power | T-0.3 shows idle CPU under 1 % and no GPU busy at idle |
| T-3.4 | Lazy Launchpad and Tablet Home | CS2-025 | `shell/shell.qml:197-247`, `Applications.qml`, `TabletHome.qml` | `LazyLoader { active: Prefs.tabletMode }`; grid built on idle | T-0.3 RSS and time to desktop improve, with 1 and 3 monitors |
| T-3.5 | GlobalShortcuts for shell keys | CS2-021 | `hyprland.conf:186-230`, `shell/shell.qml` | `bind = …, global, golden-gate:spotlight` and so on; keep `ipc` for scripts | Keypress-to-frame under 50 ms (240 fps video) |
| T-3.6 | Indexed Spotlight | CS2-022 | new `services/searchd/`; `shell/Spotlight.qml`; packages `localsearch`, `tinysparql` | Provider API ([05](05-ARCHITECTURE-PROPOSAL.md#search)); streaming results | With 200k files, median under 100 ms; content match found |
| T-3.7 | Split the large QML files | CS2-019 | `Browser.qml`, `files.qml`, `calendar.qml`, `mail.qml`, `ControlCenter.qml`, `software.qml` | Toolbar, sidebar, content and sheet files; sheets through `Loader` | No file over 800 lines; existing tests pass; first frame not slower |
| T-3.8 | Motion roles everywhere | CS2-018 | All shell surfaces | `duration:` literals → `Theme.motion.*` | Lint duration baseline ≤ 30; no dropped frames in a 60-frame capture |

## M4: Native integrations

| ID | Task | Findings | Files | Key changes | Tests / done when |
|---|---|---|---|---|---|
| T-4.1 | `citronos-networkd` | CS2-016, CS2-037, CS2-041 | new `services/networkd/`; `ControlCenter.qml`, `WifiPane.qml`, `NetworkPane.qml`, menu bar | NM D-Bus; secret agent → inline sheet; VPN import; 802.1X; captive portal | `hostapd` + `dnsmasq` CI lab: WPA2, PEAP, captive portal; SSID `a:b\c` displays correctly |
| T-4.2 | `citronos-bluetoothd` + pairing agent | CS2-014 | new `services/bluetoothd/`; `BluetoothPane.qml`, `ControlCenter.qml`, `Nearby.qml` | BlueZ D-Bus, `Agent1` → shell sheet | `btvirt` integration test; hardware: keyboard passkey and phone comparison |
| T-4.3 | logind brightness | CS2-026 | `ControlCenter.qml:110-125`, `Osd.qml`, `hyprland.conf` brightness keys | `Session.SetBrightness` over D-Bus | `execsnoop` shows no processes during a drag |
| T-4.4 | Users & Groups through accountsservice | CS2-027 | `apps/settings/panes/UsersPane.qml`; package `accountsservice` | Add, delete, admin, picture, password sheet | VM test with no terminal |
| T-4.5 | Per-app permissions | CS2-031 | new `PermissionsPane.qml`; `apps/software/helper.py`, `software.qml` | Flatpak permission store and overrides; App Store disclosure | Revoke camera → portal denial |
| T-4.6 | Per-app systemd scopes | — | `apps/lib/AppLaunch` helper used by Dock, Launchpad and Spotlight instead of `execute()` | `systemd-run --user --scope --unit=app-citronos-<id>-<rand>` | `systemctl --user list-units 'app-citronos-*'` shows running apps |
| T-4.7 | Accessibility foundation | CS2-013 | `AccessibilityPane.qml`, `hyprland.conf`, packages `orca` `espeak-ng` `at-spi2-core` | Screen reader toggle, Zoom, Increase Contrast, pointer size, sticky, slow and mouse keys | Orca walkthrough script; screenshot tests for Zoom and contrast |
| T-4.8 | Firewall zones in Settings | CS2-017 | `NetworkPane.qml` | Per-network "Private / Public" | Switching zones opens and closes AirDrop's port |

## M5: Application maturity

| ID | Task | Findings | Key changes | Done when |
|---|---|---|---|---|
| T-5.1 | Internet Accounts (GOA) | CS2-015 | Settings pane; Google, Microsoft, IMAP, CalDAV/CardDAV | OAuth sign-in for Google and Microsoft in a VM |
| T-5.2 | Calendar on EDS, read and write | CS2-042 | Replace `caldav.py` sync with EDS; keep the local store as an EDS "On This Computer" source | Create, edit and delete round-trips to a second client |
| T-5.3 | Contacts app | — | New `apps/contacts.qml` on EDS address books; used by Messages, Mail, AirDrop | Add a contact → it appears in Mail autocomplete and Messages |
| T-5.4 | Mail engine upgrade | CS2-015 | Long-lived engine: GOA tokens, IDLE, SQLite cache, folders, search, attachments, Sent `APPEND`, threading headers, multiple accounts | The acceptance list in [06 M5](06-CLUB-SODA-ROADMAP.md) |
| T-5.5 | Preview app | — | Poppler-Qt6 PDF (or PDF.js in WebEngine); images; rotate and export | A 300-page PDF opens in under 1 s |
| T-5.6 | Network locations in Files | — | gvfs SMB, SFTP and WebDAV; ⌘K "Connect to Server" | Copy 1 GB from SMB with progress and cancel |
| T-5.7 | Activity Monitor | — | Per-scope CPU and memory (T-4.6), energy estimate, quit and force quit | Shows a busy app and quits it |

## M6: Intelligence and ecosystem

| ID | Task | Findings | Key changes | Done when |
|---|---|---|---|---|
| T-6.1 | `citronos-intelligd` provider interface | CS2-028 | Gemini (port), OpenAI-compatible, Ollama | Writing Tools works with Gemini and with Ollama |
| T-6.2 | Tool registry, confirmations, audit log | CS2-028 | Scope declarations; a confirmation UI the model can't answer; Settings page | Each write tool has a no-confirmation-no-run test; red-team suite passes |
| T-6.3 | First tool set | — | Search, open app, Wi-Fi, Bluetooth, Focus, brightness and appearance toggles, calendar event | Spoken "turn on Do Not Disturb for an hour" → confirmation → done |
| T-6.4 | Summaries (opt-in) | — | Notification digest, summarise selection or document | Off by default; per-app opt-in honoured |
| T-6.5 | Peripheral framework + CitronPods package | CS2-029 | `citronos-pods-engine` package; accessory model in bluetoothd | AirPods battery on a fresh install with no ZIP or compiler |
| T-6.6 | Clipboard history | — | `wl-paste --watch` store; ⇧⌘V picker; password-manager hint respected | Copies from a password manager never appear |

- **Ahead of T-6.1: Citron moved from Gemini to Aion Labs (by the owner's choice).** Text
  goes to Aion's OpenAI-compatible API; voice is a local pipeline (`voice.py`: the speech
  gate, whisper-cpp, Aion streamed, Piper), so only words leave the computer. Image
  creation and photo editing are gone with Gemini. T-6.1's provider interface would now
  start from Aion (OpenAI-compatible) rather than port Gemini. See
  [CITRON-INTELLIGENCE.md](../CITRON-INTELLIGENCE.md).

## M7: Release engineering and hardening

| ID | Task | Findings | Key changes | Done when |
|---|---|---|---|---|
| T-7.1 | Installer: LUKS2, zram, btrfs + snapshots | CS2-012 | `apps/installer/helper.py`, `installer.qml`; `snap-pac`; boot-menu rollback | QEMU installs with encryption; a failed update is rolled back from the boot menu |
| T-7.2 | Install alongside | CS2-012 | Shrink with checks; reuse the EFI partition; refuse on BitLocker | Install next to a Windows fixture image; Windows still boots |
| T-7.3 | Upgrade test from the previous stable | — | Release pipeline QEMU job | Green on the release candidate |
| T-7.4 | Hardware matrix | — | `docs/club-soda/hardware-checklist.md` + issue template | Four machines pass |
| T-7.5 | `VERSION` and naming | CS2-038 | One file feeds `Release.qml`, `os-release`, `pkgver` and tags | All four agree |
| T-7.6 | Docs and screenshots from the real session | CS2-035 | README generator from T-0.2; rewrite `ARCHITECTURE.md` | Every image has a generator |
| T-7.7 | Optional packages: Darling, LCode toolchains; prototype frozen | CS2-032, CS2-036, CS2-039 | `citronos-darling`, `citronos-developer`; App Store "Experimental" | Base ISO is smaller; LCode installs its tools on demand |
