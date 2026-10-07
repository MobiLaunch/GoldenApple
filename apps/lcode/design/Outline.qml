// The Document Outline, beside the canvas as in Interface Builder: the app,
// its screens with what's on them (drag rows to rearrange), its variables
// and its named colours.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/catalog.js" as Catalog
import "../design.js" as Design

Rectangle {
    id: outline
    property var doc: null
    property string screenId: ""
    property var selection: ({ kind: "app", id: "" })
    property var ghost: null                  // the shared drag ghost
    property var collapsed: ({})              // node id → true
    signal select(var selection)
    signal contextMenu(string id, Item from, real x, real y)
    signal addScreen(Item from)
    signal addVariable(Item from)
    signal addColor()
    signal dropRequested(var payload, string parentId, int index)
    color: Theme.dark ? "#141416" : "#f6f6f8"

    function toggle(id) {
        const c = Object.assign({}, collapsed)
        if (c[id]) delete c[id]; else c[id] = true
        collapsed = c
    }

    readonly property var rows: {
        const out = []
        if (!doc) return out
        out.push({ kind: "app", id: "", title: doc.app.name || "App" })
        out.push({ kind: "header", title: "Screens", add: "screen" })
        for (const s of doc.screens) {
            out.push({ kind: "screen", id: s.id, title: s.title || s.id, symbol: s.symbol || "doc", current: s.id === screenId })
            if (s.id !== screenId) continue
            const hidden = {}
            Design.walk(s.root, (n, parent, depth) => {
                // Hide the contents of collapsed containers.
                if (parent && (collapsed[parent.id] || hidden[parent.id])) { hidden[n.id] = true; return }
                out.push({ kind: "node", id: n.id, depth: depth + 1, type: n.type, title: Design.label(n),
                           container: Catalog.isContainer(n.type), open: !collapsed[n.id], hasChildren: (n.children || []).length > 0 })
            })
        }
        out.push({ kind: "header", title: "Variables", add: "variable" })
        if (!doc.state.length) out.push({ kind: "hint", title: "Variables hold what your app shows and remembers." })
        for (const v of doc.state)
            out.push({ kind: "variable", id: v.name, title: v.name, detail: ({ text: "Text", number: "Number", bool: "On/Off", list: "List" })[v.type] + (v.persist ? " · Saved" : "") })
        out.push({ kind: "header", title: "Colors", add: "color" })
        for (const c of doc.colors)
            out.push({ kind: "color", id: c.name, title: c.name, light: c.light, dark: c.dark })
        return out
    }

    ListView {
        id: list
        anchors { fill: parent; topMargin: 6; bottomMargin: 6 }
        clip: true
        model: outline.rows
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property string kind: modelData.kind
            readonly property bool selected: (kind === "app" && outline.selection.kind === "app")
                || (kind === outline.selection.kind && modelData.id === outline.selection.id)
            width: list.width
            height: kind === "header" ? 30 : kind === "hint" ? 36 : 26

            // Section headers, with their + button.
            Item {
                visible: row.kind === "header"
                anchors.fill: parent
                Text {
                    x: 12; y: 12
                    text: row.modelData.title || ""
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                }
                ToolbarButton {
                    id: addButton
                    anchors { right: parent.right; rightMargin: 6; bottom: parent.bottom }
                    height: 22
                    symbol: "plus"
                    symbolSize: 12
                    Accessible.name: "Add"
                    onClicked: {
                        if (row.modelData.add === "screen") outline.addScreen(addButton)
                        else if (row.modelData.add === "variable") outline.addVariable(addButton)
                        else outline.addColor()
                    }
                }
            }
            Text {
                visible: row.kind === "hint"
                x: 14; width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.Wrap
                text: row.modelData.title || ""
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            }

            SidebarRow {
                id: sidebarRow
                visible: row.kind !== "header" && row.kind !== "hint"
                anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                selected: row.selected
                indent: row.kind === "node" ? row.modelData.depth * 12 : 0
                text: row.modelData.title || ""
                leadingSize: row.kind === "node" ? 30 : 18
                leading: Component {
                    Item {
                        Symbol {
                            visible: row.kind === "node" && row.modelData.container && row.modelData.hasChildren
                            anchors.verticalCenter: parent.verticalCenter
                            name: "chevron-small-right"
                            size: 11
                            tone: "gray"
                            rotation: row.modelData.open ? 90 : 0
                            TapHandler { onTapped: outline.toggle(row.modelData.id) }
                        }
                        Rectangle {
                            visible: row.kind === "color"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16; radius: 4
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.49; color: row.modelData.light || "#000" }
                                GradientStop { position: 0.51; color: row.modelData.dark || "#000" }
                            }
                            border { width: 0.5; color: "#33000000" }
                        }
                        Symbol {
                            visible: row.kind !== "color"
                            x: row.kind === "node" ? 13 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            size: 15
                            name: row.kind === "app" ? "appicon" : row.kind === "screen" ? (row.modelData.symbol || "doc")
                                : row.kind === "variable" ? "curlybraces" : Catalog.symbolFor(row.modelData.type || "")
                            tone: row.kind === "node" ? "auto" : "accent"
                        }
                    }
                }
                onClicked: outline.select({ kind: row.kind, id: row.modelData.id || "" })
            }
            Text {
                visible: row.kind === "variable"
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: row.modelData.detail || ""
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                enabled: row.kind === "node"
                onTapped: (p) => { outline.select({ kind: "node", id: row.modelData.id }); outline.contextMenu(row.modelData.id, row, p.position.x, p.position.y) }
            }

            // Drag a node to move it.
            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: row.kind === "node" && !!outline.ghost && row.modelData.depth > 1
                propagateComposedEvents: true
                drag.target: outline.ghost
                drag.threshold: 6
                onPressed: (m) => {
                    const p = mapToItem(outline.ghost.parent, m.x, m.y)
                    outline.ghost.prepare({ move: row.modelData.id }, row.modelData.title, Catalog.symbolFor(row.modelData.type || ""), p.x, p.y)
                }
                onClicked: (m) => {
                    // The disclosure triangle opens and closes; the rest selects.
                    if (row.modelData.container && m.x < 4 + row.modelData.depth * 12 + 26) outline.toggle(row.modelData.id)
                    else outline.select({ kind: "node", id: row.modelData.id })
                }
                drag.onActiveChanged: if (drag.active) outline.ghost.begin()
                onReleased: outline.ghost.finish()
            }

            // Drop: above, below, or (on a container's middle) inside a row.
            DropArea {
                id: drop
                anchors.fill: parent
                enabled: row.kind === "node"
                keys: ["lcode/component"]
                property string where: ""
                function place(d) {
                    const f = d.y / height
                    where = row.modelData.container && f > 0.3 && f < 0.7 ? "inside" : f < 0.5 ? "before" : "after"
                }
                onEntered: (d) => place(d)
                onPositionChanged: (d) => place(d)
                onExited: where = ""
                onDropped: (d) => {
                    const id = row.modelData.id
                    const payload = d.source && d.source.payload
                    const w = where
                    where = ""
                    if (!payload) return
                    if (w === "inside") { outline.dropRequested(payload, id, -1); return }
                    const hit = Design.find(outline.doc, id)
                    if (!hit || !hit.parent) { outline.dropRequested(payload, id, -1); return }
                    outline.dropRequested(payload, hit.parent.id, hit.index + (w === "after" ? 1 : 0))
                }
            }
            Rectangle {
                visible: drop.where === "before" || drop.where === "after"
                x: 12 + (row.modelData.depth || 0) * 12
                y: drop.where === "before" ? 0 : parent.height - 2
                width: parent.width - x - 8
                height: 2
                radius: 1
                color: Theme.accent
            }
            Rectangle {
                visible: drop.where === "inside"
                anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                radius: 6
                color: "transparent"
                border { width: 2; color: Theme.accent }
            }
        }
    }
}
