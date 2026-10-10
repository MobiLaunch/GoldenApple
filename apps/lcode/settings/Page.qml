// A settings page: scrolls when it's taller than the window.
import QtQuick
import "../../lib"

Flickable {
    id: page
    Scroller { parent: page; flickable: page }
    property var app
    property var backend
    property Item overlay: null
    default property alias content: column.data
    clip: true
    contentWidth: width
    contentHeight: column.height + 48
    boundsBehavior: Flickable.StopAtBounds
    Column {
        id: column
        x: 32; y: 24
        width: page.width - 64
        spacing: 12
    }
}
