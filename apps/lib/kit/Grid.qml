// Boxes in rows of `columns`, each column the same width.
import QtQuick
import QtQuick.Layouts

Box {
    id: grid
    property int columns: 2
    property real spacing: 12
    property real rowSpacing: -1              // -1: same as spacing
    property string alignment: "center"
    default property alias items: layout.data
    readonly property Item contentContainer: layout   // where the App Designer adds children
    contentWidth: layout.implicitWidth
    contentHeight: layout.implicitHeight

    GridLayout {
        id: layout
        readonly property string kitAxis: "grid"
        readonly property string kitAlign: grid.alignment
        readonly property var kenv: grid.kenv
        columns: Math.max(1, grid.columns)
        columnSpacing: grid.spacing
        rowSpacing: grid.rowSpacing >= 0 ? grid.rowSpacing : grid.spacing
        uniformCellWidths: true
        width: grid.innerWidth
        height: Math.min(grid.innerHeight, implicitHeight)
    }
}
