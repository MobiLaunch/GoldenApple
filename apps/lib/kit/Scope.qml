// The top of a Kit tree: its appearance (dark or light), accent colour, named
// colours, font and where its images live, inherited by every box inside.
// Pop-up menus (Picker) open on its overlay.
import QtQuick
import "../theme"

Item {
    id: scope
    property var env: ({})
    readonly property var kenv: Object.assign({ dark: Theme.dark, accent: "", colors: ({}), font: "", assetBase: "" }, env || {},
                                              { overlay: overlay })
    property alias overlay: overlay
    Item {
        id: overlay
        anchors.fill: parent
        z: 1000
    }
}
