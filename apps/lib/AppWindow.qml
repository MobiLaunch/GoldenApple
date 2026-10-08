// A CitronOS app window, drawn by the app as on the Mac: frameless, rounded,
// with traffic lights, a 52 px toolbar row to drag it by, edges to resize from,
// and optionally a sidebar running edge to edge down the window's left side
// (and a trailing one, for inspectors, on the right), as Golden Gate draws
// them: full height, flush with the window's edge, rounded only by the
// window's own corners, a hairline where the content begins.
//
// The sidebar is Liquid Glass for real: the window leaves that area transparent
// and Hyprland blurs the desktop behind it (decoration:blur), so it takes on
// the wallpaper's colour exactly like a macOS sidebar.
//
//   AppWindow {
//       title: "Weather"; implicitWidth: 900; implicitHeight: 640
//       sidebarWidth: 220; sidebar: [ ...rows... ]
//       toolbarLeft: [ ToolbarPill { ... } ]; toolbarRight: [ ... ]
//       Item { ...content... }          // fills the area right of the sidebar
//   }
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
import "theme"

FloatingWindow {
    id: win
    property real sidebarWidth: 0
    property real trailingSidebarWidth: 0  // an inspector floating at the right edge
    property color background: Theme.windowBg
    property bool forceDark: false        // Calculator is dark in both appearances
    property bool resizable: true
    property bool fullSizeContent: false  // content runs under the toolbar (Weather's sky)
    // Closing and quitting, as on the Mac: the red button and ⌘W close this
    // window (closeAction), ⌘Q quits the app (quitAction). A single-window
    // utility (Calculator, Settings) ends with its window. A document app
    // (documentApp: Notes, TextEdit) keeps running with its window put away
    // (putAway), and opening it again from the Dock, Launchpad or Spotlight
    // brings the window back (reopen, over IPC: `qs -p APP ipc call app
    // reopen`). An app with documents sets the actions to ask about unsaved
    // changes first; quitAction defaults to closeAction, so a check made on
    // close is made on quit too.
    property var quitAction: null
    property var closeAction: null        // close button and ⌘W: a function (one of several windows); quits without
    property bool documentApp: false
    signal reopened()
    signal openRequested(string path)     // a document app asked to open a file while running
    // ⌘[ and ⌘] (keyd sends Alt+Left/Right): Back and Forward, for apps with history.
    signal backRequested()
    signal forwardRequested()
    readonly property real toolbarHeight: Theme.sizeToolbar
    readonly property real inset: 0       // sidebars are edge to edge
    readonly property bool active: win._backingWindow ? win._backingWindow.active : true
    // The content column starts right of the sidebar.
    readonly property real contentX: sidebarWidth > 0 ? sidebarWidth : 0
    // The content column ends left of the trailing sidebar.
    readonly property real contentWidth: width - contentX - (trailingSidebarWidth > 0 ? trailingSidebarWidth : 0)
    default property alias content: contentArea.data
    property alias toolbarLeft: leftRow.data
    property alias toolbarRight: rightRow.data
    property alias sidebar: sidebarArea.data
    property alias trailingSidebar: trailingArea.data
    property alias toolbarCenter: centerSlot.data
    // Buttons at the sidebar's right edge (new folder, sidebar toggle in Notes);
    // next to the traffic lights while the sidebar is hidden.
    property alias toolbarSidebar: sideRow.data
    // Free-form toolbar items, placed by the app (column-aligned toolbars).
    property alias toolbarItems: freeSlot.data
    // Drawn across the whole window under the sidebar and toolbar (Weather's sky).
    property alias backdrop: backdropArea.data
    // Above everything: menus and popovers go here.
    readonly property alias overlay: overlayArea

    color: "transparent"

    // Follow the system appearance (gsettings), like the shell, unless the app
    // chooses one: appearance "light" or "dark" (LCode's Settings ▸ General).
    property string appearance: ""
    property bool _systemDark: false
    property bool _systemKnown: false
    function followScheme(line) { _systemDark = line.includes("dark"); _systemKnown = true; applyScheme() }
    function applyScheme() {
        if (forceDark || appearance === "dark") Theme.dark = true
        else if (appearance === "light") Theme.dark = false
        else if (_systemKnown) Theme.dark = _systemDark
    }
    onForceDarkChanged: applyScheme()
    onAppearanceChanged: applyScheme()
    Component.onCompleted: if (forceDark || appearance) applyScheme()
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => win.followScheme(line) }
    }
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => win.followScheme(line) }
    }
    // The system accent colour (Settings › Appearance › Color).
    function followAccent(line) { const m = /'(\w+)'/.exec(line); if (m) Theme.accentName = m[1] }
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => win.followAccent(line) }
    }
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => win.followAccent(line) }
    }

    // Liquid Glass clear or tinted, Reduce transparency and Reduce motion
    // (Settings › Appearance, Accessibility), as the shell reads them.
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let d = {}
            try { d = JSON.parse(text()) } catch (e) {}
            Theme.glassStyle = d.glass ?? "clear"
            Theme.reduceTransparency = d.reduceTransparency ?? false
            Theme.reduceMotion = d.reduceMotion ?? false
            Theme.textScale = d.textScale ?? 1
            Theme.alwaysShowScrollbars = d.scrollBars === "always"
            Theme.glassSolidity = d.glassSolidity ?? 0
        }
    }

    // The Mac's window keys. keyd turns ⌘Q and ⌘W into Ctrl+Q and Ctrl+W, and
    // ⌘[ ⌘] into Alt+Left and Alt+Right.
    function closeWindow() { if (closeAction) closeAction(); else if (documentApp) putAway(); else Qt.quit() }
    function quitApp() { if (quitAction) quitAction(); else if (documentApp && !closeAction) Qt.quit(); else closeWindow() }
    function putAway() { visible = false }
    function reopen() { visible = true; reopened() }
    IpcHandler {
        target: "app"
        enabled: win.documentApp
        function reopen(): void { win.reopen() }
        function open(path: string): void { win.reopen(); win.openRequested(path) }
    }
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.quitApp() }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeWindow() }
    Shortcut { sequence: "Alt+Left"; onActivated: win.backRequested() }
    Shortcut { sequence: "Alt+Right"; onActivated: win.forwardRequested() }

    Item {
        id: frame
        anchors.fill: parent
        // What the toolbar's glass bends: everything under the toolbar, where
        // content runs under it (fullSizeContent). Glass.qml looks for this.
        readonly property Item glassBackdrop: win.fullSizeContent ? underToolbar : null

        Item {
            id: underToolbar
            anchors.fill: parent

            // The window body: opaque everywhere except under the sidebars, which
            // are glass (the compositor blurs the desktop behind them).
            Rectangle {
                x: win.contentX
                width: win.contentWidth; height: parent.height
                topLeftRadius: win.sidebarWidth > 0 ? 0 : Theme.radiusWindow
                bottomLeftRadius: topLeftRadius
                topRightRadius: win.trailingSidebarWidth > 0 ? 0 : Theme.radiusWindow
                bottomRightRadius: topRightRadius
                color: win.background
            }

            Item {
                id: backdropArea
                anchors.fill: parent
            }

            // Glass sidebar, edge to edge.
            Rectangle {
                id: sidebarGlass
                visible: win.sidebarWidth > 0
                width: win.sidebarWidth; height: parent.height
                topLeftRadius: Theme.radiusWindow
                bottomLeftRadius: Theme.radiusWindow
                color: Theme.reduceTransparency ? Qt.rgba(Theme.sidebarBg.r, Theme.sidebarBg.g, Theme.sidebarBg.b, 1) : Theme.sidebarBg
                // Where the content begins: a hairline, as on the Mac.
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: Theme.dark ? "#59000000" : "#1a000000"
                }
                Item {
                    id: sidebarArea
                    anchors { fill: parent; topMargin: win.toolbarHeight; leftMargin: 10; rightMargin: 10; bottomMargin: 8 }
                }
            }

            // Trailing glass sidebar (inspectors), the mirror of the leading one.
            Rectangle {
                visible: win.trailingSidebarWidth > 0
                x: parent.width - win.trailingSidebarWidth
                width: win.trailingSidebarWidth; height: parent.height
                topRightRadius: Theme.radiusWindow
                bottomRightRadius: Theme.radiusWindow
                color: sidebarGlass.color
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: Theme.dark ? "#59000000" : "#1a000000"
                }
                Item {
                    id: trailingArea
                    anchors { fill: parent; topMargin: win.toolbarHeight; leftMargin: 10; rightMargin: 10; bottomMargin: 8 }
                }
            }

            Item {
                id: contentArea
                x: win.contentX
                y: win.fullSizeContent ? 0 : win.toolbarHeight
                width: win.contentWidth
                height: parent.height - y
            }
        }

        // Toolbar row: drag to move, double-click to zoom.
        Item {
            id: toolbar
            width: parent.width; height: win.toolbarHeight
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: Hyprland.dispatch("fullscreen 1")
            }
            DragHandler {
                target: null
                onActiveChanged: if (active) win.startSystemMove()
            }
            Row {
                id: leftRow
                x: Math.max(win.contentX + 10, lights.x + lights.width + 16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }
            Item {
                id: centerSlot
                x: win.contentX + (parent.width - win.contentX - width) / 2
                width: childrenRect.width; height: parent.height
            }
            Row {
                id: sideRow
                x: win.sidebarWidth > 0 ? win.sidebarWidth - width - 10 : lights.x + lights.width + 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
            }
            Item {
                id: freeSlot
                anchors.fill: parent
            }
            Row {
                id: rightRow
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 8
            }
        }

        TrafficLights {
            id: lights
            x: 20; y: Math.round((win.toolbarHeight - 13) / 2)
            active: win.active
            canZoom: win.resizable
            closeAction: win.closeAction
            onZoomHoveredChanged: zoomDelay.restart()
        }
        // Resting on the green button opens Move & Resize, after a beat as on
        // the Mac; it goes once the pointer has left both the button and it.
        Timer {
            id: zoomDelay
            interval: zoomMenu.open ? 300 : 650
            onTriggered: zoomMenu.open = lights.zoomHovered || (zoomMenu.open && zoomMenu.hovered)
        }
        Connections { target: zoomMenu; function onHoveredChanged() { zoomDelay.restart() } }

        // Window outline, drawn over everything.
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusWindow
            color: "transparent"
            border {
                width: 1
                color: win.active
                    ? (Theme.dark ? "#30ffffff" : "#26000000")
                    : (Theme.dark ? "#1affffff" : "#18000000")
            }
            Behavior on border.color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 150 } }
        }

        Item {
            id: overlayArea
            anchors.fill: parent
            z: 10
        }
        ZoomMenu {
            id: zoomMenu
            anchorX: lights.x + lights.zoomX
            anchorY: lights.y + 13 + 6
        }

        // Resize edges.
        Repeater {
            model: win.resizable ? [
                { e: Qt.LeftEdge, c: Qt.SizeHorCursor }, { e: Qt.RightEdge, c: Qt.SizeHorCursor },
                { e: Qt.TopEdge, c: Qt.SizeVerCursor }, { e: Qt.BottomEdge, c: Qt.SizeVerCursor },
                { e: Qt.TopEdge | Qt.LeftEdge, c: Qt.SizeFDiagCursor }, { e: Qt.TopEdge | Qt.RightEdge, c: Qt.SizeBDiagCursor },
                { e: Qt.BottomEdge | Qt.RightEdge, c: Qt.SizeFDiagCursor }, { e: Qt.BottomEdge | Qt.LeftEdge, c: Qt.SizeBDiagCursor },
            ] : []
            delegate: MouseArea {
                required property var modelData
                readonly property bool l: modelData.e & Qt.LeftEdge
                readonly property bool r: modelData.e & Qt.RightEdge
                readonly property bool t: modelData.e & Qt.TopEdge
                readonly property bool b: modelData.e & Qt.BottomEdge
                readonly property bool corner: (l || r) && (t || b)
                x: r ? frame.width - (corner ? 14 : 5) : 0
                y: b ? frame.height - (corner ? 14 : 5) : 0
                width: (l || r) ? (corner ? 14 : 5) : frame.width
                height: (t || b) ? (corner ? 14 : 5) : frame.height
                cursorShape: modelData.c
                onPressed: win.startSystemResize(modelData.e)
            }
        }
    }
}
