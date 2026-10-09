pragma Singleton
import QtQuick
// The preview's screen: the layers Hyprland stacks surfaces in, which layer
// surfaces HyprGlass makes glass of, and the space panels reserve.
QtObject {
    id: desk
    property var screen: ({ name: "eDP-1", width: 1440, height: 900, x: 0, y: 0, model: "Preview", devicePixelRatio: 1 })
    // [background, bottom, windows, top, overlay], set by the harness.
    property var layers: []
    property Item backdrop: null              // what glass blurs: the background layer
    // The same list as compositor/hyprland/hyprglass-sync.sh (tests/liquid-glass.py checks).
    property var glass: ["gg-menubar", "gg-dock", "gg-controlcenter", "gg-spotlight", "gg-notifications",
                         "gg-notification-center", "gg-nearby", "gg-widgets", "gg-widget-gallery", "gg-osd", "gg-alert",
                         "gg-switcher", "gg-screenshot", "gg-screenshot-thumbnail", "gg-citron"]
    // How opaque a pixel must be to become glass, per surface (the same as
    // hyprglass-sync.sh's namespace_mask_thresholds; tests/liquid-glass.py checks).
    property var thresholds: ({ "gg-menubar": 0.05, "gg-dock": 0.25, "gg-controlcenter": 0.25, "gg-spotlight": 0.25, "gg-notifications": 0.25, "gg-notification-center": 0.3, "gg-nearby": 0.25, "gg-widgets": 0.25, "gg-widget-gallery": 0.25, "gg-osd": 0.3, "gg-alert": 0.3, "gg-switcher": 0.3, "gg-screenshot": 0.5, "gg-screenshot-thumbnail": 0.3, "gg-citron": 0.5 })
    property var panels: []
    function register(p) { panels = panels.concat([p]) }
    function unregister(p) { panels = panels.filter((x) => x !== p) }
    function reserved(edge) {
        let r = 0
        for (const p of panels) {
            if (!p.visible || p.exclusiveZone <= 0) continue
            const a = p.anchors
            if (edge === "top" && a.top && !a.bottom) r = Math.max(r, p.exclusiveZone)
            if (edge === "bottom" && a.bottom && !a.top) r = Math.max(r, p.exclusiveZone)
        }
        return r
    }
}
