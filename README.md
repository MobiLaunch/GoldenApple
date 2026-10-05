# CitronOS Sprite 3.5

A Linux distribution with a Liquid Glass desktop: translucent glass materials,
spring motion, a floating Control Center, an iPad-style Dock, Spotlight, desktop
widgets and Finder-style Files, modelled closely on macOS's Liquid Glass design
language and built entirely from original artwork. Sprite is the release's
name and 3.5 its version (both kept in `apps/lib/theme/Release.qml`); it was
called Golden Gate before. Internal names (`org.goldengate.*` app IDs, `gg-*`
commands, `~/.config/golden-gate`) are unchanged, so existing installs keep
their settings.

**Citron Intelligence** adds Gemini-powered questions, Writing Tools, image
generation and photo editing. Open it with **Super+Shift+Space** or the menu
bar's wand. Add your own Gemini key in **Settings → Citron Intelligence**.
In supported editors, right-click → **Writing Tools…** or press
**Ctrl+Shift+W** to review and replace a selection. [Setup, privacy and limits](docs/CITRON-INTELLIGENCE.md).

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

![CitronOS ISO booted in QEMU](docs/screenshots/iso-boot-qemu.jpg)

## What's here

| Layer | Path | Status |
|---|---|---|
| **Design tokens**: materials, colour, type, radii, spring physics | `design/` | Done. One JSON compiles to CSS, QML, GTK and Hyprland config |
| **Icons**: first-party app icons, file/place icons and shared symbols | `icons/` | Done. One generated freedesktop theme plus optional imported artwork; [bring your own](icons/custom/README.md) |
| **Reference shell**: the desktop interaction/design reference, interactive in the browser | `prototype/` | Kept as a design reference; the live QML desktop is authoritative for native functionality |
| **Linux shell**: menu bar, Control Center, Dock (drag to rearrange), Applications, Spotlight, desktop widgets, notifications, app switcher, lock screen | `shell/` | Quickshell (QML), tested on the live ISO and real Intel/i915 hardware as well as VM/headless sessions |
| **Compositor**: blur, refraction, squircle corners, springs, key bindings | `compositor/` | Hyprland + HyprGlass; the ISO bundles a Hyprland-version-matched plugin and CitronOS applies its presets per shell surface |
| **Shared UI**: AppWindow, Glass, buttons, fields, switches, sliders, progress, sidebars, motion and symbols | `apps/lib/` | One canonical QML component store, consumed by apps, shell adapters, Setup and SDDM; Web has a centralized Qt adapter around its isolated Chromium process |
| **CitronOS apps**: Files, Web, Mail, Messages, Maps, Photos, Music, Calendar, Notes, Weather, App Store, Settings, Clock, TextEdit, Calculator and Installer | `apps/` | First-party frontends use the shared component store; mature backends such as Qt WebEngine, Flatpak, IMAP/SMTP, BlueFerry (iMessage and SMS through a paired iPhone) and Ghostty remain isolated behind CitronOS UI |
| **LCode**: an Xcode-style IDE: Welcome window and template gallery, project navigator, tabbed editor with colour themes, code completion and snippets, minimap and inline issues, a visual App Designer for CitronOS apps, the project editor (app info, icon, capabilities, scheme), Archive and the Organizer, Run/Stop and scheme ▸ destination pills, activity view, debug console, inspectors, Open Quickly, Find in Project, a Settings window, and a Simulator that runs the built app inside a device frame | `apps/lcode.qml`, `apps/lcode/` | CitronOS apps, Swift packages, Rust crates, Meson (C) projects and Python programs build, test, run and package; no debugger yet |
| **System Settings**: a near copy of macOS System Settings (glass sidebar with search suggestions, back and forward, grouped panes) that changes the real system: Wi-Fi, Bluetooth, Network, Battery, General (About, Software Update, Storage, Date & Time, Language & Region), Accessibility, Appearance (mode, accent, Liquid Glass clear or tinted), Desktop & Dock, Displays, Wallpaper, Focus, Sound, Privacy & Security, Users & Groups, Keyboard, Trackpad & Mouse | `apps/settings.qml`, `apps/settings/` | Done; `gg-settings [pane]` and `gnome-control-center [panel]` open it at a pane |
| **Setup Assistant**: the first-login hello and shared CitronOS controls over the HyprGlass desktop material, then local account creation, country or region, Wi-Fi, Data & Privacy, Location Services, time zone, crash and diagnostics sharing, and Choose Your Look | `apps/setup.qml`, `apps/setup/` | Done; runs once (`~/.config/golden-gate/setup-done`), `gg.nosetup` on the kernel command line skips it |
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
               ttf-jetbrains-mono networkmanager bluez brightnessctl playerctl grim slurp wf-recorder librsvg \
               pyside6 qt6-webengine python git xorg-server-xvfb libxtst
