// Rows from a list: each item a title (and subtitle, symbol, done mark).
// Rows can be ticked off and deleted, like a to-do list.
import QtQuick
import "kit.js" as K
import "../theme"
import ".." as Lib

Box {
    id: root
    property var items: ["First item", "Second item", "Third item"]
    property string listStyle: "inset"        // inset | plain
    property bool checkable: false
    property bool deletable: false
    property string rowSymbol: ""
    property string emptyText: "No Items"
    signal itemTapped(int index, var item)
    signal itemToggled(int index, bool done)
    signal itemDeleted(int index)
    frameWidth: "fill"
    contentWidth: 280
    contentHeight: column.implicitHeight

    function titleOf(item) { return item !== null && typeof item === "object" ? K.str(item.title !== undefined ? item.title : item.text) : K.str(item) }
    function subtitleOf(item) { return item !== null && typeof item === "object" && item.subtitle ? K.str(item.subtitle) : "" }
    function doneOf(item) { return item !== null && typeof item === "object" && !!item.done }

    Rectangle {
        anchors.fill: parent
        visible: root.listStyle === "inset"
        radius: 12
        color: root.c("tertiaryBackground")
        border { width: root.dark ? 0 : 0.5; color: "#14000000" }
    }
    Column {
        id: column
        width: parent.width
        Text {
            visible: !root.items || root.items.length === 0
            width: parent.width
            height: 44
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.emptyText
            color: root.c("tertiaryLabel")
            font { family: Theme.fontUi; pixelSize: 13 }
        }
        Repeater {
            model: root.items || []
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: column.width
                height: root.subtitleOf(modelData) ? 52 : 40
                readonly property bool done: root.doneOf(modelData)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.listStyle === "inset" ? 4 : 0
                    radius: 8
                    color: rowHover.hovered ? (root.dark ? "#0fffffff" : "#08000000") : "transparent"
                }
                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        visible: root.checkable
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20; radius: 10
                        color: row.done ? root.c("accent") : "transparent"
                        border { width: row.done ? 0 : 1.5; color: root.c("tertiaryLabel") }
                        Text { anchors.centerIn: parent; visible: row.done; text: "✓"; color: "white"; font { pixelSize: 11; weight: Font.Bold } }
                        TapHandler { onTapped: root.itemToggled(row.index, !row.done) }
                    }
                    Lib.Symbol {
                        visible: !!(root.rowSymbol || (row.modelData && row.modelData.symbol))
                        anchors.verticalCenter: parent.verticalCenter
                        name: (row.modelData && row.modelData.symbol) || root.rowSymbol
                        size: 17
                        tone: "accent"
                        color: root.c("accent")
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            width: row.width - 120
                            elide: Text.ElideRight
                            text: root.titleOf(row.modelData)
                            color: row.done ? root.c("secondaryLabel") : root.foregroundColor
                            font { family: K.fontFamily("", root.kenv, Theme.fontUi); pixelSize: 13; strikeout: row.done }
                        }
                        Text {
                            visible: !!text
                            text: root.subtitleOf(row.modelData)
                            color: root.c("secondaryLabel")
                            font { family: Theme.fontUi; pixelSize: 11 }
                        }
                    }
                }
                Text {
                    visible: root.deletable && rowHover.hovered
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Delete"
                    color: root.c("red")
                    font { family: Theme.fontUi; pixelSize: 12 }
                    TapHandler { onTapped: root.itemDeleted(row.index) }
                }
                Rectangle {
                    visible: row.index < (root.items || []).length - 1
                    x: root.checkable ? 44 : 14
                    anchors.bottom: parent.bottom
                    width: parent.width - x
                    height: 1
                    color: root.c("separator")
                }
                HoverHandler { id: rowHover }
                TapHandler { onTapped: root.itemTapped(row.index, row.modelData) }
            }
        }
    }
}
