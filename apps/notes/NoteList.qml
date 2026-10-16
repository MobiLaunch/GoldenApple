// The notes of a folder, grouped by when they were last edited (Today,
// Yesterday, Previous 7 Days, Previous 30 Days, then by month), with the
// selected note in Notes' yellow.
import QtQuick
import "../lib"
import "../lib/theme"

ListView {
    id: list
    Scroller { parent: list; flickable: list }
    property var notes: []
    property string current: ""
    property bool showFolder: false
    signal picked(string path)
    signal menu(string path, Item item, real x, real y)

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    bottomMargin: 12
    focus: true

    function group(mtime) {
        const d = new Date(mtime * 1000), now = new Date()
        const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
        const diff = Math.round((day(now) - day(d)) / 86400000)
        if (diff <= 0) return "Today"
        if (diff === 1) return "Yesterday"
        if (diff < 7) return "Previous 7 Days"
        if (diff < 30) return "Previous 30 Days"
        return d.getFullYear() === now.getFullYear() ? d.toLocaleDateString(Qt.locale(), "MMMM") : String(d.getFullYear())
    }
    function when(mtime) {
        const d = new Date(mtime * 1000), g = group(mtime)
        if (g === "Today") return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
        if (g === "Yesterday") return "Yesterday"
        if (g === "Previous 7 Days") return d.toLocaleDateString(Qt.locale(), "dddd")
        return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    model: notes
    delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property string group: list.group(modelData.mtime)
        readonly property bool firstOfGroup: index === 0 || list.group(list.notes[index - 1].mtime) !== group
        readonly property bool selected: modelData.path === list.current
        width: list.width
        height: (firstOfGroup ? 44 : 0) + 58

        Text {
            visible: row.firstOfGroup
            x: 18; y: row.index === 0 ? 12 : 18
            text: row.group
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.Bold }
        }
        Rectangle {
            visible: row.firstOfGroup
            x: 10; y: 43; width: parent.width - 20; height: 0.5
            color: Theme.separator
        }
        Rectangle {
            id: card
            x: 10; y: row.firstOfGroup ? 48 : 2
            width: parent.width - 20; height: 54
            radius: 8
            color: row.selected ? (list.activeFocus ? (Theme.dark ? "#8a6d1f" : "#fde58f") : Theme.selection) : "transparent"
            Rectangle {
                visible: !row.selected && row.index + 1 < list.notes.length && list.group(list.notes[row.index + 1].mtime) === row.group
                  && list.notes[row.index + 1].path !== list.current
                x: 12; width: parent.width - 24; height: 0.5
                anchors.top: parent.bottom; anchors.topMargin: 1
                color: Theme.separator
            }
            Column {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24
                spacing: 1
                Text {
                    width: parent.width; elide: Text.ElideRight
                    text: row.modelData.title
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                }
                Row {
                    width: parent.width
                    spacing: 6
                    Text {
                        id: whenText
                        text: list.when(row.modelData.mtime)
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        width: parent.width - whenText.width - 6; elide: Text.ElideRight
                        text: row.modelData.preview || "No additional text"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                }
                Row {
                    visible: list.showFolder
                    spacing: 4
                    Symbol { anchors.verticalCenter: parent.verticalCenter; name: "folder"; tone: "gray"; size: 11 }
                    Text {
                        text: row.modelData.folder
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                }
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (p, button) => {
                    list.forceActiveFocus()
                    if (button === Qt.RightButton) list.menu(row.modelData.path, card, p.position.x, p.position.y)
                    else list.picked(row.modelData.path)
                }
            }
        }
    }
    Keys.onUpPressed: { const i = notes.findIndex((n) => n.path === current); if (i > 0) picked(notes[i - 1].path) }
    Keys.onDownPressed: { const i = notes.findIndex((n) => n.path === current); if (i + 1 < notes.length) picked(notes[i + 1].path) }
}
