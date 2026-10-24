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

### T-0.2: Real-session harness
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

### T-1.1: Remove shell-string injection from Control Center (CS2-002) · **P0** · S
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

### T-1.2: Split the privileged update actions (CS2-001) · **P0** · S
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

### T-1.3: Signed update bundles and a release channel (CS2-003) · **P0** · M
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

### T-1.4: Theme-icon crash fix and `AppIcon` (CS2-004) · **P1** · S
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

### T-1.5: Separate lock-screen process with restore (CS2-005) · **P1** · M
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

### T-1.6: systemd user units for the session (CS2-006) · **P1** · M
- **Files:** new `distro/systemd/user/citronos-session.target`, `citronos-shell.service`,
  `citronos-shell-safe.service`, `citronos-airdrop.service`, `citronos-icon-resolver.service`;
  `compositor/hyprland/hyprland.conf:41-56` (replace the loops with
  `exec-once = systemctl --user start citronos-session.target`);
  `distro/archiso/overlay/usr/local/bin/gg-session` (import the environment); `shell/shell.qml`
  (honour `GG_SAFE=1`: no `DesktopBackdrop` windows, no widgets, no Citron).
- **Changes:**
  - `Restart=on-failure`, `RestartSec=1`, `StartLimitIntervalSec=60`, `StartLimitBurst=5`,
    `OnFailure=citronos-shell-safe.service`.
  - `StandardOutput=journal`.
  - Remove the home-made log rotation.
- **Tests:** extend `tests/shell-supervisor.py` to parse the units and assert the
  restart policy. Add a session-harness case where five kills lead to safe mode and a
  notification.
- **Done when:** `systemctl --user list-units 'citronos-*'` shows them active on the ISO.

### T-1.7: Keep Wi-Fi passwords off argv (CS2-016, interim) · **P2** · S
- **Files:** `apps/settings/panes/WifiPane.qml:44-51`; a new `gg-wifi-join` mode
  `--password-stdin`.
- **Changes:** Settings runs `["gg-wifi-join", "--password-stdin", ssid]` and writes the
  password to stdin. The helper uses `nmcli … passwd-file /dev/stdin`, or builds a
  connection with `nmcli connection add … wifi-sec.psk` read from stdin through Python's
  `subprocess` input.
- **Tests:** a stub `nmcli` that records argv and stdin. Assert the password never appears
  in argv.
- **Done when:** the test passes, and a `ps` loop during a real join shows no password.

### T-1.8: AirDrop off by default, and a firewall (CS2-017) · **P2** · S
- **Files:** `apps/airdrop/airdropd.py:319-345` (default `"off"`, remove the HTTP
  fallback, add "everyone for 10 minutes" with an expiry); `apps/airdrop.qml` (UI for
  that); `distro/archiso/packages.x86_64` (+`firewalld`); new
  `distro/archiso/overlay/etc/firewalld/services/citronos-airdrop.xml`; `apply-preferences.sh`
  (map NM connections to zones: `home` for private, `public` for the rest).
- **Tests:** extend `tests/airdrop.py`. A fresh settings file means not discoverable and
  no listener. "Everyone for 10 minutes" turns it on and it expires (with an injected
  clock). Plain HTTP is never used.
- **Done when:** `ss -lntup` on a fresh login shows no 53317 listener.

### T-1.9: Report preference-write failures in the shell (CS2-023, interim) · **P2** · S
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

### T-1.10: Security lints (CS2-001, CS2-002, CS2-016) · S
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
