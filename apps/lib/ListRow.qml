// A row in a list or a grouped form: an icon, a title and subtitle, and on
// the right whatever it holds (a value, a switch) or a chevron when it leads
// somewhere. Rows separate with a hairline that starts at the text.
//   FormSection { ListRow { title: "Wi-Fi"; symbol: "wifi"; chevron: true; onClicked: open("wifi") } }
// A row that does something (chevron, selectable) takes focus with Tab and
// acts on Space or Return; it shows a press, a hover and its selection.
import QtQuick
import "theme"

Item {
    id: row
    property string title
    property string subtitle
    property string symbol
    property color symbolColor: "transparent"   // a glyph tinted; otherwise the label's colour
    property string image                       // an app's icon, in place of a symbol
    readonly property bool hasIcon: !!symbol || !!image
    property bool chevron: false
    property bool selectable: false
    property bool selected: false
    readonly property bool activatable: (chevron || selectable) && enabled
    property bool first: index === 0
    readonly property int index: {
        const kids = parent ? parent.children : []
        for (let i = 0; i < kids.length; i++) if (kids[i] === row) return i
        return 0
    }
    default property alias trailing: slot.data
    readonly property alias trailingItem: slot
    signal clicked()

    width: parent ? parent.width : 400
    height: Math.max(Theme.fh(subtitle ? 50 : 40), slot.childrenRect.height + 16, labels.implicitHeight + 18)
    activeFocusOnTab: chevron || selectable
    Accessible.role: chevron ? Accessible.Button : selectable ? Accessible.ListItem : Accessible.StaticText
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.selectable: selectable
    Accessible.selected: selected
    Accessible.onPressAction: if (activatable) clicked()
    Keys.onSpacePressed: (event) => { if (activatable && !event.isAutoRepeat) clicked() }
    Keys.onReturnPressed: if (activatable) clicked()
    Keys.onEnterPressed: if (activatable) clicked()
    FocusRing { visible: row.activeFocus }
    opacity: enabled ? 1 : 0.5

    Rectangle {
        visible: !row.first
        x: row.hasIcon ? 50 : 14; width: parent.width - x - 14; height: 0.5
        color: Theme.separator
    }
    Rectangle {
        anchors { fill: parent; margins: 3 }
        radius: Theme.radius.field
        color: row.selected ? Theme.unemphasizedSelection : Theme.label
        opacity: row.selected ? 1 : row.activatable ? (tap.pressed ? 0.08 : hover.hovered ? 0.04 : 0) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.motion.tap.ms / 2 } }
    }
    Symbol {
        visible: !!row.symbol && !row.image
        x: 18; anchors.verticalCenter: parent.verticalCenter
        name: row.symbol; size: 18
        color: row.symbolColor
    }
    Image {
        visible: !!row.image
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28
        sourceSize: Qt.size(56, 56)
        source: row.image
    }
    Column {
        id: labels
        x: row.hasIcon ? 50 : 14
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - slot.width - 30
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
        }
        Text {
            visible: !!row.subtitle
            width: parent.width; wrapMode: Text.WordWrap
            text: row.subtitle
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.font.subheadline.pixelSize }
        }
    }
    Row {
        id: slot
        anchors { right: parent.right; rightMargin: row.chevron ? 32 : 14; verticalCenter: parent.verticalCenter }
        spacing: 8
    }
    Symbol {
        visible: row.chevron
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        name: "chevron-right"; tone: "gray"; size: 12
    }
    HoverHandler { id: hover; enabled: row.activatable }
    TapHandler { id: tap; enabled: row.activatable; onTapped: { row.forceActiveFocus(); row.clicked() } }
}
