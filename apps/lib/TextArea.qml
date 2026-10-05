// Shared multiline editor for CitronOS applications.
// Inherits TextEdit so specialized editors keep the full cursor/Markdown API.
import QtQuick
import "theme"

TextEdit {
    id: area

    property string placeholder: ""

    activeFocusOnTab: true
    selectByMouse: true
    persistentSelection: true
    wrapMode: TextEdit.Wrap
    color: Theme.label
    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
    selectedTextColor: Theme.label
    font {
        family: Theme.fontUi
        pixelSize: Theme.textBody
    }

    Accessible.role: Accessible.EditableText
    Accessible.name: placeholder

    Text {
        visible: area.placeholder.length > 0 && area.length === 0
        anchors { left: parent.left; right: parent.right; top: parent.top }
        text: area.placeholder
        color: Theme.tertiaryLabel
        font: area.font
        wrapMode: Text.Wrap
        opacity: area.activeFocus ? 0.72 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 100 } }
    }
}
