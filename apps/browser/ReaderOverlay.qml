import QtQuick
import "../lib"
import "../lib/theme"

Rectangle {
    id: root
    property string articleTitle: ""
    property string articleText: ""
    signal closed()
    color: Theme.dark ? "#20201f" : "#fbfaf7"

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: article.implicitHeight + 160
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: article
            width: Math.min(760, parent.width - 90)
            anchors.horizontalCenter: parent.horizontalCenter
            y: 70
            spacing: 22

            Text {
                width: parent.width
                text: root.articleTitle
                wrapMode: Text.WordWrap
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 34; weight: Font.DemiBold; letterSpacing: -0.6 }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.separator }
            Text {
                width: parent.width
                text: root.articleText
                wrapMode: Text.WordWrap
                color: Theme.label
                lineHeight: 1.55
                font { family: Theme.fontUi; pixelSize: 17 }
            }
        }
    }

    BrowserButton {
        anchors { top: parent.top; right: parent.right; margins: 18 }
        symbol: "xmark"; tooltip: "Close Reader"
        onClicked: root.closed()
    }
}
