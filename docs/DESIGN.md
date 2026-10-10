# Design spec: CitronOS

Values live in `design/tokens.json`; this document explains them.

## Materials: Liquid Glass

Every glass surface has four layers, back to front:

1. **Backdrop**: what's behind, blurred and saturated (compositor or `backdrop-filter`).
2. **Tint**: a translucent fill that sets the material's weight.
3. **Rim**: a 1px gradient edge, brightest where light hits (top-left and
   bottom-right corners), nearly invisible along the sides.
4. **Specular glow**: soft inner highlights hugging the top-left and bottom-right edges.

| Material | Blur | Saturate | Tint (light / dark) | Used for |
|---|---|---|---|---|
| `glassClear` | 18px | 1.9 | white 16% / navy 18% | Control Center modules, Dock, floating controls |
| `glassRegular` | 30px | 1.8 | white 62% / graphite 58% | Spotlight, notifications, widgets, app switcher |
| `menu` | 40px | 1.8 | white 74% / graphite 70% | menus, tooltips |

Control Center adds a faint cool tint (`rgba(28,48,96,.24)`) so white glyphs stay
legible when a bright window is behind it.

Refraction (the backdrop bending near the rim) is specified in
`compositor/liquid-glass/liquid-glass.frag`: a shallow lens across the body and a
stronger bend in a 12–16px rim (strongest at the corners), multi-tap sampling for
thickness, slight dispersion, and a light-facing highlight ribbon with Fresnel
falloff. [compositor/liquid-glass/README.md](../compositor/liquid-glass/README.md)
has a preview.

## Shape

- App icons use a superellipse with n = 5, drawn full bleed; the Dock adds the shadow.
- Radii: menu 14, menu item 8, window 22 (an edge-to-edge sidebar takes the
  window's corners), Control Center panel 22 and its tiles 14, toolbar
  pill 18, Dock 28.
- Hyprland windows use `rounding_power = 3.4` for continuous corners.

## Windows

- **Edge-to-edge sidebar.** Full height and flush with the window's edge, glass,
  rounded only by the window's corners, a hairline where the content begins,
  with the traffic lights inside it. The window's content is solid.
- **No toolbar background.** Controls are glass pills floating over content.
  Content scrolls under them, and a *scroll-edge effect* (blur + fade) appears
  only once scrolled.
- **Traffic lights.** 13px, 8px apart. Glyphs appear on group hover. Grey when the
  window is inactive.
- **Status bar.** Path bar plus an item count, with an icon-size slider in icon view.

## Typography

Inter Variable with `cv05 cv08 ss03`, tracking −0.6%.

| Style | Size | Weight |
|---|---|---|
| Body, menus | 13 | 400 |
| Menu bar app name, toolbar title | 13 / 15 | 700 |
| Sidebar section | 11 | 600 |
| CC module title | 14 | 600 |
| Spotlight field | 21 | 400 |

## Colour

The accent defaults to system blue `#0a84ff`, with eight accents selectable in
Settings. The menu bar has no material: each half picks white or dark text from
the brightness of the wallpaper behind it.

## Motion

| Spring | Response | Damping | Settles | Used for |
|---|---|---|---|---|
| smooth | 0.50 | 1.00 | 734ms | navigation, cross-fades |
| snappy | 0.40 | 0.86 | 557ms | controls, list reveals, sliders |
| bouncy | 0.50 | 0.70 | 818ms | Spotlight appearing, photo zoom |
| popover | 0.38 | 0.78 | 501ms | menus, Control Center modules (staggered 14ms) |
| dock | 0.22 | 0.90 | 293ms | magnification settling |
| window | 0.45 | 0.88 | 622ms | open, zoom, tile |

Signature moments:

- **Control Center** modules spring from the menu-bar button with a 14ms stagger,
  scaling from 0.72 and unblurring. Wi-Fi, Bluetooth, Focus, Display and Sound
  morph into their detail panels (right-click or long-press).
- **Dock** magnification is a cosine falloff over about 3.2 icon widths, measured
  against the resting layout. Launch is a two-hop bounce.
- **Minimise** is a two-stage genie: pinch and fall into the Dock tile.
- **Menus** blink the chosen item once before closing.
- **Photos** uses a shared-element zoom from thumbnail to viewer and back.
- **Appearance changes** cross-fade the whole screen (View Transitions).
