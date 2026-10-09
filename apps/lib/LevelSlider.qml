// Control Center's vertical glass level capsule. The fill is a clipped
// rounded rectangle, so dragging needs no extra texture or masking pass.
// The owner confirms each moved value; a binding to the real system level
// stays intact when volume/brightness is changed from another surface.
import QtQuick
import "theme"

Item {
    id: level
    property real value: 0.5
    property string label: "Level"
    property string symbol: "sun-max"
    property color symbolColor: "transparent"
    property bool expandable: false
    property bool showFocusRing: true
    signal moved(real value)
    signal expanded()

    implicitWidth: 76
    implicitHeight: 164
    readonly property real radius: width / 2
    readonly property bool pressed: drag.pressed
    property real tension: 0
    readonly property real visualXScale: Theme.reduceMotion ? 1 : 1 - tension * 0.4
    readonly property real visualYScale: Theme.reduceMotion ? 1 : 1 + tension
    function releaseStretch() {
        relax.stop()
        if (Theme.reduceMotion || !enabled) tension = 0
        else relax.start()
    }
    NumberAnimation { id: relax; target: level; property: "tension"; to: 0; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    onEnabledChanged: if (!enabled) { relax.stop(); tension = 0 }
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    readonly property real shownValue: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    property bool fillReady: false
    function syncFill(animate = true) {
        if (!fillReady) return
        fillAnimation.stop()
        const h = Math.max(0, height - 2) * shownValue
        if (!animate || drag.pressed || Theme.reduceMotion) fillClip.height = h
        else { fillAnimation.to = h; fillAnimation.start() }
    }
    onShownValueChanged: syncFill()
    onHeightChanged: syncFill(false)

    function set(v) {
        if (!enabled || !Number.isFinite(v)) return
        v = Math.max(0, Math.min(1, v))
        if (v !== shownValue) moved(v)
        if (!drag.pressed && (v >= 0.99 || v <= 0.01) && !Theme.reduceMotion) {
            tension = 0.035
            releaseStretch()
        }
    }
    function fromY(y) {
        if (height <= 0 || !enabled) return
        const v = Math.max(0, Math.min(1, 1 - y / height))
        set(v)
        if (!Theme.reduceMotion) {
            const overscroll = Math.max(0, -y, y - height) / height
            tension = Math.min(0.055, 0.012 + 0.028 * Math.pow(Math.abs(2 * v - 1), 8) + overscroll * 0.08)
        }
    }
    function expand() { if (enabled && expandable) expanded() }

    Accessible.role: Accessible.Slider
    Accessible.name: label
    Accessible.description: Math.round(shownValue * 100) + " percent"
    Accessible.onIncreaseAction: set(shownValue + 0.05)
    Accessible.onDecreaseAction: set(shownValue - 0.05)
    Keys.onUpPressed: set(shownValue + 0.05)
    Keys.onDownPressed: set(shownValue - 0.05)
    Keys.onRightPressed: set(shownValue + 0.05)
    Keys.onLeftPressed: set(shownValue - 0.05)
    Keys.onReturnPressed: expand()
    Keys.onEnterPressed: expand()
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) { set(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { set(1); event.accepted = true }
    }

    // Only the painted capsule stretches. The drag area, value mapping and
    // layout remain fixed, including when the pointer pulls past an endpoint.
    Glass {
        id: visual
        objectName: "levelSliderVisual"
        anchors.fill: parent
        radius: level.radius
        role: "clear"
        pressed: drag.pressed
        hovered: hover.hovered && level.enabled
        pressScale: 1
        lift: 0
        transform: Scale {
            origin.x: level.width / 2
            origin.y: level.shownValue >= 0.5 ? level.height : 0
            xScale: level.visualXScale
            yScale: level.visualYScale
        }
        Item {
            id: fillClip
            objectName: "levelSliderFill"
            x: 1
            width: Math.max(0, level.width - 2)
            height: 0
            y: level.height - 1 - height
            clip: true
            Component.onCompleted: { level.fillReady = true; level.syncFill(false) }
            Rectangle {
                width: fillClip.width
                height: Math.max(0, level.height - 2)
                y: fillClip.height - height
                radius: width / 2
                color: "#fafaff"
            }
        }
        // A standalone animation can be interrupted immediately; an animation
        // nested in Behavior cannot be stopped as a root animation in Qt.
        NumberAnimation { id: fillAnimation; target: fillClip; property: "height"; duration: 105; easing.type: Easing.OutCubic }
        Symbol {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            name: level.symbol
            size: Math.min(30, level.width * 0.4)
            tone: level.shownValue > 0.25 ? "dark" : "white"
            color: level.symbolColor
        }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: level.enabled
        acceptedButtons: Qt.LeftButton
        onPressedChanged: if (pressed) level.syncFill(false)
        onPressed: (mouse) => { relax.stop(); level.forceActiveFocus(); level.fromY(mouse.y) }
        onPositionChanged: (mouse) => { if (pressed) level.fromY(mouse.y) }
        onReleased: level.releaseStretch()
        onCanceled: level.releaseStretch()
    }
    TapHandler {
        enabled: level.enabled && level.expandable
        acceptedButtons: Qt.RightButton
        onTapped: level.expand()
    }
    HoverHandler { id: hover; enabled: level.enabled }
    Item {
        id: disclosure
        objectName: "levelSliderDisclosure"
        visible: level.expandable
        anchors { top: parent.top; topMargin: 7; horizontalCenter: parent.horizontalCenter }
        width: 32; height: 26
        activeFocusOnTab: visible && level.enabled
        Accessible.role: Accessible.Button
        Accessible.name: level.label + " controls"
        Accessible.onPressAction: level.expand()
        Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) level.expand() }
        Keys.onReturnPressed: level.expand()
        Keys.onEnterPressed: level.expand()
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#26000000"
            opacity: disclosureHover.hovered || disclosure.activeFocus ? 1 : 0
            Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 90 } }
        }
        Symbol { anchors.centerIn: parent; name: "chevron-up"; size: 10; tone: level.shownValue > 0.85 ? "dark" : "white" }
        HoverHandler { id: disclosureHover }
        TapHandler { enabled: level.enabled; onTapped: level.expand() }
        FocusRing { visible: level.showFocusRing && opacity > 0 }
    }
    FocusRing { visible: level.showFocusRing && opacity > 0 }
    Connections {
        target: Theme
        function onReduceMotionChanged() {
            if (!Theme.reduceMotion) return
            relax.stop()
            level.tension = 0
            level.syncFill(false)
        }
    }
}
