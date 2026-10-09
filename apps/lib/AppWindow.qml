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
import "WindowGeometry.js" as WindowGeometry

FloatingWindow {
    id: win
    // Limit the initial Wayland toplevel to the usable monitor space BEFORE
    // the compositor places it. Hyprland centers the window above the Dock,
    // so neither the 30px menu bar nor the traffic lights are covered.
    // Unlike a post-map hyprctl resize, this produces no visible second jump.
    property real _placementDockSize: Theme.sizeDockIcon
    readonly property real _placementScreenWidth: win.screen ? win.screen.width : 0
    readonly property real _placementScreenHeight: win.screen ? win.screen.height : 0
    maximumSize: Qt.size(
        WindowGeometry.maximumWidth(_placementScreenWidth),
        WindowGeometry.maximumHeight(_placementScreenHeight, _placementDockSize, Theme.sizeMenubar)
    )
    property real sidebarWidth: 0
    property real trailingSidebarWidth: 0  // an inspector floating at the right edge
    // Present sidebars and the content boundaries as one layout transaction.
    // Rapid toggles retarget the transition without restarting a fixed sequence.
    property bool choreographyReady: false
    property real presentedSidebarWidth: Math.max(0, sidebarWidth)
    property real presentedTrailingSidebarWidth: Math.max(0, trailingSidebarWidth)
    Behavior on presentedSidebarWidth {
        enabled: win.choreographyReady && !Theme.reduceMotion
        NumberAnimation { duration: 215; easing.type: Easing.OutCubic }
    }
    Behavior on presentedTrailingSidebarWidth {
        enabled: win.choreographyReady && !Theme.reduceMotion
        NumberAnimation { duration: 215; easing.type: Easing.OutCubic }
    }
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
    readonly property real contentX: presentedSidebarWidth
    // Both sidebar-open and sidebar-closed toolbar layouts must reserve the
    // same protected region for the three traffic lights and their hitboxes.
    readonly property real toolbarSafeX: lights.x + lights.width + 16
    // The shared sidebar toolbar is a separate Row. Its buttons do not
    // disappear when the sidebar closes: they park immediately after the
    // traffic lights. Reserve their *live, animated* width for other toolbar
    // controls too; traffic-light clearance alone isn't enough.
    readonly property real toolbarLeadingEnd: Math.max(toolbarSafeX,
        sideRow.x + sideRow.width + (sideRow.width > 0 ? 12 : 0))
    // Content, glass, and separators share identical animated edges.
    readonly property real contentWidth: Math.max(0, width - contentX - presentedTrailingSidebarWidth)
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
    Component.onCompleted: {
        if (forceDark || appearance) applyScheme()
        choreographyReady = true
    }
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
            win._placementDockSize = (d.dock && d.dock.size > 0) ? d.dock.size : Theme.sizeDockIcon
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
        // What the glass in this window bends (its toolbar, menus and
        // popovers): the window's body, sidebars and content, under the toolbar.
        ShaderEffectSource {
            id: underToolbarTexture
            visible: false
            sourceItem: Backdrops.used(underToolbarTexture) ? underToolbar : null
            live: true
            textureSize: Backdrops.textureSize(underToolbar.width, underToolbar.height, Screen.devicePixelRatio)
            Component.onCompleted: Backdrops.add(frame, underToolbar, underToolbarTexture)
            Component.onDestruction: Backdrops.remove(underToolbarTexture)
        }

        Item {
            id: underToolbar
            anchors.fill: parent

            // The window body: opaque everywhere except under the sidebars, which
            // are glass (the compositor blurs the desktop behind them).
            Rectangle {
                x: win.contentX
                width: win.contentWidth; height: parent.height
                topLeftRadius: win.presentedSidebarWidth > 0.5 ? 0 : Theme.radiusWindow
                bottomLeftRadius: topLeftRadius
                topRightRadius: win.presentedTrailingSidebarWidth > 0.5 ? 0 : Theme.radiusWindow
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
                visible: win.presentedSidebarWidth > 0.5
                width: win.presentedSidebarWidth; height: parent.height
                clip: true
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
                    x: 10; y: win.toolbarHeight
                    width: Math.max(0, parent.width - 20)
                    height: Math.max(0, parent.height - y - 8)
                }
            }

            // Trailing glass sidebar (inspectors), the mirror of the leading one.
            Rectangle {
                visible: win.presentedTrailingSidebarWidth > 0.5
                x: parent.width - win.presentedTrailingSidebarWidth
                width: win.presentedTrailingSidebarWidth; height: parent.height
                clip: true
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
                    x: 10; y: win.toolbarHeight
                    width: Math.max(0, parent.width - 20)
                    height: Math.max(0, parent.height - y - 8)
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
            // An inactive window gently recedes without dimming its document.
            // This doesn't take input or change the frame's measurements.
            Rectangle {
                anchors.fill: parent
                enabled: false
                color: Theme.dark ? "#16000000" : "#09000000"
                opacity: win.active ? 0 : 1
                Behavior on opacity {
                    enabled: !Theme.reduceMotion
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }
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
                x: Math.max(lights.x + lights.width + 16,
                    win.presentedSidebarWidth > 0 ? win.presentedSidebarWidth - width - 10
                        : lights.x + lights.width + 16)
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
            // The traffic light must take the SAME close path as ⌘W: document
            // windows hide/reopen, while single-window utilities actually quit.
            closeAction: function() { win.closeWindow() }
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
            Behavior on border.color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 130 } }
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
