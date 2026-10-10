// Text that opens a web address.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string title: "Learn More"
    property string url: "https://"
    tappable: true
    contentWidth: label.implicitWidth
    contentHeight: label.implicitHeight
    Text {
        id: label
        text: root.title
        color: root.foreground ? root.foregroundColor : root.c("accent")
        font { family: Theme.fontUi; pixelSize: 13; underline: linkHover.hovered }
    }
    HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
}
