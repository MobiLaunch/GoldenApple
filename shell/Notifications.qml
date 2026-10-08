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
    objectName: "notifications"
    readonly property bool dnd: Prefs.focusDnd
    readonly property var list: server.trackedNotifications.values
    property var banners: []            // notifications showing as banners, newest first
    property var received: ({})         // notification id → time received (ms)
    property bool centerOpen: false
    property bool controlCenterOpen: false   // banners step aside for Control Center
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
        return list.filter((n) => Prefs.notifyApp(keyOf(n)).badges).filter((n) => ids.includes((n.desktopEntry || "").toLowerCase())
            || ids.includes((n.appName || "").toLowerCase()) || ids.includes(ownerOf(n).toLowerCase())).length
    }
    // One name per app for its Notifications settings: the app it speaks for,
    // else its desktop file, else the name it gives.
    function keyOf(n) {
        return (ownerOf(n) || n.desktopEntry || n.appName || "notification").toLowerCase()
    }
    // The apps that have notified, for Settings → Notifications to list:
    // ~/.local/state/golden-gate/notifiers.json, { key: { name, icon } }.
    readonly property string notifiersFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/golden-gate/notifiers.json"
    property var notifiers: ({})
    FileView {
        path: root.notifiersFile
        printErrors: false
        onLoaded: { try { root.notifiers = JSON.parse(text()) } catch (e) { root.notifiers = ({}) } }
    }
    function remember(n) {
        const k = keyOf(n)
        if (notifiers[k]) return
        const all = Object.assign({}, notifiers)
        all[k] = { name: appLabel(n), icon: ownerOf(n) || n.desktopEntry || n.appIcon || "" }
        notifiers = all
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "${1%/*}" && printf "%s\\n" "$2" > "$1"', "sh", notifiersFile, JSON.stringify(all)])
    }
    // The alert sound, as the Mac plays one with each banner.
    function chime() {
        Quickshell.execDetached(["sh", "-c", "pw-play /usr/share/sounds/freedesktop/stereo/message-new-instant.oga 2>/dev/null"
            + " || canberra-gtk-play -i message-new-instant 2>/dev/null || true"])
    }
    function iconFor(n) {
        if (n.image) return n.image
        if (ownerOf(n)) return Quickshell.iconPath(ownerOf(n), true)
        // An app that names itself ("Mail") rather than its desktop file.
        const label = String(n.appName || "").toLowerCase()
        const entry = !label ? null : DesktopEntries.heuristicLookup(n.appName)
            ?? DesktopEntries.applications.values.find((e) => String(e.name).toLowerCase() === label)
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
    // The banners as a model, so each one keeps its card while others come and
    // go: a new one slides in, a leaving one slides out, the rest move along.
    ListModel { id: bannerModel }
    onBannersChanged: {
        const ids = banners.map((b) => b.id)
        for (let i = bannerModel.count - 1; i >= 0; i--)
            if (!ids.includes(bannerModel.get(i).nid)) bannerModel.remove(i)
        ids.forEach((id, i) => {
            let at = -1
            for (let j = 0; j < bannerModel.count; j++) if (bannerModel.get(j).nid === id) { at = j; break }
            if (at < 0) bannerModel.insert(i, { nid: id })
            else if (at !== i) bannerModel.move(at, i, 1)
        })
    }
    function bannerFor(id) { return banners.find((b) => b.id === id) ?? null }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.now = Date.now() }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        imageSupported: true
        bodyMarkupSupported: false
        onNotification: (n) => {
            const choice = Prefs.notifyApp(root.keyOf(n))
            root.remember(n)
            if (!choice.allow) return          // untracked, so it's dropped
            n.tracked = true
            const r = Object.assign({}, root.received); r[n.id] = Date.now(); root.received = r
            root.now = Date.now()
            n.closed.connect(() => root.dropBanner(n))
            if (!root.dnd && !root.centerOpen && choice.banners) root.banners = [n].concat(root.banners.filter((b) => b !== n)).slice(0, 4)
            if (!root.dnd && Prefs.notifySounds && choice.sound && !n.transient && !(n.hints?.["suppress-sound"] ?? false)) root.chime()
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
        // What it shows, kept once the notification itself is gone, so a card
        // sliding away doesn't empty and shrink as it goes.
        readonly property bool live: !!n
        property string title
        property string bodyText
        property string stamp
        property string icon
        property var actionList: []
        Binding on title { when: card.live; restoreMode: Binding.RestoreNone
            value: !card.live ? "" : Prefs.notifyPreviews === "never" ? root.appLabel(card.n) : card.n.summary || root.appLabel(card.n) }
        Binding on bodyText { when: card.live; restoreMode: Binding.RestoreNone
            value: !card.live ? "" : Prefs.notifyPreviews === "never" ? "Notification" : card.n.body }
        Binding on stamp { when: card.live; restoreMode: Binding.RestoreNone; value: card.live ? root.timeLabel(card.n) : "" }
        Binding on icon { when: card.live; restoreMode: Binding.RestoreNone; value: card.live ? root.iconFor(card.n) : "" }
        Binding on actionList { when: card.live; restoreMode: Binding.RestoreNone
            value: card.live ? card.n.actions.filter((a) => a.identifier !== "default") : [] }
        role: "regular"
        radius: 22
        implicitHeight: content.implicitHeight + 24
        pressed: tap.pressed
        hovered: hover.hovered
        HoverHandler { id: hover }
        TapHandler { id: tap; onTapped: if (card.live) root.open(card.n) }

        RowLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 14 }
            spacing: 11
            Item {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 36; Layout.preferredHeight: 36
                readonly property string resolved: card.icon
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
                        // Previews off: the app's name and no more, as on the Mac.
                        text: card.title
                        textFormat: Text.PlainText; elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                    }
                    Text {
                        text: card.stamp
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.bodyText
                    textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                }
                RowLayout {
                    visible: card.actionList.length > 0
                    Layout.topMargin: 6
                    spacing: 6
                    Repeater {
                        model: card.actionList
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 26; radius: 13
                            color: actionTap.pressed ? Theme.selection : Theme.fill
                            Text { anchors.centerIn: parent; text: modelData.text; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium } }
                            TapHandler { id: actionTap; onTapped: if (card.live) modelData.invoke() }
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
            Behavior on opacity { NumberAnimation { duration: 130 } }
            Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: Theme.dark ? "white" : "dark" }
            TapHandler { onTapped: if (card.live) card.n.dismiss() }
        }
    }

    // Banners. The surface reaches the screen's edge, so a banner slides in
    // from it and back out to it; only the banners take input.
    PanelWindow {
        id: bannerWindow
        screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; right: true }
        margins { top: 8; right: root.controlCenterOpen ? 356 : 0 }
        implicitWidth: 370
        // Room for four banners: a fixed size, so the surface doesn't resize
        // on every frame while they move.
        implicitHeight: 4 * 150 + 3 * 8 + 16
        exclusionMode: ExclusionMode.Normal   // sit below the menu bar
        color: "transparent"
        visible: !root.dnd && (root.banners.length > 0 || bannerList.count > 0)
        WlrLayershell.namespace: "gg-notifications"
        // What its glass bends: the desktop under it.
        DesktopBackdrop { surface: bannerWindow; namespace: "gg-notifications" }
        WlrLayershell.layer: WlrLayer.Overlay
        mask: Region { item: bannerArea }
        // Input only where the banners are. The view itself is the surface's
        // height: one that shrank with its content dropped a leaving banner
        // at once, outside it, before it could slide away.
        Item { id: bannerArea; width: bannerList.width; height: Math.min(bannerList.contentHeight, bannerList.height) }

        ListView {
            id: bannerList
            objectName: "bannerList"
            x: 0; width: 360
            height: parent.height
            interactive: false
            spacing: 8
            model: bannerModel
            readonly property real away: width + 30
            readonly property bool still: Theme.reduceMotion

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; from: bannerList.still ? 0 : bannerList.away; to: 0
                        duration: bannerList.still ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve }
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: bannerList.still ? 160 : 220 }
                }
            }
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "x"; to: bannerList.still ? 0 : bannerList.away; duration: 260; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
                }
            }
            displaced: Transition {
                NumberAnimation { property: "y"; duration: bannerList.still ? 0 : Theme.snappy.duration
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve }
                // A banner caught mid-arrival finishes arriving.
                NumberAnimation { property: "x"; to: 0; duration: 175 }
                NumberAnimation { property: "opacity"; to: 1; duration: 175 }
            }

            delegate: Card {
                id: banner
                required property int nid
                n: null
                width: bannerList.width
                height: implicitHeight
                Component.onCompleted: n = root.bannerFor(nid)
                // A swipe to the right follows the pointer and fades it.
                property real dragX: 0
                transform: Translate { x: banner.dragX }
                opacity: 1 - Math.max(0, dragX) / 320
                Behavior on dragX { enabled: !drag.active; Spring { spring: Theme.snappy } }

                // The banner goes; the notification stays in Notification Center.
                // Its time counts from when it arrived.
                readonly property int life: banner.live && banner.n.expireTimeout > 0 ? banner.n.expireTimeout * 1000 : 5500
                Timer {
                    interval: Math.max(600, banner.life - (Date.now() - (root.received[banner.nid] ?? Date.now())))
                    running: banner.live && !bannerHover.hovered && !banner.n.resident
                    onTriggered: root.dropBanner(banner.n)
                }
                HoverHandler { id: bannerHover }
                DragHandler {
                    id: drag
                    target: null
                    xAxis.enabled: true; yAxis.enabled: false
                    onTranslationChanged: banner.dragX = Math.max(-20, translation.x)
                    onActiveChanged: if (!active) {
                        if (banner.dragX > 110 && banner.live) root.dropBanner(banner.n)
                        else banner.dragX = 0
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
        // What its glass bends: the desktop under it.
        DesktopBackdrop { surface: center; namespace: "gg-notification-center" }
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
                            style: Text.Raised; styleColor: "#80000000"
                            font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
                        }
                        Glass {
                            role: "control"
                            implicitWidth: clearAll.implicitWidth + 22; implicitHeight: 24; radius: 12
                            pressed: clearTap.pressed
                            Text { id: clearAll; anchors.centerIn: parent; text: "Clear All"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium } }
                            TapHandler { id: clearTap; onTapped: root.list.slice().forEach((n) => n.dismiss()) }
                        }
                    }

                    Repeater {
                        model: center.groups
                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            required property int index
                            readonly property bool open: center.expanded[modelData.app] === true || modelData.items.length === 1
                            Layout.fillWidth: true
                            spacing: 6
                            // Opening Notification Center, the groups cascade in after
                            // the panel, one a moment after another.
                            property real shown: 1
                            opacity: shown
                            transform: Translate { x: (1 - group.shown) * 40 }
                            Connections {
                                target: root
                                function onCenterOpenChanged() {
                                    if (!root.centerOpen || Theme.reduceMotion) return
                                    group.shown = 0
                                    cascade.restart()
                                }
                            }
                            SequentialAnimation {
                                id: cascade
                                PauseAnimation { duration: 70 + Math.min(group.index, 6) * 45 }
                                NumberAnimation { target: group; property: "shown"; to: 1; duration: Theme.snappy.duration
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve }
                            }
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
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                                }
                                Glass {
                                    role: "control"
                                    implicitWidth: lessText.implicitWidth + 20; implicitHeight: 22; radius: 11
                                    Text { id: lessText; anchors.centerIn: parent; text: group.open ? "Show Less" : (group.modelData.items.length - 1) + " more"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium } }
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
                                    id: stacked
                                    required property var modelData
                                    required property int index
                                    n: modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: implicitHeight
                                    // Spreading a stack, the cards behind slide down out of it.
                                    property real spread: 0
                                    opacity: 1 - spread
                                    transform: Translate { y: -stacked.spread * 24 * Math.min(stacked.index, 3) }
                                    Component.onCompleted: if (index > 0 && !Theme.reduceMotion) { spread = 1; unstack.start() }
                                    NumberAnimation {
                                        id: unstack
                                        target: stacked; property: "spread"; to: 0
                                        duration: Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve
                                    }
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
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
                        }
                    }
                }
            }
        }
    }
}
