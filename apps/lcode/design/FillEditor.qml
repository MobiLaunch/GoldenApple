// A fill for a box's background: none, a colour, a gradient (stops, angle,
// radial, or a preset), Liquid Glass, or an image.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/kit.js" as K

Column {
    id: fe
    property var inspector: null
    property var value: null
    signal commit(var value)
    spacing: 6
    readonly property string type: K.fillType(value)
    readonly property var env: inspector ? inspector.colorPickerEnv() : ({})
    readonly property var presets: [
        ["accent", "purple"], ["#ff9f0a", "#ff375f"], ["#30d158", "#40c8e0"], ["#5e5ce6", "#bf5af2"],
        ["#ffd60a", "#ff9f0a"], ["#1c1c1e", "#3a3a3c"], ["#64d2ff", "#0a84ff"], ["#ff6b9a", "#ffb36b"],
    ]
    function patch(p) { commit(Object.assign({}, value || {}, p)) }

    PopUpButton {
        options: ["None", "Color", "Gradient", "Glass", "Image"]
        current: ["none", "color", "gradient", "material", "image"].indexOf(fe.type)
        menuParent: fe.inspector ? fe.inspector.overlay : null
        onPicked: (i) => fe.commit([null,
            { type: "color", color: "accent" },
            { type: "gradient", colors: ["accent", "purple"], angle: 135 },
            { type: "material", material: "regular" },
            { type: "image", source: "", fit: "fill" }][i])
    }

    // A colour.
    Rectangle {
        id: colorWell
        visible: fe.type === "color"
        width: fe.width
        height: 24
        radius: 6
        color: Theme.dark ? "#1affffff" : "#ffffff"
        border { width: 0.5; color: Theme.separator }
        Rectangle {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 16; radius: 4
            color: fe.type === "color" ? K.color(fe.value.color, fe.env) : "transparent"
            border { width: 0.5; color: "#33000000" }
        }
        Text {
            x: 40; anchors.verticalCenter: parent.verticalCenter
            text: fe.type === "color" ? String(fe.value.color) : ""
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 11 }
        }
        TapHandler { onTapped: fe.inspector.pickColor(colorWell, fe.value.color, (v) => fe.patch({ color: v || "accent" })) }
    }

    // A gradient.
    Column {
        visible: fe.type === "gradient"
        width: fe.width
        spacing: 6
        Row {
            spacing: 4
            Repeater {
                model: fe.type === "gradient" ? fe.value.colors || [] : []
                delegate: Rectangle {
                    id: stop
                    required property var modelData
                    required property int index
                    width: 24; height: 24; radius: 12
                    color: K.color(modelData, fe.env)
                    border { width: 1; color: "#40000000" }
                    TapHandler {
                        onTapped: fe.inspector.pickColor(stop, stop.modelData, (v) => {
                            const cs = fe.value.colors.slice(); cs[stop.index] = v || "accent"; fe.patch({ colors: cs })
                        })
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: if (fe.value.colors.length > 2) { const cs = fe.value.colors.slice(); cs.splice(stop.index, 1); fe.patch({ colors: cs }) }
                    }
                }
            }
            ToolbarButton {
                visible: fe.type === "gradient" && (fe.value.colors || []).length < 5
                height: 24
                symbol: "plus"
                symbolSize: 11
                Accessible.name: "Add a color stop"
                onClicked: fe.patch({ colors: (fe.value.colors || []).concat(["white"]) })
            }
        }
        Row {
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Angle"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            TextField {
                width: 54; height: 24
                text: fe.type === "gradient" ? String(fe.value.angle || 0) : ""
                onAccepted: { const n = parseFloat(text); if (!isNaN(n)) fe.patch({ angle: ((n % 360) + 360) % 360 }) }
            }
            ToolbarButton { height: 24; text: "↻"; onClicked: fe.patch({ angle: ((+fe.value.angle || 0) + 45) % 360 }) }
            Checkbox { width: 70; text: "Radial"; checked: fe.type === "gradient" && !!fe.value.radial; onToggled: (c) => fe.patch({ radial: c }) }
        }
        Flow {
            width: fe.width
            spacing: 4
            Repeater {
                model: fe.presets
                delegate: Rectangle {
                    required property var modelData
                    width: 26; height: 18; radius: 5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: K.color(modelData[0], fe.env) }
                        GradientStop { position: 1; color: K.color(modelData[1], fe.env) }
                    }
                    TapHandler { onTapped: fe.patch({ colors: parent.modelData.slice() }) }
                }
            }
        }
    }

    // Liquid Glass.
    PopUpButton {
        visible: fe.type === "material"
        options: ["Regular", "Thin", "Thick", "Clear"]
        current: fe.type === "material" ? Math.max(0, ["regular", "thin", "thick", "clear"].indexOf(fe.value.material)) : 0
        menuParent: fe.inspector ? fe.inspector.overlay : null
        onPicked: (i) => fe.patch({ material: ["regular", "thin", "thick", "clear"][i] })
    }

    // An image.
    Rectangle {
        id: imageWell
        visible: fe.type === "image"
        width: fe.width
        height: 24
        radius: 6
        color: Theme.dark ? "#1affffff" : "#ffffff"
        border { width: 0.5; color: Theme.separator }
        Text {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 16
            elide: Text.ElideMiddle
            text: fe.type === "image" && fe.value.source ? fe.value.source : "Choose Image…"
            color: fe.type === "image" && fe.value.source ? Theme.label : Theme.tertiaryLabel
            font { family: Theme.fontUi; pixelSize: 11 }
        }
        TapHandler { onTapped: fe.inspector.pickImage(imageWell, fe.value.source, (v) => fe.patch({ source: v })) }
    }
    Segmented {
        visible: fe.type === "image"
        options: ["Fill", "Fit"]
        current: fe.type === "image" && fe.value.fit === "fit" ? 1 : 0
        onPicked: (i) => fe.patch({ fit: i ? "fit" : "fill" })
    }
}
