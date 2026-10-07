// A text field with the Mac's rounded look and a focus ring in the accent.
// `bare: true` drops the field's own background and ring, for a container that
// draws its own (Web's Smart Search capsule), keeping one text-input control.
import QtQuick
import "theme"

Rectangle {
    id: tf
    property alias text: input.text
    property alias input: input
    property string placeholder
    property bool search: false
    property bool password: false
    property color foreground: Theme.label
    property color placeholderColor: Theme.tertiaryLabel
    property bool bare: false
    property bool placeholderOnlyWhenFocused: false
    property int fontWeight: Font.Normal
    property real glyphSize: 12            // the search glyph (Spotlight's is larger)
    signal accepted()
    implicitWidth: 200; implicitHeight: Theme.fh(26)
    radius: search ? height / 2 : 7
    color: bare ? "transparent" : Theme.dark ? "#1affffff" : "#ffffff"
    border { width: bare ? 0 : input.activeFocus ? 3 : 0.5; color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.separator }
    Behavior on border.width { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 140 } }
    Symbol { visible: tf.search; x: tf.bare ? 2 : 8; anchors.verticalCenter: parent.verticalCenter; name: "search"; tone: "gray"; size: tf.glyphSize }
    TextInput {
        id: input
        x: tf.search ? tf.glyphSize + (tf.bare ? 10 : 14) : tf.bare ? 0 : 8; width: parent.width - x - (tf.bare ? 0 : 8)
        anchors.verticalCenter: parent.verticalCenter
        color: tf.foreground
        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
        selectByMouse: true
        activeFocusOnTab: true
        Accessible.name: tf.placeholder
        clip: true
        echoMode: tf.password ? TextInput.Password : TextInput.Normal
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: tf.fontWeight }
        onAccepted: tf.accepted()
        Text {
            width: input.width
            elide: Text.ElideRight
            visible: opacity > 0
            opacity: !input.text && !input.preeditText && (input.activeFocus || !tf.placeholderOnlyWhenFocused) ? (input.activeFocus ? 0.72 : 1) : 0
            text: tf.placeholder
            color: tf.placeholderColor
            font: input.font
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 100 } }
        }
    }
}

