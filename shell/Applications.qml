// Launchpad: every app on pages of large icons over the blurred desktop, as on
// the Mac. The wallpaper blurs and dims behind a small search field; the
// icons sit in a 7 × 5 grid (fewer columns on narrow screens) with page dots
// below. Swipe, scroll, or press ← → to change pages; type to search; Return
// opens the first result; Escape or a click on empty space closes. It zooms
// in as it opens and back out as it closes. CitronOS's own apps come first,
// in the Dock's order, then everything else alphabetically. System apps
// without a CitronOS icon gather in an Other folder, as on the Mac, so the
// grid stays in one style; a search still finds them.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import "ui/theme"
import "ui/paths.js" as Paths
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
            { label: "Open New Window", action: () => entry.execute() },
            "-",
            Prefs.keptInDock.includes(entry.id)
                ? { label: "Remove from Dock", action: () => Prefs.setDockPinned(Prefs.keptInDock.filter((id) => id !== entry.id)) }
                : { label: "Add to Dock", action: () => Prefs.setDockPinned(Prefs.keptInDock.concat([entry.id])) }
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
    function dismiss() { open = false; search.text = ""; folder = null }
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
        "org.goldengate.TextEdit", "org.goldengate.LCode", "org.goldengate.AirDrop", "org.goldengate.Passwords", "org.goldengate.Software", "org.goldengate.Settings",
        "org.goldengate.Terminal", "org.goldengate.DiskUtility"
    ]
    // Utilities, as on the Mac: CitronOS's own (Terminal, Disk Utility) and
    // other apps that say they're system tools (their desktop file's
    // Categories), whatever their icon. Apps you installed stay on the grid.
    readonly property var firstPartyUtilities: ["org.goldengate.Terminal", "org.goldengate.DiskUtility"]
    readonly property var utilityCategories: ["System", "Settings", "DesktopSettings", "HardwareSettings", "Monitor",
        "TerminalEmulator", "PackageManager", "Security", "Filesystem", "Archiving", "Compression", "Accessibility"]
    function utility(e) {
        if (firstPartyUtilities.includes(e.id)) return true
        if (String(e.id).startsWith("org.goldengate.") || userApps[e.id]) return false
        const cats = [...(e.categories ?? [])].map(String)
        return cats.some((c) => utilityCategories.includes(c)) || (grouped(e) && cats.includes("Utility"))
    }
    // Icon names the CitronOS theme draws itself, and the desktop files of
    // apps you installed (Flatpak, or your own): both stay on the grid.
    property var customIcons: ({})
    property var userApps: ({})
    property bool scanned: false
    Process {
        running: true
        command: ["sh", "-c", `
            IFS=:
            for d in "\${XDG_DATA_HOME:-$HOME/.local/share}" \${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
              for f in "$d"/icons/GoldenGate/*/apps/*; do [ -e "$f" ] && echo "icon \${f##*/}"; done
            done
            for d in "$HOME/.local/share/applications" "$HOME/.local/share/flatpak/exports/share/applications" /var/lib/flatpak/exports/share/applications; do
              for f in "$d"/*.desktop; do [ -e "$f" ] && echo "app \${f##*/}"; done
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = {}, user = {}
                for (const line of text.split("\n")) {
                    const name = line.slice(line.indexOf(" ") + 1)
                    if (line.startsWith("icon ")) icons[name.replace(/\.(png|svg)$/, "")] = true
                    else if (line.startsWith("app ")) user[name.replace(/\.desktop$/, "")] = true
                }
                apps.customIcons = icons
                apps.userApps = user
                apps.scanned = true
            }
        }
    }
    function grouped(e) {
        if (!scanned || String(e.id).startsWith("org.goldengate.") || userApps[e.id]) return false
        const icon = String(e.icon ?? "")
        return icon.startsWith("/") || !customIcons[icon]
    }

    property var folder: null           // the open folder, or null
    readonly property var matches: {
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
    // The grid: a search lists every match; otherwise the Other folder sits
    // after CitronOS's own apps.
    readonly property var entries: {
        if (search.text.trim()) return matches
        // An app that repeats an icon already on the grid (Foot Client and
        // Foot Server beside Foot) joins the folder too.
        const icons = {}, kept = [], others = [], utilities = []
        for (const e of matches) {
            const icon = String(e.icon ?? "")
            const own = String(e.id).startsWith("org.goldengate.")
            if (scanned && utility(e)) utilities.push(e)
            else if (grouped(e) || (!own && icons[icon])) others.push(e)
            else { kept.push(e); icons[icon] = true }
        }
        // A folder of one is just that app.
        const folders = []
        if (utilities.length >= 2) folders.push({ isFolder: true, name: "Utilities", apps: utilities, id: "folder:utilities" })
        else kept.push(...utilities)
        if (others.length >= 2) folders.push({ isFolder: true, name: "Other", apps: others, id: "folder:other" })
        else kept.push(...others)
        if (!folders.length) return matches
        const ownCount = kept.filter((e) => firstParty.indexOf(e.id) >= 0).length
        return kept.slice(0, ownCount).concat(folders, kept.slice(ownCount))
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
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.reduceMotion ? 1 : 225; easing.type: Easing.OutCubic } }

        Image {
            id: wall
            anchors.fill: parent
            source: Paths.fileUrl(Prefs.wallpaper)
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
        // Dim enough that white labels read over the brightest wallpaper.
        Rectangle { anchors.fill: parent; color: Theme.dark ? "#78000000" : "#6b000000" }
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
        color: Qt.rgba(1, 1, 1, search.input.activeFocus ? 0.28 : 0.22)
        border { width: 0.5; color: Qt.rgba(1, 1, 1, 0.34) }
        opacity: backdrop.opacity
        TextField {
            id: search
            anchors { fill: parent; leftMargin: 4; rightMargin: 6 }
            search: true
            bare: true
            placeholder: "Search"
            foreground: "#ffffff"
            placeholderColor: Qt.rgba(1, 1, 1, 0.78)
            input.selectedTextColor: "#ffffff"
            input.font.pixelSize: Theme.fs(13)
            onTextChanged: { pages.currentIndex = 0; pages.positionViewAtBeginning() }
            input.Keys.onEscapePressed: apps.folder ? apps.folder = null : search.text ? search.text = "" : apps.dismiss()
            input.Keys.onReturnPressed: {
                const first = apps.entries[0]
                if (first) first.isFolder ? apps.folder = first : apps.launch(first)
            }
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

        // Opening zooms the icons in from a little larger, as on the Mac. An
        // open folder dims the page behind it.
        opacity: backdrop.opacity * (apps.folder ? 0.1 : 1)
        Behavior on opacity { enabled: !fade.running; NumberAnimation { duration: Theme.reduceMotion ? 1 : 190; easing.type: Easing.OutCubic } }
        interactive: !apps.folder
        scale: apps.open || Theme.reduceMotion ? 1 : 1.08
        Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

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
                        readonly property bool isFolder: !!cell.modelData.isFolder
                        // A folder: frosted rounded square with its first nine apps.
                        Rectangle {
                            visible: cell.isFolder
                            anchors.fill: icon
                            anchors.margins: apps.iconSize * 0.06
                            radius: width * 0.24
                            color: Qt.rgba(1, 1, 1, area.pressed ? 0.12 : 0.2)
                            border { width: 0.5; color: Qt.rgba(1, 1, 1, 0.3) }
                            scale: icon.scale
                            Grid {
                                anchors.centerIn: parent
                                columns: 3
                                spacing: parent.width * 0.06
                                Repeater {
                                    model: cell.isFolder ? cell.modelData.apps.slice(0, 9) : []
                                    delegate: Image {
                                        required property var modelData
                                        width: apps.iconSize * 0.22; height: width
                                        source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                                        sourceSize: Qt.size(width * 2, height * 2)
                                        smooth: true; mipmap: true
                                    }
                                }
                            }
                        }
                        Image {
                            id: icon
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: (apps.cellH - apps.iconSize - 26) / 2 }
                            width: apps.iconSize; height: apps.iconSize
                            opacity: cell.isFolder ? 0 : 1
                            source: cell.isFolder ? "" : Quickshell.iconPath(cell.modelData.icon, "application-x-executable")
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
                            style: Text.Raised; styleColor: "#8c000000"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
                        }
                        MouseArea {
                            id: area
                            anchors { fill: icon; margins: -8; bottomMargin: -30 }
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (cell.isFolder) { if (mouse.button === Qt.LeftButton) apps.folder = cell.modelData }
                                else if (mouse.button === Qt.RightButton) apps.showAppMenu(cell.modelData, cell, mouse.x, mouse.y)
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
            font { family: Theme.fontUi; pixelSize: Theme.fs(20); weight: Font.DemiBold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: search.text.trim() ? "Try another search." : "Run gg-diagnostics and check the CitronOS shell section."
            color: Qt.rgba(1, 1, 1, 0.7)
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
    }

    // --------------------------------------------------------------- folder
    // An open folder: its name over a frosted panel of its apps. A click
    // outside, or Escape, closes it.
    MouseArea {
        anchors.fill: parent
        visible: !!apps.folder
        onClicked: apps.folder = null
    }
    Rectangle {
        id: folderPanel
        readonly property int cols: Math.min(apps.folder ? Math.max(3, Math.min(6, Math.ceil(Math.sqrt(apps.folder.apps.length * 1.6)))) : 4, apps.columns)
        readonly property int count: apps.folder ? apps.folder.apps.length : 0
        readonly property real cell: Math.min(150, apps.cellW)
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 20
        width: cols * cell + 56
        height: Math.min(apps.height - 220, Math.ceil(count / cols) * (apps.iconSize * 0.8 + 52) + 48)
        radius: 36
        color: Theme.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.55) : Qt.rgba(1, 1, 1, 0.22)
        border { width: 0.5; color: Qt.rgba(1, 1, 1, 0.26) }
        visible: opacity > 0
        opacity: apps.folder ? backdrop.opacity : 0
        scale: apps.folder || Theme.reduceMotion ? 1 : 0.86
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 175; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 225; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
        MouseArea { anchors.fill: parent }        // clicks inside stay inside

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 18 }
            text: apps.folder ? apps.folder.name : ""
            color: "#ffffff"
            style: Text.Raised; styleColor: "#8c000000"
            font { family: Theme.fontDisplay; pixelSize: 30; weight: Font.DemiBold }
        }
        Flickable {
            anchors { fill: parent; margins: 24 }
            contentHeight: folderGrid.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Grid {
                id: folderGrid
                anchors.horizontalCenter: parent.horizontalCenter
                columns: folderPanel.cols
                Repeater {
                    model: ScriptModel { values: apps.folder ? apps.folder.apps : [] }
                    delegate: Item {
                        id: fcell
                        required property var modelData
                        width: folderPanel.cell
                        height: apps.iconSize * 0.8 + 52
                        Image {
                            id: ficon
                            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                            width: apps.iconSize * 0.8; height: width
                            source: Quickshell.iconPath(fcell.modelData.icon, "application-x-executable")
                            sourceSize: Qt.size(width * 2, height * 2)
                            smooth: true; mipmap: true
                            scale: farea.pressed && !Theme.reduceMotion ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        }
                        Text {
                            anchors { horizontalCenter: parent.horizontalCenter; top: ficon.bottom; topMargin: 7 }
                            width: folderPanel.cell - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: fcell.modelData.name
                            elide: Text.ElideRight
                            color: "#ffffff"
                            style: Text.Raised; styleColor: "#8c000000"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                        }
                        MouseArea {
                            id: farea
                            anchors { fill: ficon; margins: -8; bottomMargin: -28 }
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) apps.showAppMenu(fcell.modelData, fcell, mouse.x, mouse.y)
                                else apps.launch(fcell.modelData)
                            }
                        }
                    }
                }
            }
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
                Behavior on color { ColorAnimation { duration: 140 } }
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
        active: appMenu.open && !appMenu.reopening
        onCleared: if (!appMenu.reopening) appMenu.open = false
    }
}
