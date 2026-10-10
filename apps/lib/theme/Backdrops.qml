pragma Singleton
import QtQuick

// What Liquid Glass bends (Glass.qml, shaders/glasslens.frag): for each
// window or shell surface that offers one, a texture of what's behind its
// glass. An app window offers its content (AppWindow); a shell surface
// offers the desktop under it, drawn again inside it (the shell's
// DesktopBackdrop). A piece of glass uses the texture of the nearest
// surface it's in, unless it's inside what that texture shows (glass never
// bends itself).
//
// A texture renders only while some glass is sampling it (used()): a hidden
// texture nothing samples stalls the OpenGL renderer, and costs a redraw of
// the window for nothing.
//   Backdrops.add(root, item, texture)   root: the Item the glass is under;
//                                        item: what the texture shows
//   Backdrops.find(glass)                → { root, item, texture } or null
//   Backdrops.use(texture, glass, on)    glass starts or stops sampling it
QtObject {
    property var entries: []
    // Backdrops are drawn at half resolution: the glass blurs what it bends
    // anyway, so it looks the same, and each redraw of one (a scroll, a
    // window moving under the Dock) fills a quarter of the pixels.
    readonly property real resolution: 0.5
    // When the shell last asked Hyprland where the windows are: the list is
    // one for the whole shell, so a surface that asked just now answers for
    // all of them (DesktopBackdrop).
    property real windowsAskedAt: 0
    function askWindows(refresh) {
        const now = Date.now()
        if (now - windowsAskedAt < 90) return
        windowsAskedAt = now
        refresh()
    }
    function textureSize(w, h, dpr) {
        const s = resolution * (dpr > 0 ? dpr : 1)
        return Qt.size(Math.max(1, Math.ceil(w * s)), Math.max(1, Math.ceil(h * s)))
    }
    property var users: []
    function add(root, item, texture, owner) {
        entries = entries.filter((e) => e.texture !== texture)
            .concat([{ root: root, item: item, texture: texture, owner: owner ?? null }])
    }
    function remove(texture) {
        entries = entries.filter((e) => e.texture !== texture)
        users = users.filter((u) => u.texture !== texture)
    }
    function find(glass) {
        for (let p = glass ? glass.parent : null; p; p = p.parent) {
            const e = entries.find((x) => x.root === p)
            if (!e) continue
            for (let q = glass; q; q = q.parent) if (q === e.item) return null
            return e
        }
        return null
    }
    function use(texture, glass, on) {
        const rest = users.filter((u) => u.glass !== glass)
        users = on && texture ? rest.concat([{ texture: texture, glass: glass }]) : rest
    }
    function used(texture) { return users.some((u) => u.texture === texture) }
    // The DesktopBackdrop serving a surface (by its root item), for a popup
    // over it to know where it is.
    function ownerOf(root) { return entries.find((e) => e.root === root)?.owner ?? null }
}
