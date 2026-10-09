# Golden Gate System Settings — 2026-10-09 audit

## Design reference and intended structure

Golden Gate follows the macOS 27 direction: an **edge-to-edge sidebar**
with **colored section icons**, consistent corner radii, full-height native
sidebars, an understated toolbar, **grouped setting rows** with divider
insets, and clear differentiation between selected state and hover state.

Research:

- [Apple HIG — Settings](https://developer.apple.com/design/human-interface-guidelines/settings):
  stable navigation, grouped related controls, restore context, descriptive
  pane titles, standard keyboard accessibility.
- [Apple HIG — Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars):
  familiar symbols, logical groups, compact rows, show/hide sidebar affordance.
- [Apple macOS Desktop & Dock help](https://support.apple.com/en-gb/guide/mac-help/mchlp1119/mac):
  Dock size, launch animation, running indicators, recent apps, snapping,
  windows and desktop settings.
- [Hyprland core config](https://wiki.hypr.land/configuring/core/config-options/):
  native `general.snap` options, resizing border grip and gap values.
- [Hyprland input variables](https://wiki.hypr.land/0.54.0/Configuring/Variables/):
  touchpad taps, drags, scroll speed, clickfinger actions.
- [XDG Autostart specification](https://okellogg.pages.freedesktop.org/xdg-specs/autostart-spec/autostart-spec-latest.html):
  user overrides, `Hidden`, `OnlyShowIn`, and per-user login entries.

**Design principle:** no nonfunctional toggles. Missing OS subsystems should
be explicitly labeled unsupported, not silently represented by a switch
that saves a preference no process reads.

## Current pane/backend inventory

| Area | System/backend | Current status |
| --- | --- | --- |
| Wi-Fi | NetworkManager, `nmcli` | Connected (scan, join, save) |
| Bluetooth | BlueZ | Connected (pair, connect, disconnect) |
| Network | NetworkManager | Connected (status, wired connect/disconnect, Wi-Fi detail route) |
| Battery | UPower and power-profiles-daemon | Connected where hardware/service exists |
| General → About | Hardware/kernel information | Connected |
| General → Software Update | Golden Gate updater, pacman and Flatpak | Connected, privileged flow required |
| General → Storage | Mounted filesystem information | Connected |
| General → Date & Time | timedatectl, region settings | Connected; admin changes require authorization |
| General → Language & Region | Locale records and setup service | Connected |
| General → AirPlay Receiver | Local UxPlay wrapper/service | Connected where installed |
| General → Default Applications | XDG MIME handlers, `xdg-mime` | **New: real installed-handler changes** |
| General → Login Items | XDG autostart, `dex -a -e Hyprland` | **New: persists and launches at next sign-in** |
| Citron Intelligence | Local intelligence backend | Connected where configured |
| Accessibility | GNOME interface and Golden Gate desktop preferences | Connected |
| Appearance | GTK/Qt theme, GSettings, hyprglass sync | **New: live-window refraction control** |
| Control Center | Desktop `menuBar.items` | Connected to Quickshell status items |
| Desktop & Dock | `dock.*` plus `windows.json`/Hyprland | **Expanded: size, indicators, launch, recents, pinning, snapping, resizing** |
| Dock app picker | Quickshell DesktopEntries | **New: add installed apps to persistent Dock** |
| Menu Bar | Desktop preferences | Connected to menu bar clock/status presentation |
| Displays | hyprctl, brightnessctl, hyprsunset | Connected; options gated by hardware |
| Spotlight | Desktop preference categories | Connected to Spotlight |
| Wallpaper | Files/photos, wallpaper helper | Connected to shell |
| Notifications | Per-app choice and shell notification pipeline | Connected |
| Focus | Shared FocusPolicy, desktop prefs | Connected |
| Sound | PipeWire/`wpctl`, desktop alert sounds | Connected |
| Lock Screen | Hypridle `gg-idle`, desktop lock settings | Connected |
| Touch ID | fprintd/PAM | Connected on supported hardware |
| Privacy & Security | Desktop privacy, location services, reports | Connected |
| Users & Groups | System account helpers | Connected, subject to authorization |
| Keyboard | Saved `input.json` and Hyprland `input.conf` | Connected |
| Trackpad & Mouse | Saved `input.json` and Hyprland input | **Expanded: two-finger click, tap-drag, scroll factor, disable typing, drag lock** |

## Settings persistence pipeline

- `Sys.qml` writes desktop preferences through `gg-pref`: atomic nested-key
  updates shared with the shell, Settings, and Control Center.
- For input, privacy, accessibility, and **new windows**, Settings uses
  `set-prefs.py` with a locked read-modify-write of the latest record.
- Changing a trackpad/window property generates the relevant `input.conf`
  or `windows.conf` **and** sends the mapped `hyprctl keyword` command.
- `hyprland.conf` sources these files on every session start. The installer
  creates blank safe defaults when the system is first installed, including
  for already-created `/etc/skel` accounts.
- A failed write or live apply appears in the Settings error panel; the
  control is not advertised as applied when only the preference was saved.
- XDG default handlers are queried and re-queried after `xdg-mime default`.
  Login items edit `~/.config/autostart/*.desktop` and are launched next
  sign-in by `dex`, with the same XDG precedence as other Linux desktops.

## Features requiring separate backend work

These are not represented as fake functional controls:

- Apple ID, iCloud Keychain, Find My, Apple Continuity/Handoff protocol.
- Genuine Apple FaceTime call initiation and Apple's proprietary call services.
- Apple-native Stage Manager / Universal Control / Sidecar / AirDrop peer
  compatibility, beyond Golden Gate's independently implemented equivalents.
- Per-app camera/microphone permissions for every native process without
  portal/sandbox support (browser website permissions remain available).
- Full Mission Control behavior settings if the compositor does not expose
  the corresponding behavior.
- Hardware-exclusive controls (Touch ID, internal battery, Night Shift)
  on machines without the required device or service.

## Regression gate

`python tests/settings-connectivity.py` covers the saved window/input record
and live wiring, including malicious config input and concurrent-key
preservation. `python tests/settings-app-preferences.py` covers MIME handler
changes and login-item enable/disable, including rejection of malicious
desktop IDs. Both run in GitHub Actions alongside QML parsing and the native
UI preview harness.

**Hardware checks still required:** UI layout at 720p/1080p/HiDPI,
real QML scroll performance, Hyprland keyword application after changing
window settings, Bluetooth/NetworkManager/PipeWire device switching, and
the Settings updater's merge behavior on an existing installed account.
