import QtQuick
// Registers with the harness, which calls its functions (qs ipc call …).
QtObject {
    id: h
    property string target
    property bool enabled: true
    Component.onCompleted: __preview.registerIpc(h)
}
