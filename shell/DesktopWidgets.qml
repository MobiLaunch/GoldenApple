// Desktop widgets, as on the Mac: Calendar, Clock, Weather, Music, Notes and
// Batteries on the desktop, under your windows. Drag one to move it (it snaps
// to the desktop's grid and never covers another); right-click it for its
// sizes, Edit Widgets… and Remove Widget. Edit Widgets… (here or on the
// desktop's menu) opens the gallery along the bottom of the screen: click a
// widget there to add it, click a widget's − to remove it, Done to finish.
// They're kept in desktop.json ("widgets"), on the main screen.
//   qs ipc call widgets edit | done | add calendar medium
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "ui/theme"
import "ui" as Shared
import "components"
import "widgets"
import "widgets/layout.js" as Layout

Scope {
    id: root
    property var screen: Quickshell.screens[0] ?? null
    property bool editing: false

    readonly property var catalog: [
        { kind: "calendar", name: "Calendar", sizes: ["small", "medium"], app: "org.goldengate.Calendar",
          about: "See the month at a glance, and what's up next today." },
        { kind: "clock", name: "Clock", sizes: ["small"], app: "",
          about: "Keep the time in view, with the second hand sweeping." },
        { kind: "weather", name: "Weather", sizes: ["small", "medium"], app: "org.goldengate.Weather",
          about: "Conditions where you are, and the next few hours." },
        { kind: "music", name: "Music", sizes: ["small", "medium"], app: "org.goldengate.Music",
          about: "What's playing, with controls to pause and skip." },
        { kind: "notes", name: "Notes", sizes: ["small", "medium"], app: "org.goldengate.Notes",
          about: "The note you worked on last." },
        { kind: "battery", name: "Batteries", sizes: ["small"], app: "",
          about: "How much charge this computer has left." }
    ]
    function info(kind) { return catalog.find((c) => c.kind === kind) ?? catalog[0] }

    // ------------------------------------------------------------ the widgets
    readonly property var items: Prefs.widgets ?? Layout.defaults()
    readonly property var grid: Layout.grid(board.width, board.height)
    property string leaving: ""         // the widget fading out before it goes
    property string arrived: ""         // the widget just added, which pops in

    function add(kind, size) {
        const at = Layout.firstFree(items, size, grid)
        if (!at) return false
        let n = 1
        while (items.some((w) => w.id === kind + "-" + n)) n++
        arrived = kind + "-" + n
        Prefs.setWidgets(items.concat([{ id: arrived, kind: kind, size: size, col: at.col, row: at.row }]))
        return true
    }
    function remove(id) {
        if (leaving) return
        leaving = id
        removal.restart()
    }
    function move(id, col, row) {
        Prefs.setWidgets(items.map((w) => w.id === id ? Object.assign({}, w, { col: col, row: row }) : w))
    }
    function resize(id, size) {
        const w = items.find((i) => i.id === id)
        const next = w ? Layout.resized(items, w, size, grid) : null
        if (next) Prefs.setWidgets(items.map((i) => i.id === id ? next : i))
    }
    Timer {
        id: removal
        interval: Theme.reduceMotion ? 1 : 240
        onTriggered: { Prefs.setWidgets(root.items.filter((w) => w.id !== root.leaving)); root.leaving = "" }
    }
    function open(kind) {
        const app = info(kind).app
        if (kind === "battery") Quickshell.execDetached(["gg-settings", "battery"])
        else if (app) DesktopEntries.byId(app)?.execute()
    }

    // The widgets as a model that keeps each one's delegate across changes, so
    // a moved widget glides to its new place instead of being rebuilt there.
    ListModel { id: widgetModel }
    function sync() {
        for (let i = widgetModel.count - 1; i >= 0; i--)
            if (!items.some((w) => w.id === widgetModel.get(i).wid)) widgetModel.remove(i)
        for (const w of items) {
            let i = 0
            while (i < widgetModel.count && widgetModel.get(i).wid !== w.id) i++
            const row = { wid: w.id, kind: w.kind, size: w.size, col: w.col, row: w.row }
            if (i < widgetModel.count) widgetModel.set(i, row)
            else widgetModel.append(row)
        }
    }
    onItemsChanged: sync()
    Component.onCompleted: sync()

    Feeds { id: shared; wantNotes: root.editing || root.items.some((w) => w.kind === "notes") }

    IpcHandler {
        target: "widgets"
        function edit(): void { root.editing = true }
        function done(): void { root.editing = false }
        function add(kind: string, size: string): void { root.add(kind, size || "small") }
    }

    PanelWindow {
        id: board
        screen: root.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "gg-widgets"
        color: "transparent"
        // Input only where the widgets are, so the desktop's own menu still
        // opens around them; all of it while editing (a click away is Done).
        mask: Region { item: root.editing ? everything : null; regions: root.editing ? [] : tiles.regions }

        Item { id: everything; anchors.fill: parent }
        MouseArea {
            anchors.fill: parent
            enabled: root.editing
            onClicked: root.editing = false
        }

        // Where a dragged widget will land.
        Rectangle {
            id: landing
            property var at: null
            property string size: "small"
            visible: at !== null
            x: at ? Layout.x(at.col) : 0
            y: at ? Layout.y(at.row) : 0
            width: Layout.pixels(size).width; height: Layout.pixels(size).height
            radius: 22
            color: "#1fffffff"
            border { width: 1; color: "#40ffffff" }
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        Repeater {
            id: tiles
            model: widgetModel
            // One input region per widget.
            property var regions: []
            onItemAdded: (i, item) => regions = regions.concat([item.hit])
            onItemRemoved: (i, item) => regions = regions.filter((r) => r !== item.hit)

            delegate: Item {
                id: tile
                required property string wid
                required property string kind
                required property string size
                required property int col
                required property int row
                readonly property var px: Layout.pixels(size)
                readonly property bool going: root.leaving === wid
                property Region hit: Region { item: tile }

                // Where it is on the grid, plus how far it's been dragged (or
                // has yet to glide after a drop).
                property real ox: 0
                property real oy: 0
                property bool dragging: false
                x: Layout.x(col) + ox
                y: Layout.y(row) + oy
                width: px.width; height: px.height
                z: dragging ? 10 : 0
                Behavior on width { NumberAnimation { duration: Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } }
                Behavior on height { NumberAnimation { duration: Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } }

                property bool shown: root.arrived !== wid
                Component.onCompleted: if (!shown) Qt.callLater(() => { tile.shown = true; root.arrived = "" })
                opacity: shown && !going ? 1 : 0
                scale: !shown || going ? 0.7 : dragging ? 1.04 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.bouncy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.bouncy.curve } }

                ParallelAnimation {
                    id: settle
                    NumberAnimation { target: tile; property: "ox"; to: 0; duration: Theme.reduceMotion ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve }
                    NumberAnimation { target: tile; property: "oy"; to: 0; duration: Theme.reduceMotion ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve }
                }

                Glass {
                    anchors.fill: parent
                    role: "regular"
                    radius: 22
                    visible: !face.ownBackground
                    hovered: area.containsMouse && !root.editing
                }
                Face {
                    id: face
                    anchors.fill: parent
                    kind: tile.kind
                    size: tile.size
                    feeds: shared
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property point start
                    property bool moved: false
                    onPressed: (m) => {
                        if (m.button !== Qt.LeftButton) return
                        settle.stop()
                        start = mapToItem(everything, m.x, m.y)
                        moved = false
                    }
                    onPositionChanged: (m) => {
                        if (!pressed || !(m.buttons & Qt.LeftButton)) return
                        const p = mapToItem(everything, m.x, m.y)
                        if (!moved && Math.hypot(p.x - start.x, p.y - start.y) < 6) return
                        if (!moved) { moved = true; tile.dragging = true }
                        tile.ox = p.x - start.x
                        tile.oy = p.y - start.y
                        const cell = Layout.cellAt(tile.x, tile.y)
                        landing.size = tile.size
                        landing.at = Layout.nearest(root.items, { id: tile.wid, size: tile.size }, cell.col, cell.row, root.grid)
                    }
                    onReleased: (m) => {
                        if (!moved) return
                        const at = landing.at, was = Qt.point(tile.x, tile.y)
                        landing.at = null
                        if (at && (at.col !== tile.col || at.row !== tile.row)) root.move(tile.wid, at.col, at.row)
                        // Still where it was let go; glide into the cell.
                        tile.ox = was.x - Layout.x(tile.col)
                        tile.oy = was.y - Layout.y(tile.row)
                        tile.dragging = false
                        settle.restart()
                    }
                    onCanceled: { landing.at = null; tile.dragging = false; settle.restart() }
                    onClicked: (m) => {
                        if (moved) return
                        if (m.button === Qt.RightButton) {
                            const p = mapToItem(everything, m.x, m.y)
                            widgetMenu.show(tile, p.x, p.y)
                        } else if (!root.editing) root.open(tile.kind)
                    }
                }

                // The remove button while editing.
                Rectangle {
                    x: -8; y: -8
                    width: 22; height: 22; radius: 11
                    color: Theme.dark ? "#5a5a5e" : "#e8e8ed"
                    border { width: 0.5; color: Theme.dark ? "#33ffffff" : "#26000000" }
                    scale: root.editing ? (minus.pressed ? 0.88 : 1) : 0.4
                    opacity: root.editing ? 1 : 0
                    visible: opacity > 0
                    Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.bouncy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.bouncy.curve } }
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: Theme.dark ? "white" : "#3c3c43" }
                    MouseArea { id: minus; anchors.fill: parent; anchors.margins: -4; onClicked: root.remove(tile.wid) }
                }
            }
        }

        MenuPopup {
            id: widgetMenu
            property Item target: null
            property real px: 0
            property real py: 0
            function show(t, x, y) { target = t; px = x; py = y; open = true }
            anchor.window: board
            anchor.rect.x: Math.min(px, Math.max(0, board.width - menuWidth - 8))
            anchor.rect.y: Math.min(py, Math.max(0, board.height - menuHeight - 8))
            items: {
                const t = target
                if (!t) return []
                const sizes = root.info(t.kind).sizes
                const rows = sizes.length > 1 ? sizes.map((s) => ({
                    label: s[0].toUpperCase() + s.slice(1), checked: s === t.size,
                    enabled: s === t.size || !!Layout.resized(root.items, root.items.find((w) => w.id === t.wid) ?? {}, s, root.grid),
                    action: () => root.resize(t.wid, s)
                })).concat(["-"]) : []
                return rows.concat([
                    { label: "Edit Widgets…", action: () => root.editing = true },
                    "-",
                    { label: "Remove Widget", action: () => root.remove(t.wid) }
                ])
            }
        }
        HyprlandFocusGrab {
            windows: [widgetMenu]
            active: widgetMenu.open
            onCleared: widgetMenu.open = false
        }
    }

    // ------------------------------------------------------------ the gallery
    PanelWindow {
        id: gallery
        screen: root.screen
        anchors.bottom: true
        margins.bottom: 104           // above the Dock
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gg-widget-gallery"
        WlrLayershell.keyboardFocus: root.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"
        implicitWidth: Math.min((root.screen?.width ?? 1440) - 48, 960)
        implicitHeight: 404
        visible: root.editing || sheet.opacity > 0
        property string filter: ""

        Glass {
            id: sheet
            width: parent.width; height: parent.height
            role: "menu"
            radius: 28
            opacity: root.editing ? 1 : 0
            y: root.editing ? 0 : 60
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } }
            Keys.onEscapePressed: root.editing = false
            focus: root.editing

            // The apps with widgets.
            Column {
                id: side
                x: 14; y: 16
                width: 196
                spacing: 2
                Text {
                    leftPadding: 10; bottomPadding: 6
                    text: "Widgets"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.Bold }
                }
                Repeater {
                    model: [{ kind: "", name: "All Widgets" }].concat(root.catalog)
                    Rectangle {
                        required property var modelData
                        readonly property bool chosen: gallery.filter === modelData.kind
                        width: side.width; height: 32; radius: 8
                        color: chosen ? Theme.selection : rowHover.hovered ? Theme.fill : "transparent"
                        Image {
                            id: appIcon
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22
                            source: parent.modelData.app ? (Quickshell.iconPath(DesktopEntries.byId(parent.modelData.app)?.icon ?? "", true) || "") : ""
                            sourceSize: Qt.size(44, 44)
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; radius: 6
                            visible: !appIcon.visible
                            color: parent.modelData.kind === "clock" ? "#1c1c1e" : parent.modelData.kind === "battery" ? "#30d158" : Theme.accent
                            Shared.Symbol {
                                anchors.centerIn: parent
                                name: parent.parent.modelData.kind === "clock" ? "clock" : parent.parent.modelData.kind === "battery" ? "bolt" : "grid"
                                tone: "white"; size: 13
                            }
                        }
                        Text {
                            x: 38; anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.name
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: parent.chosen ? Font.DemiBold : Font.Normal }
                        }
                        HoverHandler { id: rowHover }
                        TapHandler { onTapped: gallery.filter = parent.modelData.kind }
                    }
                }
            }
            Rectangle { x: side.x + side.width + 12; y: 16; width: 1; height: parent.height - 32; color: Theme.separator }

            // The widgets on offer, at each size; click one to add it.
            Item {
                id: shelf
                x: side.x + side.width + 26
                width: parent.width - x - 20
                height: parent.height
                readonly property var chosen: gallery.filter ? root.info(gallery.filter) : null
                Text {
                    y: 18
                    width: parent.width - done.width - 12
                    text: shelf.chosen ? shelf.chosen.name : "All Widgets"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.Bold }
                }
                Text {
                    y: 42
                    width: parent.width - done.width - 12
                    text: shelf.chosen ? shelf.chosen.about : "Click a widget to add it to your desktop. Drag widgets on the desktop to move them."
                    color: Theme.secondaryLabel
                    elide: Text.ElideRight
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Shared.Button {
                    id: done
                    anchors { right: parent.right; top: parent.top; topMargin: 18 }
                    text: "Done"
                    prominent: true
                    onClicked: root.editing = false
                }
                Flickable {
                    id: strip
                    y: 70
                    width: parent.width
                    height: parent.height - y - 8
                    contentWidth: width
                    contentHeight: offers.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Flow {
                        id: offers
                        width: strip.width
                        spacing: 20
                        topPadding: 12
                        leftPadding: 10
                        rightPadding: 10
                        readonly property real k: 0.7
                        Repeater {
                            model: {
                                const list = []
                                for (const c of root.catalog)
                                    if (!gallery.filter || c.kind === gallery.filter)
                                        for (const s of (gallery.filter ? c.sizes : c.sizes.slice(0, 1))) list.push({ kind: c.kind, size: s, name: c.name })
                                return list
                            }
                            Column {
                                id: offer
                                required property var modelData
                                spacing: 8
                                readonly property var px: Layout.pixels(modelData.size)
                                Item {
                                    width: offer.px.width * offers.k; height: offer.px.height * offers.k
                                    Item {
                                        id: preview
                                        width: offer.px.width; height: offer.px.height
                                        scale: offers.k * (pick.pressed ? 0.96 : pick.containsMouse ? 1.03 : 1)
                                        transformOrigin: Item.TopLeft
                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                        Glass { anchors.fill: parent; role: "regular"; radius: 22; visible: !previewFace.ownBackground }
                                        Face { id: previewFace; anchors.fill: parent; kind: offer.modelData.kind; size: offer.modelData.size; feeds: shared }
                                    }
                                    // The add badge, as the Mac shows it on hover.
                                    Rectangle {
                                        x: -7; y: -7
                                        width: 22; height: 22; radius: 11
                                        color: "#30d158"
                                        opacity: pick.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                        Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: "white" }
                                        Rectangle { anchors.centerIn: parent; width: 2; height: 10; radius: 1; color: "white" }
                                    }
                                    MouseArea {
                                        id: pick
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.add(offer.modelData.kind, offer.modelData.size)
                                    }
                                }
                                Text {
                                    width: offer.px.width * offers.k
                                    horizontalAlignment: Text.AlignHCenter
                                    text: gallery.filter ? offer.modelData.size[0].toUpperCase() + offer.modelData.size.slice(1) : offer.modelData.name
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