scripts/install.sh           # backs up anything it replaces (*.bak-<timestamp>)
sudo scripts/install.sh --extras   # optional (needs keyd, sddm, plymouth): ⌘ layer, login theme, boot splash
```

Then log into Hyprland. Local account creation also needs the system integration:
`sudo scripts/install.sh --extras`. Besides the root-owned helper, this installs
the shared CitronOS runtime, a CitronOS SDDM/Wayland session, and the
`/etc/skel` desktop used by accounts created in Hello. It is included
automatically in ISO builds.

**Web browser:** `gg-web` opens CitronOS's native Chromium-powered browser
(Qt WebEngine, updated through Arch's `qt6-webengine` package). It has a
Safari-inspired toolbar, traffic lights, tab sidebar, start page, bookmarks,
history, downloads, and private windows. Ctrl+L focuses the address, Ctrl+T/W
opens/closes tabs, Ctrl+D bookmarks, Ctrl+J opens downloads, and Ctrl+Shift+N
opens a private window. Restored background tabs load when selected. Normal
profiles and private profiles are separate. This is an initial browser, without
Safari/iCloud services, extension management, or a password manager.

If Web has graphics trouble in your VM, run `GG_WEB_SOFTWARE=1 gg-web`.
The launcher keeps Chromium sandboxing enabled and must run as your desktop user.
CitronOS does not ship a second browser frontend: Web owns the browser experience
while Qt WebEngine/Chromium remains isolated from the Quickshell desktop process.

**Windows, Spotlight and Files.** Rest the pointer on a window's green button
for Move & Resize (halves, quarters, Fill, Center), as in macOS Sequoia; the menu
bar's Window menu has the same, with Minimize and Full Screen. From the keyboard:
⌃⌥←→↑↓ for halves, ⌃⌥U I J K for quarters, ⌃⌥↩ to fill, ⌃⌥C to center and ⌃⌥⌫
to put the window back (`gg-tile`). Mission Control (⌃↑, F3, or three fingers up)
spreads out every window on the desktop, live, with your desktops along the top:
click one to go there, + to add one, or drag a window onto it; ⌃↓ or three fingers
down is App Exposé, and three fingers sideways move between desktops. Spotlight (⌘Space) answers sums (`15% of 240`),
unit conversions (`5 km in mi`, `70 f to c`), finds System Settings panes and
files in your home folder, and falls back to a web search. In Files, Space or ⌘Y
is Quick Look, the arrows move, Return renames, ⌘O/⌘↓ opens, ⌘↑ goes up and ⌘⌫
moves to the Trash. Drag items onto a folder or a sidebar place to move them
(another disk, or a file from another app, is copied), onto the Trash to throw
them away, or out to another app. Recents lists what you've opened and changed
lately, and the Trash has Put Back and Empty Trash. Screenshots work as on a Mac: ⇧⌘3 the
screen, ⇧⌘4 a part of it (Space for a window), ⌃ added for the clipboard, and ⇧⌘5
the toolbar, which also records the screen or a selection (stop it from the menu
bar) and keeps your choice of where to save, a timer and the floating thumbnail.

**App Store, and Mac apps.** The App Store is laid out like the Mac's (Discover,
Create, Work, Play, Develop, a page for each app, Updates) and installs Linux apps
from Flathub. Its **Mac Apps** section offers the Mac apps developers ship as
downloads (the Homebrew Cask catalog, about 7,000 of them): Get downloads one from
its developer, checks it against the published checksum where there is one, and
installs it in `~/Applications` with its icon in Launchpad. Mac apps open with
[Darling](https://www.darlinghq.org), the macOS translation layer; **Set Up…**
installs Darling's official prebuilt release (`darling-bin` from the AUR) in a
Terminal window, after refreshing pacman's signing keys and updating the system.
The source packages (`darling-git`, `darling`) don't install on Arch: they need
an AUR-only build helper, 32-bit compilers and a library Arch dropped. CitronOS
also turns on Arch's `[multilib]` repository, which 32-bit software such as
Wine and Steam needs. Be aware that
Darling runs command-line programs well but its support for apps with windows is
experimental, so many Mac apps don't open yet: each app's page says whether it
opened on your computer, and Darling's output when it didn't. Apps built only for
Apple silicon are refused (Darling translates Intel code), and Mac App Store apps
aren't offered (they're tied to an Apple ID and encrypted).

**Developing apps: LCode.** `gg-lcode` (or LCode in Applications) is CitronOS's
Xcode, made so that anyone can build good-looking Linux apps. It follows Xcode 26's
layout and keyboard shortcuts, and with the ⌘ layer they are the same keys: ⌘R runs,
⌘B builds, ⌘U tests, ⌘. stops, ⇧⌘O is Open Quickly, ⇧⌘L the Library, ⌘0/⌥⌘0/⇧⌘Y
toggle the navigator, inspectors and debug area, ⌘L goes to a line and ⌘/ comments.
Like `xed`, `gg-lcode path/to/File.swift` opens the project that contains the file,
and `gg-lcode .` opens the current folder.

New Project offers apps, command-line tools and libraries in five toolchains:
*CitronOS apps* (designed in the App Designer, no code needed), *Swift* packages
(SwiftCrossUI), *Python* (GTK 4 + libadwaita), *Rust* (gtk4-rs + libadwaita) and
*C* (Meson, GTK 4). Projects stay ordinary projects for their language (LCode keeps
its own settings in `.lcode/`), so they also build with `swift build`, `cargo`,
`meson` or `python`. Set toolchain locations in Settings ▸ Locations, or with
`LCODE_SWIFT` and friends.

- **App Designer** (`Interface.lcdesign`): drag stacks, text, buttons, toggles,
  sliders, lists, images, symbols and shapes from the Library onto a live canvas in
  Light, Dark or both; style them in the inspector (colours, gradients, materials,
  corners, shadows, fonts, layout); give the app variables and named colours, and
  wire events to actions (set, toggle, add to a list, navigate, alert, open a link,
  run a command) without writing code. Live mode runs the design on the canvas.
  Building turns it into a real CitronOS app (Quickshell/QML) that saves its state.
- **Code editor**: themes, completion (keywords, your code's names, snippets whose
  `<#placeholders#>` Tab steps through), closing brackets and quotes, and tidying
  whitespace on save. The Library has snippets (make your own from a selection),
  CitronOS's symbols and the system colours.
