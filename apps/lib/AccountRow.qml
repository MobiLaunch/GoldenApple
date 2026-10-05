// Shared local-account identity row for CitronOS sidebars.
import QtQuick
import "theme"

Item {
    id: row
    property string name: ""
    property string subtitle: ""
    property bool clickable: false
    signal clicked()

    implicitWidth: 180
    implicitHeight: subtitle ? 54 : 38
    activeFocusOnTab: clickable
    Accessible.role: clickable ? Accessible.Button : Accessible.StaticText
    Accessible.name: subtitle ? name + ", " + subtitle : name
    Keys.onSpacePressed: if (clickable) clicked()
    Keys.onReturnPressed: if (clickable) clicked()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: clickable && hover.hovered
            ? (Theme.dark ? "#10ffffff" : "#08000000")
            : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 90 } }
    }

    Rectangle {
        id: avatar
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        width: row.subtitle ? 36 : 26
        height: width
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: "#a1a1a6" }
            GradientStop { position: 1; color: "#6e6e73" }
        }
        scale: !Theme.reduceMotion && tap.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 75; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: row.name.split(" ").filter((w) => w.length).map((w) => w.charAt(0)).join("").slice(0, 2).toUpperCase()
            color: "#ffffff"
            font {
                family: Theme.fontUi
                pixelSize: row.subtitle ? 14 : 10
                weight: Font.DemiBold
            }
        }
    }

    Column {
        x: row.subtitle ? 50 : 40
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - 8
        spacing: 2

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: row.name
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            visible: !!row.subtitle
            width: parent.width
            elide: Text.ElideRight
            text: row.subtitle
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11 }
        }
    }

    HoverHandler { id: hover; enabled: row.clickable }
    TapHandler {
        id: tap
        enabled: row.clickable
        onTapped: {
            row.forceActiveFocus()
            row.clicked()
        }
    }
}
