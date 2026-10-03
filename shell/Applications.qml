// Launchpad: every app on pages of large icons over the blurred desktop, as on
// the Mac. The wallpaper blurs and dims behind a small search field; the
// icons sit in a 7 × 5 grid (fewer columns on narrow screens) with page dots
// below. Swipe, scroll, or press ← → to change pages; type to search; Return
// opens the first result; Escape or a click on empty space closes. It zooms
// in as it opens and back out as it closes. Golden Gate's own apps come first,
// in the Dock's order, then everything else alphabetically.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import "ui/theme"
import "components"

PanelWindow {
    id: apps
    property bool open: false
    property real contextX: 0
    property real contextY: 0
    property var contextItems: []

    function showAppMenu(entry, item, localX, localY) {
        const point = item.mapToItem(backdrop, localX, localY)
        contextItems = [
            { label: "Open", action: () => { entry.execute(); apps.dismiss() } },
            { label: "Open New Window", action: () => entry.execute() }
        ]
        contextX = point.x
        contextY = point.y
        appMenu.open = true
    }
    // Avoid QWindow.show()/hide() name collisions. Calling those inherited
    // methods can make the layer surface visible without changing our `open`
    // state, which leaves the launcher fully transparent and non-interactive.
    function present() {
        pages.currentIndex = 0
        pages.positionViewAtBeginning()
        open = true
        console.info("Launchpad opened; visible desktop entries:", entries.length)
        Qt.callLater(() => search.input.forceActiveFocus())
    }
    function dismiss() { open = false; search.text = "" }
    function toggle() { open ? dismiss() : present() }
    function launch(entry) { entry.execute(); dismiss() }

    visible: open || fade.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "gg-applications"
    color: "transparent"
    Item { id: closedMask; width: 0; height: 0; visible: false }
    mask: Region { item: apps.open ? backdrop : closedMask }

    // ------------------------------------------------------------ the apps
    readonly property var firstParty: [
        "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail", "org.goldengate.Messages",
        "org.goldengate.Maps", "org.goldengate.Photos", "org.goldengate.Music", "org.goldengate.Calendar",
        "org.goldengate.Notes", "org.goldengate.Weather", "org.goldengate.Clock", "org.goldengate.Calculator",
        "org.goldengate.TextEdit", "org.goldengate.LCode", "org.goldengate.Software", "org.goldengate.Settings",
        "org.goldengate.Terminal"
    ]
    readonly property var entries: {
        const q = search.text.trim().toLowerCase()
        const list = [...DesktopEntries.applications.values].filter((e) => {
            if (!e || !e.name || e.noDisplay) return false
            if (!q) return true
            return [e.name, e.genericName, e.comment, e.keywords].map((s) => String(s ?? "")).join(" ").toLowerCase().includes(q)
        })
        const rank = (e) => { const i = firstParty.indexOf(e.id); return i < 0 ? 1000 : i }
        // One tile per app: the same app can be listed twice (a user copy of a
        // system entry, a wrapper beside the real thing); the first one wins.
        const seen = {}
        return list.sort((a, b) => rank(a) - rank(b) || String(a.name).localeCompare(String(b.name)))
            .filter((e) => { const k = String(e.name).toLowerCase(); if (seen[k]) return false; seen[k] = true; return true })
    }

    // Grid metrics, from the screen: Launchpad's 7 × 5 with generous margins.
    readonly property int columns: Math.max(4, Math.min(7, Math.floor((width - 160) / 150)))
    readonly property int rows: Math.max(3, Math.min(5, Math.floor((height - 220) / 150)))
    readonly property int perPage: columns * rows
    readonly property int pageCount: Math.max(1, Math.ceil(entries.length / perPage))
    readonly property real gridWidth: Math.min(width - 2 * Math.max(60, width * 0.1), columns * 190)
    readonly property real gridHeight: height - 120 - 90
    readonly property real cellW: gridWidth / columns
    readonly property real cellH: gridHeight / rows
    readonly property real iconSize: Math.round(Math.min(cellW * 0.6, cellH * 0.62, 112))

    // ------------------------------------------------------------ backdrop
    // The desktop, blurred and dimmed, as Launchpad shows it.
    Item {
        id: backdrop
        anchors.fill: parent
        opacity: apps.open ? 1 : 0
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.reduceMotion ? 1 : 260; easing.type: Easing.OutCubic } }

        Image {
            id: wall
            anchors.fill: parent
            source: "file://" + Prefs.wallpaper
            sourceSize: Qt.size(Math.max(1, apps.width / 4), Math.max(1, apps.height / 4))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: wall
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: 0.1
            autoPaddingEnabled: false
        }
        Rectangle { anchors.fill: parent; color: Theme.dark ? "#73000000" : "#40000000" }
        MouseArea {
            anchors.fill: parent
            onClicked: apps.dismiss()
            onWheel: (w) => {
                const d = Math.abs(w.angleDelta.x) > Math.abs(w.angleDelta.y) ? -w.angleDelta.x : -w.angleDelta.y
                if (Math.abs(d) >= 60) pages.flip(d > 0 ? 1 : -1)
            }
        }
    }

    // --------------------------------------------------------------- search
    Rectangle {
        id: searchBox
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 64 }
        width: 236; height: 30; radius: 9
        color: Qt.rgba(1, 1, 1, search.input.activeFocus ? 0.24 : 0.18)
        border { width: 0.5; color: Qt.rgba(1, 1, 1, 0.28) }
        opacity: backdrop.opacity
        TextField {
            id: search
            anchors { fill: parent; leftMargin: 4; rightMargin: 6 }
            search: true
            bare: true
            placeholder: "Search"
            foreground: "#ffffff"
            placeholderColor: Qt.rgba(1, 1, 1, 0.62)
            input.selectedTextColor: "#ffffff"
            input.font.pixelSize: 13
            onTextChanged: { pages.currentIndex = 0; pages.positionViewAtBeginning() }
            input.Keys.onEscapePressed: search.text ? search.text = "" : apps.dismiss()
            input.Keys.onReturnPressed: if (apps.entries.length) apps.launch(apps.entries[0])
            input.Keys.onRightPressed: (e) => { if (!search.text) pages.flip(1); else e.accepted = false }
            input.Keys.onLeftPressed: (e) => { if (!search.text) pages.flip(-1); else e.accepted = false }
        }
    }

    // ---------------------------------------------------------------- pages
    ListView {
        id: pages
        anchors { top: searchBox.bottom; topMargin: 48; horizontalCenter: parent.horizontalCenter }
        width: apps.width
        height: apps.gridHeight
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: Theme.reduceMotion ? 0 : 380
        boundsBehavior: Flickable.StopAtBounds
        clip: false
        model: apps.pageCount
        function flip(step) { currentIndex = Math.max(0, Math.min(count - 1, currentIndex + step)) }

        // Opening zooms the icons in from a little larger, as on the Mac.
        opacity: backdrop.opacity
        scale: apps.open || Theme.reduceMotion ? 1 : 1.08
        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

        delegate: Item {
            id: page
            required property int index
            width: pages.width
            height: pages.height
            // Clicks between the icons close Launchpad, like the backdrop.
            MouseArea { anchors.fill: parent; onClicked: apps.dismiss() }
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: apps.columns
                Repeater {
                    // A ScriptModel keeps each tile alive while the list
                    // changes around it (an app installing while open).
                    model: ScriptModel { values: apps.entries.slice(page.index * apps.perPage, (page.index + 1) * apps.perPage) }
                    delegate: Item {
                        id: cell
                        required property var modelData
                        width: apps.cellW
                        height: apps.cellH
                        Image {
                            id: icon
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: (apps.cellH - apps.iconSize - 26) / 2 }
                            width: apps.iconSize; height: apps.iconSize
                            source: Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
                            sourceSize: Qt.size(apps.iconSize * 2, apps.iconSize * 2)
                            smooth: true; mipmap: true
                            scale: area.pressed && !Theme.reduceMotion ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                            layer.enabled: area.pressed
                            layer.effect: MultiEffect { brightness: -0.3 }
                        }
                        Text {
                            anchors { horizontalCenter: parent.horizontalCenter; top: icon.bottom; topMargin: 8 }
                            width: Math.min(apps.cellW - 10, apps.iconSize + 36)
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.name
                            elide: Text.ElideRight
                            color: "#ffffff"
                            style: Text.Raised; styleColor: "#59000000"
                            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                        }
                        MouseArea {
                            id: area
                            anchors { fill: icon; margins: -8; bottomMargin: -30 }
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) apps.showAppMenu(cell.modelData, cell, mouse.x, mouse.y)
                                else apps.launch(cell.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // Nothing to show.
    Column {
        visible: apps.entries.length === 0
        anchors.centerIn: parent
        spacing: 8
        opacity: backdrop.opacity
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: search.text.trim() ? "No Results" : "No Applications"
            color: "#ffffff"
            font { family: Theme.fontUi; pixelSize: 20; weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: search.text.trim() ? "Try another search." : "Run gg-diagnostics and check the Golden Gate shell section."
            color: Qt.rgba(1, 1, 1, 0.7)
            font { family: Theme.fontUi; pixelSize: 13 }
        }
    }

    // ------------------------------------------------------------ page dots
    Row {
        visible: apps.pageCount > 1
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 46 }
        spacing: 10
        opacity: backdrop.opacity
        Repeater {
            model: apps.pageCount
            delegate: Rectangle {
                required property int index
                width: 7; height: 7; radius: 3.5
                color: index === pages.currentIndex ? "#ffffff" : Qt.rgba(1, 1, 1, 0.38)
                Behavior on color { ColorAnimation { duration: 160 } }
                MouseArea { anchors { fill: parent; margins: -6 } onClicked: pages.currentIndex = parent.index }
            }
        }
    }

    MenuPopup {
        id: appMenu
        anchor.window: apps
        anchor.rect.x: Math.max(8, Math.min(apps.contextX, apps.width - menuWidth - 8))
        anchor.rect.y: Math.max(8, Math.min(apps.contextY, apps.height - menuHeight - 8))
        items: apps.contextItems
    }
    HyprlandFocusGrab {
        windows: [appMenu]
        active: appMenu.open
        onCleared: appMenu.open = false
    }
}
