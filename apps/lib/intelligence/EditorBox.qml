import QtQuick
import ".." as Shared
import "../theme"

Rectangle {
    id: box
    property alias text: editor.text
    property alias editor: editor
    property alias placeholder: editor.placeholder
    property alias readOnly: editor.readOnly
    color: Theme.dark ? "#18181b" : "#ffffff"
    radius: 14
    border { width: 1; color: editor.activeFocus ? Theme.accent : Theme.separator }
    Flickable {
        id: scroll
        anchors { fill: parent; margins: 14 }
        contentWidth: width
        contentHeight: Math.max(height, editor.contentHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Shared.TextArea {
            id: editor
            width: scroll.width
            height: Math.max(scroll.height, contentHeight)
            textFormat: TextEdit.PlainText
            writingToolsEnabled: false
            onCursorRectangleChanged: {
                if (!activeFocus) return
                if (cursorRectangle.y < scroll.contentY) scroll.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > scroll.contentY + scroll.height)
                    scroll.contentY = cursorRectangle.y + cursorRectangle.height - scroll.height
            }
        }
    }
}
