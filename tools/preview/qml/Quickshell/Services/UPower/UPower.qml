pragma Singleton
import QtQuick
QtObject {
    readonly property QtObject displayDevice: QtObject {
        readonly property bool isLaptopBattery: true; readonly property bool ready: true
        readonly property real percentage: 0.82; readonly property int state: 2
        readonly property real timeToEmpty: 18000; readonly property real timeToFull: 0
    }
    readonly property bool onBattery: true
}
