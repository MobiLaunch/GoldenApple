# Liquid Glass compositor backend

Golden Gate no longer maintains its own GLSL Liquid Glass shader.

The compositor optical pipeline is provided by
[HyprGlass](https://github.com/hyprnux/hyprglass), pinned to a release built
against the exact Hyprland ABI shipped by the ISO. Golden Gate's QML `Glass`
components are now responsible only for material tint, borders, highlights,
control state, and interaction; backdrop blur/refraction/chromatic effects are
owned by HyprGlass.

Runtime configuration is centralized in:

- `compositor/hyprland/hyprglass-sync.sh`
- `compositor/hyprland/apply-preferences.sh`

The ISO build verifies the Hyprland version and the downloaded plugin SHA-256
before packaging it. If Hyprland moves to a different ABI, update the pinned
HyprGlass release rather than bypassing the version check.

This keeps one optical implementation for windows and layer surfaces and avoids
double-blurring the same surface through Hyprland's native blur.
