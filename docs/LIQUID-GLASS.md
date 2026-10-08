# Liquid Glass in CitronOS

CitronOS's translucent material, set up from the *Liquid Glass UI in Hyprland*
technical specification and adapted to CitronOS's shell, Hyprland 0.56 and the
HyprGlass options that exist. Every value below is checked by
`tests/liquid-glass.py`.

## Where each part lives

| Spec | CitronOS | Notes |
|---|---|---|
| Specular borders (`border_size 1`, 45° gradient rim) | `compositor/hyprland/hyprland.conf` `general {}`; per theme in `hyprglass-sync.sh` | Dark: `rgba(ffffff66) → rgba(ffffff11)`, as the spec. Light: the far side darkens (`rgba(ffffffb3) → rgba(0000001f)`), since a white rim disappears on light glass. |
| CitronOS's own glass (`apps/lib/Glass.qml`, materials in `design/tokens.json`) | every QML surface and control | A frosted slab: a neutral tint with the backdrop blurred and coloured through it; a one-pixel white rim lit from the top left and bright all the way round (its dimmest stretch at least a third of its brightest), brightest again at the bottom-right corner; just inside it the darker far edge and the slab's inner face catching the light, which gives the glass its thickness (on glass at least 28 px across); a frosted band inside the edge; a soft shadow. It reacts: a soft light follows the pointer across it and the rim brightens; under the pointer a control lifts a pixel and its shadow deepens; pressed, it gives a few pixels and springs back. Reduce Transparency turns the pointer light off, Reduce Motion the lift. |
| Gaps 8 / 16 | `general {}` | Windows float, so this affects tiled layouts only; the Window menu's tiling keeps its own 8 px gap. |
| Window opacity 1.0 / 1.0 | `decoration {}`; `hyprglass-sync.sh` | Window contents are solid, in front or not, so a document's text and pictures read the same over any wallpaper. The glass is in windows' sidebars and toolbars (drawn see-through by the app over the compositor's blur) and in the shell. Settings › Appearance › Transparency (`glassSolidity`, 0–1) moves that glass toward solid continuously (HyprGlass `glass_opacity` from the style's 0.58 clear / 0.76 tinted toward 0.96; CitronOS's own Glass raises its tint the same way); at Solid, or with Reduce Transparency, every window is solid, terminals included. |
| Kawase blur (12 × 4 passes, vibrancy 0.35, vibrancy darkness 0.15, contrast 1.2, brightness 1.1, noise 0.015, popups with ignorealpha 0.3, above a menu's shadow) | `design/build.mjs` → `design/dist/hyprland-motion.conf` | HyprGlass replaces this blur on its own surfaces (`manage_window_blur`, `layers:manage_blur`); Hyprland's blur covers menus, popovers and windows HyprGlass skips. |
| Shadows (range 30, power 4, `rgba(00000045)`) | same | Offset 0 10 kept, so shadows fall below windows as on the Mac. |
| Rounding 16 | **22** | Kept at the design system's window radius: CitronOS's apps draw their own 22 px corners and Hyprland's must match them. |
| HyprGlass `enabled`, `noblur`, `skip_opaque_windows`, `blur_strength 0.95`, `refraction_strength 0.55`, `edge_thickness 0.08`, `lens_distortion 0.42`, `chromatic_aberration 0.08`, `layers { manage_blur, mask_mode auto }` | `compositor/hyprland/hyprglass-sync.sh` | `noblur` isn't a HyprGlass option: `manage_window_blur 1` is what sets `noblur` on glassed windows. Thick glass: what's behind bends at a wide bevel (pulling in what lies just beyond the edge) and swells a little under the middle, so it visibly morphs as glass moves over it; the blur is light enough for the shapes to read through. These are the real-GPU profile; virtual machines keep a stronger one, as llvmpipe renders glass faintly. Glass an app draws over its own content (a toolbar over a note) bends it the same way in `apps/lib/shaders/glasslens.frag`. HyprGlass bends at the edge of a whole layer surface, not of the glass inside it, so the shell's glass bends with that shader too: each surface draws what's behind it (`shell/components/DesktopBackdrop.qml`: the wallpaper, and live captures of the windows under it, their places asked of Hyprland on every window event and ten times a second while glass is bending them) into one texture its glass samples (`apps/lib/theme/Backdrops.qml`). Each piece of glass samples only the part under it, its place a binding on every item above it (place, size, scale, transforms), so it follows layouts, scrolls and drags yet costs nothing at rest. Over bent content a control's tint thins to 80%, enough for the bending to show and what's on it to stay readable. |
| Per-app opacity (terminals) | `windowrule` in `hyprland.conf` | Written in Hyprland 0.53+ rule syntax (`windowrulev2` is gone). Terminals are a little clearer (0.97 / 0.96), as a Terminal profile can be. CitronOS's own apps draw glass only where it belongs (sidebars, toolbars) and keep their content opaque. Full-screen windows, video and games stay solid. |
| Layer blur for the bar, launcher and notifications (Waybar, rofi, swaync) | HyprGlass layer namespaces | CitronOS's shell is Quickshell: every `gg-*` surface drawn with glass is a HyprGlass layer, with a mask threshold above its shadow and below its tint. Menus that shell surfaces open have no compositor blur (`blur_popups` blurred their whole surface, a box round the menu); their own glass bends what's behind them. |
| Waybar glass style | `shell/MenuBar.qml` | The menu bar is an 8% white film with a lit hairline along the bottom; HyprGlass makes it glass. Solid with Reduce Transparency. |

## Surfaces and thresholds

| Namespace | What | Threshold |
|---|---|---|
| `gg-menubar` | menu bar | 0.05 |
| `gg-dock` | Dock | 0.25 |
| `gg-controlcenter` | Control Center | 0.25 |
| `gg-spotlight` | Spotlight | 0.25 |
| `gg-applications` | Launchpad | 0.06 |
| `gg-notifications` | notification banners | 0.25 |
| `gg-notification-center` | Notification Center | 0.3 |
| `gg-nearby` | pairing card | 0.25 |
| `gg-widgets`, `gg-widget-gallery` | desktop widgets and their gallery | 0.25 |
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
