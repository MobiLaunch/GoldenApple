// A multicolour weather glyph from weather/icons.
import QtQuick

Image {
    property string name: "cloud"
    property real size: 22
    width: size; height: size
    source: name ? Qt.resolvedUrl("icons/" + name + ".svg") : ""
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
}
