// Content taller (or wider) than its space, scrolled.
import QtQuick

Box {
    id: scroll
    property bool horizontal: false
    property bool showsIndicators: true
    default property alias items: holder.data
    readonly property Item contentContainer: holder   // where the App Designer adds children
    frameWidth: "fill"
    frameHeight: "fill"
    contentWidth: holder.implicitWidth
    contentHeight: Math.min(holder.implicitHeight, 240)
    clipContent: true

    Flickable {
        id: view
        anchors.fill: parent
        contentWidth: scroll.horizontal ? Math.max(width, holder.implicitWidth) : width
        contentHeight: scroll.horizontal ? height : Math.max(height, holder.implicitHeight)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: scroll.horizontal ? Flickable.HorizontalFlick : Flickable.VerticalFlick
        clip: true
        Item {
            id: holder
            readonly property string kitAxis: scroll.horizontal ? "hscroll" : "scroll"
            readonly property string kitAlign: "center"
            readonly property var kenv: scroll.kenv
            width: view.contentWidth
            height: view.contentHeight
            implicitWidth: { let m = 0; for (const c of children) m = Math.max(m, c.implicitWidth); return m }
            implicitHeight: { let m = 0; for (const c of children) m = Math.max(m, c.implicitHeight); return m }
        }
    }
    Rectangle {
        visible: scroll.showsIndicators && !scroll.horizontal && view.contentHeight > view.height + 1
        x: parent.width - 6; width: 3; radius: 1.5
        y: view.visibleArea.yPosition * view.height
        height: Math.max(24, view.visibleArea.heightRatio * view.height)
        color: scroll.dark ? "#55ffffff" : "#44000000"
        opacity: view.moving ? 1 : 0.5
    }
}
