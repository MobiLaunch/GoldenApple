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
│ + gtk.css     │  │  Dock · Spotlight · Switcher ·│  │  squircle rounding,   │
│               │  │  Notifications · LockScreen   │  │                       │
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
| `js/wm.js` | window manager: stacking, drag, resize, zoom, edge tiling, genie minimise |
| `js/menus.js` | menus and submenus, keyboard navigation, selection blink |
| `js/menubar.js`, `controlcenter.js`, `dock.js`, `spotlight.js`, `notifications.js` | shell surfaces |
| `js/lock.js`, `mission.js` | boot and lock screen, Mission Control |
| `js/polish.js` | pointer-following glass light, tooltips, icon and glass styles |
| `js/vfs.js` | in-memory filesystem behind Files, Spotlight and the Desktop |
| `js/apps/*.js` | Files, Photos, Settings, Web, Mail, Messages, Music, Calendar, Maps, Weather, Software, Terminal, Calculator, Notes |
| `js/glass.js` | experimental SVG refraction (`?refract`) |
| `tests/` | Playwright smoke test and the screenshot generator |

The QML shell mirrors the surfaces one to one:

| File | Surface |
|---|---|
| `MenuBar.qml` | menu bar; samples the wallpaper to pick light or dark text per side |
| `ControlCenter.qml` | modules, sliders, Now Playing (MPRIS), Focus |
| `Dock.qml` | pinned apps, running indicators, magnification, Downloads and Trash |
| `Spotlight.qml` | app and file search |
| `Notifications.qml` | freedesktop notification server, banners with actions, swipe to dismiss |
| `Switcher.qml` | ⌘Tab app switcher (Hyprland global shortcuts or IPC) |
| `LockScreen.qml` | `ext-session-lock` surface with PAM authentication |

## Springs, once

A spring is `{ response, dampingFraction }` (the SwiftUI parameterisation).
`design/build.mjs` integrates the damped oscillator analytically and emits:

- **CSS**: a 41-point `linear()` easing plus its settle duration
- **QML**: an 8-segment `Easing.BezierSpline` fitted with Hermite tangents
  (Qt stores at most 8 segments; more overflow its buffer)
- **Hyprland**: a single cubic Bézier approximation, with overshoot folded into y₁

So a Control Center module overshoots by the same amount everywhere.
