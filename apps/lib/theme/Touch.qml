pragma Singleton
// This theme singleton must be plain Qt Quick: standalone PySide6 apps such as
// CitronOS Web import the same theme as the Quickshell desktop. Importing
// Quickshell here makes even Symbol/Glass fail to instantiate in those apps.
// A running first-party AppWindow updates this on its tablet preference changes.
import QtQuick

QtObject {
    id: touch
    property bool enabled: false
}
