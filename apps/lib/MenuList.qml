// The CitronOS menu: one look for every menu in the system (the menu bar's
// menus, context menus, pop-up buttons, the Dock's menus), drawn to the macOS
// menu metrics. PopupMenu shows it inside a window; the shell's MenuPopup
// shows it in its own surface. Items:
//   { text, shortcut, action, enabled, checked, symbol, destructive, submenu: [items] }
//   { header: "Title" }          a section title
//   { separator: true } or "-"   a separator
// `label` is accepted for `text`. Rows are 24 px with the highlight inset 5 px
// from the edge in the accent; a chosen row flashes before `chosen` fires, as
// on the Mac. Arrow keys move, Right opens a submenu, Left closes one.
import QtQuick
import QtQuick.Window
import "theme"

Glass {
    id: list
    property var items: []
    property real minimumWidth: 200
    property real maximumWidth: 360
    property int selected: -1
    property bool isSubmenu: false
    signal chosen(var item)
    signal dismissed()                  // Escape
    signal back()                       // Left in a submenu

    role: "menu"
    radius: Theme.radiusMenu
    width: Math.max(minimumWidth, Math.min(maximumWidth, widest + 2 * pad))
    // Height from the items, not the column: a popup surface needs its size
    // before the column has laid out, and a late resize dismisses it.
    implicitHeight: items.reduce((h, it) => h + rowHeight(it), 0) + 2 * pad
    height: implicitHeight
    activeFocusOnTab: false

    readonly property real pad: 5
    readonly property bool flashing: flash.running
    readonly property bool hasChecks: items.some((it) => it && it.checked !== undefined)
    readonly property bool hasSymbols: items.some((it) => it && !!it.symbol)
    readonly property real lead: 10 + (hasChecks ? 14 : 0) + (hasSymbols ? 22 : 0)
    property real widest: 0

    function kind(it) {
        return it === "-" || (it && it.separator) ? "separator" : it && it.header !== undefined ? "header" : "item"
    }
    function rowHeight(it) {
        const k = kind(it)
        return k === "separator" ? 11 : k === "header" ? 22 : 24
    }
    function available(i) {
        const it = items[i]
        return i >= 0 && i < items.length && kind(it) === "item" && it.enabled !== false
    }
    function move(step) {
        for (let n = 1; n <= items.length; n++) {
            const i = ((selected < 0 ? (step > 0 ? -1 : 0) : selected) + step * n + items.length) % items.length
            if (available(i)) { select(i); return }
        }
    }
    function select(i) {
        if (selected !== i) closeSubmenu()
        selected = i
        const row = rows.itemAt(i)
        if (row) flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height),
            row.y < flick.contentY ? row.y : row.y + row.height > flick.contentY + flick.height ? row.y + row.height - flick.height : flick.contentY))
    }
    function selectFirst() { selected = -1; move(1) }
    function scrollTo(i) {
        const row = rows.itemAt(i)
        if (row) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, row.y - flick.height / 2 + row.height / 2))
        if (available(i)) select(i)
    }
    function cancelPending() {
        if (flash.running) flash.stop()
        blink = false
    }
    function activate(i) {
        if (i === undefined) i = selected
        if (!available(i) || flashing) return
        selected = i
        if (items[i].submenu) { openSubmenu(i, true); return }
        if (Theme.reduceMotion) list.chosen(items[i])
        else flash.restart()
    }
    function openSubmenu(i, focus) {
        const row = rows.itemAt(i)
        if (!row || !sub || !items[i].submenu) return
        col.forceLayout()
        sub.items = items[i].submenu
        sub.selected = -1
        const right = list.mapToItem(null, list.width + sub.width, 0).x
        const room = list.Window.window ? list.Window.window.width : Infinity
        sub.x = right - 4 > room ? 4 - sub.width : list.width - 4
        sub.y = row.y - flick.contentY
        sub.visible = true
        selected = i
        if (focus) { sub.forceActiveFocus(); sub.selectFirst() }
    }
    function closeSubmenu() {
        if (!sub || !sub.visible) return
        sub.closeSubmenu()
        sub.visible = false
        list.forceActiveFocus()
    }

    Keys.onDownPressed: move(1)
    Keys.onUpPressed: move(-1)
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onSpacePressed: activate()
    Keys.onRightPressed: if (available(selected) && items[selected].submenu) openSubmenu(selected, true)
    Keys.onLeftPressed: if (isSubmenu) back()
    Keys.onEscapePressed: { cancelPending(); dismissed() }

    // The chosen row blinks off and on before the menu goes, as on the Mac.
    SequentialAnimation {
        id: flash
        PropertyAction { target: list; property: "blink"; value: true }
        PauseAnimation { duration: 70 }
        PropertyAction { target: list; property: "blink"; value: false }
        PauseAnimation { duration: 70 }
        ScriptAction { script: list.chosen(list.items[list.selected]) }
    }
    property bool blink: false

    // Measure the widest row so the menu fits its longest label and shortcut.
    TextMetrics { id: metrics; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
    function measure() {
        let w = 0
        for (const it of items) {
            if (kind(it) !== "item") continue
            metrics.text = it.text ?? it.label ?? ""
            let rowW = lead + metrics.advanceWidth + 12
            if (it.shortcut) { metrics.text = it.shortcut; rowW += 28 + metrics.advanceWidth }
            if (it.submenu) rowW += 24
            w = Math.max(w, rowW)
        }
        widest = w
    }
    onItemsChanged: measure()
    Component.onCompleted: measure()

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // clicks inside stay inside

    Flickable {
        id: flick
        anchors { fill: parent; margins: list.pad }
        contentHeight: col.height
        clip: contentHeight > height
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: flick.width
            Repeater {
                id: rows
                model: list.items
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property string kind: list.kind(modelData)
                    readonly property bool on: kind === "item" && modelData.enabled !== false
                    readonly property bool lit: on && list.selected === index && !list.blink
                    width: col.width
                    height: list.rowHeight(modelData)

                    Rectangle {
                        visible: row.kind === "separator"
                        anchors.centerIn: parent
                        width: parent.width - 20; height: 1
                        color: Theme.separator
                    }
                    Text {
                        visible: row.kind === "header"
                        x: 10; anchors { bottom: parent.bottom; bottomMargin: 4 }
                        text: row.kind === "header" ? row.modelData.header : ""
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMenuItem
                        color: Theme.accent
                        opacity: row.lit ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: Theme.reduceMotion ? 0 : 65; easing.type: Easing.OutCubic }
                        }
                    }
                    Symbol {
                        visible: row.kind === "item" && row.modelData.checked === true
                        x: 9; anchors.verticalCenter: parent.verticalCenter
                        name: "checkmark"; size: 11
                        tone: row.lit ? "white" : row.on ? "auto" : "gray"
                    }
                    Symbol {
                        visible: row.kind === "item" && !!row.modelData.symbol
                        x: 10 + (list.hasChecks ? 14 : 0); anchors.verticalCenter: parent.verticalCenter
                        name: row.kind === "item" ? (row.modelData.symbol ?? "") : ""; size: 14
                        tone: row.lit ? "white" : row.modelData.destructive ? "red" : row.on ? "auto" : "gray"
                        opacity: row.on ? 1 : 0.5
                    }
                    Text {
                        visible: row.kind === "item"
                        x: list.lead
                        anchors.verticalCenter: parent.verticalCenter
                        width: (shortcut.visible ? shortcut.x - 12 : chevron.visible ? chevron.x - 6 : parent.width - 10) - x
                        elide: Text.ElideRight
                        text: row.kind === "item" ? (row.modelData.text ?? row.modelData.label ?? "") : ""
                        color: row.lit ? "#ffffff" : !row.on ? Theme.tertiaryLabel
                            : row.modelData.destructive ? Theme.accentRed : Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                    Text {
                        id: shortcut
                        visible: row.kind === "item" && !!row.modelData.shortcut
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: visible ? row.modelData.shortcut : ""
                        color: row.lit ? "#d9ffffff" : row.on ? Theme.secondaryLabel : Theme.tertiaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                    Symbol {
                        id: chevron
                        visible: row.kind === "item" && !!row.modelData.submenu
                        anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                        name: "chevron-right"; size: 10
                        tone: row.lit ? "white" : "gray"
                    }
                    HoverHandler {
                        enabled: row.on
                        onHoveredChanged: if (hovered) {
                            list.select(row.index)
                            if (row.modelData.submenu) list.openSubmenu(row.index, false)
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: row.on
                        onClicked: list.activate(row.index)
                    }
                }
            }
        }
    }
    Scroller { flickable: flick }

    // A submenu opens beside its row, on the side with room. Loaded by URL: a
    // component can't name itself.
    Loader {
        id: subLoader
        z: 10
        active: list.items.some((it) => it && it.submenu)
        source: active ? Qt.resolvedUrl("MenuList.qml") : ""
        onLoaded: {
            item.isSubmenu = true
            item.visible = false
            item.minimumWidth = 160
            item.chosen.connect((it) => list.chosen(it))
            item.dismissed.connect(() => list.dismissed())
            item.back.connect(() => list.closeSubmenu())
        }
    }
    readonly property var sub: subLoader.item
}
