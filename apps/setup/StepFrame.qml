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
        y: frame.height < 560 ? 18 : 32
        width: parent.width - 64
        spacing: 12
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: frame.height < 560 ? 44 : 64; height: width; radius: width / 2
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
            font { family: Theme.fontUi; pixelSize: frame.height < 560 ? 22 : 26; weight: Font.Bold }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: !!frame.text
            text: frame.text
            color: Theme.secondaryLabel
            lineHeight: 1.1
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
    }
    Item {
        id: area
        anchors { top: head.bottom; topMargin: 22; left: parent.left; right: parent.right; bottom: buttons.top; bottomMargin: 16; leftMargin: 32; rightMargin: 32 }
    }

    Item {
        id: buttons
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
        height: 32
        Button {
            visible: frame.canGoBack
            anchors.verticalCenter: parent.verticalCenter
            text: "Back"
            onClicked: frame.back()
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12
            Button {
                visible: !!frame.secondaryText
                text: frame.secondaryText
                onClicked: frame.secondary()
            }
            Button {
                text: frame.continueText
                prominent: true
                enabled: frame.canContinue
                onClicked: frame.next()
            }
        }
    }
}
