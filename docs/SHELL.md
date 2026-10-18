# The shell

CitronOS's desktop shell is one Quickshell process, `qs -c golden-gate`
(`shell/`), plus its lock screen in a process of its own,
`qs -c golden-gate-lock` (`shell-lock/`). Hyprland 0.55 or newer runs it,
configured in Lua (`compositor/hyprland/hyprland.lua`).

## What draws what

| Surface | From | Files |
|---|---|---|
| Menu bar, its menus and status items, Control Center, Spotlight (apps, files, calculator, clipboard history ⇧⌘V, emoji ⌃⌘Space), notifications and Notification Center, the ⌘Tab switcher, screenshots (⇧⌘3, ⇧⌘4, ⇧⌘5 the front window), screen recording, the wallpaper picker (⌃⌥W), volume and brightness indicators | MacShell | `shell/macshell/MacBar.qml` |
| Dock (magnification, window previews, pins, Trash), the Desktop & Dock settings window | MacShell | `shell/macshell/MacDock.qml` |
| Desktop widgets (weather, calendar, clock, music, pictures) | MacShell | `shell/macshell/MacWidgets.qml` and the `*Widget.qml` files |
| Clock (alarms, timers, world clock, stopwatch) | MacShell | `shell/macshell/ClockApp.qml` |
| Lock screen | MacShell's MacLock | `shell-lock/` |
| The wallpaper (from Settings › Wallpaper) | CitronOS | `shell/Wallpaper.qml` |
| Launchpad (F4) | CitronOS | `shell/Applications.qml` |
| Mission Control and App Exposé (⌃↑ ⌃↓, F3, three/four fingers up and down) | CitronOS | `shell/MissionControl.qml` |
| Citron (⇧⌘Space) | CitronOS | `shell/VoiceAssistant.qml` |
| AirPods and nearby-device cards | CitronOS | `shell/CitronPodsPopup.qml`, `shell/Nearby.qml` |
| Log Out, Restart and Shut Down confirmations (⇧⌘Q) | CitronOS | `shell/SessionDialog.qml` |
| Tablet Home Screen | CitronOS | `shell/TabletHome.qml` |

`shell/shell.qml` puts them together: `MacShell {}` (`shell/macshell/MacShell.qml`,
MacShell's own `shell.qml` as a Scope) beside CitronOS's surfaces. The apps
(`apps/`), System Settings, Software Update, the installer and Mac app
support are CitronOS's and unchanged by the shell.

## MacShell

MacShell is by Rickky (MIT, `third_party/macshell/LICENSE`):
https://github.com/0-ss/MacShell. The upstream commit and how its files map
here are in `third_party/macshell/UPSTREAM.md`. Every CitronOS change in its
files is marked `CitronOS:` in a comment:

- `MacShell.qml`: a Scope instead of a ShellRoot. The glass refracts the
  wallpaper CitronOS draws (`ggWallpaper`) when no wallpaper daemon reports
  one, and follows Settings › Wallpaper. Adds `notifications toggleDnd` (⌥⌘N).
- `MacBar.qml`: Terminal is Ghostty and Files is CitronOS Files. A picked
  wallpaper is saved to Settings (`gg-pref wallpaper`). The system menu
  offers About This Computer, System Settings (CitronOS Settings),
  Desktop & Dock Settings (MacShell's window), the App Store and Lock Screen
  (`gg-lock`). The switcher also switches when ⌘ is let go, so ⌘Tab works as
  on a Mac. The menu-bar logo is the CitronOS mark (`logo-white.svg`,
  `logo-black.svg`), not Apple's. Notifications follow Settings ›
  Notifications and Focus: an app that isn't allowed is dropped, one without
  banners still reaches Notification Center, Show Previews › Never hides the
  text, Focus holds banners back unless it lets the app through, and other
  apps' notifications play the alert sound chosen in Settings › Sound. The
  apps that notify are listed for Settings (`notifiers.json`).
- `MacDock.qml`: the default Dock is CitronOS's apps, Launchpad second (its
  `org.goldengate.Launchpad` entry runs `launchpad toggle`). The Trash opens
  in Files. Icons use the curated art Launchpad shows (`gg-icon-resolver`).
  `isPinned()`/`setPinned()` serve Launchpad's Add to Dock and Remove from
  Dock, and `pinned.json` is watched, so Settings › Desktop & Dock's app list
  edits the same Dock. Its About pane names CitronOS, without the dependency
  installer (Software Update installs what the desktop needs) or the
  AppleCare joke.
- `shell-lock/`: passwords are checked with PAM's `login` stack (no hyprlock
  needed). The wallpaper is CitronOS's. Touch ID unlocks beside the password
  (`gg-touchid` PAM service, with a finger enrolled and Unlock with Touch ID
  on). The message from Settings › Lock Screen shows under the password.
  `lock-via-ipc.sh` is installed as `gg-lock`.

