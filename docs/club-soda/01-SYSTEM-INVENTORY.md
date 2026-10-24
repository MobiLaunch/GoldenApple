# CitronOS 2 "Club Soda": System Inventory

Inventory of commit `ae8cbf4` (2026-10-21; "CitronOS Sprite 3.5" in
`apps/lib/theme/Release.qml`). Statuses come from reading the code and running the tests
in a container without a GPU or Wayland session (see
[03-BACKEND-AUDIT.md](03-BACKEND-AUDIT.md#how-this-was-checked-and-what-wasnt)).

**Key**

| Column | Values |
|---|---|
| Impl. | **Done**: the advertised scope is implemented · **Partial**: core works, important parts missing · **Stub**: UI with little or no back end · **Missing** |
| Works | **Tests pass**: covered by passing tests here · **Defect**: a finding says it's broken or unsafe · **Unverified**: no test, or not testable without hardware |
| Integration | How completely it uses the real system service (High / Medium / Low) |
| UI | Consistency with the shared design system (High / Medium / Low) |
| Tests | Main test files in `tests/` |

## 1. Architecture at a glance

```
 Boot:  systemd-boot → Arch kernel → getty autologin (live) / SDDM (installed)
 Login: gg-session (sh) → start-hyprland/Hyprland
          └─ exec-once: gsettings defaults, keyring, gg-apply-preferences, icon resolver,
             dex autostart, [sh loop] qs -c golden-gate, keyd mapper, polkit agent,
             hypridle, [sh loop] airdropd, AirPlay unit, Setup Assistant (first login),
             crash-watch
 Shell: ONE Quickshell process: menu bar, Dock, Launchpad, Control Center, Spotlight,
        Mission Control, Notifications (server), Lock screen, OSD, widgets, Tablet Home,
        Citron voice, CitronPods card, pairing card, screenshots
 Apps:  separate `qs -p apps/<app>.qml` processes (Quickshell as an app runtime), each
        with short-lived or long-lived Python helpers speaking JSON lines; Web is
        PySide6 + Qt WebEngine
 State: ~/.config/golden-gate/*.json (desktop.json for most preferences), Secret Service
        for secrets, ~/.local/state/golden-gate for app state
 Update: Settings → update-helper.py (pkexec) → pacman -Syu + flatpak + git snapshot
         of the CitronOS repo → scripts/install.sh --system
```

Main IPC paths: `qs -c golden-gate ipc call <target> <fn>` (CLI into the shell), file
watches on JSON files, JSON lines over stdin/stdout between QML and its helpers, and D-Bus
only where a library already provides it (PipeWire, MPRIS, UPower, BlueZ reads,
notifications, PAM). There are **no CitronOS-owned D-Bus services**.

## 2. Desktop shell (`shell/`, 16.5k lines of QML)

| Component | File(s) | Impl. | Works | Integration | UI | Tests | Notes / findings |
|---|---|---|---|---|---|---|---|
| Menu bar | `MenuBar.qml` | Done | Tests pass | High (Hyprland IPC, wallpaper sampling) | High | `menu-bar`, `menubar-room`, `menu-popup` | Over fullscreen windows: CS2-008 |
| Dock | `Dock.qml` | Done | Tests pass | High (toplevels, desktop entries) | High | `dock-drag`, `dock-lifecycle`, `dock-motion`, `dock-running` | No auto-hide or position: CS2-034. No third-party badges: CS2-024 |
| Launchpad | `Applications.qml` | Done | **Defect** | High | High | `launchpad-folders`, `qml-load` | Async icon crash: CS2-004. Always mapped: CS2-025 |
| Control Center | `ControlCenter.qml` | Done | **Defect** | Medium (PipeWire native; Wi-Fi and BT through CLIs) | High | `control-center` | SSID injection: CS2-002. CLI spawns: CS2-026 |
| Spotlight | `Spotlight.qml`, `spotlight/answers.js` | Partial | Tests pass | Low (`find` for files) | Medium | `system-settings` (pane search), `logic.mjs` (not in CI) | No index or content search: CS2-022 |
| Notifications and Notification Center | `Notifications.qml` | Done | Tests pass | Medium (in-process server) | High | `notification-banners`, `notification-settings` | Not persisted, no badge API: CS2-024 |
| Mission Control / App Exposé / Spaces | `MissionControl.qml` | Done | Tests pass | High | High | `missioncontrol` | — |
| App switcher (⌘Tab) | `Switcher.qml` | Done | Unverified | High (global shortcuts) | High | — | The only surface using Hyprland `global` binds (CS2-021) |
| Lock screen | `LockScreen.qml`, `components/LockSurface.qml` | Done | **Defect** | High (ext-session-lock, PAM, fprintd) | High | `lock-screen`, `touchid` | Crash while locked → stuck: CS2-005 |
| OSD (volume, brightness) | `Osd.qml` | Done | Unverified | High | High | — | — |
| Desktop widgets | `DesktopWidgets.qml`, `widgets/` | Done | Tests pass | Medium (weather, notes, calendar feeds) | High | `desktop-widgets` | Accessibility: CS2-013 |
| Tablet Home Screen | `TabletHome.qml` | Done | **Defect** | Medium | High | `tablet-home.mjs`, `tablet-app-interfaces` | Async icons: CS2-004. Always built: CS2-025 |
| Screenshots and recording (⇧⌘3/4/5) | `Screenshot.qml` | Done | Tests pass | High (grim, slurp, wf-recorder) | High | `screenshot` | — |
| Session dialog (log out, restart, shut down) | `SessionDialog.qml` | Done | Unverified | High (logind) | High | — | — |
| Citron voice overlay | `VoiceAssistant.qml` | Done | Tests pass | Medium | High | `intelligence-live`, `intelligence-shell-visuals` | Single provider: CS2-028 |
| CitronPods card | `CitronPodsPopup.qml` | Partial | Unverified | Medium (needs engine) | High | `citronpods-*` | Engine build: CS2-029 |
| Nearby pairing card | `Nearby.qml` | Done | Tests pass | Medium | High | `nearby` | — |
| Privacy indicators | `components/Privacy.qml`, `apps/lib/privacy/monitor.py` | Done | Tests pass | High (live `pw-dump --monitor`) | High | `privacy` | No per-app control: CS2-031 |
| Liquid Glass (shell) | `apps/lib/Glass.qml`, `components/DesktopBackdrop.qml`, HyprGlass | Done | Unverified | High | High | `glass-gpu`, `glass-lens`, `glass-reactions`, `liquid-glass` | Live capture cost: CS2-007. Plugin ABI: CS2-009 |
| Minimise / hide | `shell.qml` (special workspaces) | Done | Unverified | Medium (emulated) | — | `window-fold` | Hyprland has no native minimise |
| Wallpaper | `Wallpaper.qml`, `apps/lib/set-wallpaper.py` | Done | Tests pass | High | High | `wallpaper` | — |

## 3. Window management (`compositor/hyprland/`)

| Component | Impl. | Works | Notes |
|---|---|---|---|
| Floating, centred windows | Done | Tests pass (`window-placement.mjs`, `window-open`) | Every window floats; placement is biased up 28 px for the Dock |
| Tiling (Move & Resize, ⌃⌥ keys) | Done | Tests pass (`tiling`, `tile-layout`) | `gg-tile` (`tile.py`) |
| Snapping | Done | Unverified | Native Hyprland `snap {}` |
| Title bars for non-CitronOS apps | Done | Tests pass (`titlebars`) | `hyprbars`, built per Hyprland |
| Workspaces and gestures | Done | Unverified | 3- and 4-finger gestures; Mission Control through `qs ipc` |
| Fullscreen | Partial | **Defect** | Shell surfaces stay on top: CS2-008 |
| Multi-monitor | Partial | Unverified | Shell surfaces per screen through `Variants`; Displays pane writes `displays.conf`; no hot-plug test |
| ⌘ key layer | Done | Unverified | keyd maps ⌘+letter to Ctrl+letter |

## 4. Applications (`apps/`)

| App | Main files | Impl. | Works | Integration | UI | Tests | Notes / findings |
|---|---|---|---|---|---|---|---|
| Files | `files.qml` (2,038), `files/helper.py` | Done | Tests pass | High (gio trash, udisks) | High | `files-helper`, `files-workflow`, `files-interactions`, `files-disks`, `quicklook` | Monolith: CS2-019. No network locations (SMB/SFTP) found |
| Web | `browser/` (Browser.qml 3,157) | Done | Tests pass in CI (refuses root here) | High (Qt WebEngine, keyring) | High | `native-browser`, `browser-*`, `web-diagnose` | Monolith: CS2-019. No extensions, sync or printing (README) |
| Mail | `mail.qml`, `mail/helper.py` | **Partial** | Tests pass | Low | High | `mail-connect`, `mail-drafts`, `mail-layout`, `mail-categories-badges` | INBOX only, one account, no OAuth: CS2-015 |
| Messages | `messages.qml`, `messages/` + BlueFerry | Partial | Tests pass | Medium (BlueFerry over BT) | High | `messages-media` | Needs a paired iPhone. Media through an optional Mac relay |
| Calendar | `calendar.qml`, `calendar/` | Partial | Tests pass | Medium | High | `calendar-store`, `calendar-reminders`, `calendar-caldav`, `calendar-recurrence.mjs` | CalDAV read-only: CS2-042 |
| Photos | `photos.qml`, `photos/` | Partial | Unverified | Medium (folders) | High | — | Library is ~/Pictures and ~/Videos. Editing only through Citron. No crop, rotate, import or albums sync found |
| Music | `music.qml`, `music/` | Done | Tests pass | High (MPRIS) | High | `music-workflow`, `music-playlists`, `music-ui` | Local files only |
| Notes | `notes.qml`, `notes/` | Done | Tests pass | Medium (Markdown files) | High | `notes-trash`, `notes-conflicts` | — |
| Maps | `maps.qml`, `maps/` | Done | Tests pass | Medium (online tiles and routing) | Medium | `maps` | Accessibility: CS2-013 |
| Weather | `weather.qml`, `weather/` | Done | Tests pass | Medium (Open-Meteo, CARTO) | High | `weather` | — |
| Clock | `clock.qml`, `clock/helper.py` | Done | Tests pass | High (systemd timers) | High | `clock-helper` | — |
| Calculator | `calculator.qml` | Done | Tests pass | — | Medium | `calculator` | Accessibility: CS2-013 |
| TextEdit | `textedit.qml`, `textedit/helper.py` | Done | Tests pass | Medium | High | `intelligence-ui` | — |
| Passwords | `passwords.qml`, `passwords/helper.py` | Done | Tests pass | High (Secret Service) | High | `passwords-app` | — |
| App Store | `software.qml`, `software/` | Done | Tests pass | High (Flatpak) | High | `app-store`, `mac-apps`, `darling-setup` | Mac Apps unsandboxed: CS2-032. No permissions view: CS2-031 |
| System Settings | `settings.qml`, `settings/` (34 panes) | Done (thin in places) | Tests pass | Medium–High | High | `settings-*`, `system-settings`, `region-settings`, `displays-scale`, `text-size` | Users: CS2-027. Accessibility: CS2-013. Wi-Fi: CS2-016. Bluetooth: CS2-014 |
| Software Update | `settings/panes/UpdatePane.qml`, `update-helper.py`, `golden_update.py` | Done | Tests pass | — | High | `golden-update`, `update-keyring`, `update-outcomes` | **CS2-001, CS2-003** |
| Disk Utility | `diskutility.qml`, `lib/disks/` | Done | Tests pass | High (udisks2) | High | `disks`, `disk-utility` | — |
| Archive Utility | `archive.qml`, `archive/helper.py` | Done | Tests pass | Medium | High | `archive-utility` | — |
| AirDrop | `airdrop.qml`, `airdrop/airdropd.py` | Done | Tests pass | Medium (LocalSend protocol) | High | `airdrop` | Exposed by default: CS2-017 |
| Screen Mirroring / AirPlay | `mirroring/`, `gg-airplay.service` | Partial | Tests pass | Medium (UxPlay, gnome-network-displays) | Medium | `airplay-receiver` | — |
| Terminal | Ghostty (`themes/ghostty`) | Done | — | — | Medium | — | Third-party |
| LCode (IDE) | `lcode.qml`, `lcode/` | Done (no debugger) | Tests pass | Medium | High | `lcode` | Pulls developer tools into the base image: CS2-039 |
| Setup Assistant | `setup.qml`, `setup/` | Done | Tests pass | High | High | `setup-browser`, `setup-finish` | — |
| Installer | `installer.qml`, `installer/helper.py` | Partial | Tests pass | High | High | `installer-*` | No encryption, swap or dual boot: CS2-012 |
| Citron Intelligence | `apps/lib/intelligence/` | Partial | Tests pass | Low (Gemini only) | High | `intelligence*` | CS2-028 |
| CitronPods | `apps/citronpods/` | Partial | Unverified | Medium | High | `citronpods-*` | CS2-029 |
| **Contacts** | — | **Missing** | — | — | — | — | Needed by Messages, Mail, AirDrop "Contacts only" |
| **Reminders** | — | **Missing** | — | — | — | — | Calendar has reminders. No task app |
| **Preview** (PDF and images) | — | **Missing** | — | — | — | — | No PDF viewer in the image (Quick Look aside) |
| **Activity Monitor** | — | **Missing** | — | — | — | — | No process or energy viewer |
| **Backup** (Time Machine style) | — | **Missing** | — | — | — | — | No backup or restore anywhere |

## 5. System services and integration

| Domain | Back end used | Impl. | Notes |
|---|---|---|---|
| Networking | NetworkManager through `nmcli` text | Partial | No D-Bus. No VPN set-up or 802.1X. Password on argv: CS2-016 |
| Bluetooth | BlueZ: D-Bus reads (shell), `bluetoothctl` writes and pairing (Settings) | Partial | No pairing agent: CS2-014 |
| Audio | PipeWire (`Quickshell.Services.Pipewire`), `wpctl` keys | Done | The model to follow |
| Media keys / Now Playing | MPRIS, `playerctl` | Done | — |
| Display | `hyprctl keyword monitor`, `displays.conf`, revert watchdog | Done | `displays-scale` test |
| Brightness | `brightnessctl` (process per change) | Done | CS2-026 |
| Night Shift | `hyprsunset` | Done | — |
| Power | UPower, power-profiles-daemon, hypridle, logind | Done | — |
| Storage | udisks2 | Done | — |
| Authentication | PAM (`login`), fprintd (`gg-touchid`), polkit-gnome agent, gnome-keyring | Done | Passwordless polkit rule: CS2-001 |
| Accounts | `useradd` in the installer, `getent` in Settings | Partial | No accountsservice: CS2-027 |
| Packages | pacman (`-Syu` through the helper), Flatpak (user) | Done | CitronOS itself isn't packaged: CS2-011 |
| Updates | GitHub branch snapshot + `install.sh` | **Defect** | CS2-003 |
| Notifications | In-shell `NotificationServer` | Partial | CS2-024 |
| Search | `find`, desktop entries, Settings pane list | Partial | CS2-022 |
| Preferences | `desktop.json` + `gg-pref`, gsettings for GNOME keys | Done | CS2-023 |
| Accessibility | Theme flags only | **Partial (minimal)** | CS2-013 |
| Firewall | — | **Missing** | CS2-017 |
| Backups / snapshots | — | **Missing** | CS2-012 |

## 6. Boot, install and release

| Component | Path | Impl. | Notes |
|---|---|---|---|
| ISO build | `distro/archiso/build.sh` | Done | Not reproducible: CS2-010. HyprGlass pin: CS2-009 |
| ISO boot test | `.github/workflows/boot-test.yml`, `distro/archiso/boot-test.sh` | Done | QEMU, plain VGA |
| Bootloader | systemd-boot | Done | UEFI only |
| Login | SDDM theme (`themes/sddm`) | Done | `sddm-theme` test |
| Boot splash | Plymouth (`themes/plymouth`) | Done | — |
| First run | Setup Assistant | Done | — |
| Install to disk | Installer | Partial | CS2-012 |
| Offline update | `scripts/make-update-bundle.sh`, `gg-update-disk` | Done | Unsigned: CS2-003 |
| Diagnostics | `gg-diagnostics`, `crash-watch.sh` | Done | Opens a prefilled GitHub issue. Polling: CS2-040 |

## 7. Design and theming

| Component | Path | Impl. | Notes |
|---|---|---|---|
| Tokens | `design/tokens.json` → `build.mjs` | Done | Used inconsistently: CS2-018, CS2-043 |
| Shared QML components | `apps/lib/` | Done | Gaps listed in [02 §4](02-UI-UX-AUDIT.md#4-proposed-shared-components-additions-to-appslib) |
| Icons | `icons/` (GoldenGate theme, OrchardKit symbols, icon resolver) | Done | — |
| GTK theme | `design/gtk`, `design/dist/gtk.css` | Done | Not applied to Flatpaks: CS2-030 |
| Fonts | `themes/fontconfig` (Golden Gate UI → Inter) | Done | — |
| Reference prototype | `prototype/` | Done (frozen?) | Duplicate implementation: CS2-036 |

## 8. Tooling and tests

- **135 test files** (Python and Node); 134 are wired into the 9 GitHub workflows. In
  this audit's baseline, 125 passed and 10 failed for environmental reasons only (Darling
  source not supplied, run as root, generated symbols not built). See
  [03](03-BACKEND-AUDIT.md#test-baseline).
- `tools/preview/preview.py`: a PySide6 harness that loads shell and app QML with
  Quickshell stubs (no Wayland needed). It backs `qml-load` and `check-qml`.
- CI jobs: `generated` (tokens and icons, about 80 string guards, a staged install), `ui`
  (Playwright on the prototype), `native-controls`, `browser-and-setup`, ISO build, ISO boot
  test, Darling builds, GTK theme.
- **Missing:** a real-session test (Hyprland + Quickshell) with crash detection; performance
  budgets; security lints; upgrade testing from the previous release; hardware matrix.
