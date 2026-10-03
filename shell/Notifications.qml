// Notifications (replaces mako): the server, the banners and Notification Center.
// A banner slides in from the right, can be swiped away and leaves after a few
// seconds; the notification itself stays in Notification Center, grouped by app,
// until it is cleared or opened, as on the Mac. Clicking a notification opens
// it (the app's default action, else the app). Focus (Do Not Disturb) keeps
// notifications but suppresses banners. Notification Center opens from the
// clock in the menu bar.
//   qs ipc call notifications toggleCenter | clear | toggleDnd
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"

Scope {
    id: root
    readonly property bool dnd: Prefs.focusDnd
    readonly property var list: server.trackedNotifications.values
    property var banners: []            // notifications showing as banners, newest first
    property var received: ({})         // notification id → time received (ms)
    property bool centerOpen: false
    property real now: Date.now()

    // Unread notifications for an app, for the Dock's badge.
    // Services that notify on an app's behalf: BlueFerry delivers Messages'
    // iPhone messages, so its notifications belong to Messages.
    readonly property var owners: ({ "blueferry": "org.goldengate.Messages", "io.weirdware.blueferry": "org.goldengate.Messages" })
    function ownerOf(n) {
        return owners[(n.desktopEntry || "").toLowerCase()] || owners[(n.appName || "").toLowerCase()] || ""
    }
    function countFor(appId, startupClass) {
        const ids = [appId, appId.split(".").pop(), startupClass ?? ""].map((s) => s.toLowerCase()).filter((s) => s)
        return list.filter((n) => ids.includes((n.desktopEntry || "").toLowerCase())
            || ids.includes((n.appName || "").toLowerCase()) || ids.includes(ownerOf(n).toLowerCase())).length
    }
    function iconFor(n) {
        if (n.image) return n.image
        if (ownerOf(n)) return Quickshell.iconPath(ownerOf(n), true)
        const entry = n.appName ? DesktopEntries.heuristicLookup(n.appName) : null
        // iconPath(…, true) returns "" for a missing icon instead of Qt's checkerboard.
        for (const name of [n.appIcon, n.desktopEntry, entry?.icon ?? ""]) {
            const path = name ? Quickshell.iconPath(name, true) : ""
            if (path) return path
        }
        return ""
    }
    function appLabel(n) {
        const entry = ownerOf(n) ? DesktopEntries.byId(ownerOf(n)) : n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        return entry?.name || n.appName || "Notification"
    }
    function timeLabel(n) {
        const t = received[n.id] ?? now
        const minutes = Math.floor((now - t) / 60000)
        if (minutes < 1) return "now"
        if (minutes < 60) return minutes + "m ago"
        const d = new Date(t)
        return new Date(now).toDateString() === d.toDateString()
            ? Qt.formatTime(d, "h:mm AP") : Qt.formatDate(d, "ddd")
    }
    // Opening a notification runs its default action, else brings up its app,
    // and then it's done.
    function open(n) {
        const action = n.actions.find((a) => a.identifier === "default")
        if (action) action.invoke()
        // BlueFerry's default action asks a running Messages to show the
        // message; make sure Messages is running to receive it.
        if (ownerOf(n)) DesktopEntries.byId(ownerOf(n))?.execute()
        else if (!action) {
            const entry = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry)
                : n.appName ? DesktopEntries.heuristicLookup(n.appName) : null
            entry?.execute()
        }
        n.dismiss()
        centerOpen = false
    }
    function dropBanner(n) { banners = banners.filter((b) => b !== n) }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        onNotification: (n) => {
            n.tracked = true
            const r = Object.assign({}, root.received); r[n.id] = Date.now(); root.received = r
            root.now = Date.now()
            n.closed.connect(() => root.dropBanner(n))
            if (!root.dnd && !root.centerOpen) root.banners = [n].concat(root.banners.filter((b) => b !== n)).slice(0, 4)
        }
    }

    IpcHandler {
        target: "notifications"
        function toggleDnd(): void { Quickshell.execDetached(["gg-pref", "focus.dnd", root.dnd ? "false" : "true"]) }
        function setDnd(on: bool): void { Quickshell.execDetached(["gg-pref", "focus.dnd", on ? "true" : "false"]) }
        function clear(): void { root.list.slice().forEach((n) => n.dismiss()) }
        function toggleCenter(): void { root.centerOpen = !root.centerOpen }
    }
    onCenterOpenChanged: if (centerOpen) { banners = []; now = Date.now() }

    // One notification, as a banner or in Notification Center.
    component Card: Glass {
        id: card
        required property var n
        role: "regular"
        radius: 22
        implicitHeight: content.implicitHeight + 24
        pressed: tap.pressed
        hovered: hover.hovered
        HoverHandler { id: hover }
        TapHandler { id: tap; onTapped: root.open(card.n) }

        RowLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
            spacing: 11
            Item {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 36; Layout.preferredHeight: 36
                readonly property string resolved: root.iconFor(card.n)
                Image { anchors.fill: parent; sourceSize: Qt.size(72, 72); source: parent.resolved; visible: parent.resolved !== "" }
                Rectangle {
                    anchors.fill: parent; radius: 9
                    visible: parent.resolved === ""
                    gradient: Gradient { GradientStop { position: 0; color: "#ff6b5f" } GradientStop { position: 1; color: "#ff2d55" } }
                    Symbol { anchors.centerIn: parent; name: "bell"; size: 20; tone: "white" }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Text {
                        Layout.fillWidth: true
                        text: card.n.summary || root.appLabel(card.n)
                        textFormat: Text.PlainText; elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }
                    Text {
                        text: root.timeLabel(card.n)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.n.body
                    textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
                RowLayout {
                    visible: card.n.actions.some((a) => a.identifier !== "default")
                    Layout.topMargin: 6
                    spacing: 6
                    Repeater {
                        model: card.n.actions.filter((a) => a.identifier !== "default")
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 26; radius: 13
                            color: actionTap.pressed ? Theme.selection : Theme.fill
                            Text { anchors.centerIn: parent; text: modelData.text; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                            TapHandler { id: actionTap; onTapped: modelData.invoke() }
                        }
                    }
                }
            }
        }
        // The close button appears on hover, top left like the system's.
        Glass {
            role: "control"
            x: -7; y: -7; width: 22; height: 22; radius: 11
            opacity: hover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: Theme.dark ? "white" : "dark" }
            TapHandler { onTapped: card.n.dismiss() }
        }
    }

    // Banners.
    PanelWindow {
        id: bannerWindow
        screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; right: true }
        margins { top: 8; right: 10 }
        implicitWidth: 360
        implicitHeight: Math.max(1, column.implicitHeight + 8)
        exclusionMode: ExclusionMode.Normal   // sit below the menu bar
        color: "transparent"
        visible: !root.dnd && root.banners.length > 0
        WlrLayershell.namespace: "gg-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region { item: column }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 8
            Repeater {
                model: root.banners
                delegate: Card {
                    id: banner
                    required property var modelData
                    n: modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    // Slide in from the right; follow the pointer when swiped. A
                    // banner rebuilt when the list changes is already in place.
                    property real dragX: 0
                    property bool shown: Date.now() - (root.received[modelData.id] ?? 0) > 400
                    x: (shown ? 0 : width + 20) + dragX
                    opacity: 1 - Math.max(0, dragX) / 320
                    Behavior on x { enabled: !drag.active; Spring { spring: Theme.snappy } }
                    Component.onCompleted: shown = true

                    // The banner goes; the notification stays in Notification Center.
                    Timer {
                        interval: banner.n.expireTimeout > 0 ? banner.n.expireTimeout * 1000 : 5500
                        running: !bannerHover.hovered && !banner.n.resident
                        onTriggered: root.dropBanner(banner.n)
                    }
                    HoverHandler { id: bannerHover }
                    DragHandler {
                        id: drag
                        target: null
                        xAxis.enabled: true; yAxis.enabled: false
                        onTranslationChanged: banner.dragX = Math.max(-20, translation.x)
                        onActiveChanged: if (!active) { if (banner.dragX > 110) root.dropBanner(banner.n); else banner.dragX = 0 }
                    }
                }
            }
        }
    }

    // Notification Center: the notifications so far, grouped by app, newest first.
    PanelWindow {
        id: center
        screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; right: true; left: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.centerOpen || panel.x < center.width
        WlrLayershell.namespace: "gg-notification-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        readonly property var groups: {
            const by = {}, order = []
            for (const n of root.list.slice().sort((a, b) => (root.received[b.id] ?? 0) - (root.received[a.id] ?? 0))) {
                const key = root.appLabel(n)
                if (!by[key]) { by[key] = []; order.push(key) }
                by[key].push(n)
            }
            return order.map((k) => ({ app: k, items: by[k] }))
        }
        property var expanded: ({})

        MouseArea { anchors.fill: parent; onClicked: root.centerOpen = false }   // click away closes
        Item {
            id: panel
            width: 380
            anchors { top: parent.top; bottom: parent.bottom; topMargin: 30; bottomMargin: 10 }
            x: root.centerOpen ? center.width - width - 6 : center.width + 20
            Behavior on x { Spring { spring: Theme.snappy } }
            focus: root.centerOpen
            Keys.onEscapePressed: root.centerOpen = false
            MouseArea { anchors.fill: parent }   // clicks inside stay inside

            Flickable {
                anchors.fill: parent
                contentHeight: stack.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ColumnLayout {
                    id: stack
                    width: parent.width
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10; Layout.rightMargin: 4
                        visible: center.groups.length > 0
                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: "#ffffff"
                            style: Text.Raised; styleColor: "#40000000"
                            font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                        }
                        Glass {
                            role: "control"
                            implicitWidth: clearAll.implicitWidth + 22; implicitHeight: 24; radius: 12
                            pressed: clearTap.pressed
                            Text { id: clearAll; anchors.centerIn: parent; text: "Clear All"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                            TapHandler { id: clearTap; onTapped: root.list.slice().forEach((n) => n.dismiss()) }
                        }
                    }

                    Repeater {
                        model: center.groups
                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            readonly property bool open: center.expanded[modelData.app] === true || modelData.items.length === 1
                            Layout.fillWidth: true
                            spacing: 6
                            // An app with several notifications shows them stacked; a click spreads them.
                            RowLayout {
                                visible: group.modelData.items.length > 1
                                Layout.fillWidth: true
                                Layout.leftMargin: 10; Layout.rightMargin: 4
                                Text {
                                    Layout.fillWidth: true
                                    text: group.modelData.app
                                    color: "#ffffff"
                                    style: Text.Raised; styleColor: "#40000000"
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                                }
                                Glass {
                                    role: "control"
                                    implicitWidth: lessText.implicitWidth + 20; implicitHeight: 22; radius: 11
                                    Text { id: lessText; anchors.centerIn: parent; text: group.open ? "Show Less" : (group.modelData.items.length - 1) + " more"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium } }
                                    TapHandler {
                                        onTapped: { const e = Object.assign({}, center.expanded); e[group.modelData.app] = !group.open; center.expanded = e }
                                    }
                                }
                                Glass {
                                    role: "control"
                                    implicitWidth: 22; implicitHeight: 22; radius: 11
                                    Symbol { anchors.centerIn: parent; name: "xmark"; size: 9; tone: Theme.dark ? "white" : "dark" }
                                    TapHandler { onTapped: group.modelData.items.slice().forEach((n) => n.dismiss()) }
                                }
                            }
                            Repeater {
                                model: group.open ? group.modelData.items : group.modelData.items.slice(0, 1)
                                delegate: Card {
                                    required property var modelData
                                    n: modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: implicitHeight
                                    // A collapsed stack shows the edge of the cards behind.
                                    Item {
                                        visible: !group.open && group.modelData.items.length > 1
                                        anchors { left: parent.left; right: parent.right; top: parent.bottom; leftMargin: 12; rightMargin: 12 }
                                        height: 8
                                        clip: true
                                        Rectangle {
                                            width: parent.width; height: 30; y: -22; radius: 18
                                            color: Theme.dark ? "#8c2c2c30" : "#b3f4f4f7"
                                            border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1a000000" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Glass {
                        visible: center.groups.length === 0
                        role: "regular"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: 22
                        Text {
                            anchors.centerIn: parent
                            text: "No Notifications"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                        }
                    }
                }
            }
        }
    }
}
