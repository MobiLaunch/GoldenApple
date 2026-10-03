// A Golden Gate symbol, tinted (the accent colour unless you choose another).
import QtQuick
import ".." as Lib

Box {
    id: root
    property string name: "star"
    property real size: 24
    contentWidth: size
    contentHeight: size

    Lib.Symbol {
        anchors.centerIn: parent
        name: root.name
        size: root.size
        tone: root.foreground === "white" ? "white" : root.foreground === "label" ? "auto" : root.foreground === "secondaryLabel" || root.foreground === "gray" ? "gray"
            : root.foreground === "red" ? "red" : "accent"
        color: root.c(root.foreground || "accent", "#0a84ff")
    }
}
