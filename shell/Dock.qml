// Dock: iPad-style glass shelf with fixed-size icons, running indicators,
 // launch bounce and tooltips. Pointer-driven magnification is intentionally
 // absent: the shelf never changes geometry while the pointer moves.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "ui/theme"
import "components"

PanelWindow {
    id: dock
    property bool liveSession: false
    // Keep in Dock / Remove from Dock, dragging and Launchpad's Add to Dock all
    // edit the one list in desktop.json (dock.pinned), through Prefs.
    readonly property var keptIds: Prefs.keptInDock
    property var pinned: (liveSession ? ["org.goldengate.Installer"] : []).concat(keptIds.filter((id) => id !== "org.goldengate.Installer"))
    property var notifications: null    // Notification Center, for the red badges
    function keep(entry, on) {
        const ids = keptIds.filter((id) => id !== entry.id)
        if (on) ids.push(entry.id)
        Prefs.setDockPinned(ids)
    }

    // ---------------------------------------------------------- rearranging
    // As on the Mac: drag an icon along the Dock and the others make room;
    // drag a kept app up off the Dock and "Remove" shows, and it goes in a
    // puff; drag a running app in among the kept ones to keep it there.
    //
    // The pointer is measured against `ground`, a line along the bottom of the
    // surface that never moves: not against the dragged icon (which moves with
    // the pointer, so its own coordinates would feed back into the drag) and
    // not against the shelf (which recentres as icons make room). The icon is
    // then placed where the pointer is, whatever the shelf did meanwhile.
    property string dragId: ""
    property bool dragKept: false
    property real dragDX: 0
    property real dragDY: 0
    property int dropSlot: -1           // where it lands among the kept apps; -1: nowhere
    readonly property bool dragging: dragId !== ""
    readonly property bool removing: dragging && dragKept && dragDY < -(baseSize * 1.15)
    readonly property real step: baseSize + 6
    // The kept apps in the order they'd be in if the icon were let go now.
    readonly property var previewOrder: orderAfter(entries.map((e) => e.id), dragId, removing ? -1 : dropSlot)
    // ids with id taken out and put back at slot (among the others); slot -1
    // leaves it out (dragged off, or a running app dragged nowhere).
    function orderAfter(ids, id, slot) {
        const out = ids.filter((x) => x !== id)
        if (id && slot >= 0) out.splice(Math.min(slot, out.length), 0, id)
        return out
    }
    function slotX(id) { return Math.max(0, previewOrder.indexOf(id)) * step }
    function dragMoved(groundPoint) {
        const p = ground.mapToItem(keptBox, groundPoint.x, groundPoint.y)
        // Where the icon's middle is (it may have been picked up off-centre).
        const mid = ground.mapToItem(keptBox, pressGroundX + dragDX + baseSize / 2, 0).x
        const others = entries.filter((e) => e.id !== dragId).length
        const near = mid < keptBox.width + baseSize && p.y > -baseSize * 1.15 && p.y < baseSize * 1.6
        // The live session's Installer stays first.
        const first = liveSession ? 1 : 0
        dropSlot = near ? Math.max(first, Math.min(others, Math.round((mid - baseSize / 2) / step))) : -1
    }
    function dragEnded() {
        const id = dragId
        if (removing) {
            // Where the icon is: under the pointer.
            const p = ground.mapToItem(null, pressGroundX + dragDX, 0)
            const top = keptBox.mapToItem(null, 0, 0).y
            poof.play(p.x + baseSize / 2, top + dragDY + baseSize / 2)
            Prefs.setDockPinned(keptIds.filter((k) => k !== id))
        } else if (dropSlot >= 0) {
            const order = previewOrder.filter((k) => k !== "org.goldengate.Installer")
            if (JSON.stringify(order) !== JSON.stringify(keptIds)) Prefs.setDockPinned(order)
        }
        dragId = ""
        dropSlot = -1
        dragDX = 0
        dragDY = 0
    }
    property real slotXAtPress: 0
    property real pressGroundX: 0       // where the lifted icon was on the ground line when picked up
    // Size from Settings › Desktop & Dock. Keep every icon on one stable grid.
    readonly property int tileCount: entries.length + runningIds.length + places.length
    // Density is a high-water mark for this session. Closing an app must not
    // resize every remaining icon (or the compositor's reserved work area).
    property int densityCount: 0
    onTileCountChanged: densityCount = Math.max(densityCount, tileCount)
    readonly property real restingWidth: tileCount * (baseSize + 6) + 28
    property real baseSize: Math.min(Prefs.dockSize, Math.max(16, (width - 48) / (densityCount + 3) - 6))
    Behavior on baseSize { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
    property var launcher: null   // AppLaunch on this screen: the icon grows into the window
    property var applications: null
    property real contextX: 0
    property real contextY: 0
    property var contextItems: []

    function openEntry(entry) {
        if (applications?.open) applications.dismiss()
        const parked = minimizedFor(entry)
        const wins = windowsFor(entry)
        if (parked) restore(parked)
        else if (wins.length) wins[0].activate()
        else if (!entry.synthetic) { retainForLaunch(entry); entry.execute() }
    }

    function quitEntry(entry) {
        const wins = windowsFor(entry)
        // These are Wayland toplevels (windowsFor), which close themselves;
        // they carry no Hyprland IPC object.
        for (let i = 0; i < wins.length; i++) wins[i].close()
    }

    function showEntryMenu(entry, item, localX, localY) {
        const point = item.mapToItem(shelf, localX, localY)
        const wins = windowsFor(entry)
        let menu = [
            { label: wins.length ? "Show" : "Open", action: () => dock.openEntry(entry) }
        ]
        if (wins.length) {
            menu.push("-")
            for (let i = 0; i < wins.length; i++) {
                const win = wins[i]
                menu.push({ label: win.title || entry.name || "Window", action: () => { if (applications?.open) applications.dismiss(); win.activate() } })
            }
        }
        menu.push("-")
        const kept = dock.pinned.includes(entry.id)
        if (entry.id !== "org.goldengate.Installer" && !entry.synthetic)
            menu.push({ label: kept ? "Remove from Dock" : "Keep in Dock", action: () => dock.keep(entry, !kept) })
        if (wins.length) {
            menu.push("-")
            menu.push({ label: "Quit", shortcut: "⌘Q", action: () => dock.quitEntry(entry) })
        }
        contextItems = menu
        contextX = shelf.x + point.x
        contextY = shelf.y + point.y
        dockMenu.open = true
    }

    function showPlaceMenu(place, item, localX, localY) {
        const point = item.mapToItem(shelf, localX, localY)
        if (place.action === "applications") {
            contextItems = [{ label: "Open Applications", action: () => dock.openApplications() }]
        } else if (place.name === "Downloads") {
            contextItems = [{ label: "Open Downloads", action: () => Quickshell.execDetached(place.exec) }]
        } else {
            contextItems = [
                { label: "Open Trash", action: () => Quickshell.execDetached(place.exec) },
                "-",
                { label: "Empty Trash", enabled: dock.trashFull, action: () => dock.emptyTrash() }
            ]
        }
        contextX = shelf.x + point.x
        contextY = shelf.y + point.y
        dockMenu.open = true
    }

    function emptyTrash() { Trash.empty() }

    // The Dock icon of the app a window belongs to (its class), for a closing
    // window to fold back into: x across the screen, y up from its bottom
    // edge (negative), which is where every full-width bottom surface agrees.
    property var tiles: []
    function iconFor(appClass) {
        const c = String(appClass ?? "").toLowerCase()
        if (!c) return null
        const tile = tiles.find((t) => {
            const id = String(t.modelData?.id ?? "").toLowerCase()
            const startup = String(t.modelData?.startupClass ?? "").toLowerCase()
            return id === c || id.split(".").pop() === c || (startup && startup === c)
        })
        if (!tile || !tile.visible) return null
        const p = tile.iconItem.mapToItem(ground, 0, 0)
        return { entry: tile.modelData, rect: Qt.rect(p.x, p.y - ground.height + 1, tile.iconItem.width, tile.iconItem.height) }
    }

    function openApplications() {
        if (applications)
            applications.present()
    }

    anchors { bottom: true; left: true; right: true }
    // Room for the label, its gap, the bounce and an icon dragged up off the
    // Dock. Always this tall: a surface resized under a pressed pointer moves
    // everything under it (and can cancel the press).
    implicitHeight: Prefs.dockSize + 230
    exclusiveZone: Prefs.dockSize + 22
    color: "transparent"
    WlrLayershell.namespace: "gg-dock"
    WlrLayershell.layer: applications?.visible ? WlrLayer.Overlay : WlrLayer.Top
    // Touch-style shelf: only the shelf itself takes input, except while an
    // icon is dragged, when the whole surface follows the pointer.
    mask: Region { item: dock.dragging ? dragZone : shelf }
    Item { id: dragZone; anchors.fill: parent }
    // What the shelf's glass bends: the desktop under it.
    DesktopBackdrop { surface: dock; namespace: "gg-dock" }
    Item {
        id: ground
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    Process {
        running: true
        command: ["sh", "-c", "test -d /run/archiso && printf yes || true"]
        stdout: StdioCollector { onStreamFinished: dock.liveSession = text.trim() === "yes" }
    }
    // Written by icons/build.mjs unless a custom Calendar icon replaces the default.
    Image {
        id: calBlank
        readonly property bool loaded: status === Image.Ready
        visible: false
        source: Qt.resolvedUrl("assets/calendar-blank.svg")
    }

    // Right of the separator: Downloads and the Trash (full or empty).
    readonly property bool trashFull: Trash.full     // components/Trash.qml watches it
    readonly property var places: [
        { name: "Applications", icon: "apps", action: "applications" },
        { name: "Downloads", icon: "folder", exec: ["gg-files", Quickshell.env("HOME") + "/Downloads"] },
        { name: "Trash", icon: trashFull ? "user-trash-full" : "user-trash", exec: ["gg-files", "trash:"] },
    ]

    // Reading applications.values makes this re-evaluate once the entry scan finishes.
    readonly property var entries: {
        DesktopEntries.applications.values;
        return pinned.map((id) => DesktopEntries.byId(id)).filter((e) => e)
    }
    // Open apps that aren't kept in the Dock, in the order they opened: every
    // one, as on the Mac. Its desktop entry is found by id, by id in lower
    // case, by Quickshell's guess, or by the entry's StartupWMClass (hidden
    // entries too: a running app is shown either way). An app with no entry
    // at all (a script, an AppImage, a Mac app) gets a stand-in: its name made
    // from its window's id and the icon theme's icon for that id. Apps whose
    // entry couldn't be found used to be left out of the Dock altogether.
    readonly property var running: {
        DesktopEntries.applications.values;
        const out = []
        for (const t of ToplevelManager.toplevels.values) {
            const appId = t.appId ?? ""
            if (!appId) continue
            if (entries.some((e) => windowsFor(e).includes(t))) continue
            const entry = entryForWindow(appId)
            // (Found only by the guess or its StartupWMClass, a kept app's
            // window showed a second icon here, and no dot on the kept one.)
            if (entries.some((e) => e.id === entry.id) || out.some((e) => e.id === entry.id)) continue
            out.push(entry)
        }
        return out
    }
    // Stable app identities, independent of Wayland's window list snapshots.
    // Keep the last icon briefly, then animate its whole slot (including gap)
    // away. Reopening at either stage reverses the same delegate's transition.
    property var runningIds: []
    property var runningRecords: ({})
    readonly property int recentHoldMs: 900
    readonly property int departureMs: 220
    onRunningChanged: reconcileRunning()
    onEntriesChanged: reconcileRunning()
    function reconcileRunning() {
        const now = Date.now(), next = Object.assign({}, runningRecords)
        const active = running.map(e => e.id), kept = entries.map(e => e.id)
        let ids = runningIds.filter(id => !kept.includes(id))
        for (const id of Object.keys(next)) if (kept.includes(id)) delete next[id]
        for (const e of running) {
            if (!ids.includes(e.id)) ids.push(e.id)
            next[e.id] = { entry: e, phase: "active", deadline: 0 }
        }
        for (const id of ids) {
            if (!active.includes(id) && next[id]?.phase === "active")
                next[id] = { entry: next[id].entry, phase: "recent", deadline: now + recentHoldMs }
        }
        runningRecords = next
        if (ids.join("\n") !== runningIds.join("\n")) runningIds = ids
    }
    function expireRecent() {
        const now = Date.now(), next = Object.assign({}, runningRecords)
        let changed = false
        for (const id of runningIds) {
            const r = next[id]
            if (id === dragId) continue
            if (!r || r.phase === "active" || now < r.deadline) continue
            if (r.phase === "recent" && !Prefs.reduceMotion) {
                next[id] = { entry: r.entry, phase: "leaving", deadline: now + departureMs + 50 }
            } else delete next[id]
            changed = true
        }
        if (!changed) return
        runningRecords = next
        const ids = runningIds.filter(id => next[id])
        if (ids.join("\n") !== runningIds.join("\n")) runningIds = ids
    }
    function retainForLaunch(entry) {
        if (!runningRecords[entry.id]) return
        const next = Object.assign({}, runningRecords)
        next[entry.id] = { entry: entry, phase: "recent", deadline: Date.now() + 8000 }
        runningRecords = next
    }
    Timer {
        interval: 25; repeat: true
        running: dock.runningIds.some(id => dock.runningRecords[id]?.phase !== "active")
        onTriggered: dock.expireRecent()
    }
    function entryForWindow(appId) {
        const lower = appId.toLowerCase()
        const found = DesktopEntries.byId(appId) ?? DesktopEntries.byId(lower) ?? DesktopEntries.heuristicLookup(appId)
            ?? DesktopEntries.applications.values.find((e) => (e.startupClass ?? "").toLowerCase() === lower)
        if (found) return found
        const name = appId.split(".").pop().replace(/[-_]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase())
        return { id: appId, name: name || appId, icon: lower, startupClass: appId, synthetic: true, execute: () => {} }
    }
    // Apps asking for attention (a window marked urgent): their icons bounce
    // until one of their windows is brought forward, as on the Mac.
    property var attention: []          // lower-case window classes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "urgent") {
                const address = "0x" + String(event.data).replace(/^0x/, "")
                const t = Hyprland.toplevels.values.find((w) => (w.lastIpcObject?.address ?? "") === address)
                const cls = (t?.wayland?.appId ?? t?.lastIpcObject?.class ?? "").toLowerCase()
                if (cls && !dock.attention.includes(cls)) dock.attention = dock.attention.concat([cls])
            } else if (event.name === "activewindow") {
                const cls = String(event.parse(2)[0] ?? "").toLowerCase()
                if (dock.attention.includes(cls)) dock.attention = dock.attention.filter((c) => c !== cls)
            }
        }
    }
    function wantsAttention(entry) {
        const appId = (entry.id ?? "").toLowerCase()
        const startup = (entry.startupClass ?? "").toLowerCase()
        return attention.some((c) => c === appId || c === appId.split(".").pop() || (!!startup && c === startup))
    }
    function windowsFor(entry) {
        const appId = (entry.id ?? "").toLowerCase()
        const bare = appId.split(".").pop()
        const startup = (entry.startupClass ?? "").toLowerCase()
        return ToplevelManager.toplevels.values.filter((t) => {
            const id = (t.appId ?? "").toLowerCase()
            return id === appId || id === bare || (!!startup && id === startup)
                || (!!id && dock.entryForWindow(t.appId).id === entry.id)
        })
    }
    // A window of this app parked by the yellow light (shell.qml) or ⌘H, to bring back.
    function minimizedFor(entry) {
        const appId = (entry.id ?? "").toLowerCase()
        const bare = appId.split(".").pop()
        const startup = (entry.startupClass ?? "").toLowerCase()
        return Hyprland.toplevels.values.find((t) => {
            // Minimised (yellow light, ⌘M) or hidden (⌘H): both come back on a click.
            if (t.workspace?.name !== "special:minimized" && t.workspace?.name !== "special:hidden") return false
            const cls = (t.wayland?.appId ?? t.lastIpcObject?.class ?? "").toLowerCase()
            return cls === appId || cls === bare || (!!startup && cls === startup)
        })
    }
    function restore(t) {
        // A Dock click belongs to the Dock's monitor, not whichever monitor last
        // had keyboard focus. This keeps restored windows on the screen clicked.
        const monitor = Hyprland.monitorFor(dock.screen)
        const ws = monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
        const address = t.address ? "0x" + t.address.replace(/^0x/, "") : t.lastIpcObject?.address
        if (address) Hyprland.dispatch(`movetoworkspace ${ws},address:${address}`)
        if (monitor?.name) Hyprland.dispatch(`focusmonitor ${monitor.name}`)
    }
    // One app in the Dock: icon, running dot, badge, tooltip, launch bounce.
    component AppTile: Item {
        id: tile
        required property var modelData
        required property int index
        property bool kept: false
        property real layoutOriginX: kept ? keptBox.x : 0
        readonly property var wins: dock.windowsFor(modelData)
        readonly property Item iconItem: icon
        Component.onCompleted: dock.tiles = dock.tiles.concat([tile])
        Component.onDestruction: dock.tiles = dock.tiles.filter((t) => t !== tile)
        readonly property bool lifted: dock.dragId === (modelData.id ?? "") && dock.dragKept === kept
        width: dock.baseSize
        height: row.height
        z: lifted ? 100 : 0
        // While dragged, it sits under the pointer: where it was picked up plus
        // how far the pointer has gone, less wherever its slot has moved to
        // since (the shelf recentring as icons make room). A running app that
        // won't land anywhere is dimmed.
        readonly property real groundX: shelf.x + row.x + layoutOriginX + x
        transform: Translate {
            x: tile.lifted ? dock.pressGroundX + dock.dragDX - tile.groundX : 0
            y: tile.lifted ? dock.dragDY : 0
        }
        opacity: tile.lifted && !tile.kept && dock.dropSlot < 0 ? 0.6 : 1

        // The icon bounces while the app opens, until its first window shows
        // (or eight seconds pass), and while it asks for attention.
        property bool launching: false
        readonly property bool opening: dock.launcher?.state_ === "opening" && (dock.launcher.entry?.id ?? "") === (modelData.id ?? "")
        readonly property bool hopping: (launching || opening || dock.wantsAttention(modelData)) && !Prefs.reduceMotion
        onWinsChanged: if (wins.length) launching = false
        Timer { running: tile.launching; interval: 8000; onTriggered: tile.launching = false }

        // Calendar apps show today's date, drawn over a date-less icon.
        readonly property bool calendar: /calendar/i.test(modelData.icon ?? "") && calBlank.loaded

        Image {
            id: icon
            width: dock.baseSize; height: dock.baseSize
            x: 0
            property real launchOffset: 0
            y: tile.height - height + launchOffset
            z: Math.round(width * 10)
            source: tile.calendar ? calBlank.source : Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
            sourceSize: Qt.size(dock.baseSize * 2, dock.baseSize * 2)
            smooth: true; mipmap: true
            // Pressed, the icon darkens and settles a few percent, without
            // fighting the Dock's size-based magnification wave.
            scale: !Prefs.reduceMotion && tipArea.pressed ? 0.955 : 1
            Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
            readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
            layer.enabled: gpu && tipArea.pressed
            layer.effect: MultiEffect { brightness: -0.28 }
            opacity: !gpu && tipArea.pressed ? 0.7 : 1
            // A hop is thrown up and falls back as under gravity (out, then in);
            // the last one always lands.
            SequentialAnimation on launchOffset {
                running: tile.hopping
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: -Math.round(dock.baseSize * 0.4); duration: 175; easing.type: Easing.OutQuad }
                NumberAnimation { to: 0; duration: 175; easing.type: Easing.InQuad }
                PauseAnimation { duration: 110 }
            }
            Text {
                visible: tile.calendar
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.30 - baselineOffset
                text: Qt.formatDate(clock.date, "ddd").toUpperCase()
                color: "#ff3b30"
                font { family: Theme.fontUi; pixelSize: Math.max(6, Math.round(parent.height * 0.13)); weight: Font.DemiBold; letterSpacing: 0.5 }
            }
            Text {
                visible: tile.calendar
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.76 - baselineOffset
                text: clock.date.getDate()
                color: "#1c1c1e"
                font { family: Theme.fontUi; pixelSize: Math.max(12, Math.round(parent.height * 0.46)); weight: Font.Light; letterSpacing: -2 }
            }
        }
        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: -6 }
            width: 4; height: 4; radius: 2
            color: Theme.dark ? "#ccffffff" : "#8c000000"
            opacity: tile.wins.length && Prefs.dockIndicators ? 1 : 0
            scale: opacity > 0.5 ? 1 : 0.2
            Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 260 } }
            Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.bouncy } }
        }
        // Unread notifications, as a red badge on the icon's top right.
        readonly property int badge: dock.notifications ? dock.notifications.countFor(modelData.id ?? "", modelData.startupClass ?? "") : 0
        property int lastBadge: 0
        onBadgeChanged: {
            if (badge > lastBadge && lastBadge > 0 && !Prefs.reduceMotion) badgePulse.restart()
            lastBadge = badge
        }
        Rectangle {
            id: badgeDot
            // Pops in on a spring; a new notification bumps it.
            scale: tile.badge > 0 ? 1 : 0
            visible: scale > 0.01
            Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.bouncy } }
            property real bump: 1
            transform: Scale { origin.x: badgeDot.width / 2; origin.y: badgeDot.height / 2; xScale: badgeDot.bump; yScale: badgeDot.bump }
            SequentialAnimation {
                id: badgePulse
                NumberAnimation { target: badgeDot; property: "bump"; to: 1.28; duration: 120; easing.type: Easing.OutQuad }
                NumberAnimation { target: badgeDot; property: "bump"; to: 1; duration: 280; easing.type: Easing.OutBack }
            }
            z: 1000
            readonly property real size: Math.max(16, Math.round(dock.baseSize * 0.34))
            x: icon.x + icon.width - width * 0.75
            y: icon.y - height * 0.25
            height: size
            width: Math.max(size, badgeText.implicitWidth + size * 0.6)
            radius: size / 2
            color: Theme.accentRed
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: tile.badge > 99 ? "99+" : tile.badge
                color: "#ffffff"
                font { family: Theme.fontUi; pixelSize: Math.round(parent.size * 0.62); weight: Font.DemiBold }
            }
        }
        property bool tooltipReady: false
        Timer {
            id: tooltipDwell
            interval: 300
            onTriggered: if (tipArea.containsMouse && !tipArea.pressed && !tile.lifted)
                tile.tooltipReady = true
        }
        Glass {
            id: tip
            readonly property bool shown: (tile.tooltipReady && tipArea.containsMouse && !tipArea.pressed)
                || (tile.lifted && dock.removing)
            visible: opacity > 0
            opacity: shown ? 1 : 0
            scale: Prefs.reduceMotion ? 1 : shown ? 1 : 0.94
            transformOrigin: Item.Bottom
            Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 0 : (tip.shown ? 115 : 80) } }
            Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.popover } }
            anchors { bottom: icon.top; bottomMargin: 10 }
            x: Math.max(8 - tile.groundX, Math.min((parent.width - width) / 2, dock.width - 8 - tile.groundX - width))
            width: Math.min(dock.width - 16, tipText.implicitWidth + 24); height: 26; radius: 13
            role: "menu"
            Text { id: tipText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: tile.lifted && dock.removing ? "Remove" : tile.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium } }
        }
        MouseArea {
            id: tipArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property point start             // on the ground line
            property bool moved: false
            onEntered: { tile.tooltipReady = false; tooltipDwell.restart() }
            onExited: { tooltipDwell.stop(); tile.tooltipReady = false }
            // A stand-in (no desktop entry) can't be kept: nothing would open it again.
            readonly property bool movable: tile.modelData.id !== "org.goldengate.Installer" && !tile.modelData.synthetic
            function onGround(mouse) { return tipArea.mapToItem(ground, mouse.x, mouse.y) }
            onPressed: mouse => {
                tooltipDwell.stop(); tile.tooltipReady = false
                start = onGround(mouse); moved = false
            }
            onPositionChanged: mouse => {
                if (!pressed || !(pressedButtons & Qt.LeftButton) || !movable) return
                const p = onGround(mouse)
                const dx = p.x - start.x, dy = p.y - start.y
                if (!moved && Math.hypot(dx, dy) < 8) return
                if (!moved) {
                    moved = true
                    dock.slotXAtPress = tile.kept ? dock.slotX(tile.modelData.id) : 0
                    dock.pressGroundX = tile.groundX
                    dock.dragKept = tile.kept
                    dock.dragId = tile.modelData.id
                }
                dock.dragDX = dx
                dock.dragDY = dy
                dock.dragMoved(p)
            }
            onReleased: { if (moved) dock.dragEnded() }
            onCanceled: { if (moved) dock.dragEnded() }
            onClicked: mouse => {
                if (moved) return
                if (mouse.button === Qt.RightButton) {
                    dock.showEntryMenu(tile.modelData, tile, mouse.x, mouse.y)
                    return
                }
                if (dock.applications?.open) dock.applications.dismiss()
                const parked = dock.minimizedFor(tile.modelData)
                if (parked) dock.restore(parked)
                else if (tile.wins.length) tile.wins[0].activate()
                else if (dock.launcher?.enabled && Prefs.animateLaunch) {
                    dock.retainForLaunch(tile.modelData)
                    tile.launching = true
                    const p = icon.mapToItem(null, 0, 0)
                    dock.launcher.launch(tile.modelData, Qt.rect(p.x, dock.launcher.height - dock.height + p.y, icon.width, icon.height))
                } else {
                    dock.retainForLaunch(tile.modelData)
                    if (Prefs.animateLaunch) tile.launching = true
                    tile.modelData.execute()
                }
            }
        }
    }

    Glass {
        id: shelf
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
        width: row.width + 18
        height: dock.baseSize + 18
        role: "dock"
        radius: Theme.radiusDock + 2

        Row {
            id: row
            objectName: "dockRow"
            anchors { left: parent.left; leftMargin: 9; bottom: parent.bottom; bottomMargin: 9 }
            // Each slot owns its spacing so the last disappearing slot cannot
            // leave a one-frame Row spacing jump when its delegate is removed.
            spacing: 0
            height: dock.baseSize
            Item {
                id: keptBox
                width: dock.previewOrder.length * dock.step
                height: dock.baseSize
                anchors.bottom: parent.bottom
                Behavior on width { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                Repeater {
                    model: ScriptModel { values: dock.entries }
                    delegate: AppTile {
                        id: keptTile
                        kept: true
                        anchors.bottom: parent.bottom
                        // In its slot; the one being dragged stays where it was
                        // picked up (it follows the pointer from there).
                        x: lifted ? dock.slotXAtPress : dock.slotX(modelData.id)
                        Behavior on x { enabled: !keptTile.lifted && !Prefs.reduceMotion; NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
                    }
                }
            }
            // Apps running that aren't kept in the Dock, after a divider, as on the Mac.
            Item {
                id: runningGroup
                width: runningRow.width; height: dock.baseSize
                anchors.bottom: parent.bottom
                Row {
                    id: runningRow
                    height: parent.height
                    Item {
                        readonly property real presence: {
                            let max = 0
                            for (let i = 0; i < runningSlots.count; i++)
                                max = Math.max(max, runningSlots.itemAt(i)?.presence ?? 0)
                            return max
                        }
                        width: 17 * presence; height: dock.baseSize
                        opacity: presence
                        Rectangle {
                            x: (parent.width - 6 * parent.presence - width) / 2
                            y: (parent.height - height) / 2
                            width: 1; height: parent.height - 12
                            color: Theme.dark ? "#40ffffff" : "#2e000000"
                        }
                    }
                    Repeater {
                        id: runningSlots
                        model: ScriptModel { values: dock.runningIds }
                        delegate: Item {
                            id: slot
                            required property string modelData
                            required property int index
                            objectName: "dockSlot:" + modelData
                            readonly property var record: dock.runningRecords[modelData]
                            property bool ready: false
                            property real presence: ready && record && record.phase !== "leaving" ? 1 : 0
                            Component.onCompleted: ready = true
                            Behavior on presence { enabled: !Prefs.reduceMotion; NumberAnimation { duration: dock.departureMs; easing.type: Easing.OutCubic } }
                            Connections {
                                target: Prefs
                                function onReduceMotionChanged() {
                                    if (!Prefs.reduceMotion) return
                                    // Reapply the target while Behavior is disabled;
                                    // this cancels its internally owned animation.
                                    slot.presence = Qt.binding(() => slot.ready && slot.record && slot.record.phase !== "leaving" ? 1 : 0)
                                }
                            }
                            width: dock.step * presence; height: dock.baseSize
                            opacity: presence
                            enabled: presence > 0.5 && !!record && record.phase !== "leaving" && (!record.entry.synthetic || record.phase === "active")
                            AppTile {
                                modelData: slot.record?.entry ?? ({ id: slot.modelData, name: slot.modelData, icon: "application-x-executable" })
                                index: slot.index
                                layoutOriginX: runningGroup.x + slot.x
                                x: (slot.width - 6 * slot.presence - width) / 2
                                anchors.bottom: parent.bottom
                            }
                        }
                    }
                }
            }
            Item {
                width: 17; height: dock.baseSize
                anchors.bottom: parent.bottom
                Rectangle { x: (parent.width - 6 - width) / 2; y: (parent.height - height) / 2; width: 1; height: parent.height - 12; color: Theme.dark ? "#40ffffff" : "#2e000000" }
            }
            Repeater {
                model: dock.places
                delegate: Item {
                    id: place
                    required property var modelData
                    required property int index
                    width: dock.baseSize + (index < dock.places.length - 1 ? 6 : 0)
                    height: row.height

                    Image {
                        id: placeIcon
                        width: dock.baseSize
                        height: dock.baseSize
                        x: 0
                        y: place.height - height
                        z: Math.round(width * 10)
                        // Applications is an app icon like its neighbours: the theme's
                        // squircle (icons/custom/apps/launcher.png, as view-app-grid).
                        source: place.modelData.action === "applications"
                            ? (Quickshell.iconPath("view-app-grid", true) || Quickshell.iconPath("start-here", true) || Qt.resolvedUrl("assets/symbols/apps@accent.svg"))
                            : Quickshell.iconPath(place.modelData.icon, "folder")
                        sourceSize: Qt.size(dock.baseSize * 2, dock.baseSize * 2)
                        smooth: true; mipmap: true
                        scale: !Prefs.reduceMotion && placeArea.pressed ? 0.955 : 1
                        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 75; easing.type: Easing.OutCubic } }
                        readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
                        layer.enabled: gpu && placeArea.pressed
                        layer.effect: MultiEffect { brightness: -0.28 }
                        opacity: !gpu && placeArea.pressed ? 0.7 : 1
                    }
                    Glass {
                        id: placeTip
                        readonly property bool shown: placeArea.containsMouse && !placeArea.pressed
                        visible: opacity > 0
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.9
                        transformOrigin: Item.Bottom
                        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : (placeTip.shown ? 115 : 80) } }
                        Behavior on scale { Spring { spring: Theme.popover } }
                        anchors { bottom: placeIcon.top; bottomMargin: 10 }
                        x: Math.max(8 - (shelf.x + row.x + place.x), Math.min((placeIcon.width - width) / 2, dock.width - 8 - (shelf.x + row.x + place.x) - width))
                        width: Math.min(dock.width - 16, placeText.implicitWidth + 24); height: 26; radius: 13
                        role: "menu"
                        Text { id: placeText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 24); elide: Text.ElideRight; textFormat: Text.PlainText; text: place.modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium } }
                    }
                    MouseArea {
                        id: placeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                dock.showPlaceMenu(place.modelData, place, mouse.x, mouse.y)
                                return
                            }
                            if (place.modelData.action === "applications")
                                dock.openApplications()
                            else {
                                if (dock.applications?.open) dock.applications.dismiss()
                                Quickshell.execDetached(place.modelData.exec)
                            }
                        }
                    }
                }
            }
        }
    }
    // The puff an icon leaves when it's dragged off the Dock.
    Item {
        id: poof
        z: 1000
        width: 1; height: 1
        function play(px, py) {
            const p = mapFromItem(null, px, py)
            cloud.x = p.x; cloud.y = p.y
            puff.restart()
        }
        Item {
            id: cloud
            opacity: 0
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    readonly property real angle: index / 7 * Math.PI * 2
                    width: 22; height: 22; radius: 11
                    x: Math.cos(angle) * cloud.spread - 11
                    y: Math.sin(angle) * cloud.spread - 11
                    color: Theme.dark ? "#d9e5e5ea" : "#e6ffffff"
                    border { width: 0.5; color: "#26000000" }
                    scale: 0.5 + cloud.spread / 40
                }
            }
            property real spread: 4
        }
        ParallelAnimation {
            id: puff
            NumberAnimation { target: cloud; property: "spread"; from: 4; to: 30; duration: 315; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: cloud; property: "opacity"; from: 0; to: 1; duration: 60 }
                NumberAnimation { target: cloud; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
            }
        }
    }

    MenuPopup {
        id: dockMenu
        growFrom: Item.BottomLeft
        anchor.window: dock
        anchor.rect.x: Math.max(8, Math.min(dock.contextX, dock.width - menuWidth - 8))
        anchor.rect.y: Math.max(8, dock.contextY - menuHeight - 10)
        items: dock.contextItems
    }
    HyprlandFocusGrab {
        windows: [dockMenu]
        active: dockMenu.open && !dockMenu.reopening
        onCleared: if (!dockMenu.reopening && !dockMenu.suppressClear) dockMenu.open = false
    }

}

