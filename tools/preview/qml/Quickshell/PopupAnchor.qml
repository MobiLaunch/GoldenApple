import QtQuick
QtObject {
    property QtObject window
    property Item item
    readonly property PopupRect rect: PopupRect {}
    property int edges
    property int gravity
    property int adjustment
}
