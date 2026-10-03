// Pick a colour: a system colour (they adapt to light and dark), one of the
// app's named colours, or any colour at all (hue, saturation, brightness,
// opacity, or hex).
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit/kit.js" as K

Popover {
    id: picker
    property var doc: null
    property string value: ""
    property bool allowNone: true
    property bool customOnly: false            // named colours' light/dark values are plain hex
    property int page: 0
    signal picked(string value)
    panelWidth: 292

    // Custom colour state.
    property real hue: 0.6
    property real sat: 0.8
    property real val: 1
    property real alphaValue: 1
    readonly property color custom: Qt.hsva(hue, sat, val, alphaValue)
    readonly property string customHex: {
        const c = custom
        const h = (n) => Math.round(n * 255).toString(16).padStart(2, "0")
        return "#" + (alphaValue < 0.999 ? h(c.a) : "") + h(c.r) + h(c.g) + h(c.b)
    }
    readonly property var env: {
        const colors = {}
        for (const c of (doc ? doc.colors || [] : [])) colors[c.name] = c
        return { dark: Theme.dark, accent: doc ? doc.app.accent : "", colors: colors }
    }

    function show(from, x, y, current) {
        value = current || ""
        page = customOnly ? 2 : K.isHex(value) ? 2 : (doc && (doc.colors || []).some((c) => c.name === value)) ? 1 : 0
        const c = Qt.color(K.color(value || "accent", env))
        hue = Math.max(0, c.hsvHue); sat = c.hsvSaturation; val = c.hsvValue; alphaValue = c.a
        hexField.text = K.isHex(value) ? value : ""
        openAt(from, x, y)
    }
    function setCustom() { hexField.text = customHex; picked(customHex) }

    Column {
        width: parent.width
        spacing: 10
        Segmented {
            visible: !picker.customOnly
            anchors.horizontalCenter: parent.horizontalCenter
            options: ["System", "App", "Custom"]
            current: picker.page
            onPicked: (i) => picker.page = i
        }

        // System colours.
        Grid {
            visible: picker.page === 0 && !picker.customOnly
            columns: 7
            spacing: 6
            Repeater {
                model: (picker.allowNone ? [""] : []).concat(K.SYSTEM_NAMES)
                delegate: Item {
                    required property string modelData
                    width: 34; height: 34
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26; height: 26; radius: 13
                        color: parent.modelData ? K.color(parent.modelData, picker.env) : "transparent"
                        border { width: picker.value === parent.modelData ? 2.5 : 0.5; color: picker.value === parent.modelData ? Theme.accent : "#33000000" }
                        Text {
                            visible: !parent.parent.modelData
                            anchors.centerIn: parent
                            text: "∅"
                            color: Theme.secondaryLabel
                            font.pixelSize: 13
                        }
                    }
                    HoverHandler { id: swatchHover }
                    TapHandler { onTapped: { picker.value = parent.modelData; picker.picked(parent.modelData) } }
                    Rectangle {
                        visible: swatchHover.hovered
                        z: 5
                        y: -22
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: tip.implicitWidth + 12; height: 20; radius: 6
                        color: Theme.dark ? "#3a3a3c" : "#2c2c2e"
                        Text { id: tip; anchors.centerIn: parent; text: parent.parent.modelData || "Default"; color: "white"; font.pixelSize: 10 }
                    }
                }
            }
        }

        // The app's named colours.
        Column {
            visible: picker.page === 1 && !picker.customOnly
            width: parent.width
            spacing: 4
            Text {
                visible: !picker.doc || !(picker.doc.colors || []).length
                width: parent.width
                wrapMode: Text.Wrap
                text: "Your app's own colours appear here. Add one in the outline's Colors section."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Repeater {
                model: picker.doc ? picker.doc.colors : []
                delegate: SidebarRow {
                    required property var modelData
                    width: parent.width
                    height: 28
                    text: modelData.name
                    selected: picker.value === modelData.name
                    leadingSize: 18
                    leading: Component {
                        Rectangle {
                            width: 18; height: 18; radius: 5
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.49; color: modelData.light }
                                GradientStop { position: 0.51; color: modelData.dark }
                            }
                        }
                    }
                    onClicked: { picker.value = modelData.name; picker.picked(modelData.name) }
                }
            }
        }

        // Any colour.
        Column {
            visible: picker.page === 2 || picker.customOnly
            width: parent.width
            spacing: 10
            Rectangle {
                id: square
                width: parent.width
                height: 150
                radius: 8
                color: Qt.hsva(picker.hue, 1, 1, 1)
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "#00ffffff" } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    gradient: Gradient { GradientStop { position: 0; color: "#00000000" } GradientStop { position: 1; color: "black" } }
                }
                Rectangle {
                    x: picker.sat * parent.width - 7
                    y: (1 - picker.val) * parent.height - 7
                    width: 14; height: 14; radius: 7
                    color: "transparent"
                    border { width: 2; color: "white" }
                }
                MouseArea {
                    anchors.fill: parent
                    function set(m) {
                        picker.sat = Math.max(0, Math.min(1, m.x / width))
                        picker.val = Math.max(0, Math.min(1, 1 - m.y / height))
                        picker.setCustom()
                    }
                    onPressed: (m) => set(m)
                    onPositionChanged: (m) => { if (pressed) set(m) }
                }
            }
            // Hue.
            Rectangle {
                width: parent.width
                height: 14
                radius: 7
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#ff0000" }
                    GradientStop { position: 0.17; color: "#ffff00" }
                    GradientStop { position: 0.33; color: "#00ff00" }
                    GradientStop { position: 0.5; color: "#00ffff" }
                    GradientStop { position: 0.67; color: "#0000ff" }
                    GradientStop { position: 0.83; color: "#ff00ff" }
                    GradientStop { position: 1.0; color: "#ff0000" }
                }
                Rectangle {
                    x: picker.hue * parent.width - 8; y: -2
                    width: 16; height: 18; radius: 8
                    color: Qt.hsva(picker.hue, 1, 1, 1)
                    border { width: 2; color: "white" }
                }
                MouseArea {
                    anchors.fill: parent
                    function set(m) { picker.hue = Math.max(0, Math.min(0.999, m.x / width)); picker.setCustom() }
                    onPressed: (m) => set(m)
                    onPositionChanged: (m) => { if (pressed) set(m) }
                }
            }
            // Opacity.
            Rectangle {
                width: parent.width
                height: 14
                radius: 7
                color: "#d0d0d4"
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.hsva(picker.hue, picker.sat, picker.val, 0) }
                        GradientStop { position: 1; color: Qt.hsva(picker.hue, picker.sat, picker.val, 1) }
                    }
                }
                Rectangle {
                    x: picker.alphaValue * parent.width - 8; y: -2
                    width: 16; height: 18; radius: 8
                    color: "white"
                    border { width: 1; color: "#40000000" }
                }
                MouseArea {
                    anchors.fill: parent
                    function set(m) { picker.alphaValue = Math.max(0, Math.min(1, m.x / width)); picker.setCustom() }
                    onPressed: (m) => set(m)
                    onPositionChanged: (m) => { if (pressed) set(m) }
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    width: 30; height: 28; radius: 6
                    color: picker.custom
                    border { width: 0.5; color: "#33000000" }
                }
                TextField {
                    id: hexField
                    width: 150
                    height: 28
                    placeholder: "#RRGGBB"
                    onAccepted: {
                        const t = text.trim().startsWith("#") ? text.trim() : "#" + text.trim()
                        if (!K.isHex(t)) return
                        const c = Qt.color(t)
                        picker.hue = Math.max(0, c.hsvHue); picker.sat = c.hsvSaturation; picker.val = c.hsvValue; picker.alphaValue = c.a
                        picker.picked(t)
                    }
                }
            }
        }
    }
}
