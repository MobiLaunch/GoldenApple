// A small card: a big value, an optional line under it, and a note at the bottom.
import QtQuick

Card {
    id: card
    property string value
    property string detail
    property string note
    default property alias extra: slot.data

    Label { y: 2; text: card.value; px: 30; w: Font.Normal; wrapMode: Text.NoWrap }
    Label { y: 38; visible: !!card.detail; text: card.detail; px: 17; w: Font.DemiBold; width: parent.width }
    Item { id: slot; anchors.fill: parent }
    Label {
        anchors.bottom: parent.bottom
        width: parent.width
        text: card.note; px: 12; w: Font.Medium; lineHeight: 0.95
    }
}
