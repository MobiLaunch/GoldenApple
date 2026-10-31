// A list beside its detail, inside a window's content (Mail's mailboxes and
// messages, Passwords' accounts): the sidebar on the left, the detail filling
// the rest.
//   NavigationSplitView {
//       sidebar: [ ListView { … } ]
//       Item { … the detail … }
//   }
// The sidebar can be hidden and shown (toggle(), ⌃⌘S); below `collapseWidth`
// it hides itself and, shown again, slides over the detail rather than
// squeezing it, as on an iPad (`overlaid`); a click on the detail or Escape
// puts it away again. It slides on the snappy curve; with Reduce Motion it
// appears in place.
import QtQuick
import "theme"

Item {
    id: split
    property real sidebarWidth: 240
    property real minimumDetailWidth: 360
    property real collapseWidth: sidebarWidth + minimumDetailWidth
    property bool sidebarShown: true
    property string sidebarTitle: "Sidebar"
    property alias sidebar: sidebarArea.data
    default property alias detail: detailArea.data
    readonly property bool compact: width > 0 && width < collapseWidth   // 0: not laid out yet
    readonly property bool overlaid: compact && sidebarShown
    readonly property real presented: sidebarShown ? sidebarWidth : 0

    // What you chose with room to spare, given back when there's room again.
    property bool wideChoice: true
    function toggle() {
        sidebarShown = !sidebarShown
        if (!compact) wideChoice = sidebarShown
    }
    onCompactChanged: sidebarShown = compact ? false : wideChoice

    Shortcut {
        sequence: "Ctrl+Meta+S"
        enabled: split.visible
        onActivated: split.toggle()
    }

    property real shownWidth: presented
    // Laid out as it is to begin with; it moves only when it changes after.
    property bool settled: false
    Component.onCompleted: Qt.callLater(() => settled = true)
    Behavior on shownWidth { enabled: split.settled && !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.snappy.ms; easing.type: Easing.OutCubic } }

    Item {
        id: detailArea
        objectName: "splitDetail"
        x: split.compact ? 0 : split.shownWidth
        width: split.width - x
        height: split.height
        Accessible.role: Accessible.Pane
        Accessible.name: "Detail"
    }
    // Over the detail while the sidebar slides over it: a click puts it away.
    MouseArea {
        anchors.fill: detailArea
        enabled: split.overlaid
        visible: enabled
        Accessible.ignored: true
        onClicked: split.sidebarShown = false
    }
    Rectangle {
        id: sidebarPanel
        objectName: "splitSidebar"
        width: split.sidebarWidth
        height: split.height
        x: split.shownWidth - width
        visible: x > -width
        color: split.compact ? Theme.windowBg : "transparent"
        clip: true
        Accessible.role: Accessible.Pane
        Accessible.name: split.sidebarTitle
        Keys.onEscapePressed: (event) => { if (split.overlaid) split.sidebarShown = false; else event.accepted = false }
        Item { id: sidebarArea; anchors.fill: parent }
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 0.5
            color: Theme.separator
        }
    }
}
