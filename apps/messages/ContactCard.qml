// Native macOS-style contact information card shared by Messages threads.
// Real actions only: composing a message, WebRTC video invite and FaceTime URL.
import QtQuick
import QtQuick.Layouts
import "../lib"
import "../lib/theme"

Item {
    id: card
    property var contact: null
    property bool shown: false
    property string address: ""
    signal messageRequested()
    signal videoRequested()
    signal faceTimeRequested()
    signal copyRequested(string value)
    width: parent ? parent.width : 600
    height: parent ? parent.height : 500
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 70
    Behavior on opacity { enabled: !Theme.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Accessible.role: Accessible.Dialog
    Accessible.name: "Contact details"

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#99000000" : "#57000000"
        TapHandler { onTapped: card.shown = false }
    }
    Glass {
        id: panel
        anchors.centerIn: parent
        role: "menu"
        width: Math.min(390, card.width - 36)
        height: Math.min(452, card.height - 30)
        radius: 26
        scale: card.shown ? 1 : 0.97
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        ColumnLayout {
            anchors { fill: parent; leftMargin: 22; rightMargin: 22; topMargin: 18; bottomMargin: 18 }
            spacing: 9
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ToolbarButton { symbol: "xmark"; round: true; onClicked: card.shown = false }
            }
            Avatar {
                Layout.alignment: Qt.AlignHCenter
                name: card.contact?.name ?? ""
                group: !!card.contact?.is_group
                photoPath: card.contact?.photo_path || card.contact?.contact_photo_path || ""
                size: 94
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                text: card.contact?.name ?? "Contact"
                color: Theme.label
                elide: Text.ElideRight
                font { family: Theme.fontDisplay; pixelSize: Theme.fs(24); weight: Font.DemiBold }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: card.contact?.is_group ? "Group Conversation" : card.address.includes("@") ? "Email" : "Mobile"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button { Layout.fillWidth: true; text: "Message"; onClicked: { card.shown = false; card.messageRequested() } }
                Button { Layout.fillWidth: true; text: "Video"; onClicked: { card.shown = false; card.videoRequested() } }
                Button { Layout.fillWidth: true; text: "FaceTime Link"; onClicked: { card.shown = false; card.faceTimeRequested() } }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.separator
                Layout.topMargin: 5
            }
            Text { text: card.contact?.is_group ? "Participants" : "Contact Information"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium } }
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: contactInfo.height
                clip: true
                Column {
                    id: contactInfo
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: card.contact?.is_group ? (card.contact?.recipients ?? []) : card.address ? [card.address] : []
                        delegate: Rectangle {
                            required property var modelData
                            width: contactInfo.width
                            height: 46
                            radius: 10
                            color: Theme.fill
                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                spacing: 8
                                Symbol { name: String(modelData).includes("@") ? "envelope" : "phone"; size: 16; tone: "gray"; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    width: contactInfo.width - 96
                                    text: String(modelData)
                                    elide: Text.ElideMiddle
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                }
                            }
                            ToolbarButton { anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }; symbol: "copy"; round: true; onClicked: card.copyRequested(String(modelData)) }
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "Contact details synchronized from your iPhone."
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            }
        }
    }
}
