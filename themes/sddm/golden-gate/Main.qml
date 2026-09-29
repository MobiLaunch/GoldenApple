// SDDM (Qt 6) greeter: the same LockSurface the shell's lock screen uses, plus
// user picking and power buttons. scripts/install.sh copies shell/components and
// shell/theme next to this file.
import QtQuick
import QtQuick.Layouts
import "components"
import "theme"

Item {
    id: root
    // SDDM resizes the root object to each greeter view. Keep design-time size
    // as an implicit hint so non-1080p and multi-monitor greeters are not pinned
    // to a 1920×1080 scene.
    implicitWidth: 1920; implicitHeight: 1080
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    // SDDM exposes userModel as QAbstractListModel; role numbers are not part of
    // its theme API. Read documented name/realName roles from the delegate.
    readonly property string userLogin: users.currentItem?.loginName || userModel.lastUser || ""
    readonly property string userDisplay: users.currentItem?.displayName || userLogin

    LockSurface {
        id: surface
        anchors.fill: parent
        wallpaper: config.background ? "file://" + config.background : ""
        userName: root.userDisplay || "Golden User"
        onSubmitted: (password) => sddm.login(root.userLogin, password, root.sessionIndex)
        Component.onCompleted: reset()
    }
    Connections {
        target: sddm
        function onLoginFailed() { surface.fail() }
    }

    // Power buttons, bottom right.
    // Children of Glass land in its content item, so refer to the button by id.
    component PowerButton: Glass {
        id: pb
        property string icon
        property string label
        signal activated()
        width: 44; height: 44; radius: 22
        tint: "#33ffffff"
        Symbol { anchors.centerIn: parent; name: pb.icon; size: 18 }
        MouseArea { anchors.fill: parent; onClicked: pb.activated() }
        Text { anchors { top: parent.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter } text: pb.label; color: "#d0ffffff"; font { family: Theme.fontUi; pixelSize: 11 } }
    }
    Row {
        anchors { right: parent.right; bottom: parent.bottom; margins: 36 }
        spacing: 22
        PowerButton { icon: "moon"; label: "Sleep"; visible: sddm.canSuspend; onActivated: sddm.suspend() }
        PowerButton { icon: "arrow-clockwise"; label: "Restart"; visible: sddm.canReboot; onActivated: sddm.reboot() }
        PowerButton { icon: "power"; label: "Shut Down"; visible: sddm.canPowerOff; onActivated: sddm.powerOff() }
    }

    // Other users: small avatars bottom-left when there is more than one.
    // A ListView gives us SDDM's documented model roles without hard-coding the
    // private integer role ids, and remains usable when many accounts exist.
    ListView {
        id: users
        visible: userModel.count > 1
        anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
        width: Math.min(Math.max(40, userModel.count * 52 - 12), root.width - 72)
        height: 40
        spacing: 12
        orientation: ListView.Horizontal
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: userModel
        currentIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
        delegate: Rectangle {
            required property int index
            required property string name
            required property string realName
            readonly property string loginName: name
            readonly property string displayName: realName || name
            width: 40; height: 40; radius: 20
            color: index === users.currentIndex ? "#66ffffff" : "#26ffffff"
            border.width: 1; border.color: "#59ffffff"
            Text { anchors.centerIn: parent; text: parent.displayName.slice(0, 1).toUpperCase(); color: "white"; font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold } }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    users.currentIndex = index
                    surface.reset()
                }
            }
        }
    }
}
