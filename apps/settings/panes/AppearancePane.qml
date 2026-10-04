// Appearance, as on macOS 27: Auto / Light / Dark as little desktops, Liquid
// Glass Clear or Tinted, the accent colour (for GTK apps, the shell and the
// Golden Gate apps alike), and scroll bars.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property string mode: "light"
    property string accent: "blue"
    property bool overlayScroll: true
    Component.onCompleted: {
        sys.sh("cat \"$HOME/.config/golden-gate/appearance.json\" 2>/dev/null", (o) => { try { mode = JSON.parse(o).mode } catch (e) { mode = Theme.dark ? "dark" : "light" } })
        sys.run(["gsettings", "get", "org.gnome.desktop.interface", "accent-color"], (o) => { const m = /'(\w+)'/.exec(o); if (m) accent = m[1] })
        sys.run(["gsettings", "get", "org.gnome.desktop.interface", "overlay-scrolling"], (o) => overlayScroll = o.trim() !== "false")
    }
    function setMode(m) {
        mode = m
        sys.writeJson("appearance.json", { mode: m })
        const dark = m === "dark" || (m === "auto" && (new Date().getHours() < 7 || new Date().getHours() >= 19))
        sys.run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", dark ? "prefer-dark" : "default"])
    }

    component Thumb: Item {
        id: th
        property bool dark: false
        property bool split: false
        property bool chosen: false
        property string label
        signal picked()
        width: 90; height: 80
        Rectangle {
            width: 90; height: 58; radius: 8
            color: "transparent"
            border { width: 3; color: th.chosen ? Theme.accent : "transparent" }
            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: 6; clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#3b6fd8" }
                    GradientStop { position: 1; color: "#8b5cd6" }
                }
                Repeater {
                    model: th.split ? [false, true] : [th.dark]
                    delegate: Item {
                        required property bool modelData
                        required property int index
                        x: th.split ? index * 42 : 0; width: th.split ? 42 : 84; height: 52; clip: true
                        Rectangle {
                            x: (th.split ? -index * 42 : 0) + 16; y: 18; width: 56; height: 30; radius: 4
                            color: modelData ? "#2c2c2e" : "#ffffff"
                            Row { x: 4; y: 4; spacing: 2; Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; delegate: Rectangle { required property string modelData; width: 4; height: 4; radius: 2; color: modelData } } }
                        }
                        Rectangle { x: (th.split ? -index * 42 : 0) + 8; y: 6; width: 34; height: 8; radius: 2; color: Theme.accent; opacity: 0.9 }
                    }
                }
            }
            TapHandler { onTapped: th.picked() }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 62
            text: th.label
            color: th.chosen ? Theme.label : Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12; weight: th.chosen ? Font.Bold : Font.Normal }
        }
    }

    Group {
        SetRow {
            title: "Appearance"
            Thumb { label: "Auto"; split: true; chosen: pane.mode === "auto"; onPicked: pane.setMode("auto") }
            Thumb { label: "Light"; chosen: pane.mode === "light"; onPicked: pane.setMode("light") }
            Thumb { label: "Dark"; dark: true; chosen: pane.mode === "dark"; onPicked: pane.setMode("dark") }
        }
        SetRow {
            title: "Liquid Glass"
            subtitle: "Choose your preferred look for Liquid Glass."
            Repeater {
                model: [{ v: "clear", t: "Clear" }, { v: "tinted", t: "Tinted" }]
                delegate: Item {
                    required property var modelData
                    readonly property bool chosen: (pane.sys.prefs.glass ?? "clear") === modelData.v
                    width: 90; height: 80
                    Rectangle {
                        width: 90; height: 58; radius: 8
                        color: "transparent"
                        border { width: 3; color: parent.chosen ? Theme.accent : "transparent" }
                        Rectangle {
                            anchors { fill: parent; margins: 3 }
                            radius: 6
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#f7c77a" }
                                GradientStop { position: 1; color: "#6aa6f0" }
                            }
                            Glass {
                                anchors.centerIn: parent
                                width: 60; height: 24; radius: 12
                                tint: modelData.v === "clear" ? "#40ffffff" : "#c8f2f2f5"
                                lens: 6
                            }
                        }
                        TapHandler { onTapped: pane.sys.setPref(["glass"], modelData.v) }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter; y: 62
                        text: modelData.t
                        color: parent.chosen ? Theme.label : Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12; weight: parent.chosen ? Font.Bold : Font.Normal }
                    }
                }
            }
        }
    }
    Group {
        title: "Theme"
        SetRow {
            title: "Color"
            Repeater {
                // [gsettings value, colour, name]
                model: [["blue", "#0a84ff", "Blue"], ["purple", "#bf5af2", "Purple"], ["pink", "#ff375f", "Pink"], ["red", "#ff453a", "Red"],
                        ["orange", "#ff9f0a", "Orange"], ["yellow", "#ffd60a", "Yellow"], ["green", "#30d158", "Green"], ["slate", "#8e8e93", "Graphite"]]
                delegate: Item {
                    required property var modelData
                    readonly property bool chosen: pane.accent === modelData[0]
                    width: 26; height: 40
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 26; height: 26; radius: 13
                        color: "transparent"
                        border { width: 2.5; color: parent.chosen ? modelData[1] : "transparent" }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 20; height: 20; radius: 10
                            color: modelData[1]
                            border { width: 0.5; color: "#26000000" }
                            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "#ffffff"; visible: chosen }
                            scale: accentTap.pressed ? 0.85 : 1
                            Behavior on scale { Spring { spring: Theme.bouncy } }
                        }
                        TapHandler {
                            id: accentTap
                            onTapped: { pane.accent = modelData[0]; pane.sys.run(["gsettings", "set", "org.gnome.desktop.interface", "accent-color", modelData[0]]) }
                        }
                    }
                    Text {
                        visible: parent.chosen
                        anchors.horizontalCenter: parent.horizontalCenter; y: 28
                        text: modelData[2]
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                }
            }
        }
    }
    Group {
        title: "Windows"
        SetRow {
            title: "Show scroll bars"
            PopUpButton {
                menuParent: pane.nav.overlay
                options: ["Automatically based on mouse or trackpad", "Always"]
                current: pane.overlayScroll ? 0 : 1
                onPicked: (i) => { pane.overlayScroll = i === 0; pane.sys.run(["gsettings", "set", "org.gnome.desktop.interface", "overlay-scrolling", i === 0 ? "true" : "false"]) }
            }
        }
    }
}
