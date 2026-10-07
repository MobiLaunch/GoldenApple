// The lock screen and the login window, as on macOS 26: the date and a large
// clock over your wallpaper, and your picture and name at the bottom. Press a
// key or move the pointer and it wakes: the wallpaper softens behind a dim, the
// clock steps back and the password field rises under your name (the login
// window starts awake). A wrong password shakes the field and clears it; the
// right one fades everything but the wallpaper away, so the desktop (on the
// same wallpaper) comes through without a jump. Escape puts it back to sleep.
// Pure Qt Quick, so the Quickshell lock screen and the SDDM theme share it.
//   signal submitted(string password)  → check it; then fail() or unlock()
//   signal unlocked()                   → the unlock animation has finished
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../ui/theme"

Item {
    id: root
    property string userName: "Golden User"
    property string initials: userName.split(" ").filter((w) => w).map((w) => w[0]).join("").slice(0, 2).toUpperCase()
    property var avatars: []            // where the account picture may be, tried in turn
    property int avatarTry: 0
    property url wallpaper
    property string hint: ""            // shown under the field after three wrong tries
    property string message: ""         // Settings → Lock Screen: "Show message when locked"
    property bool login: false          // the login window: awake from the start
    property bool busy: false
    property real battery: -1           // 0…1, or -1 for no battery
    property bool charging: false
    property bool awake: login
    property int failures: 0
    readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool still: Theme.reduceMotion
    signal submitted(string password)
    signal unlocked()

    function wake() {
        if (leaving.running) return
        awake = true
        idle.restart()
    }
    function submit() {
        if (busy || leaving.running) return
        wake()
        busy = true
        submitted(field.text)
    }
    function fail() {
        busy = false
        field.text = ""
        failures++
        shake.restart()
        flash.restart()
        field.input.forceActiveFocus()
    }
    function reset() {
        leaving.stop()
        field.text = ""
        busy = false
        failures = 0
        awake = login
        content.opacity = 1
        arrive.restart()
        field.input.forceActiveFocus()
    }
    function typed(text) { field.text = text }
    function unlock() {
        busy = false
        idle.stop()
        leaving.restart()
    }

    Timer { id: idle; interval: 20000; onTriggered: if (!root.login && !field.text && !root.busy) root.awake = false }

    // ------------------------------------------------------------ the wallpaper
    // Sharp while asleep; awake, softened and dimmed so the field reads.
    Item {
        id: backdrop
        anchors.fill: parent
        property real zoom: 1
        scale: zoom
        Image {
            id: picture
            anchors.fill: parent
            source: root.wallpaper
            sourceSize: Qt.size(root.width, root.height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: !root.gpu
        }
        MultiEffect {
            anchors.fill: parent
            source: picture
            visible: root.gpu
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 64
            blur: root.awake ? 0.62 : 0
            saturation: root.awake ? 0.12 : 0
            Behavior on blur { NumberAnimation { duration: root.still ? 0 : 520; easing.type: Easing.OutCubic } }
            Behavior on saturation { NumberAnimation { duration: 520 } }
        }
    }
    Rectangle {   // darker behind the date and clock, so white numerals read over a pale sky
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#47000a28" }
            GradientStop { position: 0.34; color: "#14000a28" }
            GradientStop { position: 0.6; color: "#00000a28" }
            GradientStop { position: 1.0; color: "#4d000a28" }
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "#000a1a"
        opacity: root.awake ? 0.22 : 0
        Behavior on opacity { NumberAnimation { duration: root.still ? 0 : 420; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        property point last: Qt.point(-1, -1)
        // A real move, not the pointer settling as the surface appears.
        onPositionChanged: (m) => {
            if (last.x >= 0 && Math.hypot(m.x - last.x, m.y - last.y) > 3) root.wake()
            last = Qt.point(m.x, m.y)
        }
        onPressed: { root.wake(); field.input.forceActiveFocus() }
    }

    SystemClockProxy { id: clock }

    // Everything but the wallpaper, faded together on unlock.
    Item {
        id: content
        anchors.fill: parent

        // ------------------------------------------------------- date and time
        Column {
            id: when
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Math.round(root.height * 0.075) }
            property real lift: 0
            transform: Translate { y: when.lift }
            scale: root.awake ? 0.94 : 1
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: root.still ? 0 : Theme.smooth.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth.curve } }
            spacing: -Math.round(time.size * 0.1)
            layer.enabled: root.gpu
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#59001433"; shadowBlur: 0.7; shadowVerticalOffset: 2 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(clock.now, "dddd, MMMM d")
                color: "#f0ffffff"
                font { family: Theme.fontDisplay; pixelSize: Math.max(18, Math.round(root.height * 0.026)); weight: Font.DemiBold }
            }
            Text {
                id: time
                readonly property int size: Math.round(Math.min(root.height * 0.205, root.width * 0.16, 210))
                anchors.horizontalCenter: parent.horizontalCenter
                // "h" is 24-hour unless an AM/PM marker is present; the lock clock shows 1:34, not 13:34.
                text: Qt.formatTime(clock.now, "h:mm AP").replace(/\s*[AP]M$/i, "")
                color: "#ebffffff"
                font {
                    family: Theme.fontDisplay
                    pixelSize: time.size
                    weight: Font.Bold
                    letterSpacing: -Math.round(time.size * 0.035)
                }
            }
        }

        // The lock message, under the clock, until you start to unlock.
        Text {
            visible: root.message !== "" && !root.login
            anchors { horizontalCenter: parent.horizontalCenter; top: when.bottom; topMargin: 6 }
            width: Math.min(parent.width - 80, 560)
            horizontalAlignment: Text.AlignHCenter
            text: root.message
            textFormat: Text.PlainText; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
            color: "#e6ffffff"
            opacity: root.awake ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.still ? 0 : 200 } }
            font { family: Theme.fontUi; pixelSize: Math.max(14, Math.round(root.height * 0.018)); weight: Font.Medium }
            layer.enabled: root.gpu
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#59001433"; shadowBlur: 0.6; shadowVerticalOffset: 1 }
        }

        // ------------------------------------------------------------ status
        Row {
            anchors { right: parent.right; top: parent.top; margins: 18 }
            visible: root.battery >= 0
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(root.battery * 100) + "%"
                color: "white"
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
            }
            Item {   // the battery, drawn
                width: 27; height: 13
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { width: 24; height: 13; radius: 4; color: "transparent"; border { width: 1.2; color: "#b3ffffff" } }
                Rectangle { x: 25; y: 4.5; width: 1.6; height: 4; radius: 0.8; color: "#b3ffffff" }
                Rectangle {
                    x: 2.2; y: 2.2; height: 8.6; radius: 2
                    width: Math.max(2, 19.6 * root.battery)
                    color: root.charging ? "#30d158" : root.battery <= 0.2 ? "#ff453a" : "white"
                }
            }
        }

        // ------------------------------------------------- the user, the field
        Column {
            id: who
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.round(root.height * 0.085) }
            property real lift: 0
            transform: Translate { y: who.lift }
            spacing: 0

            Item {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72
                scale: root.awake ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: root.still ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#a5aab5" }
                        GradientStop { position: 1; color: "#7c818c" }
                    }
                    visible: photo.status !== Image.Ready
                    Text {
                        anchors.centerIn: parent
                        text: root.initials
                        color: "white"
                        font { family: Theme.fontDisplay; pixelSize: 28; weight: Font.DemiBold; letterSpacing: 0.5 }
                    }
                }
                // The picture, clipped round (a rounded path filled with it).
                Image {
                    id: photo
                    anchors.fill: parent
                    source: root.avatars[root.avatarTry] ?? ""
                    onStatusChanged: if (status === Image.Error && root.avatarTry < root.avatars.length) root.avatarTry++
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Shape {
                    anchors.fill: parent
                    visible: photo.status === Image.Ready
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 0; strokeColor: "transparent"
                        fillItem: photo
                        PathAngleArc { centerX: 36; centerY: 36; radiusX: 36; radiusY: 36; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border { width: 1; color: "#40ffffff" } }
                MouseArea { anchors.fill: parent; onClicked: { root.wake(); field.input.forceActiveFocus() } }
            }
            Item { width: 1; height: 10 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userName
                color: "white"
                font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                style: Text.Raised; styleColor: "#26001433"
            }
            Item { width: 1; height: 12 }

            // The password field: a capsule of smoky glass that rises on wake.
            Item {
                id: slot
                anchors.horizontalCenter: parent.horizontalCenter
                width: 236; height: 34
                property real shakeX: 0
                Glass {
                    id: capsule
                    width: parent.width; height: parent.height
                    x: slot.shakeX
                    radius: 17
                    role: "clear"
                    // The same smoky glass in light and dark: it sits on the
                    // wallpaper, not a window, and carries white text either way.
                    tint: Qt.tint("#701c2333", Qt.rgba(1, 0.23, 0.19, 0.45 * slot.flash))
                    opacity: root.awake ? 1 : 0
                    scale: root.awake ? 1 : 0.86
                    transform: Translate { y: root.awake ? 0 : 10; Behavior on y { NumberAnimation { duration: root.still ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } } }
                    Behavior on opacity { NumberAnimation { duration: root.still ? 0 : 240; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: root.still ? 0 : Theme.snappy.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.snappy.curve } }

                    TextField {
                        id: field
                        anchors { left: parent.left; right: go.left; leftMargin: 7; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        height: 28
                        password: true
                        placeholder: root.busy ? "" : "Enter Password"
                        foreground: "white"
                        placeholderColor: "#bfffffff"
                        color: "transparent"
                        border.width: 0
                        enabled: !root.busy
                        input.passwordCharacter: "●"
                        input.font.pixelSize: 13
                        input.font.letterSpacing: field.text ? 2 : 0     // the dots, not the placeholder
                        input.focus: true
                        input.onTextChanged: if (field.text) root.wake()
                        input.Keys.onPressed: (e) => {
                            root.wake()
                            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.submit(); e.accepted = true }
                            else if (e.key === Qt.Key_Escape) {
                                field.text = ""
                                if (!root.login) root.awake = false
                                e.accepted = true
                            }
                        }
                    }
                    // The arrow, once there's something to send; a spinner while it's checked.
                    Item {
                        id: go
                        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        width: 26; height: 26
                        Rectangle {
                            anchors.fill: parent
                            radius: 13
                            color: "#4dffffff"
                            opacity: field.text && !root.busy ? 1 : 0
                            scale: field.text && !root.busy ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on scale { Spring { spring: Theme.bouncy } }
                            Symbol { anchors.centerIn: parent; name: "arrow-up"; size: 13 }
                            MouseArea { anchors.fill: parent; enabled: parent.opacity > 0.5; onClicked: root.submit() }
                        }
                        Shape {
                            anchors.centerIn: parent
                            width: 16; height: 16
                            visible: root.busy
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: "white"; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 8; centerY: 8; radiusX: 6.5; radiusY: 6.5; startAngle: 0; sweepAngle: 280 }
                            }
                            RotationAnimation on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite; running: root.busy }
                        }
                    }
                }
                property real flash: 0
            }
            Item { width: 1; height: 10 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 16
                text: root.failures >= 3 && root.hint ? root.hint
                    : root.awake ? "" : (root.login ? "" : "Press any key or click to unlock")
                color: "#d9ffffff"
                opacity: text ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
            }
        }
    }

    // ------------------------------------------------------------- animations
    // Arriving: the wallpaper settles from a little closer, the clock drops in
    // and the user rises, each a beat after the other.
    ParallelAnimation {
        id: arrive
        NumberAnimation { target: backdrop; property: "zoom"; from: root.still ? 1 : 1.06; to: 1; duration: 900; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PropertyAction { targets: [when, who]; property: "opacity"; value: 0 }
            PauseAnimation { duration: root.still ? 0 : 80 }
            ParallelAnimation {
                NumberAnimation { target: when; property: "opacity"; to: 1; duration: root.still ? 0 : 520; easing.type: Easing.OutCubic }
                NumberAnimation { target: when; property: "lift"; from: root.still ? 0 : -26; to: 0; duration: root.still ? 0 : Theme.smooth.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth.curve }
                SequentialAnimation {
                    PauseAnimation { duration: root.still ? 0 : 140 }
                    ParallelAnimation {
                        NumberAnimation { target: who; property: "opacity"; to: 1; duration: root.still ? 0 : 480; easing.type: Easing.OutCubic }
                        NumberAnimation { target: who; property: "lift"; from: root.still ? 0 : 24; to: 0; duration: root.still ? 0 : Theme.smooth.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.smooth.curve }
                    }
                }
            }
        }
    }
    // Leaving: the clock lifts away, the rest fades and the wallpaper sharpens.
    SequentialAnimation {
        id: leaving
        ScriptAction { script: root.awake = false }
        ParallelAnimation {
            NumberAnimation { target: content; property: "opacity"; to: 0; duration: root.still ? 0 : 340; easing.type: Easing.InCubic }
            NumberAnimation { target: when; property: "lift"; to: -40; duration: root.still ? 0 : 380; easing.type: Easing.InCubic }
            NumberAnimation { target: who; property: "lift"; to: 30; duration: root.still ? 0 : 380; easing.type: Easing.InCubic }
        }
        PauseAnimation { duration: root.still ? 0 : 140 }
        ScriptAction { script: root.unlocked() }
    }
    // The "no" shake, dying away, and a red flush through the glass.
    SequentialAnimation {
        id: shake
        NumberAnimation { target: slot; property: "shakeX"; to: -16; duration: 45; easing.type: Easing.OutSine }
        NumberAnimation { target: slot; property: "shakeX"; to: 14; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: slot; property: "shakeX"; to: -11; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: slot; property: "shakeX"; to: 8; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: slot; property: "shakeX"; to: -4; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: slot; property: "shakeX"; to: 0; duration: 80; easing.type: Easing.OutSine }
    }
    SequentialAnimation {
        id: flash
        NumberAnimation { target: slot; property: "flash"; to: 1; duration: 90 }
        NumberAnimation { target: slot; property: "flash"; to: 0; duration: 700; easing.type: Easing.OutCubic }
    }
}
