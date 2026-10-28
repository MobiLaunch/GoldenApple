// Brief word at the foot of a window: "Copied", "Couldn't save — Try Again".
// Put one in the window and call show(); several in a row wait their turn.
//   Toast { id: toast; anchors.fill: parent }
//   toast.show("Link copied")
//   toast.show("The note couldn't be saved", { kind: "error", actionText: "Try Again", action: () => save() })
// It rises in and leaves after `timeout` (longer with an action, and never
// while the pointer is on it); with Reduce Motion it fades in place. Screen
// readers hear it as an alert. It never takes keyboard focus from the work.
import QtQuick
import "theme"

Item {
    id: host
    property var queue: []
    property var current: null
    readonly property bool showing: current !== null
    z: 900

    function show(text, options) {
        const t = Object.assign({ text: String(text), kind: "info", actionText: "", action: null, timeout: 0 }, options ?? {})
        if (!t.timeout) t.timeout = t.actionText ? 6000 : 3200
        queue = queue.concat([t])
        if (!current) next()
    }
    function next() {
        if (!queue.length) { current = null; return }
        current = queue[0]
        queue = queue.slice(1)
        life.interval = current.timeout
        life.restart()
    }
    function dismiss() {
        life.stop()
        leaving.restart()
    }
    Timer { id: life; running: false; onTriggered: if (!hover.hovered) host.dismiss(); else restart() }
    Timer { id: leaving; interval: Theme.motion.snappy.ms; onTriggered: host.next() }

    Rectangle {
        id: pill
        objectName: "toast"
        readonly property bool up: host.current !== null && !leaving.running
        anchors.horizontalCenter: parent.horizontalCenter
        y: host.height - height - 24 + (up || Theme.reduceMotion ? 0 : 16)
        width: Math.min(host.width - 32, row.implicitWidth + 32)
        height: Math.max(36, row.implicitHeight + 14)
        radius: height / 2
        color: Theme.windowBg
        border { width: 0.5; color: Theme.separator }
        opacity: up ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.snappy.ms; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.snappy.ms; easing.type: Easing.OutCubic } }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: host.current?.text ?? ""
        HoverHandler { id: hover }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10
            Symbol {
                visible: (host.current?.kind ?? "info") !== "info"
                anchors.verticalCenter: parent.verticalCenter
                name: host.current?.kind === "success" ? "checkmark" : "warning"
                color: host.current?.kind === "success" ? Theme.accentGreen : Theme.accentRed
                size: 14
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: host.current?.text ?? ""
                width: Math.min(implicitWidth, host.width - 140)
                elide: Text.ElideRight
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize; weight: Font.Medium }
            }
            Button {
                visible: !!host.current?.actionText
                anchors.verticalCenter: parent.verticalCenter
                text: host.current?.actionText ?? ""
                onClicked: { const a = host.current?.action; host.dismiss(); if (a) a() }
            }
        }
    }
}
