// A Golden Gate app window, drawn by the app as on the Mac: frameless, rounded,
// with traffic lights, a 52 px toolbar row to drag it by, edges to resize from,
// and optionally a sidebar floating 8 px inside the window.
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
    property color background: Theme.windowBg
    property bool forceDark: false        // Calculator is dark in both appearances
    property bool resizable: true
    property bool fullSizeContent: false  // content runs under the toolbar (Weather's sky)
    readonly property real toolbarHeight: Theme.sizeToolbar
    readonly property real inset: 8
    readonly property bool active: win._backingWindow ? win._backingWindow.active : true
    // The content column starts right of the sidebar.
    readonly property real contentX: sidebarWidth > 0 ? inset + sidebarWidth : 0
    default property alias content: contentArea.data
    property alias toolbarLeft: leftRow.data
    property alias toolbarRight: rightRow.data
    property alias sidebar: sidebarArea.data
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

    // Follow the system appearance (gsettings), like the shell.
    function followScheme(line) { if (!forceDark) Theme.dark = line.includes("dark") }
    onForceDarkChanged: if (forceDark) Theme.dark = true
    Component.onCompleted: if (forceDark) Theme.dark = true
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
        }
    }

    Item {
        id: frame
        anchors.fill: parent

        // The window body: opaque everywhere except under the floating sidebar.
        Shape {
            anchors.fill: parent
            visible: win.sidebarWidth > 0
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: win.background
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathRectangle { x: 0; y: 0; width: frame.width; height: frame.height; radius: Theme.radiusWindow }
                PathRectangle { x: win.inset; y: win.inset; width: win.sidebarWidth; height: frame.height - 2 * win.inset; radius: Theme.radiusSidebar }
            }
        }
        Rectangle {
            anchors.fill: parent
            visible: win.sidebarWidth <= 0
            radius: Theme.radiusWindow
            color: win.background
        }

        Item {
            id: backdropArea
            anchors.fill: parent
        }

        // Floating glass sidebar.
        Rectangle {
            id: sidebarGlass
            visible: win.sidebarWidth > 0
            x: win.inset; y: win.inset
            width: win.sidebarWidth; height: parent.height - 2 * win.inset
            radius: Theme.radiusSidebar
            color: Theme.sidebarBg
            border { width: 1; color: Theme.dark ? "#1affffff" : "#80ffffff" }
            Item {
                id: sidebarArea
                anchors { fill: parent; topMargin: win.toolbarHeight - win.inset; leftMargin: 8; rightMargin: 8; bottomMargin: 8 }
            }
        }

        Item {
            id: contentArea
            x: win.contentX
            y: win.fullSizeContent ? 0 : win.toolbarHeight
            width: parent.width - x
            height: parent.height - y
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
                x: win.sidebarWidth > 0 ? win.inset + win.sidebarWidth - width - 8 : lights.x + lights.width + 16
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
        }

        // Window outline, drawn over everything.
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusWindow
            color: "transparent"
            border { width: 1; color: Theme.dark ? "#26ffffff" : "#26000000" }
        }

        Item {
            id: overlayArea
            anchors.fill: parent
            z: 10
        }

        // Resize edges.
        Repeater {
            model: win.resizable ? [
                { e: Qt.LeftEdge, c: Qt.SizeHorCursor }, { e: Qt.RightEdge, c: Qt.SizeHorCursor },
                { e: Qt.TopEdge, c: Qt.SizeVerCursor }, { e: Qt.BottomEdge, c: Qt.SizeVerCursor },
                { e: Qt.BottomEdge | Qt.RightEdge, c: Qt.SizeFDiagCursor }, { e: Qt.BottomEdge | Qt.LeftEdge, c: Qt.SizeBDiagCursor },
            ] : []
            delegate: MouseArea {
                required property var modelData
                readonly property bool l: modelData.e & Qt.LeftEdge
                readonly property bool r: modelData.e & Qt.RightEdge
                readonly property bool t: modelData.e & Qt.TopEdge
                readonly property bool b: modelData.e & Qt.BottomEdge
                x: r ? frame.width - (b ? 14 : 5) : 0
                y: b ? frame.height - (l || r ? 14 : 5) : 0
                width: (l || r) ? (b ? 14 : 5) : frame.width
                height: (t || b) && !(l || r) ? 5 : (b ? 14 : frame.height)
                cursorShape: modelData.c
                onPressed: win.startSystemResize(modelData.e)
            }
        }
    }
}
