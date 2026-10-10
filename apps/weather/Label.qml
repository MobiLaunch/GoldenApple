// Card text: white Inter at a size (px), weight (w) and opacity (alpha).
import QtQuick
import "../lib/theme"

Text {
    property real px: 13
    property int w: Font.Medium
    property real alpha: 1
    color: Qt.rgba(1, 1, 1, alpha)
    font.family: Theme.fontUi
    font.pixelSize: px
    font.weight: w
    wrapMode: Text.WordWrap
}
