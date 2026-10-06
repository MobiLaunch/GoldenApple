# Liquid Glass in CitronOS

CitronOS's translucent material, set up from the *Liquid Glass UI in Hyprland*
technical specification and adapted to CitronOS's shell, Hyprland 0.56 and the
HyprGlass options that exist. Every value below is checked by
`tests/liquid-glass.py`.

## Where each part lives

| Spec | CitronOS | Notes |
|---|---|---|
| Specular borders (`border_size 1`, 45° gradient rim) | `compositor/hyprland/hyprland.conf` `general {}`; per theme in `hyprglass-sync.sh` | Dark: `rgba(ffffff66) → rgba(ffffff11)`, as the spec. Light: the far side darkens (`rgba(ffffffb3) → rgba(0000001f)`), since a white rim disappears on light glass. |
| Gaps 8 / 16 | `general {}` | Windows float, so this affects tiled layouts only; the Window menu's tiling keeps its own 8 px gap. |
| Window opacity 0.88 / 0.78 | `decoration {}`; per setting in `hyprglass-sync.sh` | Clear glass (default): 0.88 / 0.78. Tinted: 0.95 / 0.90. Reduce Transparency: solid, including the per-app rules. |
| Kawase blur (12 × 4 passes, vibrancy 0.35, vibrancy darkness 0.15, contrast 1.2, brightness 1.1, noise 0.015, popups with ignorealpha 0.2) | `design/build.mjs` → `design/dist/hyprland-motion.conf` | HyprGlass replaces this blur on its own surfaces (`manage_window_blur`, `layers:manage_blur`); Hyprland's blur covers menus, popovers and windows HyprGlass skips. |
| Shadows (range 30, power 4, `rgba(00000045)`) | same | Offset 0 10 kept, so shadows fall below windows as on the Mac. |
| Rounding 16 | **22** | Kept at the design system's window radius: CitronOS's apps draw their own 22 px corners and Hyprland's must match them. |
| HyprGlass `enabled`, `noblur`, `skip_opaque_windows`, `blur_strength 1.2`, `refraction_strength 0.08`, `chromatic_aberration 0.03`, `layers { manage_blur, mask_mode auto }` | `compositor/hyprland/hyprglass-sync.sh` | `noblur` isn't a HyprGlass option: `manage_window_blur 1` is what sets `noblur` on glassed windows. The spec's physics are the real-GPU profile; virtual machines keep a stronger one, as llvmpipe renders glass faintly. |
| Per-app opacity (editors, terminals, file managers) | `windowrule` in `hyprland.conf` | Written in Hyprland 0.53+ rule syntax (`windowrulev2` is gone). Ghostty (Terminal) 0.85 / 0.75; LCode and TextEdit 0.88 / 0.80; Files 0.90 / 0.82; the spec's own classes are kept too. Full-screen windows, video and games stay solid. |
| Layer blur for the bar, launcher and notifications (Waybar, rofi, swaync) | HyprGlass layer namespaces | CitronOS's shell is Quickshell: every `gg-*` surface drawn with glass is a HyprGlass layer, with a mask threshold above its shadow and below its tint. Menus that shell surfaces open get `blur_popups`. |
| Waybar glass style | `shell/MenuBar.qml` | The menu bar is an 8% white film with a lit hairline along the bottom; HyprGlass makes it glass. Solid with Reduce Transparency. |

## Surfaces and thresholds

| Namespace | What | Threshold |
|---|---|---|
| `gg-menubar` | menu bar | 0.05 |
| `gg-dock` | Dock | 0.08 |
| `gg-controlcenter` | Control Center | 0.08 |
| `gg-spotlight` | Spotlight | 0.08 |
| `gg-applications` | Launchpad | 0.06 |
| `gg-notifications` | notification banners | 0.08 |
| `gg-notification-center` | Notification Center | 0.3 |
| `gg-nearby` | pairing card | 0.08 |
| `gg-widgets`, `gg-widget-gallery` | desktop widgets and their gallery | 0.2 |
| `gg-osd` | volume and brightness | 0.3 |
| `gg-alert` | Restart / Shut Down / Log Out | 0.3 |
| `gg-switcher` | ⌘Tab | 0.3 |
| `gg-screenshot` | ⇧⌘5 toolbar (its 40% dim stays clear) | 0.5 |
| `gg-screenshot-thumbnail` | the floating thumbnail | 0.3 |
| `gg-citron` | Citron's voice capsule (its edge glow stays under the line, clear) | 0.5 |

A pixel more opaque than the threshold becomes glass, so a threshold sits
above the surface's shadow (or dim) and below its tint.

## Checking it on a running system

```sh
hyprctl configerrors                                   # should print nothing
hyprctl getoption plugin:hyprglass:refraction_strength
hyprctl getoption decoration:active_opacity
hyprctl hyprglass stats                                # glass cache hits per monitor
```