`shell/shell.qml` declares `MacShell {}` after Launchpad and Mission Control:
they share the Top layer, and the surface made last is drawn on top, so the
menu bar and Dock stay over Launchpad as on a Mac.

MacShell keeps its own settings in `~/.config/macbar`, `~/.config/macdock`,
`~/.config/macwidgets`, `~/.config/macshell` and `~/.config/maclock`. Its
Desktop & Dock Settings window is where the Dock's look, the menu bar, glass
style, widgets and lock screen are set; Settings › Desktop & Dock and
Control Center open it at the right pane. CitronOS's Settings app still owns
everything else: Wi-Fi, Bluetooth, displays, keyboard, trackpad (MacShell's
own input sliders change only the running session), accounts, wallpaper,
appearance, notifications, Focus, Software Update.

Carried over from the old shell (`tests/macshell-ports.py`):

- The Window menu has Sequoia's Move & Resize (Fill, Center, halves,
  quarters, Return to Previous Size) through `gg-tile`, Bring All to Front
  and Mission Control; the app menu's Hide Others and Show All minimise and
  restore the other apps' windows. Menu shortcuts are written as on a Mac
  (⇧⌘Z, not Ctrl+Shift+Z): keyd makes ⌘ Ctrl for apps.
- Control Center adds AirDrop (`gg-airdrop`), Screen Mirroring (the AirPlay
  Receiver, `gg-airplay.service`, with its status and code), AirPods
  (CitronPods) and the quick actions Mission Control, Screenshot, Calculator,
  Timer, Quick Note and Lock Screen. AirDrop and Screen Mirroring are added
  once to a layout made before them. Its Focus is CitronOS's Focus
  (`focus.session`), so Settings, the Focus moon and Do Not Disturb agree.
- The menu bar has the Focus moon, a Citron item (`citron toggle`) and the
  location arrow, a blue privacy dot while an app locates
  (`apps/lib/privacy/location.py`: Weather's and Maps' helpers, GeoClue).
  Desktop & Dock › Menu Bar can hide the first two.
- Dock icons wear red badges: an app's notifications in Notification Center,
  or Mail's unread count (`mail-badges.json`), unless Settings ›
  Notifications turns the app's badges off.
- Light/Dark and the accent colour follow Settings › Appearance, and
  MacShell's own Light/Dark switch sets the system's.

Not on MacShell yet: Reduce Motion for MacShell's own animations and the
tablet top-right swipe for Control Center.

## Hyprland's Lua config

`compositor/hyprland/hyprland.lua` is installed as `~/.config/hypr/hyprland.lua`.
Hyprland 0.55+ reads it in preference to an older `hyprland.conf`. The parts
CitronOS writes live beside it in `~/.config/hypr/golden-gate/` and are each
loaded with `part()`, so one that is missing or broken doesn't stop the rest:

| Part | Written by |
|---|---|
| `motion.lua` | `design/build.mjs`, from the design tokens (`design/dist/hyprland-motion.lua`) |
| `glass.lua` | `gg-hyprglass-sync`: HyprGlass, the hyprbars title bars, window rims, Reduce Transparency |
| `input.lua` | Setup Assistant, Settings › Keyboard and Trackpad (`set-prefs.py`) |
| `accessibility.lua` | Settings › Accessibility |
| `windows.lua` | Settings › Desktop & Dock (window snapping) |
| `machine.lua` | `machine-conf.sh`, at every login (virtual machines, no GPU) |
| `displays.lua` | Settings › Displays |

Hyprland reloads a part when it changes. To change the running session,
`gg-hyprset` turns `section:key value` pairs and monitor rules into one
`hyprctl eval`, since Lua mode has no `hyprctl keyword`. Dispatches use the
Lua dispatchers, e.g. `hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })'`.
At login `gg-session` runs `migrate-fragments.py`, which carries settings an
account kept in the old `input.conf`, `accessibility.conf`, `windows.conf`
and `displays.conf` over to their `.lua` parts, once.

## Checks

- `tests/hyprland-lua.py` runs `hyprland.lua` and every part, in each form its
  writer produces, against Hyprland 0.56.2's API
  (`tests/data/hyprland-0.56-api.json`, generated from Hyprland's stubs and
  wiki). It catches unknown options, dispatchers, rule fields, animations and
  curves.
- The preview harness (`tools/preview`) can't run MacShell (it needs Wayland,
  the system tray, screencopy and shaders), so it loads a stand-in
  (`tools/preview/macshell/MacShell.qml`) and the tests there cover CitronOS's
  surfaces (`tests/launchpad.py`, `tests/missioncontrol.py`, …).
- `.github/workflows/shell.yml` installs CitronOS into a new Arch account and
  runs Hyprland's own `--verify-config`. It then loads the shell and the lock
  screen in headless Sway, fails on QML errors, and keeps the screenshots.
- The ISO's boot test (`distro/archiso/boot-test.sh`) runs the real session in
  QEMU and fails on any `hyprland-config` error.
