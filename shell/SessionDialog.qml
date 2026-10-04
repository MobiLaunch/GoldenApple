// Restart, Shut Down and Log Out ask first, as on the Mac: an alert with the
// action as its default button and a 60-second countdown that carries it out
// if nobody answers. Return confirms, Escape cancels.
//   qs ipc call session ask shutdown|restart|logout
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "ui" as Shared
import "ui/theme"
import "components"

PanelWindow {
    id: dialog
    property string action: ""          // "shutdown" | "restart" | "logout"
    property int remaining: 60
    readonly property bool open: action !== ""
    readonly property var copy: ({
        shutdown: { verb: "Shut Down", noun: "shut down your computer", auto: "the computer will shut down" },
        restart: { verb: "Restart", noun: "restart your computer", auto: "the computer will restart" },
        logout: { verb: "Log Out", noun: "quit all applications and log out", auto: "you will be logged out" }
    })[action] ?? { verb: "", noun: "", auto: "" }

    function ask(what) {
        if (!["shutdown", "restart", "logout"].includes(what)) return
        remaining = 60
        action = what
        Qt.callLater(() => confirm.forceActiveFocus())
    }
    function cancel() { action = "" }
    function carryOut() {
        const what = action
        action = ""
        if (what === "shutdown") Quickshell.execDetached(["systemctl", "poweroff"])
        else if (what === "restart") Quickshell.execDetached(["systemctl", "reboot"])
        else if (what === "logout") Hyprland.dispatch("exit")
    }

    IpcHandler {
        target: "session"
        function ask(what: string): void { dialog.ask(what) }
    }
    Timer {
        running: dialog.open; interval: 1000; repeat: true
        onTriggered: if (--dialog.remaining <= 0) dialog.carryOut()
    }

    // On the screen in use.
    screen: Quickshell.screens.find((s) => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    visible: open || card.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-alert"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent }   // the alert is modal

    Glass {
        id: card
        role: "menu"
        width: 280
        height: col.implicitHeight + 40
        radius: 26
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -parent.height * 0.12 }
        opacity: dialog.open ? 1 : 0
        scale: dialog.open || Theme.reduceMotion ? 1 : 0.92
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 160 } }
        Behavior on scale { Spring { spring: Theme.popover } }
        Keys.onEscapePressed: dialog.cancel()

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 10
            Symbol {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 2
                name: "logo"; size: 56
                tone: "auto"
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Are you sure you want to " + dialog.copy.noun + " now?"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "If you do nothing, " + dialog.copy.auto + " automatically in " + dialog.remaining + " second" + (dialog.remaining === 1 ? "" : "s") + "."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11 }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8
                Shared.Button {
                    Layout.fillWidth: true; Layout.preferredHeight: 28
                    text: "Cancel"
                    onClicked: dialog.cancel()
                    Keys.onEscapePressed: dialog.cancel()
                }
                Shared.Button {
                    id: confirm
                    Layout.fillWidth: true; Layout.preferredHeight: 28
                    text: dialog.copy.verb
                    prominent: true
                    onClicked: dialog.carryOut()
                    Keys.onEscapePressed: dialog.cancel()
                }
            }
        }
    }
}
