// Smoked optical-glass intelligence sphere, inspired by a dark lens with a
// grazing prismatic caustic. One lightweight blur for the light band, never a
// backdrop-capture loop. Respects Reduce Motion and works in software mode.
import QtQuick
import QtQuick.Effects
import "theme"

Item {
    id: orb
    property real level: 0
    property string mode: "idle"
    property bool running: visible
    implicitWidth: 214
    implicitHeight: 214
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
    readonly property bool reduceMotion: Theme.reduceMotion
    property real energy: 0
    property real sweep: 0
    FrameAnimation {
        running: orb.running && !orb.reduceMotion
        onTriggered: {
            orb.sweep = (orb.sweep + Math.min(frameTime, 0.05) * (orb.mode === "thinking" ? 0.20 : 0.085)) % 1
            const t = Math.max(0, Math.min(1, orb.level))
            orb.energy += (t - orb.energy) * (t > orb.energy ? 0.24 : 0.055)
        }
    }

    // Outer shadow lives outside the sphere so the centre stays truly black.
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.96; height: width
        radius: width / 2
        color: "#06070d"
        opacity: 0.76
        visible: orb.effects
        layer.enabled: orb.effects
        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.98; shadowColor: "#99000000"; shadowVerticalOffset: 9 }
    }
    Rectangle {
        id: lens
        anchors.centerIn: parent
        width: Math.min(orb.width, orb.height) * 0.94
        height: width
        radius: width / 2
        clip: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#171720" }
            GradientStop { position: 0.18; color: "#06070a" }
            GradientStop { position: 0.72; color: "#020307" }
            GradientStop { position: 1.0; color: "#15161d" }
        }
        // Tiny optical spill, tucked behind the central prismatic stripe.
        Rectangle {
            x: parent.width * 0.10; y: parent.height * (0.49 + 0.025 * Math.sin(orb.sweep * 6.283))
            width: parent.width * 0.80
            height: parent.height * (0.19 + orb.energy * 0.05)
            radius: height / 2
            opacity: orb.mode === "muted" ? 0.15 : 0.47 + orb.energy * 0.17
            rotation: -2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#052c67" }
                GradientStop { position: 0.15; color: "#466dff" }
                GradientStop { position: 0.35; color: "#a4d8ff" }
                GradientStop { position: 0.52; color: "#ffbba4" }
                GradientStop { position: 0.67; color: "#ffedb5" }
                GradientStop { position: 0.83; color: "#a8baff" }
                GradientStop { position: 1; color: "#1b193e" }
            }
            layer.enabled: orb.effects
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.93; blurMax: 22 }
        }
        // Narrow, brighter horizon caustic grazing the middle of the glass.
        Rectangle {
            x: parent.width * 0.11
            y: parent.height * (0.515 + 0.025 * Math.sin(orb.sweep * 6.283 + 0.5))
            width: parent.width * 0.78
            height: Math.max(2, parent.height * 0.037)
            radius: height / 2
            opacity: orb.mode === "error" ? 0.35 : orb.mode === "muted" ? 0.25 : 0.83
            rotation: -1.8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#001a38" }
                GradientStop { position: 0.20; color: "#72b9ff" }
                GradientStop { position: 0.36; color: "#c4d6ff" }
                GradientStop { position: 0.51; color: "#ffeecb" }
                GradientStop { position: 0.64; color: "#ffa9b2" }
                GradientStop { position: 0.81; color: "#91afff" }
                GradientStop { position: 1; color: "#151628" }
            }
            layer.enabled: orb.effects
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.65; blurMax: 10 }
        }
        // Soft internal lower-reflection, like light wrapping around a lens.
        Rectangle {
            x: parent.width * 0.08; y: parent.height * 0.80
            width: parent.width * 0.84; height: parent.height * 0.31
            radius: width * 0.48
            color: "#1e2030"
            opacity: 0.26
            layer.enabled: orb.effects
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.8; blurMax: 22 }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: "#32404a"
            opacity: 0.58
        }
        Rectangle {
            x: parent.width * 0.08; y: parent.height * 0.06
            width: parent.width * 0.84; height: parent.height * 0.20
            radius: width / 2
            color: "#20ffffff"
            opacity: 0.12
            layer.enabled: orb.effects
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.93; blurMax: 25 }
        }
    }
    // Separate glancing rim preserves the glass silhouette without a hard
    // shadow line; visible against bright and dark wallpaper.
    Rectangle {
        anchors.centerIn: parent
        width: lens.width; height: lens.height; radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: "#6b8396"
        opacity: 0.21
    }
    Accessible.role: Accessible.Graphic
    Accessible.name: mode === "listening" ? "Citron Intelligence listening" :
        mode === "thinking" ? "Citron Intelligence processing" : "Citron Intelligence glass orb"
}
