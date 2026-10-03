// A line of text the user types, rounded, plain or a search field.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string value: ""
    property string placeholder: "Text"
    property string fieldStyle: "rounded"     // rounded | plain | search
    property bool secure: false
    signal edited(string value)
    signal submitted()
    contentWidth: 200
    contentHeight: 30

    Rectangle {
        anchors.fill: parent
        visible: root.fieldStyle !== "plain"
        radius: root.fieldStyle === "search" ? height / 2 : 8
        color: root.dark ? "#1affffff" : "#ffffff"
        border { width: input.activeFocus ? 2 : 0.5; color: input.activeFocus ? K.alpha(String(root.c("accent")), 0.6) : (root.dark ? "#33ffffff" : "#2e000000") }
    }
    Text {
        visible: root.fieldStyle === "search"
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: root.c("secondaryLabel")
        font.pixelSize: 15
    }
    TextInput {
        id: input
        x: root.fieldStyle === "search" ? 28 : root.fieldStyle === "plain" ? 0 : 10
        width: parent.width - x - 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        echoMode: root.secure ? TextInput.Password : TextInput.Normal
        color: root.foregroundColor
        selectionColor: K.alpha(String(root.c("accent")), 0.35)
        selectedTextColor: root.foregroundColor
        clip: true
        font { family: Theme.fontUi; pixelSize: 13 }
        // The app's variable follows through `edited`; assigning value here would
        // cut it loose from that variable.
        onTextEdited: root.edited(text)
        onAccepted: root.submitted()
        Text {
            visible: !input.text
            text: root.placeholder
            color: root.c("tertiaryLabel")
            font: input.font
        }
    }
}
