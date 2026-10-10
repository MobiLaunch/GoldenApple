// Touch-first Home Screen. The same installed apps, wallpaper and widget
// feeds as desktop mode, but a separately persisted tablet widget arrangement.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "components"
import "ui" as Shared
import "ui/theme"
import "ui/paths.js" as Paths
import "widgets"
import "widgets/layout.js" as Layout
import "widgets/tablet-layout.js" as TabletLayout

PanelWindow {
    id: tablet
    objectName: "tabletHome"
    visible: Prefs.tabletMode
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "gg-tablet-home"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    property bool editing: false
    property var approvedIcons: ({})
    readonly property var widgets: TabletLayout.normalized(Prefs.tabletWidgets)
    readonly property var catalog: [
        {kind: "calendar", title: "Calendar", sizes: ["small", "medium"]},
        {kind: "clock", title: "Clock", sizes: ["small"]},
        {kind: "weather", title: "Weather", sizes: ["small", "medium"]},
        {kind: "music", title: "Music", sizes: ["small", "medium"]},
        {kind: "notes", title: "Notes", sizes: ["small", "medium"]},
        {kind: "battery", title: "Batteries", sizes: ["small"]}
    ]
    readonly property bool portrait: width < height
    readonly property int iconColumns: portrait ? 4 : Math.max(5, Math.min(8, Math.floor((width - 72) / 124)))
    readonly property int iconSize: Math.max(57, Math.min(84, (contentWidth - (iconColumns - 1) * 14) / iconColumns - 24))
    readonly property real contentWidth: Math.max(300, Math.min(1100, width - (portrait ? 40 : 76)))
    readonly property var curatedApps: {
        const names = new Set(Prefs.defaultDockPinned.concat([
            "org.goldengate.ArchiveUtility", "org.goldengate.DiskUtility"
        ]))
        return DesktopEntries.applications.values.filter(e =>
            !!e?.id && !!e.name && !e.noDisplay &&
            (names.has(e.id) || !!approvedIcons[e.id]?.icon)
        ).sort((a,b) => {
            const ia = Prefs.defaultDockPinned.indexOf(a.id)
            const ib = Prefs.defaultDockPinned.indexOf(b.id)
            return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib) ||
                String(a.name).localeCompare(String(b.name))
        }).slice(0, 96)
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") +
              "/golden-gate/launchpad-icons.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text())
                tablet.approvedIcons = data.version === 1 ? (data.apps || {}) : ({})
            } catch (e) { tablet.approvedIcons = ({}) }
        }
    }
    function scrollToTop() { scroll.contentY = 0 }
    function iconFor(app) {
        const path = approvedIcons[app.id]?.icon
        if (path && String(path).startsWith("/")) return "file://" + encodeURI(path)
        return Quickshell.iconPath(app.icon, "application-x-executable")
    }
    function save(cards) { Prefs.setTabletWidgets(TabletLayout.normalized(cards)) }
    function add(kind, size) { save(TabletLayout.add(widgets, kind, size)) }
    function remove(id) { save(TabletLayout.remove(widgets, id)) }
    function resize(id) {
        const w = widgets.find(c => c.id === id)
        if (!w) return
        const options = TabletLayout.CATALOG[w.kind]
        save(TabletLayout.resize(widgets, id, options[(options.indexOf(w.size) + 1) % options.length]))
    }
    function move(id, index) { save(TabletLayout.move(widgets, id, index)) }
    function openWidget(kind) {
        const destinations = {
            calendar:"org.goldengate.Calendar", weather:"org.goldengate.Weather",
            music:"org.goldengate.Music", notes:"org.goldengate.Notes"
        }
        if (kind === "battery") Quickshell.execDetached(["gg-settings", "battery"])
        else if (destinations[kind]) DesktopEntries.byId(destinations[kind])?.execute()
    }
    function dropWidget(id, center) {
        let bestIndex = -1, bestDistance = Infinity
        for (let i = 0; i < widgetRepeater.count; i++) {
            const candidate = widgetRepeater.itemAt(i)
            if (!candidate || candidate.modelData.id === id) continue
            const x = candidate.x + candidate.width / 2
            const y = candidate.y + candidate.height / 2
            const distance = (x-center.x)*(x-center.x) + (y-center.y)*(y-center.y)
            if (distance < bestDistance) { bestIndex = i; bestDistance = distance }
        }
        if (bestIndex >= 0) move(id, bestIndex)
    }

    Feeds { id: feeds; wantNotes: tablet.widgets.some(w => w.kind === "notes") }

    // Accessible, springy touch controls, no permanent editing toolbar.
    component TouchPill: Rectangle {
        id: pill
        property string label: ""
        property bool prominent: false
        signal tapped()
        height: 44; width: pillText.implicitWidth + 30; radius: height/2
        color: prominent ? "#e13a72c5" : "#bc151b27"
        border { width: 1; color: prominent ? "#7ba9e4" : "#5fffffff" }
        scale: press.pressed && !Theme.reduceMotion ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: "#ffffff"
            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
        }
        MouseArea { id: press; anchors.fill: parent; onClicked: pill.tapped() }
        Accessible.role: Accessible.Button
        Accessible.name: pill.label
    }

    // The icon grid and widgets scroll together, beneath real app windows.
    // The actual global menu bar, Dock and Control Center stay independent.
    Flickable {
        id: scroll
        anchors { fill: parent; topMargin: Theme.sizeMenubar + 8; bottomMargin: Math.max(100, Prefs.dockSize + 48) }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: homeContent.implicitHeight + 45

        Column {
            id: homeContent
            width: Math.min(scroll.width - 20, tablet.contentWidth)
            x: (scroll.width - width)/2
            spacing: 20

            Row {
                width: parent.width
                height: 48
                spacing: 10
                Text {
                    width: parent.width - editHome.width - 22
                    anchors.verticalCenter: parent.verticalCenter
                    text: tablet.editing ? "Customize Home" : "Home"
                    color: "#ffffff"
                    font { family: Theme.fontDisplay; pixelSize: Theme.fs(27); weight: Font.Bold }
                }
                TouchPill {
                    id: editHome
                    anchors.verticalCenter: parent.verticalCenter
                    label: tablet.editing ? "Done" : "Edit Home"
                    prominent: tablet.editing
                    onTapped: tablet.editing = !tablet.editing
                }
            }

            Column {
                width: parent.width
                spacing: 11
                Row {
                    width: parent.width
                    height: 25
                    Text {
                        width: parent.width - 60
                        text: "WIDGETS"
                        color: "#f1f4fa"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Bold; letterSpacing: 1.2 }
                    }
                    Text {
                        visible: tablet.editing
                        text: "Move · Resize · Remove"
                        color: "#dce7f7"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                }
                Flow {
                    id: widgetFlow
                    objectName: "tabletWidgetFlow"
                    width: parent.width
                    spacing: 12
                    height: implicitHeight
                    Repeater {
                        id: widgetRepeater
                        model: tablet.widgets
                        delegate: Item {
                            id: widgetTile
                            required property var modelData
                            readonly property var natural: Layout.pixels(modelData.size)
                            readonly property real fitScale: Math.min(1, widgetFlow.width / natural.width)
                            property real dragX: 0
                            property real dragY: 0
                            readonly property int place: tablet.widgets.findIndex(w => w.id === modelData.id)
                            width: natural.width * fitScale
                            height: natural.height * fitScale
                            z: widgetDrag.pressed ? 20 : 0
                            transform: Translate { x: widgetTile.dragX; y: widgetTile.dragY }
                            Item {
                                width: widgetTile.natural.width
                                height: widgetTile.natural.height
                                scale: widgetTile.fitScale
                                transformOrigin: Item.TopLeft
                                Glass {
                                    anchors.fill: parent
                                    role: "regular"; radius: 22
                                    visible: !widgetFace.ownBackground
                                }
                                Face {
                                    id: widgetFace
                                    anchors.fill: parent
                                    kind: widgetTile.modelData.kind
                                    size: widgetTile.modelData.size
                                    feeds: feeds
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 22
                                    color: "#14000000"
                                    border { width: tablet.editing ? 2 : 0; color: "#95ffffff" }
                                }
                            }
                            MouseArea {
                                id: widgetDrag
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                property point origin: Qt.point(0,0)
                                property bool moved: false
                                onPressed: (m) => { origin = Qt.point(m.x,m.y); moved = false }
                                onPressAndHold: tablet.editing = true
                                onPositionChanged: (m) => {
                                    if (!pressed || !tablet.editing) return
                                    if (!moved && Math.hypot(m.x-origin.x,m.y-origin.y) < 10) return
                                    moved = true
                                    widgetTile.dragX += m.x - origin.x
                                    widgetTile.dragY += m.y - origin.y
                                }
                                onReleased: {
                                    if (moved && tablet.editing) {
                                        // mapToItem already includes the
                                        // Translate transform: adding dragX
                                        // again would double the drop distance.
                                        const c = widgetTile.mapToItem(widgetFlow,
                                            widgetTile.width/2, widgetTile.height/2)
                                        tablet.dropWidget(widgetTile.modelData.id, c)
                                    }
                                    widgetTile.dragX = 0; widgetTile.dragY = 0
                                }
                                onCanceled: { widgetTile.dragX = 0; widgetTile.dragY = 0 }
                                onClicked: if (!tablet.editing && !moved) tablet.openWidget(widgetTile.modelData.kind)
                            }
                            Row {
                                visible: tablet.editing
                                anchors { right: parent.right; top: parent.top; margins: -5 }
                                spacing: 4
                                TouchPill {
                                    label: "−"
                                    onTapped: tablet.remove(widgetTile.modelData.id)
                                }
                                TouchPill {
                                    visible: TabletLayout.CATALOG[widgetTile.modelData.kind]?.length > 1
                                    label: "Size"
                                    onTapped: tablet.resize(widgetTile.modelData.id)
                                }
                            }
                            Row {
                                visible: tablet.editing
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -5 }
                                spacing: 6
                                TouchPill {
                                    label: "←"
                                    onTapped: tablet.move(widgetTile.modelData.id, Math.max(0, widgetTile.place - 1))
                                }
                                TouchPill {
                                    label: "→"
                                    onTapped: tablet.move(widgetTile.modelData.id, Math.min(tablet.widgets.length - 1, widgetTile.place + 1))
                                }
                            }
                        }
                    }
                }
                // An inline gallery eliminates the tiny desktop-only right-click
                // menu when a user is operating entirely by touch.
                Flow {
                    id: widgetGallery
                    objectName: "tabletWidgetPicker"
                    visible: tablet.editing
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: tablet.catalog
                        delegate: TouchPill {
                            required property var modelData
                            label: "+ " + modelData.title
                            onTapped: tablet.add(modelData.kind, modelData.sizes[0])
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 12
                Text {
                    text: "APPS"
                    color: "#f1f4fa"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Bold; letterSpacing: 1.2 }
                }
                Grid {
                    id: appGrid
                    objectName: "tabletAppColumns"
                    width: parent.width
                    columns: tablet.iconColumns
                    columnSpacing: 10
                    rowSpacing: 15
                    Repeater {
                        model: tablet.curatedApps
                        delegate: Item {
                            id: appTile
                            required property var modelData
                            width: (appGrid.width - (tablet.iconColumns - 1) * appGrid.columnSpacing) / tablet.iconColumns
                            height: tablet.iconSize + 43
                            Image {
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                width: tablet.iconSize; height: tablet.iconSize
                                source: tablet.iconFor(appTile.modelData)
                                sourceSize: Qt.size(tablet.iconSize * 2, tablet.iconSize * 2)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                            }
                            Rectangle {
                                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                height: 25
                                width: Math.min(parent.width, appName.implicitWidth + 14)
                                radius: 10
                                color: "#660d1420"
                                Text {
                                    id: appName
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, appTile.width - 12)
                                    text: appTile.modelData.name
                                    elide: Text.ElideRight
                                    color: "#ffffff"
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            scale: appTouch.pressed && !Theme.reduceMotion ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                            MouseArea {
                                id: appTouch; anchors.fill: parent
                                onClicked: if (!tablet.editing) appTile.modelData.execute()
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Open " + modelData.name
                        }
                    }
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Swipe down from the top-right corner for Control Center"
                color: "#e1e8f4"
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
        }
    }
}
