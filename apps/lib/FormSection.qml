// Rows on a rounded card, as System Settings groups them, with an optional
// heading above and a note below.
//   FormSection {
//       title: "Battery"; footer: "Shown in the menu bar."
//       FormRow { title: "Show percentage"; Switch { … } }
//   }
import QtQuick
import "theme"

Item {
    id: section
    default property alias rows: col.data
    property string title
    property string footer
    width: parent ? parent.width : 500
    implicitHeight: card.y + card.height + (footer ? note.implicitHeight + 8 : 0)
    height: implicitHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: title

    Text {
        id: heading
        visible: !!section.title
        x: 4; y: 4
        text: section.title
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize; weight: Font.Bold }
    }
    Rectangle {
        id: card
        y: section.title ? heading.implicitHeight + 12 : 0
        width: parent.width; height: col.height
        radius: Theme.radius.menu
        color: Theme.groupedCard
        border { width: 0.75; color: Theme.groupedCardBorder }
        Column { id: col; width: parent.width }
    }
    Text {
        id: note
        visible: !!section.footer
        anchors { top: card.bottom; topMargin: 6; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
        text: section.footer
        wrapMode: Text.Wrap
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.font.footnote.pixelSize }
    }
}
