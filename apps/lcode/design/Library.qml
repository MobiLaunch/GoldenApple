// The Library (⇧⌘L), as in Xcode: the components and ready-made pieces you
// can add. Double-click one to add it after the selection, or drag it onto
// the canvas or the outline.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/catalog.js" as Catalog

Popover {
    id: lib
    property var ghost: null
    property string query: ""
    signal chosen(var entry)
    panelWidth: 380
    panelHeight: 470
    modal: !(ghost && ghost.dragging)
    opacity: ghost && ghost.dragging ? 0.15 : 1

    readonly property var entries: {
        const q = query.trim().toLowerCase()
        const out = []
        let section = null
        for (const e of Catalog.CATALOG.library) {
            if (e.section) { section = { section: e.section }; continue }
            const info = Catalog.component(e.type) || {}
            const item = { type: e.type, title: e.title || info.title, symbol: e.symbol || info.symbol,
                           detail: e.detail || info.detail || "", props: e.props || null, children: e.children || null }
            if (q && !(item.title + " " + item.detail + " " + item.type).toLowerCase().includes(q)) continue
            if (section) { out.push(section); section = null }
            out.push(item)
        }
        return out
    }
    property var hovered: null

    onVisibleChanged: if (visible) { search.text = ""; search.input.forceActiveFocus() }

    Column {
        width: parent.width
        spacing: 8
        TextField {
            id: search
            width: parent.width
            height: 30
            search: true
            placeholder: "Filter"
            onTextChanged: lib.query = text
            onAccepted: { const first = lib.entries.find((e) => !e.section); if (first) { lib.chosen(first); lib.close() } }
        }
        Flickable {
            width: parent.width
            height: 470 - 24 - 30 - 8 - 8 - detail.height
            contentHeight: flow.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Flow {
                id: flow
                width: parent.width
                spacing: 4
                Repeater {
                    model: lib.entries
                    delegate: Item {
                        id: tile
                        required property var modelData
                        width: modelData.section ? flow.width : (flow.width - 8) / 3
                        height: modelData.section ? 24 : 74
                        Text {
                            visible: !!tile.modelData.section
                            y: 8
                            text: tile.modelData.section || ""
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                        }
                        Rectangle {
                            visible: !tile.modelData.section
                            anchors.fill: parent
                            radius: 10
                            color: tileArea.containsMouse ? Theme.fill : "transparent"
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 8
                                width: 38; height: 38; radius: 10
                                color: Theme.dark ? "#2c2c2e" : "#ffffff"
                                border { width: 0.5; color: Theme.separator }
                                Symbol { anchors.centerIn: parent; name: tile.modelData.symbol || "square-dashed"; size: 20; tone: "accent" }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 52
                                width: parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.title || ""
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 11 }
                            }
                        }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            enabled: !tile.modelData.section
                            hoverEnabled: true
                            drag.target: lib.ghost
                            drag.threshold: 6
                            onEntered: lib.hovered = tile.modelData
                            onPressed: (m) => {
                                const p = mapToItem(lib.ghost.parent, m.x, m.y)
                                lib.ghost.prepare({ entry: tile.modelData }, tile.modelData.title, tile.modelData.symbol, p.x, p.y)
                            }
                            drag.onActiveChanged: if (drag.active) lib.ghost.begin()
                            onReleased: if (lib.ghost.dragging) { lib.ghost.finish(); lib.close() }
                            onDoubleClicked: { lib.chosen(tile.modelData); lib.close() }
                        }
                    }
                }
            }
        }
        Column {
            id: detail
            width: parent.width
            spacing: 2
            Rectangle { width: parent.width; height: 1; color: Theme.separator }
            Text {
                topPadding: 6
                text: lib.hovered ? lib.hovered.title : "Library"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                height: 32
                wrapMode: Text.Wrap
                text: lib.hovered ? lib.hovered.detail : "Double-click to add after the selection, or drag onto the canvas."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11 }
            }
        }
    }
}
