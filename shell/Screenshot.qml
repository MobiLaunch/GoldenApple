// Screenshots and screen recording, as on the Mac.
//   ⇧⌘3  the whole screen            ⌃⇧⌘3  …to the clipboard
//   ⇧⌘4  drag over a part of it      ⌃⇧⌘4  …to the clipboard
//        (Space while choosing: pick a window instead)
//   ⇧⌘5  the toolbar: entire screen, a window or a selection, or record the
//        screen or a selection; Options holds where to save, a timer, the
//        floating thumbnail and the pointer. The selection is kept between uses.
// A capture lands as "Screenshot 2026-10-04 at 9.41.12 PM.png" (Desktop by
// default) and shows a floating thumbnail at the corner for a few seconds:
// click it to open the file, drag it into an app, or swipe it away. While
// recording, a stop button sits in the menu bar (MenuBar asks `recording`).
// grim takes pictures, wf-recorder records, wl-copy fills the clipboard.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"
import "ui/paths.js" as Paths
import "ui" as Shared

Scope {
    id: root
    // "" (closed) | "toolbar" | "area" | "window"
    property string mode: ""
    // In the toolbar: screen | window | selection | recordScreen | recordSelection
    property string choice: "selection"
    property bool toClipboard: false
    property bool fromToolbar: false
    property int countdown: 0
    readonly property bool recording: recorder.running
    readonly property bool recordingChoice: choice === "recordScreen" || choice === "recordSelection"

    // Options, kept in desktop.json (screenshot.*) through gg-pref.
    readonly property string saveTo: Prefs.data.screenshot?.saveTo ?? "desktop"   // desktop | documents | pictures | clipboard
    readonly property int timer: Prefs.data.screenshot?.timer ?? 0
    readonly property bool showThumbnail: Prefs.data.screenshot?.thumbnail ?? true
    readonly property bool showPointer: Prefs.data.screenshot?.pointer ?? false
    function setOption(key, value) {
        const next = Object.assign({}, Prefs.data.screenshot ?? {})
        next[key] = value
        Prefs.data = Object.assign({}, Prefs.data, { screenshot: next })   // at once, before the file is rewritten
        Quickshell.execDetached(["gg-pref", "screenshot." + key, JSON.stringify(value)])
    }

    // The screen in front, and where it sits in the desktop's coordinates.
    property var screen: Quickshell.screens[0]
    readonly property var monitor: Hyprland.monitorFor(screen)
    function frontScreen() {
        const name = Hyprland.focusedMonitor?.name
        return Quickshell.screens.find((s) => s.name === name) ?? Quickshell.screens[0]
    }
    // The selection, on the screen (kept between uses, as on the Mac).
    property rect selection: Qt.rect(0, 0, 0, 0)

    function open(kind, clipboard) {
        if (recording) return
        screen = frontScreen()
        toClipboard = !!clipboard
        fromToolbar = kind === "toolbar"
        if (selection.width < 8) {
            const w = screen?.width ?? 1440, h = screen?.height ?? 900
            selection = Qt.rect(Math.round(w * 0.25), Math.round(h * 0.25), Math.round(w * 0.5), Math.round(h * 0.5))
        }
        hovered = null
        mode = kind
    }
    function close() { mode = ""; countdown = 0 }

    // ------------------------------------------------------------ capturing
    function home() { return Quickshell.env("HOME") }
    function folder() {
        return saveTo === "documents" ? home() + "/Documents" : saveTo === "pictures" ? home() + "/Pictures" : home() + "/Desktop"
    }
    function stamp() { return Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' h.mm.ss AP") }
    function geometry(r) {
        const ox = monitor?.x ?? 0, oy = monitor?.y ?? 0
        return Math.round(ox + r.x) + "," + Math.round(oy + r.y) + " " + Math.max(1, Math.round(r.width)) + "x" + Math.max(1, Math.round(r.height))
    }
    // What to take, once the overlay is out of the way: a rect on this screen,
    // or null for the whole screen.
    property var pendingRect: null
    property bool pendingRecord: false
    function take(rect, record) {
        pendingRect = rect
        pendingRecord = !!record
        if (fromToolbar && timer > 0 && !record) {
            countdown = timer
            tick.restart()
            return
        }
        mode = ""
        settle.restart()
    }
    Timer { id: tick; interval: 1000; repeat: true; onTriggered: if (--root.countdown <= 0) { stop(); root.mode = ""; settle.restart() } }
    // A beat for the overlay to leave the screen before the picture is taken.
    Timer { id: settle; interval: 220; onTriggered: root.pendingRecord ? root.startRecording() : root.capture() }

    property string lastFile: ""
    function capture() {
        const clip = toClipboard || saveTo === "clipboard"
        const file = clip ? "" : folder() + "/Screenshot " + stamp() + ".png"
        const target = pendingRect ? ["-g", geometry(pendingRect)] : ["-o", screen?.name ?? ""]
        const grim = ["grim"].concat(showPointer ? ["-c"] : [], target)
        lastFile = file
        shooter.command = clip
            ? ["sh", "-c", 'grim "$@" - | wl-copy -t image/png', "sh"].concat(grim.slice(1))
            : ["sh", "-c", 'mkdir -p "$(dirname "$0")" && exec grim "$@" "$0"', file].concat(grim.slice(1))
        shooter.running = true
    }
    Process {
        id: shooter
        onExited: (code) => {
            if (code !== 0) return
            Quickshell.execDetached(["sh", "-c", "pw-play /usr/share/sounds/freedesktop/stereo/camera-shutter.oga 2>/dev/null || true"])
            if (root.lastFile && root.showThumbnail) thumb.show(root.lastFile, false)
        }
    }

    function startRecording() {
        const file = folder() + "/Screen Recording " + stamp() + ".mp4"
        lastFile = file
        recorder.command = ["wf-recorder", "-y", "-f", file].concat(pendingRect ? ["-g", geometry(pendingRect)] : ["-o", screen?.name ?? ""])
        recorder.running = true
    }
    function stopRecording() { if (recorder.running) recorder.signal(2) }      // SIGINT: wf-recorder finishes the file
    Process {
        id: recorder
        onExited: if (root.lastFile && root.showThumbnail) thumb.show(root.lastFile, true)
    }

    // The toolbar's Capture/Record button, or Return.
    function go() {
        if (choice === "screen") take(null, false)
        else if (choice === "selection") take(selection, false)
        else if (choice === "recordScreen") take(null, true)
        else if (choice === "recordSelection") take(selection, true)
        else if (choice === "window" && hovered) take(hovered.rect, false)
    }

    // Windows on this desktop, top first, for picking one.
    property var hovered: null
    function windowAt(x, y) {
        const ox = monitor?.x ?? 0, oy = monitor?.y ?? 0
        const ws = monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id
        const wins = Hyprland.toplevels.values
            .map((t) => t.lastIpcObject)
            .filter((o) => o && o.at && o.size && o.workspace?.id === ws && !o.hidden)
            .sort((a, b) => (a.focusHistoryID ?? 99) - (b.focusHistoryID ?? 99))
        const o = wins.find((o) => x >= o.at[0] - ox && y >= o.at[1] - oy && x <= o.at[0] - ox + o.size[0] && y <= o.at[1] - oy + o.size[1])
        return o ? { title: o.title, rect: Qt.rect(o.at[0] - ox, o.at[1] - oy, o.size[0], o.size[1]) } : null
    }

    IpcHandler {
        target: "screenshot"
        function toolbar(): void { root.open("toolbar", false) }
        function record(): void { root.choice = "recordSelection"; root.open("toolbar", false) }
        function area(): void { root.open("area", false) }
        function areaToClipboard(): void { root.open("area", true) }
        function window(): void { root.open("window", false) }
        function screen(): void { root.screen = root.frontScreen(); root.toClipboard = false; root.fromToolbar = false; root.take(null, false) }
        function screenToClipboard(): void { root.screen = root.frontScreen(); root.toClipboard = true; root.fromToolbar = false; root.take(null, false) }
        function stop(): void { root.stopRecording() }
    }

    // ------------------------------------------------------------ the overlay
    PanelWindow {
        id: overlay
        screen: root.screen
        visible: root.mode !== ""
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "gg-screenshot"

        readonly property bool selecting: root.mode === "area" || (root.mode === "toolbar" && (root.choice === "selection" || root.choice === "recordSelection"))
        readonly property bool picking: root.mode === "window" || (root.mode === "toolbar" && root.choice === "window")
        readonly property bool whole: root.mode === "toolbar" && (root.choice === "screen" || root.choice === "recordScreen")
        // In ⇧⌘4 nothing is chosen until you drag.
        property bool dragging: false
        readonly property rect sel: root.selection
        readonly property bool showSel: selecting && (root.mode === "toolbar" || dragging) && root.countdown === 0

        FocusScope {
            anchors.fill: parent
            focus: overlay.visible
            Keys.onEscapePressed: root.close()
            Keys.onReturnPressed: if (root.mode === "toolbar") root.go()
            Keys.onEnterPressed: if (root.mode === "toolbar") root.go()
            Keys.onSpacePressed: {
                if (root.mode === "area") root.mode = "window"
                else if (root.mode === "window" && !root.fromToolbar) root.mode = "area"
            }
        }

        // The dim: everywhere but the selection (or the window under the pointer).
        readonly property rect clear: showSel ? sel : picking && root.hovered ? root.hovered.rect : Qt.rect(0, 0, 0, 0)
        // ⇧⌘4 leaves the screen as it is until you drag, as on the Mac.
        readonly property color dim: whole ? "#14000000" : root.mode === "area" && !dragging ? "transparent" : "#66000000"
        Rectangle { x: 0; y: 0; width: parent.width; height: overlay.clear.y; color: overlay.dim }
        Rectangle { x: 0; y: overlay.clear.y + overlay.clear.height; width: parent.width; height: parent.height - y; color: overlay.dim }
        Rectangle { x: 0; y: overlay.clear.y; width: overlay.clear.x; height: overlay.clear.height; color: overlay.dim }
        Rectangle { x: overlay.clear.x + overlay.clear.width; y: overlay.clear.y; width: parent.width - x; height: overlay.clear.height; color: overlay.dim }

        // The window under the pointer, lit, with its camera.
        Rectangle {
            visible: overlay.picking && !!root.hovered
            x: root.hovered?.rect.x ?? 0; y: root.hovered?.rect.y ?? 0
            width: root.hovered?.rect.width ?? 0; height: root.hovered?.rect.height ?? 0
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
            border { width: 2; color: Theme.accent }
            radius: 12
            Symbol { anchors.centerIn: parent; name: "screenshot"; size: 40; tone: "white" }
        }

        // Choosing a part: drag to draw it; in the toolbar, drag inside to move
        // it and pull its handles to resize it.
        MouseArea {
            id: chooser
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: overlay.selecting ? Qt.CrossCursor : Qt.ArrowCursor
            property point start
            property rect from
            property string grab: ""          // "" new | "move" | handle name
            onPositionChanged: (m) => {
                if (overlay.picking) { root.hovered = root.windowAt(m.x, m.y); return }
                root.pointer = Qt.point(m.x, m.y)
                if (!pressed || !overlay.selecting) return
                const dx = m.x - start.x, dy = m.y - start.y
                if (grab === "") {
                    overlay.dragging = true
                    root.selection = Qt.rect(Math.min(start.x, m.x), Math.min(start.y, m.y), Math.abs(dx), Math.abs(dy))
                } else if (grab === "move") {
                    root.selection = Qt.rect(Math.max(0, Math.min(width - from.width, from.x + dx)),
                                             Math.max(0, Math.min(height - from.height, from.y + dy)), from.width, from.height)
                } else {
                    let x0 = from.x, y0 = from.y, x1 = from.x + from.width, y1 = from.y + from.height
                    if (grab.includes("l")) x0 = Math.min(x1 - 8, from.x + dx)
                    if (grab.includes("r")) x1 = Math.max(x0 + 8, from.x + from.width + dx)
                    if (grab.includes("t")) y0 = Math.min(y1 - 8, from.y + dy)
                    if (grab.includes("b")) y1 = Math.max(y0 + 8, from.y + from.height + dy)
                    root.selection = Qt.rect(x0, y0, x1 - x0, y1 - y0)
                }
            }
            onPressed: (m) => {
                start = Qt.point(m.x, m.y)
                from = root.selection
                grab = ""
                if (root.mode === "toolbar" && overlay.selecting) {
                    const h = handles.at(m.x, m.y)
                    if (h) grab = h
                    else if (m.x > from.x && m.y > from.y && m.x < from.x + from.width && m.y < from.y + from.height) grab = "move"
                }
            }
            onReleased: (m) => {
                if (overlay.picking) {
                    const w = root.windowAt(m.x, m.y)
                    if (w) root.take(w.rect, false)
                    return
                }
                if (root.mode === "area" && overlay.dragging) {
                    overlay.dragging = false
                    if (root.selection.width > 4 && root.selection.height > 4) root.take(root.selection, false)
                }
            }
        }

        // The selection's edge and its eight handles.
        Item {
            id: handles
            visible: overlay.showSel
            x: overlay.sel.x; y: overlay.sel.y; width: overlay.sel.width; height: overlay.sel.height
            Rectangle { anchors.fill: parent; color: "transparent"; border { width: 1; color: "#e6ffffff" } }
            readonly property var spots: [["tl", 0, 0], ["t", 0.5, 0], ["tr", 1, 0], ["r", 1, 0.5], ["br", 1, 1], ["b", 0.5, 1], ["bl", 0, 1], ["l", 0, 0.5]]
            function at(px, py) {
                if (root.mode !== "toolbar") return ""
                for (const [n, fx, fy] of spots)
                    if (Math.abs(px - (x + width * fx)) <= 9 && Math.abs(py - (y + height * fy)) <= 9) return n
                return ""
            }
            Repeater {
                model: root.mode === "toolbar" ? handles.spots : []
                Rectangle {
                    required property var modelData
                    x: handles.width * modelData[1] - 5; y: handles.height * modelData[2] - 5
                    width: 10; height: 10; radius: 5
                    color: "#ffffff"
                    border { width: 0.5; color: "#59000000" }
                }
            }
            // Its size, under it, while it's drawn or changed.
            Rectangle {
                visible: chooser.pressed
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 8 }
                width: sizeLabel.implicitWidth + 16; height: 22; radius: 11
                color: "#b3000000"
                Text {
                    id: sizeLabel
                    anchors.centerIn: parent
                    text: Math.round(overlay.sel.width) + " × " + Math.round(overlay.sel.height)
                    color: "#ffffff"
                    font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium }
                }
            }
        }

        // ⇧⌘4's crosshair readout, before you drag.
        Text {
            visible: root.mode === "area" && !overlay.dragging
            x: root.pointer.x + 12; y: root.pointer.y + 12
            text: Math.round(root.pointer.x) + "\n" + Math.round(root.pointer.y)
            color: "#ffffff"
            style: Text.Outline; styleColor: "#80000000"
            font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium; features: { "tnum": 1 } }
        }

        // The timer's countdown.
        Glass {
            visible: root.countdown > 0
            anchors.centerIn: parent
            width: 120; height: 120; radius: 60
            role: "regular"
            Text {
                anchors.centerIn: parent
                text: root.countdown
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 56; weight: Font.Light }
            }
        }

        // ---------------------------------------------------- the toolbar
        Glass {
            id: bar
            visible: root.mode === "toolbar" && root.countdown === 0
            role: "regular"
            radius: 16
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 110 }
            width: tools.implicitWidth + 20
            height: 52
            // Pressing on the toolbar doesn't start a selection under it.
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

            component Choice: Rectangle {
                id: c
                property string value
                property string symbol
                property string tip
                width: 40; height: 36; radius: 9
                color: root.choice === value ? (Theme.dark ? "#33ffffff" : "#1f000000") : cHover.hovered ? (Theme.dark ? "#14ffffff" : "#0d000000") : "transparent"
                Symbol { anchors.centerIn: parent; name: c.symbol; size: 20; tone: "auto" }
                HoverHandler { id: cHover }
                TapHandler { onTapped: { root.choice = c.value; root.hovered = null } }
                Accessible.role: Accessible.RadioButton
                Accessible.name: c.tip
                Accessible.checked: root.choice === value
            }
            component Sep: Rectangle { width: 1; height: 24; color: Theme.separator }

            RowLayout {
                id: tools
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: closeHover.hovered ? (Theme.dark ? "#33ffffff" : "#1a000000") : "transparent"
                    Symbol { anchors.centerIn: parent; name: "xmark"; size: 12; tone: "auto" }
                    HoverHandler { id: closeHover }
                    TapHandler { onTapped: root.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Close"
                }
                Sep { Layout.leftMargin: 4; Layout.rightMargin: 4 }
                Choice { value: "screen"; symbol: "capture-screen"; tip: "Capture Entire Screen" }
                Choice { value: "window"; symbol: "window"; tip: "Capture Selected Window" }
                Choice { value: "selection"; symbol: "capture-selection"; tip: "Capture Selected Portion" }
                Sep { Layout.leftMargin: 4; Layout.rightMargin: 4 }
                Choice { value: "recordScreen"; symbol: "record-screen"; tip: "Record Entire Screen" }
                Choice { value: "recordSelection"; symbol: "record-selection"; tip: "Record Selected Portion" }
                Sep { Layout.leftMargin: 4; Layout.rightMargin: 4 }
                Rectangle {
                    id: optionsButton
                    implicitWidth: optionsRow.implicitWidth + 18; implicitHeight: 30; radius: 8
                    color: optionsMenu.open || optHover.hovered ? (Theme.dark ? "#1fffffff" : "#12000000") : "transparent"
                    Row {
                        id: optionsRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: "Options"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } anchors.verticalCenter: parent.verticalCenter }
                        Symbol { name: "chevron-down"; size: 10; tone: "auto"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    HoverHandler { id: optHover }
                    TapHandler { onTapped: optionsMenu.open = !optionsMenu.open }
                }
                Shared.Button {
                    Layout.leftMargin: 6
                    text: root.recordingChoice ? "Record" : "Capture"
                    enabled: root.choice !== "window" || !!root.hovered
                    onClicked: root.go()
                }
            }
        }

        MenuPopup {
            id: optionsMenu
            instant: true
            anchor.window: overlay
            anchor.rect.x: bar.x + optionsButton.x + 10
            anchor.rect.y: bar.y - menuHeight - 12
            items: [
                { header: "Save to" },
                { label: "Desktop", checked: root.saveTo === "desktop", action: () => root.setOption("saveTo", "desktop") },
                { label: "Documents", checked: root.saveTo === "documents", action: () => root.setOption("saveTo", "documents") },
                { label: "Pictures", checked: root.saveTo === "pictures", action: () => root.setOption("saveTo", "pictures") },
                { label: "Clipboard", checked: root.saveTo === "clipboard", action: () => root.setOption("saveTo", "clipboard") },
                "-",
                { header: "Timer" },
                { label: "None", checked: root.timer === 0, action: () => root.setOption("timer", 0) },
                { label: "5 Seconds", checked: root.timer === 5, action: () => root.setOption("timer", 5) },
                { label: "10 Seconds", checked: root.timer === 10, action: () => root.setOption("timer", 10) },
                "-",
                { header: "Options" },
                { label: "Show Floating Thumbnail", checked: root.showThumbnail, action: () => root.setOption("thumbnail", !root.showThumbnail) },
                { label: "Show Mouse Pointer", checked: root.showPointer, action: () => root.setOption("pointer", !root.showPointer) }
            ]
        }
    }
    property point pointer: Qt.point(0, 0)

    // ------------------------------------------------------------ the thumbnail
    PanelWindow {
        id: thumb
        screen: root.screen
        property string file: ""
        property bool video: false
        property bool shown: false
        function show(f, v) { file = f; video = v; shown = true; slide.x = 0; linger.restart() }
        function dismiss() { shown = false }
        visible: shown || card.opacity > 0.01
        anchors { right: true; bottom: true }
        margins { right: 16; bottom: 96 }
        implicitWidth: 220; implicitHeight: 150
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gg-screenshot-thumbnail"

        Timer { id: linger; interval: 5000; onTriggered: if (!cardHover.hovered) thumb.dismiss(); else restart() }

        Item {
            id: slide
            width: parent.width; height: parent.height
            Behavior on x { enabled: !swipe.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Rectangle {
                id: card
                anchors { fill: parent; margins: 6 }
                radius: 10
                color: Theme.dark ? "#2c2c2e" : "#ffffff"
                border { width: 3; color: "#ffffff" }
                opacity: thumb.shown ? 1 : 0
                scale: thumb.shown ? 1 : 0.92
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                clip: true
                Image {
                    anchors { fill: parent; margins: 3 }
                    visible: !thumb.video
                    source: thumb.file && !thumb.video ? Paths.fileUrl(thumb.file) : ""
                    sourceSize: Qt.size(420, 280)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }
                Column {
                    visible: thumb.video
                    anchors.centerIn: parent
                    spacing: 6
                    Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: "video"; size: 34; tone: "auto" }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Screen Recording"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                }
            }
            HoverHandler { id: cardHover }
            // Click: open it. Drag up or out: into another app. Swipe right: away.
            DragHandler {
                id: swipe
                xAxis.enabled: true; yAxis.enabled: false
                target: slide
                onActiveChanged: if (!active) { if (slide.x > 60) thumb.dismiss(); slide.x = 0 }
            }
            TapHandler { onTapped: { Quickshell.execDetached(["xdg-open", thumb.file]); thumb.dismiss() } }
            Item {
                id: dragOut
                Drag.active: dragOutArea.drag.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": Paths.fileUrl(thumb.file) + "\r\n" })
                Drag.onDragFinished: thumb.dismiss()
            }
            MouseArea {
                id: dragOutArea
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 40                     // the top edge: drag up and out to hand the file over
                drag.target: dragOut
            }
        }
    }
}
