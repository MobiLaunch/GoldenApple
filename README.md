# Golden Gate

A Linux distribution with a Liquid Glass desktop: translucent glass materials,
spring motion, a floating Control Center, a magnifying Dock, Spotlight, and
Finder-style Files, modelled closely on the macOS "Golden Gate" design language
and built entirely from original artwork.

![Files, light](docs/screenshots/files-light.jpg)

| | |
|---|---|
| ![Control Center](docs/screenshots/control-center.jpg) | ![Dark mode and context menu](docs/screenshots/files-dark-menu.jpg) |
| ![Mission Control](docs/screenshots/mission-control.jpg) | ![Spotlight](docs/screenshots/spotlight.jpg) |
| ![Maps](docs/screenshots/maps.jpg) | ![Weather](docs/screenshots/weather.jpg) |
| ![Music, dark](docs/screenshots/music.jpg) | ![System Settings](docs/screenshots/settings.jpg) |
| ![Mail](docs/screenshots/mail.jpg) | ![Calendar](docs/screenshots/calendar.jpg) |
| ![Lock screen](docs/screenshots/lock.jpg) | ![Control Center detail](docs/screenshots/control-center-detail.jpg) |

**The real Linux shell** (Quickshell, captured in a headless Wayland session):

| | |
|---|---|
| ![Desktop](docs/screenshots/shell-desktop.jpg) | ![Control Center](docs/screenshots/shell-control-center.jpg) |
| ![Notification](docs/screenshots/shell-notification.jpg) | ![Lock screen](docs/screenshots/shell-lock.jpg) |

**The live ISO**, booted in QEMU with plain VGA graphics and no 3D acceleration
(from the automatic boot test that runs after every ISO build):

![Golden Gate ISO booted in QEMU](docs/screenshots/iso-boot-qemu.jpg)

## What's here

| Layer | Path | Status |
|---|---|---|
| **Design tokens**: materials, colour, type, radii, spring physics | `design/` | Done. One JSON compiles to CSS, QML, GTK and Hyprland config |
| **Icons**: first-party app icons, file/place icons and shared symbols | `icons/` | Done. One generated freedesktop theme plus optional imported artwork; [bring your own](icons/custom/README.md) |
| **Reference shell**: the desktop interaction/design reference, interactive in the browser | `prototype/` | Kept as a design reference; the live QML desktop is authoritative for native functionality |
| **Linux shell**: menu bar, Control Center, Dock, Applications, Spotlight, notifications, app switcher, lock screen | `shell/` | Quickshell (QML), tested on the live ISO and real Intel/i915 hardware as well as VM/headless sessions |
| **Compositor**: blur, refraction, squircle corners, springs, key bindings | `compositor/` | Hyprland + HyprGlass; the ISO bundles a Hyprland-version-matched plugin and Golden Gate applies its presets per shell surface |
| **Shared UI**: AppWindow, Glass, buttons, fields, switches, sliders, progress, sidebars, motion and symbols | `apps/lib/` | One canonical QML component store, consumed by apps, shell adapters, Setup and SDDM; Web has a centralized Qt adapter around its isolated Chromium process |
| **Golden Gate apps**: Files, Web, Mail, Messages, Maps, Photos, Music, Calendar, Notes, Weather, App Store, Settings, Clock, TextEdit, Calculator and Installer | `apps/` | First-party frontends use the shared component store; mature backends such as Qt WebEngine, Flatpak, IMAP/SMTP, Matrix and Ghostty remain isolated behind Golden Gate UI |
| **LCode**: an Xcode-style IDE for Swift on Linux: Welcome window, project navigator, tabbed editor with Xcode syntax colours, minimap and inline issues, Run/Stop and scheme ▸ destination pills, activity view, debug console, inspectors, Open Quickly, Find in Project, and a Simulator that runs the built app inside a device frame | `apps/lcode.qml`, `apps/lcode/` | Swift packages (SwiftCrossUI app, command-line tool, library) build, test and run; no debugger or code completion yet |
| **System Settings**: a near copy of macOS System Settings (glass sidebar with search suggestions, back and forward, grouped panes) that changes the real system: Wi-Fi, Bluetooth, Network, Battery, General (About, Software Update, Storage, Date & Time, Language & Region), Accessibility, Appearance (mode, accent, Liquid Glass clear or tinted), Desktop & Dock, Displays, Wallpaper, Focus, Sound, Privacy & Security, Users & Groups, Keyboard, Trackpad & Mouse | `apps/settings.qml`, `apps/settings/` | Done; `gg-settings [pane]` and `gnome-control-center [panel]` open it at a pane |
| **Setup Assistant**: the first-login hello and shared Golden Gate controls over the HyprGlass desktop material, then local account creation, country or region, Wi-Fi, Data & Privacy, Location Services, time zone, crash and diagnostics sharing, and Choose Your Look | `apps/setup.qml`, `apps/setup/` | Done; runs once (`~/.config/golden-gate/setup-done`), `gg.nosetup` on the kernel command line skips it |
| **Theming**: fonts, ⌘ key layer, login screen, boot splash, terminal | `themes/` | Done: fontconfig, keyd, SDDM theme, Plymouth theme, Ghostty |
| **Distro**: bootable live ISO + graphical installer | `distro/archiso/`, `apps/installer*` | Boots on real hardware; native installer performs UEFI preflight, disk erase/partitioning, filesystem copy, account provisioning, initramfs, systemd-boot and verification |

