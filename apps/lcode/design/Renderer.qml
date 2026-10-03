// Draws one screen of a design with real Golden Gate Kit components, the way
// the built app will: every node becomes a Kit item, {templates} and bindings
// follow the runtime's variables, and actions run in its sandbox.
//
// The tree is rebuilt whenever the design changes (designs are small); the
// runtime keeps the variables, so a rebuild doesn't lose what you typed.
import QtQuick
import "../../lib/kit" as Kit
import "../../lib/kit/catalog.js" as Catalog
import "../design.js" as Design

Kit.Screen {
    id: renderer
    property var doc: null
    property string screenId: ""
    property var runtime: null
    property var items: ({})                  // node id → { item, depth, node }
    property int generation: 0
    interactive: true

    readonly property var components: ({})
    function component(type) {
        if (!components[type]) components[type] = Qt.createComponent(Qt.resolvedUrl("../../lib/kit/" + type + ".qml"))
        return components[type]
    }

    onDocChanged: rebuildTimer.restart()
    onScreenIdChanged: rebuildTimer.restart()
    Component.onCompleted: rebuild()
    Timer { id: rebuildTimer; interval: 1; onTriggered: renderer.rebuild() }

    function clear() {
        const old = []
        for (let i = 0; i < contentContainer.children.length; i++) old.push(contentContainer.children[i])
        for (const c of old) { c.visible = false; c.parent = null; c.destroy() }
        items = ({})
    }

    function rebuild() {
        clear()
        if (!doc || !runtime) return
        const screen = Design.screenById(doc, screenId) || doc.screens[0]
        if (!screen) return
        const map = {}
        build(screen.root, contentContainer, 0, map)
        items = map
        generation++
    }

    // Designer-only keys that aren't Kit properties.
    readonly property var designerKeys: ["nodeName", "binding", "visibleWhen", "visibleWhenNot"]

    function build(node, parentItem, depth, map) {
        const info = Catalog.component(node.type)
        const comp = component(node.type)
        if (!info || comp.status !== Component.Ready) {
            if (comp && comp.status === Component.Error) console.warn(comp.errorString())
            return null
        }
        const props = node.props || {}
        const templates = info.templates || []
        const bind = info.bind || null
        const bound = !!(props.binding && bind && bind.prop && renderer.hasVariable(props.binding))
        const initial = {}
        for (const k in props) {
            if (designerKeys.indexOf(k) >= 0) continue
            if (bound && k === bind.prop) continue
            if (templates.indexOf(k) >= 0 && typeof props[k] === "string" && props[k].indexOf("{") >= 0) continue
            initial[k] = props[k]
        }
        const item = comp.createObject(parentItem, initial)
        if (!item) return null
        map[node.id] = { item: item, depth: depth, node: node }
        wire(item, node, info, bound)
        if (node.children && item.contentContainer)
            for (const child of node.children) build(child, item.contentContainer, depth + 1, map)
        return item
    }

    function hasVariable(name) { return !!doc && doc.state.some((v) => v.name === name) }

    function wire(item, node, info, bound) {
        const rt = runtime
        const props = node.props || {}
        for (const k of info.templates || []) {
            const t = props[k]
            if (typeof t === "string" && t.indexOf("{") >= 0) item[k] = Qt.binding(() => rt.text(t))
        }
        if (bound) {
            const v = props.binding
            const bind = info.bind
            item[bind.prop] = Qt.binding(() => rt.values[v])
            if (bind.signal) item[bind.signal].connect((value) => rt.set(v, value))
            if (node.type === "List") {
                item.itemToggled.connect((index, done) => rt.setItem(v, index, "done", done))
                item.itemDeleted.connect((index) => rt.removeAt(v, index))
            }
        }
        if (props.visibleWhen && hasVariable(props.visibleWhen)) {
            const v = props.visibleWhen, not = !!props.visibleWhenNot
            if (info.plain) item.visible = Qt.binding(() => !!rt.values[v] !== not)
            else item.shown = Qt.binding(() => !!rt.values[v] !== not)
        }
        const events = Object.assign({}, info.events || {})
        if (!info.plain && !events.tap) events.tap = "tapped"
        if (node.type === "Link") item.tapped.connect(() => rt.openUrl(rt.text(String(props.url || ""))))
        const actions = node.actions || {}
        for (const ev in actions) {
            const signal = events[ev]
            const list = actions[ev]
            if (!signal || !list || !list.length || !item[signal]) continue
            if (signal === "tapped" && node.type !== "Button" && node.type !== "Link") item.tappable = true
            if (signal === "itemTapped") item[signal].connect((index, row) => rt.perform(list, { index: index, item: row }))
            else item[signal].connect(() => rt.perform(list, null))
        }
    }

    // --------------------------------------------------------- geometry
    function boxOf(entry) { return entry.item.box ? entry.item.box : entry.item }

    function shownInTree(item) {
        for (let p = item; p && p !== renderer; p = p.parent) if (!p.visible || p.opacity === 0) return false
        return true
    }

    // The deepest node under a point (in `from`'s coordinates).
    function nodeAt(from, x, y) {
        let best = null
        for (const id in items) {
            const e = items[id]
            const b = boxOf(e)
            if (!shownInTree(e.item)) continue
            const p = from.mapToItem(b, x, y)
            if (p.x < 0 || p.y < 0 || p.x > b.width || p.y > b.height) continue
            if (!best || e.depth >= best.depth) best = e
        }
        return best ? best.node.id : ""
    }

    // A node's box in `target`'s coordinates.
    function rectOf(id, target) {
        const e = items[id]
        if (!e || !shownInTree(e.item)) return null
        const b = boxOf(e)
        const p = b.mapToItem(target, 0, 0)
        const q = b.mapToItem(target, b.width, b.height)
        return { x: p.x, y: p.y, width: q.x - p.x, height: q.y - p.y }
    }

    // Where a drop at a point would go: { parent, index, line: {x, y, w, h} in target coordinates }.
    function dropTarget(from, x, y, target, exclude) {
        let id = nodeAt(from, x, y)
        // Find the nearest container at or above the node under the pointer.
        let path = id ? Design.pathTo(doc, id) : []
        if (!path.length) {
            const screen = Design.screenById(doc, screenId) || doc.screens[0]
            path = [screen.root.id]
        }
        let containerId = ""
        for (let i = path.length - 1; i >= 0; i--) {
            const n = Design.find(doc, path[i]).node
            if (Catalog.isContainer(n.type) && path[i] !== exclude && !(exclude && Design.isInside(doc, path[i], exclude))) { containerId = path[i]; break }
        }
        if (!containerId) return null
        const container = Design.find(doc, containerId).node
        const kids = (container.children || []).filter((c) => c.id !== exclude)
        const horizontal = container.type === "HStack" || (container.type === "ScrollView" && container.props && container.props.horizontal)
        let index = kids.length
        let line = null
        for (let i = 0; i < kids.length; i++) {
            const r = rectOf(kids[i].id, from)
            if (!r) continue
            const mid = horizontal ? r.x + r.width / 2 : r.y + r.height / 2
            if ((horizontal ? x : y) < mid) {
                index = i
                const t = rectOf(kids[i].id, target)
                if (t) line = horizontal ? { x: t.x - 3, y: t.y, w: 2, h: t.height } : { x: t.x, y: t.y - 3, w: t.width, h: 2 }
                break
            }
        }
        if (!line) {
            const lastRect = kids.length ? rectOf(kids[kids.length - 1].id, target) : null
            const box = rectOf(containerId, target)
            if (lastRect) line = horizontal ? { x: lastRect.x + lastRect.width + 1, y: lastRect.y, w: 2, h: lastRect.height }
                                            : { x: lastRect.x, y: lastRect.y + lastRect.height + 1, w: lastRect.width, h: 2 }
            else if (box) line = { x: box.x + 4, y: box.y + 4, w: Math.max(8, box.width - 8), h: 2 }
        }
        // Keep the index in the document's terms (the excluded node may sit before it).
        if (exclude) {
            const all = container.children || []
            const before = index < kids.length ? kids[index].id : null
            index = before ? all.findIndex((c) => c.id === before) : all.length
        }
        return { parent: containerId, index: index, line: line }
    }
}
