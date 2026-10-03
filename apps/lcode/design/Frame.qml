// A Golden Gate app window on the designer's canvas: the same chrome the
// built app gets from AppWindow (traffic lights, the floating glass sidebar
// listing the screens, the toolbar row), drawn here in the frame's own
// appearance so light and dark can sit side by side.
import QtQuick
import "../../lib" as Lib
import "../../lib/kit" as Kit
import "../../lib/kit/kit.js" as K
import "../design.js" as Design

Item {
    id: frame
    property var doc: null
    property string screenId: ""
    property bool dark: false
    property var runtime: null
    property string assetBase: ""
    property real frameWidth: 900
    property real frameHeight: 620
    readonly property alias renderer: renderer
    readonly property alias content: content
    signal screenClicked(string id)

    readonly property var app: doc ? doc.app : ({})
    readonly property bool sidebar: app.style === "sidebar"
    readonly property real inset: 8
    readonly property real sidebarWidth: sidebar ? (app.sidebarWidth || 220) : 0
    readonly property var env: doc ? Design.environment(doc, dark, assetBase) : ({ dark: dark })
    readonly property color windowColor: app.background ? K.color(app.background, env, dark ? "#1e1e1e" : "#ffffff") : (dark ? "#1e1e1e" : "#ffffff")
    readonly property color labelColor: dark ? "#ebffffff" : "#e0000000"
    width: frameWidth
    height: frameHeight

    // Window shadow and body.
    Repeater {
        model: 8
        delegate: Rectangle {
            required property int index
            readonly property real s: (index + 1) * 4
            x: -s / 2; y: -s / 2 + 8
            width: frame.width + s; height: frame.height + s
            radius: 22 + s / 2
            color: "#000000"
            opacity: 0.035
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: 22
        color: frame.windowColor
        border { width: 1; color: frame.dark ? "#3dffffff" : "#26000000" }
    }

    // The sidebar: a floating glass panel listing the screens.
    Rectangle {
        visible: frame.sidebar
        x: frame.inset; y: frame.inset
        width: frame.sidebarWidth
        height: frame.height - 2 * frame.inset
        radius: 16
        color: frame.dark ? "#ff2a2a2e" : "#fff0f0f3"
        border { width: 1; color: frame.dark ? "#1affffff" : "#14000000" }
        Column {
            x: 8; y: 52
            width: parent.width - 16
            spacing: 2
            Repeater {
                model: frame.doc ? frame.doc.screens : []
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool selected: frame.runtime && frame.runtime.screen === modelData.id
                    width: parent.width
                    height: 28
                    radius: 7
                    color: selected ? (frame.dark ? "#1fffffff" : "#14000000") : "transparent"
                    Lib.Symbol {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.modelData.symbol || "doc"
                        size: 15
                        tone: "accent"
                        color: K.color("accent", frame.env)
                    }
                    Text {
                        x: 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.title || row.modelData.id
                        color: frame.labelColor
                        font { family: "SF Pro Text"; pixelSize: 13; weight: row.selected ? Font.DemiBold : Font.Normal }
                    }
                    TapHandler { onTapped: frame.screenClicked(row.modelData.id) }
                }
            }
        }
    }

    // Traffic lights.
    Row {
        x: frame.inset + 12; y: 20
        spacing: 8
        Repeater {
            model: ["#ff5f57", "#febc2e", "#28c840"]
            delegate: Rectangle {
                required property string modelData
                width: 12; height: 12; radius: 6
                color: modelData
                border { width: 0.5; color: "#26000000" }
            }
        }
    }
    // Back, for multi-screen apps without a sidebar.
    Rectangle {
        visible: !frame.sidebar && frame.runtime && frame.runtime.backStack.length > 0
        x: 92; y: 10
        width: 32; height: 32; radius: 16
        color: frame.dark ? "#1affffff" : "#0d000000"
        Lib.Symbol { anchors.centerIn: parent; name: "chevron-left"; size: 14; tone: frame.dark ? "white" : "dark" }
        TapHandler { onTapped: frame.runtime.back() }
    }

    // The content: the screen, as the app will draw it.
    Kit.Scope {
        id: content
        x: frame.sidebar ? frame.inset + frame.sidebarWidth : 0
        y: 52                                  // under the toolbar row, as in AppWindow
        width: frame.width - x
        height: frame.height - y
        env: frame.env
        clip: true
        Renderer {
            id: renderer
            anchors.fill: parent
            doc: frame.doc
            screenId: frame.screenId
            runtime: frame.runtime
        }
        Kit.AlertHost { app: frame.runtime }
    }
}
