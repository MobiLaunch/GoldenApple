# CitronOS 2 "Club Soda": Roadmap

Milestones follow the brief's M0–M7 structure, re-ordered by risk and dependency. Each
milestone lists its scope (backlog task IDs from [07](07-IMPLEMENTATION-BACKLOG.md)), its
dependencies, and **measurable exit criteria**. Stability work, visual refinement and new
capability are kept in separate tracks so a delay in one doesn't hold up the others.

```
            ┌ M0 ┐┌──── M1 ────┐┌──────── M2 ────────┐┌──────── M3 ────────┐
 Trust      │base││ P0 + supvsn ││ packages + signing  ││ snapshots + channels │
 Platform   │line││             ││ settingsd, notifyd  ││ networkd, btd, searchd│──► M4 integrations
 Design     │    ││ AppIcon     ││ tokens + lint (M2)  ││ shell refinement (M3)│
 Apps       │    ││             ││                     ││ accounts back end    │──► M5 app maturity
 Ecosystem  │    ││             ││                     ││                      │──► M6 Citron/peripherals
 Release    │    ││ session CI  ││ reproducible ISO    ││ upgrade tests        │──► M7 hardening, RC
```

Durations assume one or two full-time contributors (people or agents) with review, and are
indicative only.

---

## M0: Audit and baseline (this document set) · done except T-0.3

**Scope:** inventory, findings, architecture and roadmap (docs 01–08). T-0.1 recorded the
test baseline. T-0.2 built the session harness. T-0.3 (performance baseline) carries over
into M1.
**Exit criteria:**
- [x] Every major subsystem is inspected or explicitly marked "not testable here".
- [x] Test baseline recorded: 125 pass, 10 environmental, 0 real failures.
- [x] T-0.2: a real-session harness runs in CI and captures every shell surface.
- [ ] T-0.3: a performance baseline is recorded (start-up time, idle CPU and RSS, glass
  on and off) on at least a VM and one Intel laptop.

## M1: Trust and stability · about 3 weeks · **done**

The highest-value first milestone: it closes the three P0 security problems and the main
crash and stuck-session paths. Every task is small or medium, and none needs the larger
re-architecture.

**Scope:** T-1.1 to T-1.10. These are: the SSID injection, split polkit actions, signed
update bundles and a release channel, the async-icon crash fix, the lock-screen
separation, systemd user units, Wi-Fi password off argv, AirDrop off by default plus a
firewall, Prefs write errors, and security lints.
**Depends on:** nothing.
**Status:** T-1.1 to T-1.10 are built and tested in CI. See the "As built" notes in
[07](07-IMPLEMENTATION-BACKLOG.md). **All exit criteria are met.** The session harness
(T-0.2) checks the cold starts, the lock kills and AirDrop's port; the rest is checked on
the ISO itself: its boot test boots with `gg.selftest`, and the live session checks its
units, safe mode, the firewall zones and the lock screen under systemd and Hyprland
(`distro/archiso/selftest/`). Its first run found two bugs, both fixed: one shell crash
started safe mode, and networks never got their zone.
**Exit criteria:**
- [x] `tests/security-lint.py` passes: no shell strings built from data, no passwordless
  action that runs downloaded code, no secrets on argv.
- [x] `pkexec update-helper set-source` asks for a password. An update bundle that isn't
  signed by the release key is refused.
- [x] 20 of 20 cold starts in the session harness with no Quickshell crash report.
- [x] Killing the lock process while locked gives a working lock screen within 3 s, 5 of 5
  times (about 2 s each in CI).
