# Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  design/tokens.json   ← single source of truth (materials, type,     │
│                          radii, spring physics)                       │
│        │  design/build.mjs                                            │
│        ├──► prototype/assets/tokens.css    (CSS vars + linear() springs)
│        ├──► shell/theme/Theme.qml          (QML singleton + Bézier springs)
│        ├──► design/dist/gtk.css            (libadwaita / GTK 4 overrides)
│        └──► design/dist/hyprland-motion.conf (beziers, blur, rounding)
│                                                                       │
│  icons/source.mjs  (+ icons/custom/ overrides)                        │
│        │  icons/build.mjs                                             │
│        ├──► icons/GoldenGate/       freedesktop icon theme            │
│        ├──► shell/assets/symbols/   white glyphs for the QML shell    │
│        └──► prototype/assets/icons.js                                 │
└──────────────────────────────────────────────────────────────────────┘

Runtime on Linux
┌───────────────┐  ┌──────────────────────────────┐  ┌───────────────────────┐
│ Apps          │  │ Quickshell shell (shell/)     │  │ Hyprland compositor   │
│ GTK4/libadw.  │  │  MenuBar · ControlCenter ·    │  │  blur on gg-* layers, │
│ + gtk.css     │  │  Dock · Spotlight             │  │  squircle rounding,   │
│ Qt (gtk3 plat)│  │  layer-shell surfaces gg-*    │  │  spring beziers,      │
│ icon theme    │  │  talks to NM, BlueZ, PipeWire,│  │  key bindings         │
│ Inter (fontc.)│  │  MPRIS, UPower, brightnessctl │  │  (+ hyprglass plugin) │
└───────────────┘  └──────────────────────────────┘  └───────────────────────┘
        stock Arch Linux: kernel, systemd, Mesa, PipeWire, NetworkManager
```

## Why these pieces

| Need | Choice | Why |
|---|---|---|
| Base | Arch + archiso | Current Mesa/kernel for good compositor performance. archiso's `releng` profile gives a bootable ISO with little code. |
| Compositor | Hyprland | Built-in blur on layer surfaces with `ignorealpha`, `rounding_power` for continuous corners, configurable animations, a plugin API for the refraction shader. |
| Shell | Quickshell (QML) | Layer-shell windows, Wayland toplevel tracking, and service bindings (PipeWire, MPRIS, UPower, Bluetooth, Hyprland IPC) in declarative QML. Qt Quick is GPU-rendered and animates smoothly. |
| Apps | GNOME apps + libadwaita CSS | libadwaita ≥ 1.6 exposes its palette as CSS variables, so one generated `gtk.css` re-skins every app. |
| Type | Inter + fontconfig | Closest open neo-grotesque to the reference; grayscale AA and light hinting match the rendering style. |

## The reference prototype

`prototype/` is a complete browser implementation of the desktop. It exists so
that design decisions (glass recipes, spring curves, menu spacing, toolbar
pills) can be iterated in seconds and screenshot-tested, then carried into QML
with the same tokens. When the QML shell and the prototype disagree, the
prototype is the spec.

Module map:

| File | Role |
|---|---|
| `js/wm.js` | window manager: stacking, drag, resize, zoom, genie-style minimise |
| `js/menus.js` | menus and submenus, keyboard navigation, selection blink |
| `js/menubar.js`, `controlcenter.js`, `dock.js`, `spotlight.js`, `notifications.js` | shell surfaces |
| `js/apps/*.js` | Files, Photos, Settings, Terminal, Calculator, Notes |
| `js/glass.js` | experimental SVG refraction (`?refract`) |

## Springs, once

A spring is `{ response, dampingFraction }` (the SwiftUI parameterisation).
`design/build.mjs` integrates the damped oscillator analytically and emits:

- **CSS**: a 41-point `linear()` easing plus its settle duration
- **QML**: a 12-segment `Easing.BezierSpline` fitted with Hermite tangents
- **Hyprland**: a single cubic Bézier approximation, with overshoot folded into y₁

So a Control Center module overshoots by the same amount everywhere.
