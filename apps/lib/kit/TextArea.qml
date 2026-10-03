// Several lines of text the user types.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string value: ""
    property string placeholder: "Type here…"
    signal edited(string value)
    contentWidth: 260
    contentHeight: 110

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.dark ? "#1affffff" : "#ffffff"
        border { width: area.activeFocus ? 2 : 0.5; color: area.activeFocus ? K.alpha(String(root.c("accent")), 0.6) : (root.dark ? "#33ffffff" : "#2e000000") }
    }
    Flickable {
        id: flick
        anchors { fill: parent; margins: 8 }
        contentHeight: area.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TextEdit {
            id: area
            width: flick.width
            text: root.value
            wrapMode: TextEdit.Wrap
            color: root.foregroundColor
            selectionColor: K.alpha(String(root.c("accent")), 0.35)
            font { family: Theme.fontUi; pixelSize: 13 }
            onTextChanged: if (text !== root.value) root.edited(text)
            Text {
                visible: !area.text
                text: root.placeholder
                color: root.c("tertiaryLabel")
                font: area.font
            }
        }
    }
}
