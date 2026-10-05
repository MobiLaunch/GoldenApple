// SDDM (Qt 6) greeter: the same LockSurface the shell's lock screen uses, plus
// user picking and power buttons. scripts/install.sh stages it like the shell:
// components/ (the lock surface and wrappers) and ui/ (the shared UI and theme).
import QtQuick
import QtQuick.Layouts
import "components"
import "ui/theme"

Item {
    id: root
    // SDDM resizes the root object to each greeter view. Keep design-time size
    // as an implicit hint so non-1080p and multi-monitor greeters are not pinned
    // to a 1920×1080 scene.
    implicitWidth: 1920; implicitHeight: 1080
    property int goldenSessionIndex: -1
    readonly property int sessionIndex: goldenSessionIndex >= 0 ? goldenSessionIndex
                                                                 : (sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0)
    // SDDM exposes userModel as QAbstractListModel; role numbers are not part of
    // its theme API. Read documented name/realName roles from the delegate.
    readonly property string userLogin: users.currentItem?.loginName || userModel.lastUser || ""
    readonly property string userDisplay: users.currentItem?.displayName || userLogin
    readonly property string userIcon: users.currentItem?.iconPath || ""

    // Prefer the dedicated Golden Gate session when it is installed. SDDM's
    // session model is also a QAbstractListModel, so discover it through delegate
    // roles rather than assuming a private role number.
    Repeater {
        model: sessionModel
        delegate: Item {
            required property int index
            required property string name
            visible: false
            Component.onCompleted: {
                if (name === "Golden Gate")
                    root.goldenSessionIndex = index
            }
        }
    }

    LockSurface {
        id: surface
        anchors.fill: parent
        login: true
        wallpaper: config.background ? "file://" + config.background : ""
        userName: root.userDisplay || "Golden User"
        avatars: root.userIcon ? ["file://" + root.userIcon] : []
        onSubmitted: (password) => sddm.login(root.userLogin, password, root.sessionIndex)
        Component.onCompleted: reset()
    }
    Connections {
        target: sddm
        function onLoginFailed() { surface.fail() }
        function onLoginSucceeded() { surface.unlock() }
    }

    // Sleep, Restart and Shut Down, bottom right, rising in after the user.
    // Children of Glass land in its content item, so refer to the button by id.
    component PowerButton: Item {
        id: pb
        property string icon
        property string label
        signal activated()
        width: 64; height: 64
        Glass {
            id: disc
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40; height: 40; radius: 20
            role: "clear"
            tint: "#4d1c2333"
            hovered: tap.containsMouse
            pressed: tap.pressed
            Symbol { anchors.centerIn: parent; name: pb.icon; size: 17 }
        }
        Text {
            anchors { top: disc.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
            text: pb.label
            color: "white"
            opacity: tap.containsMouse ? 1 : 0.78
            Behavior on opacity { NumberAnimation { duration: 150 } }
            font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium }
        }
        MouseArea { id: tap; anchors.fill: parent; hoverEnabled: true; onClicked: pb.activated() }
    }
    Row {
        id: power
        anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
        spacing: 10
        opacity: 0
        Component.onCompleted: rise.start()
        NumberAnimation on opacity { id: rise; running: false; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
        PowerButton { icon: "moon"; label: "Sleep"; visible: sddm.canSuspend; onActivated: sddm.suspend() }
        PowerButton { icon: "arrow-clockwise"; label: "Restart"; visible: sddm.canReboot; onActivated: sddm.reboot() }
        PowerButton { icon: "power"; label: "Shut Down"; visible: sddm.canPowerOff; onActivated: sddm.powerOff() }
    }

    // Other users: small avatars bottom-left when there is more than one.
    // A ListView gives us SDDM's documented model roles without hard-coding the
    // private integer role ids, and remains usable when many accounts exist.
    ListView {
        id: users
        // Keep the current delegate instantiated even for a one-user system so
        // userLogin/userDisplay always resolve; only the picker chrome is hidden.
        opacity: userModel.count > 1 ? 1 : 0
        enabled: userModel.count > 1
        interactive: userModel.count > 1
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
            required property string icon
            readonly property string loginName: name
            readonly property string displayName: realName || name
            readonly property string iconPath: icon
            width: 40; height: 40; radius: 20
            color: index === users.currentIndex ? "#66ffffff" : "#26ffffff"
            border.width: index === users.currentIndex ? 2 : 1; border.color: index === users.currentIndex ? "white" : "#59ffffff"
            Behavior on color { ColorAnimation { duration: 160 } }
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
