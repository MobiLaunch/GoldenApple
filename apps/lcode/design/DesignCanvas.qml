// The App Designer's canvas: the app's window, rendered live, in light, dark
// or both side by side. In Select mode a click selects what's under it (the
// outline and inspector follow), and things dropped from the Library land
// where the blue line shows; in Live mode the app simply works.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../design.js" as Design

Item {
    id: canvas
    property var doc: null
    property string screenId: ""
    property string selectedId: ""
    property string mode: "select"           // select | live
    property string appearance: "light"      // light | dark | both
    property string device: "window"         // window | compact | large
    property real zoom: 1
    property var runtime: null
    property string assetBase: ""
    signal selectRequested(string id)
    signal screenRequested(string id)
    signal contextMenuRequested(string id, real x, real y)
    signal dropRequested(var payload, string parentId, int index)
    signal editTextRequested(string id)

    readonly property var variants: appearance === "both" ? [false, true] : [appearance === "dark"]
    readonly property var size: {
        const a = doc ? doc.app : {}
        if (device === "compact") return { w: Math.max(a.minWidth || 0, 520), h: Math.max(a.minHeight || 0, 400) }
        if (device === "large") return { w: 1280, h: 800 }
        return { w: a.width || 900, h: a.height || 620 }
    }
    readonly property real gap: 60
    readonly property real stageWidth: variants.length * size.w + (variants.length - 1) * gap + 2 * 50
    readonly property real stageHeight: size.h + 40 + 2 * 40

    property string hoverId: ""
    property var dropLine: null
    property int tick: 0                       // overlay geometry refresh

    onVariantsChanged: Qt.callLater(fit)
    onSizeChanged: Qt.callLater(fit)
    function fit() {
        zoom = Math.max(0.25, Math.min(1, (view.width - 20) / stageWidth, (view.height - 20) / stageHeight))
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#161618" : "#ebebee"
    }
    // A faint dot grid, as on Xcode's canvas.
    Canvas {
        anchors.fill: parent
        opacity: 0.5
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = Theme.dark ? "#33ffffff" : "#26000000"
            for (let x = 10; x < width; x += 20) for (let y = 10; y < height; y += 20) ctx.fillRect(x, y, 1, 1)
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: Math.max(width, canvas.stageWidth * canvas.zoom)
        contentHeight: Math.max(height, canvas.stageHeight * canvas.zoom)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false                    // the wheel scrolls; drags select or drop

        Item {
            id: stage
            width: canvas.stageWidth
            height: canvas.stageHeight
            scale: canvas.zoom
            transformOrigin: Item.TopLeft
            x: Math.max(0, (view.width - canvas.stageWidth * canvas.zoom) / 2)
            y: Math.max(0, (view.height - canvas.stageHeight * canvas.zoom) / 2)

            Row {
                x: 50; y: 40
                spacing: canvas.gap
                Repeater {
                    id: frames
                    model: canvas.variants
                    delegate: Column {
                        required property bool modelData
                        readonly property alias frame: frame
                        spacing: 14
                        Text {
                            text: (canvas.doc ? (Design.screenById(canvas.doc, canvas.screenId) || {}).title || "" : "") + "  ·  " + (modelData ? "Dark" : "Light")
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                        }
                        Frame {
                            id: frame
                            doc: canvas.doc
                            screenId: canvas.screenId
                            dark: modelData
                            runtime: canvas.runtime
                            assetBase: canvas.assetBase
                            frameWidth: canvas.size.w
                            frameHeight: canvas.size.h
                            onScreenClicked: (id) => canvas.screenRequested(id)
                        }
                    }
                }
            }
        }

        // Selection, hover and drop marks, drawn unscaled over the stage.
        Item {
            id: overlay
            width: view.contentWidth
            height: view.contentHeight
            readonly property var rects: {
                canvas.tick
                const out = { selected: [], hover: [] }
                for (let i = 0; i < frames.count; i++) {
                    const col = frames.itemAt(i)
                    if (!col) continue
                    const r = col.frame.renderer
                    if (canvas.selectedId) { const s = r.rectOf(canvas.selectedId, overlay); if (s) out.selected.push(s) }
                    if (canvas.hoverId && canvas.hoverId !== canvas.selectedId) { const h = r.rectOf(canvas.hoverId, overlay); if (h) out.hover.push(h) }
                }
                return out
            }
            Repeater {
                model: canvas.mode === "select" ? overlay.rects.hover : []
                delegate: Rectangle {
                    required property var modelData
                    x: modelData.x - 1; y: modelData.y - 1; width: modelData.width + 2; height: modelData.height + 2
                    color: "transparent"
                    border { width: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) }
                }
            }
            Repeater {
                model: canvas.mode === "select" ? overlay.rects.selected : []
                delegate: Item {
                    required property var modelData
                    x: modelData.x - 2; y: modelData.y - 2; width: modelData.width + 4; height: modelData.height + 4
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border { width: 2; color: Theme.accent }
                    }
                    Repeater {
                        model: [[0, 0], [1, 0], [0, 1], [1, 1]]
                        delegate: Rectangle {
                            required property var modelData
                            width: 7; height: 7; radius: 3.5
                            x: modelData[0] * parent.width - 3.5
                            y: modelData[1] * parent.height - 3.5
                            color: "white"
                            border { width: 1.5; color: Theme.accent }
                        }
                    }
                }
            }
            Rectangle {
                visible: !!canvas.dropLine
                x: canvas.dropLine ? canvas.dropLine.x : 0
                y: canvas.dropLine ? canvas.dropLine.y : 0
                width: canvas.dropLine ? Math.max(2, canvas.dropLine.w) : 0
                height: canvas.dropLine ? Math.max(2, canvas.dropLine.h) : 0
                radius: 1
                color: Theme.accent
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                enabled: canvas.mode === "select"
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                function nodeAt(m) {
                    for (let i = 0; i < frames.count; i++) {
                        const col = frames.itemAt(i)
                        if (!col) continue
                        const p = pointer.mapToItem(col.frame, m.x, m.y)
                        if (p.x < 0 || p.y < 0 || p.x > col.frame.width || p.y > col.frame.height) continue
                        // The sidebar's rows pick screens, as in the app.
                        if (col.frame.sidebar && p.x < col.frame.inset + col.frame.sidebarWidth) return { sidebar: col.frame, x: p.x, y: p.y }
                        return { id: col.frame.renderer.nodeAt(pointer, m.x, m.y) }
                    }
                    return { id: "" }
                }
                onPositionChanged: (m) => { const hit = nodeAt(m); canvas.hoverId = hit.id || "" }
                onExited: canvas.hoverId = ""
                onClicked: (m) => {
                    const hit = nodeAt(m)
                    if (hit.sidebar) {
                        // Map the click to a sidebar row: rows start at 52 and are 30 apart.
                        const row = Math.floor((hit.y - 52 - hit.sidebar.inset) / 30)
                        const s = canvas.doc && canvas.doc.screens[row]
                        if (s) canvas.screenRequested(s.id)
                        return
                    }
                    if (m.button === Qt.RightButton) {
                        if (hit.id) canvas.selectRequested(hit.id)
                        canvas.contextMenuRequested(hit.id || "", m.x, m.y)
                        return
                    }
                    canvas.selectRequested(hit.id || "")
                }
                onDoubleClicked: (m) => { const hit = nodeAt(m); if (hit.id) canvas.editTextRequested(hit.id) }
                onWheel: (w) => {
                    if (w.modifiers & Qt.ControlModifier) {
                        canvas.zoom = Math.max(0.25, Math.min(3, canvas.zoom * (w.angleDelta.y > 0 ? 1.1 : 1 / 1.1)))
                        return
                    }
                    view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY - w.angleDelta.y))
                    view.contentX = Math.max(0, Math.min(view.contentWidth - view.width, view.contentX - w.angleDelta.x))
                }
            }
        }
    }

    // Library items (and moved items) dropped on the canvas.
    DropArea {
        anchors.fill: parent
        keys: ["lcode/component"]
        function target(d) {
            const p = canvas.mapToItem(pointer, d.x, d.y)
            for (let i = 0; i < frames.count; i++) {
                const col = frames.itemAt(i)
                if (!col) continue
                const q = pointer.mapToItem(col.frame, p.x, p.y)
                if (q.x < 0 || q.y < 0 || q.x > col.frame.width || q.y > col.frame.height) continue
                const payload = d.source && d.source.payload ? d.source.payload : null
                return col.frame.renderer.dropTarget(pointer, p.x, p.y, overlay, payload && payload.move ? payload.move : "")
            }
            return null
        }
        onPositionChanged: (d) => { const t = target(d); canvas.dropLine = t ? t.line : null }
        onExited: canvas.dropLine = null
        onDropped: (d) => {
            const t = target(d)
            canvas.dropLine = null
            if (t && d.source && d.source.payload) canvas.dropRequested(d.source.payload, t.parent, t.index)
        }
    }

    Timer {
        interval: 90
        repeat: true
        running: canvas.visible && canvas.mode === "select"
        onTriggered: canvas.tick++
    }
}