- **Project editor**: display name, version, bundle identifier, the app icon
  (colours, gradient, symbol or text, previewed light and dark), capabilities, and
  the scheme's arguments, environment and build configuration.
- **Archive and the Organizer**: Product ▸ Archive makes a release build; the
  Organizer installs it on this computer (with its icon in Applications), or exports
  a PKGBUILD, a Flatpak manifest or a portable archive.
- **Settings** (⌘,): appearance, git identity, Behaviors (show the console or issues,
  notify or play a sound when builds and runs start and end), editor Themes (14
  built in, or duplicate one and change every colour), Text Editing (font, line
  numbers, minimap, indentation, completion), Key Bindings (rebind any command),
  your own Simulator devices, and toolchain Locations.

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
account through the CitronOS login session; choosing Get Started keeps the
current session instead. On a live ISO, accounts and files remain temporary
unless persistence is configured. You can sign in on another console (Ctrl+Alt+F2)
and run `gg-session`; this does not install the system onto disk.

**As a bootable ISO.** The *Build ISO* GitHub Action builds one whenever
`distro/`, the installer or the workflow changes, and attaches it to the run
as the `golden-gate-iso` artifact. On an Arch host:

```sh
sudo pacman -S archiso librsvg nodejs base-devel git
sudo GG_BUILD_AUR=1 distro/archiso/build.sh   # → out/citronos-sprite-<date>-x86_64.iso
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

**Updating an installed system.** Settings ▸ General ▸ Software Update's
Update Now installs Arch updates and CitronOS's newest commit from GitHub
together, no new ISO needed (`apps/settings/golden_update.py`). It follows the
repository and branch the ISO was built from (recorded in
`/usr/share/golden-gate/version.json`); Update Source changes them, and takes a
read-only fine-grained token (Contents: read) for a private repository. Each
account's shell is refreshed; a Hyprland, GTK or Ghostty file you edited is
kept, with the new one beside it as `*.golden-gate-new`.

Without GitHub, from a USB stick, either way keeps accounts and files:

- **Boot the new ISO and update the disk:** open Terminal in the live session
  and run `sudo gg-update-disk`. It finds the CitronOS installed on the
  computer, asks to confirm, and installs the ISO's own version onto it
  (the ISO carries its source as `/usr/share/golden-gate/source.tar.gz`).
- **Carry an update bundle to the installed system:** make one with
  `scripts/make-update-bundle.sh golden-gate-update.tar.gz`, copy that one file
  to any USB stick, then on the installed system:

  ```sh
  tar xzf /run/media/$USER/*/golden-gate-update.tar.gz
  sudo python3 golden-gate/apps/settings/golden_update.py install-local
  ```

  This is also how a system installed before Software Update knew about Golden
  Gate gets the updater the first time.

## Testing

```sh
npm run test:ui       # Playwright clicks through every app and system surface
npm run screenshots   # regenerates docs/screenshots from the prototype
shell/tests/screenshot.sh out/   # runs the real Quickshell shell in headless Sway
```

The test suite covers the browser reference, QML parsing, native control behavior,
installer safety gates, Settings wiring, shared-component architecture, default-app
identity/MIME handling, browser isolation, native application backends, and
LCode's projects, toolchains, App Designer, packaging, settings, Simulator and code
editor (`tests/lcode.py`, with a stand-in `swift`, so no toolchain is needed; themes,
key bindings and completion in `tests/logic.mjs`). The
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
Liquid Glass optics are provided by HyprGlass at the compositor boundary. CitronOS
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
remain inside CitronOS Settings instead of opening a second settings UI.
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
  (`node icons/build.mjs`): the original CitronOS icons come back.
- Everything else (symbols, folder icons, wallpapers) is original. SF Symbols and
  SF Pro are not used; the typeface is [Inter](https://rsms.me/inter/) (OFL).
- Recreating a visual *style* is common practice, but Apple's names and logos are
  trademarks. The UI avoids Apple's logo (the menu-bar mark is a lemon with its leaf) and
  uses generic app names (Files, Photos, Web). A few feature names used for
  familiarity, such as *Spotlight* and *Control Center*, and the repository name
  "GoldenApple" should be renamed before any public release.

## Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md).
