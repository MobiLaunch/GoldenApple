# Liquid Glass in the compositor

Blur alone produces frosted glass. The Golden Gate material also bends the
backdrop near its rim like a lens and catches light along the edge. On Linux,
only the compositor can see the pixels behind a surface, so that part has to
live in Hyprland.

## Today (works now)

`compositor/hyprland/hyprland.conf` enables Hyprland's dual-Kawase blur on the
shell's layer surfaces (`gg-dock`, `gg-controlcenter`, `gg-spotlight`,
`gg-menubar`). `ignorealpha` keeps the blur to the painted glass shapes. The shell
(`shell/components/Glass.qml`) paints the tint, rim and light catch on top.
The result is the full "regular" material without refraction.

## Next: `hyprglass` plugin (planned)

A small Hyprland plugin that:

1. Hooks layer-surface rendering for namespaces matching `^gg-`.
2. Reads the glass shapes (rect + radius) the shell publishes over a tiny IPC
   (`qs ipc` → plugin socket), since one layer can hold several modules.
3. Renders `liquid-glass.frag` over the already-blurred backdrop for each shape.

`liquid-glass.frag` is written and documented. It uses the same maths as
`prototype/js/glass.js`: a rounded-rect SDF, a smoothstep lens profile across a
bezel band, slight chromatic dispersion, and a light-facing specular rim. The
plugin plumbing is the remaining work.
