// Space between groups of rows, with a hairline.
import QtQuick
import "../../lib/theme"

Item {
    width: parent ? parent.width : 400
    height: 17
    Rectangle { y: 8; width: parent.width; height: 1; color: Theme.separator }
}