- [x] `systemctl --user status citronos-shell` is active, and five kills in 60 s end in safe
  mode (the boot test's self-test, on the ISO).
- [x] `ss -lntup` shows no AirDrop listener after login on a "public" connection. (Nothing
  listens with receiving off, a new account's default, in the harness and on the ISO; and on
  the ISO the public zone keeps AirDrop and AirPlay out, while the wired network is home.)

## M2: Platform foundations and design system · about 6 weeks

Two tracks in parallel.

**Platform track (T-2.1 to T-2.6):**
- PKGBUILDs and a signed `[citronos]` repository;
- a reproducible ISO from a pinned Arch Linux Archive date;
- Hyprland and HyprGlass in lock-step;
- the `citronos` Python package;
- `citronos-settingsd`;
- `citronos-notifyd` with the LauncherEntry API.

**Design track (T-2.7 to T-2.11):**
- role tokens (type, radius, colour, motion);
- the design lint with a shrinking baseline;
- the new shared components;
- migration of the six worst files;
- Accessible annotations on all shell surfaces.

**Depends on:** M1 (lints, session harness).
**Status:** the platform track has begun with the `citronos` Python package (T-2.4).
The design track: the design lint (T-2.8), role tokens (T-2.7)
and the shell's accessibility annotations (T-2.11) are built, and the migration (T-2.10)
has moved the type ramp and all six of the worst files (the lock screen, Calculator,
Settings, Web, Maps and Citron) onto roles; see [07](07-IMPLEMENTATION-BACKLOG.md). Lint
numbers now: radius 399, duration 126, colour 1,055, `fs()` 87; pointer handlers without
annotations 162 (0 in `shell/`).
**Exit criteria:**
- `pacman -Qkk citronos-*` is clean on an ISO install, and `install.sh` is used only for
  development.
- Two CI ISO builds of the same commit produce identical package manifests.
- A notification survives a shell restart, and an Electron app's badge appears on the Dock.
- Design lint numbers:

  | Measure | Target |
  |---|---|
  | literal radii | ≤ 40 (from 426) |
  | literal durations | ≤ 30 (from 198) |
  | literal colours | ≤ 600 (from 1,586) |

- Screenshot review shows no regressions in light or dark.
- No `fs(n)` call sites remain. Text Size 85 % to 150 % passes the screenshot tests.

## M3: Desktop refinement · about 4 weeks

**Scope (T-3.1 to T-3.8):**
- the Dock and menu bar hide in fullscreen, and the Dock gets auto-hide, position and
  display settings;
- the glass window lens becomes opt-in and captures on damage;
- Launchpad and Tablet Home are built lazily;
- GlobalShortcuts replace `qs ipc` for shell keys;
- Spotlight runs on `citronos-searchd` with localsearch;
- Control Center gets an inline Wi-Fi prompt;
- the large QML files are split;
- the motion system is applied to every shell surface.

**Depends on:** M2 (tokens and settingsd), plus `citronos-networkd` from M4 for the inline
Wi-Fi prompt. That task may slip into M4.
**Exit criteria:**
- `mpv --fs` shows no shell pixels.
- The shell's idle CPU is under 1 % with one window behind the Dock (on the T-0.3 laptop).
- Median time from keypress to the first Spotlight frame is under 50 ms (240 fps video).
- A seven-level-deep file is found by a word in its contents.
- No QML file in `apps/` or `shell/` is over 800 lines.
- In a 60-frame presentation of Control Center, Spotlight and Mission Control, no frame is
  dropped on the reference laptop.

## M4: Native integrations · about 6 weeks

**Scope (T-4.1 to T-4.8):**
- `citronos-networkd` (VPN import, 802.1X, captive portal, secret agent);
- `citronos-bluetoothd` with a pairing agent;
- logind brightness;
- Users & Groups through accountsservice;
- per-app permissions;
- per-app systemd scopes;
- the accessibility foundation (Orca, Zoom, Increase Contrast, pointer size, key aids);
- firewall zones in Settings.

**Depends on:** M1 (units) and M2 (settingsd, the Python package).
**Exit criteria:**
- Pair a passkey keyboard and a phone.
- Import and connect a WireGuard config.
- Join a PEAP network in a test lab, or with `hostapd` in CI.
- Create, promote and delete a user with no terminal.
- Revoke an app's camera access and see the portal deny it.
- Do the Orca walkthrough of Dock → Files → Spotlight → a notification, by keyboard only.
- `execsnoop` shows no processes started by Control Center interactions.

## M5: Application maturity · about 8 weeks

**Scope (T-5.1 to T-5.7):**
- Internet Accounts (GOA);
- Calendar and Contacts on EDS (read and write);
- the new Contacts app;
- the Mail engine upgrade (OAuth, IDLE, cache, folders, attachments, Sent, threading);
- the Preview app (PDF);
- network locations in Files;
- Activity Monitor.

**Depends on:** M4 (scopes for Activity Monitor), M2 (notifyd for Mail badges).
**Exit criteria:**
- Gmail and Outlook through OAuth: read, reply with an attachment, and the reply threads
  correctly in a second client.
- The unread badge updates with Mail closed.
- A CalDAV event is created and edited and appears in a second client.
- A 300-page PDF opens in under 1 s.
- Connect to an SMB share and copy a 1 GB file with progress and cancel.
- Activity Monitor shows per-app CPU and memory, and can quit an app.

## M6: Intelligence and ecosystem · about 6 weeks

**Scope (T-6.1 to T-6.6):**
- `citronos-intelligd` with the provider interface (Gemini, OpenAI-compatible, Ollama);
- the tool registry with confirmations and an audit log;
- the first tool set (search, open app, settings toggles, calendar event);
- notification and document summaries (opt-in);
- the peripheral framework, with CitronPods packaged and as one provider;
- clipboard history.

**Depends on:** M3 (search), M4 (bluetoothd, network), M5 (accounts for calendar tools).
**Exit criteria:**
- The same Writing Tools task succeeds with Gemini and with a local Ollama model.
- Every write tool has a test that proves it can't run without confirmation, and the
  red-team prompt suite passes.
- AirPods pair and show battery on a fresh install with no ZIP or compiler.
- Clipboard history never stores items marked by a password manager.

## M7: Release engineering and hardening · about 4 weeks, then the release candidate

**Scope (T-7.1 to T-7.7):**
- installer encryption (LUKS2), zram and btrfs with snapshots, plus rollback in the boot
  menu;
- install alongside Windows;
- the upgrade test from the previous stable release;
- a hardware matrix checklist;
- the `VERSION` file, version naming and `os-release`;
- docs and screenshots regenerated from the real session;
- the prototype frozen and Darling and LCode made optional packages.

**Depends on:** all of the above.
**Exit criteria (release gates):**
- Zero open P0 or P1 findings.
- Clean installs pass on the four hardware-matrix machines, with encryption on.
- An upgrade from the previous stable release passes, and so does a forced failed upgrade
  that is rolled back from the boot menu.
- The ISO build is reproducible: two builds give the same manifest.
- `os-release`, About This Computer, `pacman -Q citronos` and the git tag agree.
- Every README screenshot comes from the session harness.

---

## Version: decided

Club Soda is **CitronOS 4.0** (`apps/lib/theme/Release.qml`: release "Club Soda",
version "4.0"; `os-release` codename `club-soda`). Releases are tagged `v4.0.x`, and
betas `v4.1.0-beta.n` once 4.1 begins (CS2-038).

## Tracks at a glance

| Track | M1 | M2 | M3 | M4 | M5 | M6 | M7 |
|---|---|---|---|---|---|---|---|
| Stability and security | ●●● | ●● | ● | ●● | ● | ● | ●●● |
| Visual refinement | ● | ●●● | ●●● | ● | ● | ● | ● |
| New capability | — | ● | ● | ●● | ●●● | ●●● | ● |
