// A message in place, at the top of a pane or a form: an error that couldn't
// be saved (CS2-023), a warning, a note, a success. Opens and closes by
// growing and shrinking, with Reduce Motion at once. An optional action
// ("Try Again") and a close button, both reachable from the keyboard.
//   InlineBanner { kind: "error"; text: sys.writeError; onDismissed: sys.writeError = "" }
// It shows while it has text, except a message it was dismissed from; a new
// message (or the same one set again after being cleared) shows again.
import QtQuick
import "theme"

Item {
    id: banner
    property string kind: "error"           // error | warning | info | success
    property string text
    property string actionText
    property string dismissedText: ""
    readonly property bool shown: !!text && text !== dismissedText
    onTextChanged: if (text !== dismissedText) dismissedText = ""
    property bool dismissible: true
    property bool floating: false           // over other content: an opaque base under the tint
    signal action()
    signal dismissed()
    readonly property color tone: ({ error: Theme.accentRed, warning: Theme.accentOrange,
                                     info: Theme.accentBlue, success: Theme.accentGreen })[kind] ?? Theme.accentBlue
    readonly property string symbol: ({ error: "warning", warning: "warning", info: "info", success: "checkmark" })[kind] ?? "info"

    implicitWidth: 360
    implicitHeight: shown ? box.height : 0
    height: implicitHeight
    clip: true
    visible: height > 0.5
    Behavior on implicitHeight { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.snappy.ms; easing.type: Easing.OutCubic } }

    Rectangle {
        visible: banner.floating
        anchors.fill: box
        radius: box.radius
        color: Theme.windowBg
        opacity: box.opacity
    }
    Rectangle {
        id: box
        objectName: "inlineBannerBox"
        width: parent.width
        height: Math.max(36, row.implicitHeight + 16)
        radius: Theme.radius.card
        color: Qt.rgba(banner.tone.r, banner.tone.g, banner.tone.b, Theme.dark ? 0.22 : 0.12)
        border { width: 0.5; color: Qt.rgba(banner.tone.r, banner.tone.g, banner.tone.b, 0.45) }
        opacity: banner.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.tap.ms } }
        Accessible.role: Accessible.AlertMessage
        Accessible.name: banner.text

        Row {
            id: row
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 8 }
            spacing: 8
            Symbol { anchors.verticalCenter: parent.verticalCenter; name: banner.symbol; size: 14; color: banner.tone }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: row.width - 22 - (act.visible ? act.width + 8 : 0) - (close.visible ? close.width + 8 : 0) - 8
                text: banner.text
                wrapMode: Text.Wrap
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
            }
            Button {
                id: act
                visible: !!banner.actionText
                anchors.verticalCenter: parent.verticalCenter
                text: banner.actionText
                onClicked: banner.action()
            }
            Item {
                id: close
                objectName: "inlineBannerClose"
                visible: banner.dismissible
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                activeFocusOnTab: visible && banner.shown
                Accessible.role: Accessible.Button
                Accessible.name: "Dismiss"
                Accessible.onPressAction: banner.dismiss()
                Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) banner.dismiss() }
                Keys.onReturnPressed: banner.dismiss()
                FocusRing {}
                Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: "gray" }
                TapHandler { onTapped: banner.dismiss() }
            }
        }
    }
    function dismiss() { dismissedText = text; dismissed() }
}
