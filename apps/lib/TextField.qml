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
    signal cleared()
    function clearSearch() {
        if (!enabled || !search || password || !input.text.length) return
        input.text = ""
        input.forceActiveFocus()
        cleared()
    }
    implicitWidth: 200; implicitHeight: Theme.fh(26)
    radius: search ? height / 2 : 7
    color: bare ? "transparent" : Theme.dark ? "#1affffff" : "#ffffff"
    border {
        width: bare ? 0 : input.activeFocus ? 3 : 0.5
        color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
            : fieldHover.hovered && enabled && !bare
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.23)
                : Theme.separator
    }
    HoverHandler { id: fieldHover; enabled: tf.enabled }
    Behavior on border.width { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 140 } }
    Symbol {
        visible: tf.search
        x: tf.bare ? 2 : 8
        anchors.verticalCenter: parent.verticalCenter
        name: "search"; tone: "gray"; size: tf.glyphSize
    }
    // A native search field exposes a quiet clear affordance only when it has
    // text. Escape performs the same action without dismissing the parent.
    Item {
        id: clearButton
        objectName: "searchClearButton"
        readonly property bool shown: tf.search && !tf.password && !!input.text
        property bool ready: false
        function syncOpacity(animate = true) {
            if (!ready) return
            clearOpacityTween.stop()
            const target = shown ? 1 : 0
            if (!animate || Theme.reduceMotion) opacity = target
            else { clearOpacityTween.to = target; clearOpacityTween.start() }
        }
        onShownChanged: syncOpacity()
        Component.onCompleted: { ready = true; syncOpacity(false) }
        x: tf.width - width - (tf.bare ? 0 : 4)
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: Math.max(20, tf.height - 4)
        opacity: 0
        visible: opacity > 0
        z: 2
        activeFocusOnTab: shown && tf.enabled
        Accessible.role: Accessible.Button
        Accessible.name: "Clear search"
        Accessible.onPressAction: tf.clearSearch()
        Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) tf.clearSearch() }
        Keys.onReturnPressed: tf.clearSearch()
        FocusRing { }
        NumberAnimation {
            id: clearOpacityTween
            target: clearButton; property: "opacity"
            duration: 110
            easing.type: Easing.OutCubic
        }
        Connections {
            target: Theme
            function onReduceMotionChanged() {
                if (!Theme.reduceMotion) return
                // Standalone animation: Qt can actually stop it mid-flight.
                clearButton.syncOpacity(false)
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 16; height: 16; radius: 8
            color: Theme.dark ? "#6bffffff" : "#66000000"
            scale: !Theme.reduceMotion && clearTap.pressed ? 0.89
                : !Theme.reduceMotion && clearHover.hovered ? 1.08 : 1
            Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
            Symbol { anchors.centerIn: parent; name: "xmark"; size: 9; tone: Theme.dark ? "dark" : "white" }
        }
        HoverHandler { id: clearHover; enabled: clearButton.shown }
        TapHandler {
            id: clearTap
            enabled: clearButton.shown && tf.enabled
            onTapped: tf.clearSearch()
        }
    }
    TextInput {
        id: input
        objectName: "textFieldNativeInput"
        x: tf.search ? tf.glyphSize + (tf.bare ? 10 : 14) : tf.bare ? 0 : 8
        width: Math.max(0, parent.width - x - (tf.bare ? 0 : 8) - (clearButton.shown ? clearButton.width + 2 : 0))
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
        Keys.onEscapePressed: (event) => {
            if (tf.search && input.text.length > 0 && !tf.password) {
                tf.clearSearch()
                event.accepted = true
            } else {
                event.accepted = false
            }
        }
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

