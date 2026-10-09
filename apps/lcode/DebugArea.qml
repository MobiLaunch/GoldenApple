// The debug area under the editor: the console with the running program's
// output (and test output), and a field that types into its standard input.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: debug
    property var app
    property var backend
    // Measure drag movement in a stationary coordinate system.
    property Item resizeCoordinateSpace: null
    signal hideRequested()
    signal resizeBy(real dy)

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#1f1f24" : "#ffffff"
    }

    // Drag the top edge to resize.
    Rectangle {
        width: parent.width
        height: 1
        color: Theme.separator
    }
    MouseArea {
        width: parent.width
        height: 6
        y: -3
        cursorShape: Qt.SizeVerCursor
        property real startY
        function pointerY(m) {
            return mapToItem(debug.resizeCoordinateSpace || debug, m.x, m.y).y
        }
        onPressed: (m) => startY = pointerY(m)
        onPositionChanged: (m) => {
            if (!pressed) return
            const next = pointerY(m)
            const delta = next - startY
            if (Math.abs(delta) < 0.5) return
            startY = next
            debug.resizeBy(delta)
        }
    }

    Item {
        id: bar
        width: parent.width
        height: 30
        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            ToolbarButton {
                symbol: "panel-bottom"
                symbolSize: 15
                Accessible.name: "Hide the Debug Area (⇧⌘Y)"
                onClicked: debug.hideRequested()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: debug.app.appRunning ? "Console — " + debug.app.schemeName + " on " + debug.app.destinationName : "Console"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
            }
        }
        ToolbarButton {
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            symbol: "trash"
            symbolSize: 15
            Accessible.name: "Clear Console (⌘K)"
            onClicked: debug.app.consoleText = ""
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
    }

    Flickable {
        id: scroller
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: input.top }
        clip: true
        contentWidth: width
        contentHeight: output.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        acceptedButtons: Qt.NoButton
        property bool follow: true
        onContentYChanged: follow = contentY + height >= contentHeight - 8
        TextArea {
            id: output
            x: 10; y: 6
            width: scroller.width - 20
            readOnly: true
            wrapMode: TextEdit.WrapAnywhere
            text: debug.app.consoleText
            color: Theme.label
            font { family: "monospace"; pixelSize: Theme.fs(12) }
            onTextChanged: if (scroller.follow) Qt.callLater(() => scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height))
        }
    }

    TextField {
        id: input
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 6 }
        height: 28
        enabled: debug.app.appRunning
        placeholder: debug.app.appRunning ? "Type input for " + debug.app.schemeName + " and press Return" : "Console input is available while a program runs"
        onAccepted: {
            debug.backend.call("stdin", { text: text + "\n" })
            debug.app.appendConsole(text + "\n")
            text = ""
        }
    }
}
