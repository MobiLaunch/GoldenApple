// A settings pane: a scrolling column of groups under the toolbar, with the
// pane's own header (big icon, title, description) where it has one.
import QtQuick
import "../lib"
import "../lib/theme"

Flickable {
    id: pane
    Scroller { parent: pane; flickable: pane }
    property var sys
    property var nav                 // push(sub-page), window overlay for menus
    property string headerSymbol
    property color headerTint: "#8e8e93"
    property string headerTitle
    property string headerText
    default property alias content: col.data
    contentHeight: col.height + 40
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    topMargin: 8

    Column {
        id: col
        x: 20; width: pane.width - 40
        spacing: 18
        // Header, as in Wi-Fi or Battery: icon, title and a line about it.
        Column {
            visible: !!pane.headerTitle
            width: parent.width
            spacing: 6
            PaneIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                symbol: pane.headerSymbol; tint: pane.headerTint; size: 56
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pane.headerTitle
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                visible: !!pane.headerText
                text: pane.headerText
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
        }
    }
}
