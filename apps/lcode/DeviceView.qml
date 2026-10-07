// A simulated device, drawn in points: body, bezel and buttons, the screen
// with the app's live frames, status bar and home indicator, the camera
// housing, and the home screen of installed apps. Touches, scrolling and
// keys go to the app (through the helper's display agent).
import Quickshell
import QtQuick
import QtQuick.Shapes
import "../lib"
import "../lib/theme"
import "../lib/paths.js" as Paths
import "devices.js" as Devices

Item {
    id: view
    property var app
    property var backend
    readonly property var device: app.simDevice
    readonly property int orientation: app.simOrientation
    readonly property var body: Devices.bodySize(device, orientation)
    readonly property var screen: Devices.screenSize(device, orientation)
    readonly property var insets: Devices.insets(device, orientation)
    readonly property var appArea: Devices.appSize(device, orientation)
    readonly property real fit: Math.min(1, (width - 32) / body.w, (height - 24) / body.h)
    readonly property var frame: app.simFrame
    readonly property bool showApp: app.simPower === "on" && !app.simShowingHome && !!frame && frame.window
                                    && frame.w === appArea.w && frame.h === appArea.h
    readonly property string screenMode: app.simPower === "off" ? "off" : app.simPower === "booting" ? "boot" : showApp ? "app" : "home"
    property date now: new Date()
    Timer { interval: 10000; running: true; repeat: true; onTriggered: view.now = new Date() }

    function luminance(c) { return c ? 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] : 0 }
    readonly property bool darkTop: screenMode !== "app" || !frame || luminance(frame.top) < 140
    readonly property bool darkBottom: screenMode !== "app" || !frame || luminance(frame.bottom) < 140

    function input(cmd) { backend.call("simInput", { input: cmd }) }

    // Save what's on screen, status bar included, to ~/Pictures.
    function screenshot(done) {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' hh.mm.ss")
        const path = Quickshell.env("HOME") + "/Pictures/Simulator Screenshot - " + device.name + " - " + stamp + ".png"
        screenItem.grabToImage((result) => done(result.saveToFile(path) ? path : ""))
    }

    Item {
        id: stage
        width: view.body.w
        height: view.body.h
        anchors.centerIn: parent
        scale: view.fit

        // ---- Body, drawn upright for the portrait device and rotated into place.
        Item {
            id: bodyFrame
            readonly property real w: view.device.width + 2 * view.device.bezelX
            readonly property real h: view.device.height + 2 * view.device.bezelY
            width: w; height: h
            anchors.centerIn: parent
            rotation: view.orientation

            // Side buttons: action and volume on the left, power on the right.
            Repeater {
                model: view.device.tablet
                    ? [{ x: bodyFrame.w - 2, y: 90, h: 50 }, { x: bodyFrame.w - 2, y: 150, h: 50 }]
                    : [{ x: -4, y: bodyFrame.h * 0.17, h: 30 }, { x: -4, y: bodyFrame.h * 0.25, h: 58 },
                       { x: -4, y: bodyFrame.h * 0.33, h: 58 }, { x: bodyFrame.w - 2, y: bodyFrame.h * 0.27, h: 92 }]
                delegate: Rectangle {
                    required property var modelData
                    x: modelData.x; y: modelData.y
                    width: 6; height: modelData.h
                    radius: 2.5
                    color: Theme.dark ? "#4a4a4e" : "#3a3a3d"
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: view.device.cutout === "home-button" ? 56 : view.device.corner + view.device.bezelX
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#2a2a2c" }
                    GradientStop { position: 0.5; color: "#161618" }
                    GradientStop { position: 1; color: "#2a2a2c" }
                }
                border { width: 3; color: Theme.dark ? "#6b6b70" : "#4c4c50" }
            }
            // The black glass around the screen (the bezel proper).
            Rectangle {
                anchors { fill: parent; margins: 5 }
                visible: view.device.cutout !== "home-button"
                radius: view.device.corner + view.device.bezelX - 5
                color: "#0b0b0c"
            }
            // Classic design: earpiece and home button.
            Rectangle {
                visible: view.device.cutout === "home-button"
                anchors.horizontalCenter: parent.horizontalCenter
                y: view.device.bezelY / 2 - 3
                width: 60; height: 6; radius: 3
                color: "#38383c"
            }
            Rectangle {
                visible: view.device.cutout === "home-button"
                anchors.horizontalCenter: parent.horizontalCenter
                y: bodyFrame.h - view.device.bezelY / 2 - height / 2
                width: view.device.bezelY * 0.66; height: width; radius: width / 2
                color: "#0d0d0f"
                border { width: 2.5; color: "#59595d" }
                TapHandler { onTapped: view.app.simShowingHome = true }
            }
        }

        // ---- Screen, upright in the current orientation.
        Item {
            id: screenItem
            width: view.screen.w
            height: view.screen.h
            anchors.centerIn: parent
            clip: true

            Rectangle { anchors.fill: parent; color: "#000000" }

            // Boot: the CitronOS mark on black.
            Symbol {
                anchors.centerIn: parent
                visible: view.screenMode === "boot"
                name: "logo"
                size: 72
                tone: "white"
            }

            // Home screen: wallpaper and installed apps.
            Item {
                anchors.fill: parent
                visible: view.screenMode === "home"
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#2a5cdb" }
                        GradientStop { position: 0.55; color: "#6b38c7" }
                        GradientStop { position: 1; color: "#f26b73" }
                    }
                }
                Grid {
                    x: view.insets.left + (view.appArea.w - width) / 2
                    y: view.insets.top + 28
                    columns: view.device.tablet ? 6 : 4
                    columnSpacing: view.device.tablet ? 44 : 26
                    rowSpacing: 18
                    Repeater {
                        model: view.app.installedApps
                        delegate: Column {
                            id: icon
                            required property string modelData
                            spacing: 6
                            readonly property var colors: ["#3478f6", "#34c759", "#ff9500", "#af52de", "#ff3b30", "#5856d6"]
                            readonly property color tint: colors[Array.from(modelData).reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % colors.length]
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: view.device.tablet ? 74 : 62
                                height: width
                                radius: width * 0.225
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Qt.lighter(icon.tint, 1.2) }
                                    GradientStop { position: 1; color: Qt.darker(icon.tint, 1.15) }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: icon.modelData.charAt(0).toUpperCase()
                                    color: "#ffffff"
                                    font { family: Theme.fontDisplay; pixelSize: parent.width * 0.5; weight: Font.Bold }
                                }
                                TapHandler { onTapped: view.app.launchInstalled(icon.modelData) }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: view.device.tablet ? 90 : 76
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: icon.modelData
                                color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: view.app.appRunning && view.app.pendingRunTitle === icon.modelData
                                width: 4; height: 4; radius: 2
                                color: "#ffffff"
                            }
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    visible: view.app.installedApps.length === 0
                    spacing: 8
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(view.now, "h:mm")
                        color: "#ffffff"
                        font { family: Theme.fontDisplay; pixelSize: 64; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Run an app from LCode to install it here."
                        color: "#e6ffffff"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                    }
                }
            }

            // The app: system areas tinted to match its edges, then its frames.
            Rectangle {
                visible: view.screenMode === "app"
                width: parent.width; height: view.insets.top + 1
                color: view.frame ? Qt.rgba(view.frame.top[0] / 255, view.frame.top[1] / 255, view.frame.top[2] / 255, 1) : "#ffffff"
            }
            Rectangle {
                visible: view.screenMode === "app"
                y: view.insets.top
                width: parent.width; height: parent.height - y
                color: view.frame ? Qt.rgba(view.frame.bottom[0] / 255, view.frame.bottom[1] / 255, view.frame.bottom[2] / 255, 1) : "#ffffff"
            }
            Item {
                id: appFrame
                visible: view.screenMode === "app"
                x: view.insets.left
                y: view.insets.top
                width: view.appArea.w
                height: view.appArea.h
                property int front: 0
                property int wanted: -1
                Connections {
                    target: view
                    function onFrameChanged() {
                        if (!view.frame) return
                        const back = 1 - appFrame.front
                        appFrame.wanted = back
                        const img = back === 0 ? imageA : imageB
                        img.source = Paths.fileUrl(view.frame.frame) + "?" + view.frame.seq
                    }
                }
                Image {
                    id: imageA
                    visible: appFrame.front === 0
                    cache: false
                    asynchronous: true
                    smooth: view.fit < 0.99
                    onStatusChanged: if (status === Image.Ready && appFrame.wanted === 0) appFrame.front = 0
                }
                Image {
                    id: imageB
                    visible: appFrame.front === 1
                    cache: false
                    asynchronous: true
                    smooth: view.fit < 0.99
                    onStatusChanged: if (status === Image.Ready && appFrame.wanted === 1) appFrame.front = 1
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    hoverEnabled: true
                    function button(b) { return b === Qt.RightButton ? 3 : b === Qt.MiddleButton ? 2 : 1 }
                    onPressed: (m) => {
                        keys.forceActiveFocus()
                        view.input({ t: "motion", x: Math.round(m.x), y: Math.round(m.y) })
                        view.input({ t: "button", b: button(m.button), down: true })
                    }
                    onReleased: (m) => view.input({ t: "button", b: button(m.button), down: false })
                    onPositionChanged: (m) => view.input({ t: "motion", x: Math.round(Math.max(0, Math.min(width - 1, m.x))), y: Math.round(Math.max(0, Math.min(height - 1, m.y))) })
                    onWheel: (w) => {
                        const steps = Math.max(1, Math.min(10, Math.round(Math.abs(w.angleDelta.y || w.angleDelta.x) / 120)))
                        const b = w.angleDelta.y > 0 ? 4 : w.angleDelta.y < 0 ? 5 : w.angleDelta.x > 0 ? 6 : 7
                        for (let i = 0; i < steps; i++) { view.input({ t: "button", b: b, down: true }); view.input({ t: "button", b: b, down: false }) }
                    }
                }
            }

            // Status bar.
            Item {
                id: statusBar
                visible: view.screenMode !== "off" && view.screenMode !== "boot" && view.insets.top > 0
                width: parent.width
                height: view.insets.top
                readonly property color fg: view.darkTop ? "#ffffff" : "#000000"
                readonly property bool island: view.device.cutout === "island"
                readonly property real ear: (width / 2 - 63) / 2
                readonly property real big: height >= 44 ? 1 : 0.8
                Text {
                    x: statusBar.island ? statusBar.ear - width / 2 + 4 : view.device.tablet ? 20 : (parent.width - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: statusBar.big === 1 ? 3 : 0
                    text: Qt.formatTime(view.now, "h:mm") + (view.device.tablet ? "  " + Qt.formatDate(view.now, "ddd MMM d") : "")
                    color: statusBar.fg
                    font { family: Theme.fontUi; pixelSize: 17 * statusBar.big; weight: Font.DemiBold }
                }
                Row {
                    x: statusBar.island ? parent.width - statusBar.ear - width / 2 - 4 : parent.width - width - 14
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: statusBar.big === 1 ? 3 : 0
                    spacing: 5 * statusBar.big
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1.5
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                anchors.bottom: parent.bottom
                                width: 3 * statusBar.big; height: (4 + 2.5 * index) * statusBar.big; radius: 1
                                color: statusBar.fg
                            }
                        }
                    }
                    Symbol {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "wifi"
                        size: 17 * statusBar.big
                        tone: view.darkTop ? "white" : "dark"
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 27 * statusBar.big; height: 13 * statusBar.big
                        Rectangle {
                            width: parent.width - 2.5; height: parent.height; radius: 4
                            color: "transparent"
                            border { width: 1; color: Qt.rgba(statusBar.fg.r, statusBar.fg.g, statusBar.fg.b, 0.45) }
                            Rectangle { x: 2; y: 2; width: (parent.width - 4) * 0.8; height: parent.height - 4; radius: 2; color: statusBar.fg }
                        }
                        Rectangle { x: parent.width - 1.5; y: parent.height / 2 - 2; width: 1.5; height: 4; radius: 0.75; color: Qt.rgba(statusBar.fg.r, statusBar.fg.g, statusBar.fg.b, 0.45) }
                    }
                }
            }

            // Home indicator: tap it (or press ⇧⌘H) to go home.
            Rectangle {
                visible: view.screenMode !== "off" && view.screenMode !== "boot" && view.insets.bottom > 0 && view.device.cutout !== "home-button"
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 13
                width: Math.min(140, parent.width * 0.35); height: 5; radius: 2.5
                color: view.darkBottom ? "#ffffff" : "#000000"
                TapHandler { margin: 12; onTapped: view.app.simShowingHome = true }
            }

            // Rounded screen corners: bezel-coloured corner pieces over the content.
            Repeater {
                model: view.device.corner > 0 ? [0, 1, 2, 3] : []
                delegate: Shape {
                    id: corner
                    required property int modelData
                    readonly property real r: view.device.corner
                    width: r; height: r
                    x: modelData === 1 || modelData === 2 ? screenItem.width - r : 0
                    y: modelData >= 2 ? screenItem.height - r : 0
                    rotation: [0, 90, 180, 270][modelData]
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "#0b0b0c"
                        strokeColor: "transparent"
                        startX: 0; startY: 0
                        PathLine { x: corner.r; y: 0 }
                        PathArc { x: 0; y: corner.r; radiusX: corner.r; radiusY: corner.r; direction: PathArc.Counterclockwise }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }

        // ---- Camera housing over the screen, rotated with the body.
        Item {
            width: bodyFrame.w; height: bodyFrame.h
            anchors.centerIn: parent
            rotation: view.orientation
            visible: view.device.cutout === "island" && view.screenMode !== "off"
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: view.device.bezelY + 11
                width: 126; height: 37; radius: 18.5
                color: "#000000"
            }
        }
    }

    // Keys go to the app while it's on screen; ⌘ shortcuts stay with the Simulator.
    Item {
        id: keys
        focus: true
        Keys.onPressed: (e) => {
            if (view.screenMode !== "app" || (e.modifiers & Qt.ControlModifier)) return
            view.input({ t: "key", code: e.nativeScanCode, down: true })
            e.accepted = true
        }
        Keys.onReleased: (e) => {
            if (view.screenMode !== "app" || (e.modifiers & Qt.ControlModifier)) return
            view.input({ t: "key", code: e.nativeScanCode, down: false })
            e.accepted = true
        }
    }
}
