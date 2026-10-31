// An alert, as the Mac lays one out: the app's icon, a bold title, the
// message, and the buttons along the bottom, right to left: the default
// (Return), Cancel (Escape), then the others. A destructive choice is red and
// never the default: with one, Return means Cancel (Apple's guidance), so a
// stray keypress can't erase anything. Built on ModalSheet: it dims the
// window, holds focus, and gives it back to what opened it.
//   Alert {
//       id: alert
//       title: "Delete “Ferry tickets”?"
//       message: "This can't be undone."
//       buttons: [{ text: "Delete", role: "destructive" }, { text: "Cancel", role: "cancel" }]
//       onChosen: (role, index) => if (role === "destructive") remove()
//   }
//   alert.open()
import QtQuick
import "theme"

ModalSheet {
    id: alert
    property string title
    property string message
    property string symbol: "warning"
    // [{ text, role: "default" | "cancel" | "destructive" | "other" }]
    property var buttons: [{ text: "OK", role: "default" }]
    signal chosen(string role, int index)
    panelWidth: 380
    dismissible: buttons.some((b) => b.role === "cancel")

    // Right to left (the Row below runs that way): default, cancel, the rest.
    readonly property var ordered: {
        const rank = (b) => b.role === "default" ? 0 : b.role === "cancel" ? 1 : 2
        return buttons.map((b, i) => Object.assign({ index: i }, b)).sort((a, b) => rank(a) - rank(b) || a.index - b.index)
    }
    readonly property int defaultIndex: {
        const d = buttons.findIndex((b) => b.role === "default")
        if (d >= 0) return d
        if (buttons.some((b) => b.role === "destructive")) return buttons.findIndex((b) => b.role === "cancel")
        return buttons.length === 1 ? 0 : -1
    }
    readonly property int cancelIndex: buttons.findIndex((b) => b.role === "cancel")
    property bool choosing: false
    function choose(index) {
        const b = buttons[index]
        if (!b) return
        choosing = true
        close()
        choosing = false
        chosen(b.role ?? "other", index)
    }
    // Clicked away (only possible with a Cancel button): that's Cancel.
    onClosed: if (!choosing && cancelIndex >= 0) chosen("cancel", cancelIndex)

    Item {
        id: keys
        objectName: "alertKeys"
        focus: true
        width: parent.width
        height: column.height
        Keys.onReturnPressed: if (alert.defaultIndex >= 0) alert.choose(alert.defaultIndex)
        Keys.onEnterPressed: if (alert.defaultIndex >= 0) alert.choose(alert.defaultIndex)
        Keys.onEscapePressed: if (alert.cancelIndex >= 0) alert.choose(alert.cancelIndex)
        Column {
            id: column
            width: parent.width
            spacing: 10
            Accessible.role: Accessible.AlertMessage
            Accessible.name: alert.title
            Accessible.description: alert.message
            Symbol { name: alert.symbol; size: 40; tone: "auto"; visible: !!alert.symbol }
            Text {
                width: parent.width
                text: alert.title
                wrapMode: Text.Wrap
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.font.headline.pixelSize; weight: Font.Bold }
            }
            Text {
                width: parent.width
                visible: !!alert.message
                text: alert.message
                wrapMode: Text.Wrap
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
            }
            Item { width: 1; height: 6 }
            Row {
                objectName: "alertButtons"
                anchors.right: parent.right
                layoutDirection: Qt.RightToLeft
                spacing: 8
                Repeater {
                    model: alert.ordered
                    Button {
                        required property var modelData
                        objectName: "alertButton-" + (modelData.role ?? "other")
                        text: modelData.text
                        prominent: modelData.index === alert.defaultIndex
                        destructive: modelData.role === "destructive"
                        onClicked: alert.choose(modelData.index)
                    }
                }
            }
        }
    }
    onShownChanged: if (shown) Qt.callLater(() => keys.forceActiveFocus())
}