## Try it

**In a browser (any OS):**

```sh
npm run dev          # builds tokens + icons, serves prototype/ on :8080
```

Open http://localhost:8080. The session boots, then locks: type any password.
Things to try:

- ⌘/Ctrl-Space for Spotlight (try `12*(3+4)` or an app name)
- right-click anything; right-click or long-press a Control Center button for its details
- Ctrl-↑ for Mission Control, Ctrl-Tab for the app switcher
- hover the Dock; minimise a window with the yellow light, restore it from the Dock
- in Files: Space for Quick Look, Return to rename, ⇧⌘N for a folder, drag onto the Trash
- Settings → Appearance for dark mode, accent colours, icon and glass styles

URL flags reproduce a scene: `?quiet&theme=dark&open=photos,terminal&cc=1`
skips the boot and opens those apps; `?lock` starts at the lock screen.

**On an existing Arch Linux + Hyprland machine:**

```sh
sudo pacman -S hyprland hypridle quickshell qt6-svg qt6-wayland inter-font \
               ttf-jetbrains-mono networkmanager bluez brightnessctl playerctl grim slurp librsvg \
               pyside6 qt6-webengine python git xorg-server-xvfb libxtst
scripts/install.sh           # backs up anything it replaces (*.bak-<timestamp>)
sudo scripts/install.sh --extras   # optional (needs keyd, sddm, plymouth): ⌘ layer, login theme, boot splash
```

Then log into Hyprland. Local account creation also needs the system integration:
`sudo scripts/install.sh --extras`. Besides the root-owned helper, this installs
the shared Golden Gate runtime, a Golden Gate SDDM/Wayland session, and the
`/etc/skel` desktop used by accounts created in Hello. It is included
automatically in ISO builds.

