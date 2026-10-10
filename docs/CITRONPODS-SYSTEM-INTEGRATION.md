# CitronPods M10 in Golden Gate

Golden Gate integrates the existing Qt6 CitronPods M10 daemon as a first-party OS service and displays the native AirPods interface inside Quickshell. There is no separate CitronPods GUI or Launchpad application.

## Features

- System Settings > AirPods: actual device names, connect/disconnect, batteries (left/right/case), noise-control modes, Conversation Awareness, audio routing, ear detection and connection popup.
- Control Center: connected AirPods capsule, device battery, ANC/Transparency/Adaptive controls.
- Golden Gate shell: native transient glass connection card with M10's original Pro/classic/Max vector silhouettes.
- Shared state interface: private atomic JSON snapshot in $XDG_RUNTIME_DIR/citronpods/state.json with D-Bus fallback. Backend alone owns BlueZ and Apple L2CAP.
- Popup events are tied to daemon identity, sequence and trusted connections; nearby unverified BLE advertisements never automatically launch a pairing dialog.

## Golden Gate automatic engine integration

The earlier separate-application workflow has been replaced with a quiet
system-native first-login setup. In addition to `citronpods-daemon.service`,
Golden Gate installs these systemd user units:

- `citronpods-engine-bootstrap.service` — a locked, low-priority one-shot
  that adopts an existing daemon, or compiles the native C++ backend only.
- `citronpods-engine-bootstrap.path` — watches `~/Downloads` for the
  previously created M10 Qt6-Fixed source archive, so users do not need to
  run a second installer manually.

**Source availability:** the M10 source ZIP is still needed once if the
daemon is not already installed. It is not yet bundled in the Golden Gate
Git tree. Auto-setup accepts only the exact verified M10 Qt6-fixed ZIP
(SHA-256 `d14d3e74efb716357713d024bcb7c2311ae1226d8fa6bb883f4b9237661b4da4`)
to prevent executing untrusted CMake scripts from other Downloads ZIPs.
You may select alternate trusted sources explicitly in AirPods Settings.

Status and diagnostics are visible in AirPods Settings, or from:

```sh
cat ~/.local/state/golden-gate/citronpods-engine-status
tail -n 80 ~/.local/state/golden-gate/citronpods-build.log
gg-citronpods status
```

The desktop uses one service and one shell UI. No duplicate Qt app is
built or installed. Control Center offers a route to Settings when the
engine is not yet online.

### Drop shadow polish

- Standard floating `Glass` panels and menus no longer use the detached
  shader halo that gets cropped to a rectangular Wayland surface boundary.
  Standalone Controls, Sidebars and Dock keep their own subtler contact
  shadows.
- Context-menu popup carriers no longer reserve 24–28 pixels of unused
  transparent margin around the rounded card; the carrier is just 8 pixels
  larger for antialiasing.
- HyprGlass deliberately does not apply whole-surface blur to
  `gg-controlcenter` and `gg-citronpods`; their own rounded glass lenses
  keep the tint/refraction without a blocky rectangular backdrop.
- Automated tests cover source integrity, daemon-only installation,
  background setup, and the compositor/glass contracts. Real AirPods
  Bluetooth/ANC/hardware GPU behavior must still be verified on a device.

## One-time backend setup

The shell, Settings, service unit and launch commands are installed with every Golden Gate update. To use a machine that does not already have citronpods-daemon installed, the existing Qt6-fixed M10 C++ source archive must be compiled once. The archive is not included in the GoldenApple Git tree. The command builds *only the daemon*, not the duplicate Qt application.

    sudo pacman -S --needed base-devel cmake ninja qt6-base qt6-declarative qt6-connectivity libpulse
    gg-install-citronpods ~/Downloads/LibrePods-CitronPods-M10-Qt6-Fixed.zip
    gg-citronpods status
    gg-citronpods show

If citronpods-daemon was already installed to /usr/bin or /usr/local/bin by an earlier CitronPods build, Golden Gate discovers and enables the existing daemon on update, without compiling another copy.

The installer checks that the supplied archive is an M10 source tree, rejects unsafe archive paths/symlinks/oversized members, verifies the Qt6 Bluetooth SocketState scope fix, builds using CMake/Ninja in a temporary directory, installs only the daemon in ~/.local/bin and enables the first-party user service.

## Diagnostics

    systemctl --user status citronpods-daemon.service
    journalctl --user -u citronpods-daemon.service -n 80 --no-pager
    gg-citronpods status

Unpaired BLE advertisements are unauthenticated and may be spoofed. Noise control and battery reporting are restricted to hardware and firmware on which the M10 protocol works. The integration does not claim Apple's iCloud pairing, Find My or Continuity capabilities. Missing values are not fabricated.

## Clipped shadow polish

The wide glass shadow shader extended past narrow Wayland popup bounds and beyond Control Center's rectangular scrolling viewport. The compositor clipped those rounded shadows along straight edges, causing dark, blocky bars.

Golden Gate adds Glass.shadowEnabled to disable only those offending shadow passes on Control Center modules, context menus and the connection card. The rounded glass tint, edge highlights, backdrop refraction and Reduce Motion/Transparency behavior remain unchanged. Ordinary application windows retain their soft diffuse shadows.

## Verification

Run python tests/citronpods-integration.py to test first-party UI wiring, safety checks and a simulated M10 backend-only installation. The QML preview also opens the AirPods pane and popup without a daemon. Full Qt6 compilation and Bluetooth/ANC verification still require the actual Arch system.
