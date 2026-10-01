// Shared section label used in first-party Golden Gate sidebars.
import QtQuick
import "theme"

Text {
    property real topSpacing: 14
    leftPadding: 10
    topPadding: topSpacing
    bottomPadding: 4
    color: Theme.secondaryLabel
    font {
        family: Theme.fontUi
        pixelSize: 11
        weight: Font.DemiBold
    }
}
