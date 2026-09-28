// One Setup Assistant step, laid out as on the Mac: a symbol in a blue
// circle, the title and a line of explanation, the step's controls, then
// Back on the left and Continue on the right.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: frame
    property string symbol
    property color symbolColor: Theme.accent
    property string title
    property string text
    property string continueText: "Continue"
    property bool canContinue: true
    property bool canGoBack: true
    property string secondaryText: ""   // e.g. "Set Up Later", left of Continue
    default property alias content: area.data
    signal next()
    signal back()
    signal secondary()

    Column {
        id: head
        anchors.horizontalCenter: parent.horizontalCenter
        y: 40
        width: parent.width - 120
        spacing: 12
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64; height: 64; radius: 32
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(frame.symbolColor, 1.25) }
                GradientStop { position: 1; color: frame.symbolColor }
            }
            Symbol { anchors.centerIn: parent; name: frame.symbol; tone: "white"; size: 32 }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: frame.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: !!frame.text
            text: frame.text
            color: Theme.secondaryLabel
            lineHeight: 1.1
            font { family: Theme.fontUi; pixelSize: 13 }
        }
    }
    Item {
        id: area
        anchors { top: head.bottom; topMargin: 22; left: parent.left; right: parent.right; bottom: buttons.top; bottomMargin: 16; leftMargin: 60; rightMargin: 60 }
    }

    Item {
        id: buttons
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
        height: 32
        Text {
            visible: frame.canGoBack
            anchors.verticalCenter: parent.verticalCenter
            text: "Back"
            color: Theme.accent
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
            TapHandler { onTapped: frame.back() }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 18
            Text {
                visible: !!frame.secondaryText
                anchors.verticalCenter: parent.verticalCenter
                text: frame.secondaryText
                color: Theme.accent
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                TapHandler { onTapped: frame.secondary() }
            }
            Rectangle {
                width: Math.max(104, label.width + 36); height: 30; radius: 15
                color: frame.canContinue ? Theme.accent : (Theme.dark ? "#33ffffff" : "#26000000")
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: frame.continueText
                    color: frame.canContinue ? "#ffffff" : Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                }
                TapHandler { enabled: frame.canContinue; onTapped: frame.next() }
            }
        }
    }
}
