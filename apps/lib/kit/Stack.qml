// A row or column of boxes (VStack and HStack). alignment places boxes across
// the stack (leading/center/trailing in a column, top/center/bottom in a row);
// justify places the whole group along it when nothing fills the stack.
import QtQuick
import QtQuick.Layouts
import "kit.js" as K

Box {
    id: stack
    property bool vertical: true
    property real spacing: 8
    property string alignment: "center"
    property string justify: "start"          // start | center | end
    default property alias items: layout.data
    readonly property Item contentContainer: layout   // where the App Designer adds children

    // Does something in the stack (a Spacer, or a box framed "fill") take up the slack?
    readonly property bool filled: {
        for (const c of layout.children)
            if (c.visible && (vertical ? c.Layout.fillHeight : c.Layout.fillWidth)) return true
        return false
    }
    contentWidth: layout.implicitWidth
    contentHeight: layout.implicitHeight

    GridLayout {
        id: layout
        readonly property string kitAxis: stack.vertical ? "v" : "h"
        readonly property string kitAlign: stack.alignment
        readonly property var kenv: stack.kenv
        flow: stack.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columns: stack.vertical ? 1 : -1
        rows: stack.vertical ? -1 : 1
        rowSpacing: stack.spacing
        columnSpacing: stack.spacing
        width: stack.vertical || stack.filled ? stack.innerWidth : Math.min(stack.innerWidth, implicitWidth)
        height: !stack.vertical || stack.filled ? stack.innerHeight : Math.min(stack.innerHeight, implicitHeight)
        x: stack.vertical || stack.filled ? 0 : K.place(stack.justify, stack.innerWidth, width)
        y: !stack.vertical || stack.filled ? 0 : K.place(stack.justify, stack.innerHeight, height)
    }
}
