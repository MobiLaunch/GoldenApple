// Shared multiline editor for CitronOS applications.
// Inherits TextEdit so specialized editors keep the full cursor/Markdown API.
import QtQuick
import QtQuick.Window
import "theme"

TextEdit {
    id: area

    property string placeholder: ""
    property bool writingToolsEnabled: true
    property string writingContext: ""
    function openWritingTools() {
        if (!writingToolsEnabled || readOnly || length === 0) return
        if (writingLoader.item) writingLoader.item.open()
        else writingLoader.active = true
    }

    Shortcut {
        sequence: "Ctrl+Shift+W"
        enabled: area.activeFocus && area.writingToolsEnabled && !area.readOnly
        onActivated: area.openWritingTools()
    }
    Loader {
        id: writingLoader
        z: 2000
        active: false
        parent: area.Window.window ? area.Window.window.contentItem : area
        anchors.fill: parent
        source: "intelligence/WritingTools.qml"
        onLoaded: { item.editor = area; item.open() }
    }
    PopupMenu {
        id: contextMenu
        parent: area.Window.window ? area.Window.window.contentItem : area
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => contextMenu.popup(area, point.position.x, point.position.y, [
            { text: "Cut", enabled: !area.readOnly && !!area.selectedText, action: () => area.cut() },
            { text: "Copy", enabled: !!area.selectedText, action: () => area.copy() },
            { text: "Paste", enabled: !area.readOnly && area.canPaste, action: () => area.paste() },
            { text: "Select All", enabled: area.length > 0, action: () => area.selectAll() },
            { separator: true },
            { text: "Writing Tools…", enabled: area.writingToolsEnabled && !area.readOnly && area.length > 0,
              action: () => area.openWritingTools() }
        ])
    }

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
