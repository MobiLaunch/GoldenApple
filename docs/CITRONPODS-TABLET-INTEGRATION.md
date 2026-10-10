# CitronPods & Tablet Mode: system integration

## CitronPods M10

Golden Gate includes the system-facing components, not the separate
third-party Qt GUI:

- `citronpods-daemon.service`: a **user** systemd daemon for BlueZ/Bluetooth
  and the AirPods-specific control/telemetry protocol.
- `CitronPodsService.qml`: shared, version-checked, stale-data-aware D-Bus
  and private JSON state consumer used by Settings and Control Center.
- `CitronPodsPopup.qml`: one transient Golden Gate pairing/battery card
  that only appears after trusted state transitions.
- Settings → **AirPods**: discovered devices, connectivity, genuine battery
  readings, ANC, conversation awareness and device options when supported.
- `gg-citronpods`: status, open Settings/card, restart and diagnostics.

### Installing the engine

The native backend is GPL-3.0-derived CitronPods M10 Qt6-Fixed source.
**It is not vendored into the Golden Gate repository or installed from an
unknown network mirror.** This protects the original source and lets
Golden Gate install only the daemon. A user-provided compatible ZIP is
still required once on a clean machine.

Put `LibrePods-CitronPods-M10-Qt6-Fixed.zip` in `~/Downloads`.
After updating Golden Gate, open Settings → AirPods → Install Engine.
The Settings picker automatically detects the ZIP and offers one-click
compilation. Or use:

```sh
gg-install-citronpods             # auto-discover M10 ZIP in Downloads
gg-citronpods status
gg-citronpods show
```

The installer validates archive paths/sizes, expected daemon sources and
the Qt Bluetooth enum fix, then compiles **only** `citronpods-daemon`.
It installs the user service and starts it. Native build tools (gcc,
cmake, ninja) are included in new Golden Gate images. No duplicate
Qt GUI is installed. A missing source or unsupported AirPods model
never causes fake telemetry.

**Testing:** The M10 archive's own `check_m10.py` suite passed offline.
Actual AirPods pairing, model support and audio routing still require
testing on physical Bluetooth hardware.

## Flat shadow correction

The default context menu now has **no detached shader shadow**. This
prevents Wayland's rectangular pop-up surface from cutting a soft shadow
into a square; menus retain rounded glass rims, refraction and tint.

Control Center no longer receives a SECOND, whole-layer HyprGlass
pass. It still draws the actual per-control translucent rounded glass
using the system's Qt backdrop lens. This avoids the rectangular layer
silhouette beneath otherwise circular and pill-shaped controls.

This is a targeted fix, not a removal of systemwide window shadows.

## Tablet Mode (initial implementation)

Settings → Desktop & Dock → **Tablet Mode** enables a persistent,
opt-in touch presentation with the same apps, profiles and data:

- Dock: larger, stable app icons and more bottom clearance.
- Home Screen/Launchpad: four columns in portrait, six in landscape;
  touch-sized icons retain macOS-style curated artwork.
- Control Center: larger module targets and more legible compact labels.
- On-screen keyboard: Settings offers **Show Keyboard** and **Hide**,
  backed by the open-source Squeekboard Wayland input method and its
  D-Bus `SetVisible` API. New images include `squeekboard`.
- `iio-sensor-proxy` is available to support optional accelerometer
  rotation integrations on tablets with suitable sensor drivers.

The user's choice persists as `tablet.enabled` in the same
`desktop.json` watched by Quickshell. No reboot, second OS, iPadOS
binary compatibility or loss of desktop features is involved.

### Not yet implemented

This is the foundation, **not a complete iPadOS replacement**.
Automatic screen/touch digitizer rotation, two-app Stage Manager,
gesture-driven home-indicator navigation, app-specific compact UI,
stylus handwriting, tablet login/lock experience, and touch-keyboard
focus interoperability across every native and XWayland app still
require further integration and physical-tablet testing.

Rotation mapping is intentionally not applied automatically yet:
Windows convertible panels often have varying manufacturer-specific
initial orientations; guessing a rotation can make touch coordinates
unusable. A subsequent phase should add an opt-in, sensor-tested
calibration workflow before enabling it.