**Web browser:** `gg-web` opens Golden Gate's native Chromium-powered browser
(Qt WebEngine, updated through Arch's `qt6-webengine` package). It has a
Safari-inspired toolbar, traffic lights, tab sidebar, start page, bookmarks,
history, downloads, and private windows. Ctrl+L focuses the address, Ctrl+T/W
opens/closes tabs, Ctrl+D bookmarks, Ctrl+J opens downloads, and Ctrl+Shift+N
opens a private window. Restored background tabs load when selected. Normal
profiles and private profiles are separate. This is an initial browser, without
Safari/iCloud services, extension management, or a password manager.

If Web has graphics trouble in your VM, run `GG_WEB_SOFTWARE=1 gg-web`.
The launcher keeps Chromium sandboxing enabled and must run as your desktop user.
Golden Gate does not ship a second browser frontend: Web owns the browser experience
while Qt WebEngine/Chromium remains isolated from the Quickshell desktop process.

**Developing apps: LCode.** `gg-lcode` (or LCode in Applications) is Golden Gate's
Xcode. It follows Xcode 26's layout and keyboard shortcuts, and with the ⌘ layer
they are the same keys: ⌘R runs, ⌘B builds, ⌘U tests, ⌘. stops, ⇧⌘O is Open
Quickly, ⌘0/⌥⌘0/⇧⌘Y toggle the navigator, inspectors and debug area, ⌘L goes to a
line and ⌘/ comments. Like `xed`, `gg-lcode path/to/File.swift` opens the package
that contains the file, and `gg-lcode .` opens the current folder. Projects are
plain Swift packages (LCode's own settings live in `.lcode/`), so they also build
with `swift build` and open in Xcode. LCode needs a Swift toolchain: `yay -S
swift-bin` from the AUR, or [swiftly](https://www.swift.org/install/linux/); set
another one in LCode ▸ Settings or with `LCODE_SWIFT`.

Run an app on *My Linux PC*, or on an LPhone or LPad. The Simulator is a private
X server (Xvfb) the size of the device's screen: LCode starts the built program
there, mirrors it into a device frame, and passes your clicks, scrolling and typing
back to it. Rotate with ⌘← and ⌘→, take a screenshot with ⌘S; ⇧⌘H goes to the home screen, which lists the
apps you have run. Apps can tell they are in the Simulator from `LCODE_SIMULATOR=1`
and `LCODE_DEVICE_ID`. The Simulator runs Linux apps (GTK, SwiftCrossUI, Qt,
anything that speaks X11); it does not run iOS apps. It needs `xorg-server-xvfb`
and `libxtst`, which the ISO includes.

**Hello and accounts:** account creation is the first step after Hello. It creates
a password-protected local administrator account, requests existing administrator
authorization on installed systems, and passes the password through standard input.
Existing desktop users can keep their current account. Setup saves your choices
for the new account and waits for successful writes before closing. On installed
systems the Welcome page can sign out after saving so you can continue in the new
account through the Golden Gate login session; choosing Get Started keeps the
current session instead. On a live ISO, accounts and files remain temporary
unless persistence is configured. You can sign in on another console (Ctrl+Alt+F2)
and run `gg-session`; this does not install the system onto disk.

**As a bootable ISO.** The *Build ISO* GitHub Action builds one whenever
`distro/`, the installer or the workflow changes, and attaches it to the run
as the `golden-gate-iso` artifact. On an Arch host:

```sh
sudo pacman -S archiso librsvg nodejs base-devel git
sudo GG_BUILD_AUR=1 distro/archiso/build.sh   # → out/golden-gate-<date>-x86_64.iso
```

`GG_BUILD_AUR=1` builds anything in `packages.extra` that isn't in the official
repositories from the AUR. The live session logs in as `golden` (no password)
and starts the desktop. In a virtual machine, give it 6 GB of memory and 4 CPUs.
QEMU: use `-accel kvm` (Linux) or `-accel whpx` (Windows, after enabling the
Windows Hypervisor Platform feature); `-vga std` works, and
`-device virtio-vga-gl -display gtk,gl=on` adds 3D on Linux. VirtualBox:
VMSVGA graphics; the desktop renders in software there, with or without 3D
acceleration. If VirtualBox shows a green turtle in its status bar, it is running
on top of Hyper-V and everything is many times slower: turn off Hyper-V, Windows
Hypervisor Platform and Memory Integrity, or use QEMU with `-accel whpx`. In a
virtual machine the desktop always runs at 1× scale, and without a GPU it uses
lighter effects (`compositor/hyprland/machine-conf.sh`). If the desktop can't
start, the session drops to a shell that says why.

## Testing

```sh
npm run test:ui       # Playwright clicks through every app and system surface
npm run screenshots   # regenerates docs/screenshots from the prototype
shell/tests/screenshot.sh out/   # runs the real Quickshell shell in headless Sway
```

The test suite covers the browser reference, QML parsing, native control behavior,
installer safety gates, Settings wiring, shared-component architecture, default-app
identity/MIME handling, browser isolation, native application backends, and
LCode's projects, builds, Simulator and code editor (`tests/lcode.py`, with a
stand-in `swift`, so no toolchain is needed). The
live desktop is also validated directly on the ISO because compositor, layer-shell
and hardware behavior cannot be proven by the browser prototype alone.

The apps in `apps/` are Quickshell configs, one entry file each. Their controls come
from the single canonical component store in `apps/lib` (installed as
`/usr/share/golden-gate/ui` and linked into the app tree), so buttons, switches,
sliders, text fields, traffic lights and glass chrome cannot drift per app. Run one on its own with
`qs -p apps/calculator.qml`; the installer copies them to
`/usr/share/golden-gate/apps` with a desktop entry each. Weather uses Open-Meteo
(no API key) and CARTO/OpenStreetMap tiles with RainViewer radar; for offline
work, `apps/weather/tests/make-fixture.py DIR` writes a recorded-format forecast
and `GG_WEATHER_FIXTURE=DIR QML_XHR_ALLOW_FILE_READ=1 qs -p apps/weather.qml`
runs from it. Music plays your own files (~/Music, scanned by `apps/music/scan.sh`
with ffmpeg into ~/.cache/golden-gate/music), .m3u playlists from ~/Music/Playlists
and internet radio from radio-browser.info; it has no Apple Music streaming.
Liquid Glass optics are provided by HyprGlass at the compositor boundary. Golden Gate
does not maintain a second refraction shader for Setup or individual controls; apps use
the shared QML material/chrome from `apps/lib`, installed once as
`/usr/share/golden-gate/ui`. Crash reports: `gg-diagnostics` writes a report to
~/Documents/Diagnostics, and if you opted in, a notification offers one when an
app crashes; nothing is sent until you submit it yourself.
Settings writes what the shell and apps watch through the atomic `gg-pref`
backend: ~/.config/golden-gate/desktop.json (wallpaper, Dock size and magnification,
glass style, reduce motion and transparency), plus Hyprland fragments in
~/.config/hypr/golden-gate (input.conf, accessibility.conf, displays.conf) applied
live with `hyprctl keyword`. Unknown legacy `gnome-control-center` panel names
remain inside Golden Gate Settings instead of opening a second settings UI.
Notes keeps each note as a Markdown file in ~/Documents/Notes/<folder>/, named
after its first line. Photos shows ~/Pictures and ~/Videos, with the folders in
~/Pictures as albums. Maps uses OpenStreetMap throughout (CARTO tiles, Photon
search, OSRM routes), so it needs no account.

`shell/tests/screenshot.sh` starts Sway with the pixman renderer and Mesa's
llvmpipe, loads the shell, drives it over IPC and captures the screenshots
above. No GPU needed. Two things this turned up that static checks never would:

- Qt's `BezierEase` keeps at most 8 spline segments; longer curves corrupt the
  heap. The QML springs are fitted with exactly 8.
- Qt's SVG renderer ignores `clip-path`, so the app icons fill their squircle
  through a pattern instead.

## Why a distribution, not a kernel fork

The look and feel of a desktop lives in user space: the compositor, the shell,
toolkit themes, fonts and icons. The Linux kernel doesn't take part. So Golden
Gate stays on the stock Arch kernel and packages and owns everything above them.
That keeps hardware support and security updates coming from upstream for free.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the layers fit.

## Design

[docs/DESIGN.md](docs/DESIGN.md) is the spec: the three glass materials, the
typography scale, corner radii, and how springs are defined once and reproduced
identically in CSS, QML and the compositor.

## Your own icons

Drop SVG or PNG files into `icons/custom/apps/` (or `places/`, `symbols/`) named
after the icon, e.g. `files.svg`, and run `npm run build`. Your artwork replaces
the built-in icon everywhere: the prototype, the Linux icon theme, and every file
manager that looks up `system-file-manager`, `org.gnome.Nautilus`, and so on.
Details and sizing guidance are in [icons/custom/README.md](icons/custom/README.md).

## Legal notes

- **This build uses Apple's own app icons** (`icons/custom/`, imported with
  `icons/import-icon-pack.sh` from a set exported from macOS 27). Apple licenses
  them for Apple platforms only, so this repository and its ISOs must stay
  private. For anything public, delete `icons/custom/apps*` and rebuild
  (`node icons/build.mjs`): the original Golden Gate icons come back.
- Everything else (symbols, folder icons, wallpapers) is original. SF Symbols and
  SF Pro are not used; the typeface is [Inter](https://rsms.me/inter/) (OFL).
- Recreating a visual *style* is common practice, but Apple's names and logos are
  trademarks. The UI avoids Apple's logo (the menu-bar mark is a bridge tower) and
  uses generic app names (Files, Photos, Web). A few feature names used for
  familiarity, such as *Spotlight* and *Control Center*, and the repository name
  "GoldenApple" should be renamed before any public release.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).

