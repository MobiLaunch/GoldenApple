// Lock / login surface: large glass clock over the wallpaper, avatar, and a
// glass password capsule. Pure Qt Quick, so both the Quickshell lock screen and
// the SDDM login theme use it.
//   signal submitted(string password)   → check it; call fail() on a wrong one
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../ui/theme"

Item {
    id: root
    property string userName: "Golden User"
    property string initials: userName.split(" ").map((w) => w[0]).join("").slice(0, 2).toUpperCase()
    property url wallpaper
    property string hint: ""
    property bool busy: false
    signal submitted(string password)

    function fail() {
        shake.restart();
        field.text = "";
        busy = false;
    }
    function reset() { field.text = ""; busy = false; field.forceActiveFocus() }

    Image { anchors.fill: parent; source: root.wallpaper; fillMode: Image.PreserveAspectCrop; asynchronous: true }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            // Darker behind the date and clock, so white numerals read over a pale sky.
            GradientStop { position: 0.0; color: "#4d000a28" }
            GradientStop { position: 0.32; color: "#1f000a28" }
            GradientStop { position: 0.55; color: "#00000a28" }
            GradientStop { position: 1.0; color: "#40000a28" }
        }
    }

    SystemClockProxy { id: clock }

    ColumnLayout {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.09 }
        spacing: 0
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.now, "dddd, MMMM d")
            color: "#ebffffff"
            style: Text.Raised
            styleColor: "#33001e5a"
            font { family: Theme.fontUi; pixelSize: 24; weight: Font.DemiBold }
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#66001433"; shadowBlur: 0.5; shadowVerticalOffset: 1 }
        }
        // Glass numerals: translucent white with a brighter top.
        Text {
            id: time
            Layout.alignment: Qt.AlignHCenter
            // "h" is 24-hour unless an AM/PM marker is present; the lock clock shows 1:34, not 13:34.
            text: Qt.formatTime(clock.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
            font { family: Theme.fontUi; pixelSize: 132; weight: Font.Bold; letterSpacing: -6 }
            color: "#e6ffffff"
            // A soft shadow keeps the numerals readable over a pale sky.
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#59001433"; shadowBlur: 0.6; shadowVerticalOffset: 2 }
            style: Text.Raised
            styleColor: "#2e001e5a"
        }
    }

    ColumnLayout {
        id: user
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.09 }
        spacing: 10
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 64; implicitHeight: 64; radius: 32
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ffb347" }
                GradientStop { position: 0.6; color: "#ff5e7e" }
                GradientStop { position: 1; color: "#7b61ff" }
            }
            border.width: 1.5; border.color: "#59ffffff"
            Text { anchors.centerIn: parent; text: root.initials; color: "white"; font { family: Theme.fontUi; pixelSize: 24; weight: Font.DemiBold } }
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: root.userName; color: "white"; font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold } }
        Glass {
            id: capsule
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220; Layout.preferredHeight: 34
            radius: 17
            // The same smoky glass in light and dark: the field sits on the
            // wallpaper, not on a window, and carries white text either way.
            role: "clear"
            tint: "#701c2333"
            transform: Translate { id: shakeX }
            TextField {
                id: field
                anchors { left: parent.left; right: go.left; leftMargin: 7; rightMargin: 6; verticalCenter: parent.verticalCenter }
                height: 28
                password: true
                placeholder: root.busy ? "Unlocking…" : "Enter Password"
                foreground: "white"
                placeholderColor: "#c0ffffff"
                color: "transparent"
                border.width: 0
                enabled: !root.busy
                input.passwordCharacter: "●"
                input.font.pixelSize: 13
                input.font.letterSpacing: field.text ? 2 : 0     // the dots, not the placeholder
                input.focus: true
                input.Keys.onReturnPressed: { root.busy = true; root.submitted(field.text) }
                input.Keys.onEnterPressed: { root.busy = true; root.submitted(field.text) }
            }
            Rectangle {
                id: go
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                width: 26; height: 26; radius: 13
                color: "#4dffffff"
                opacity: field.text ? 1 : 0
                scale: field.text ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { Spring { spring: Theme.bouncy } }
                Symbol { anchors.centerIn: parent; name: "arrow-up"; size: 13 }
                MouseArea { anchors.fill: parent; onClicked: { root.busy = true; root.submitted(field.text) } }
            }
        }
        Text { Layout.alignment: Qt.AlignHCenter; visible: root.hint !== ""; text: root.hint; color: "#c0ffffff"; font { family: Theme.fontUi; pixelSize: 11 } }
    }

    // The classic "no" shake.
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeX; property: "x"; to: -14; duration: 50 }
        NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: -10; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: 8; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: -4; duration: 60 }
        NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
    }
}
