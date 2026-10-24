pragma Singleton
import QtQuick
QtObject {
    id: bt
    property Component device: Component {
        QtObject {
            property string name; property string deviceName; property string address; property string icon
            property bool connected; property bool paired: true; property bool trusted: true; property real battery: 0.8
            property bool batteryAvailable: true
            function connect() {} function disconnect() {} function pair() {} function forget() {}
        }
    }
    readonly property var list: [
        device.createObject(bt, { name: "AirPods Pro", deviceName: "AirPods Pro", address: "AA:BB:CC:00:11:22", icon: "audio-headphones", connected: true }),
        device.createObject(bt, { name: "Magic Keyboard", deviceName: "Magic Keyboard", address: "AA:BB:CC:00:11:33", icon: "input-keyboard", connected: false }),
        device.createObject(bt, { name: "Jordan's iPhone", deviceName: "iPhone", address: "AA:BB:CC:00:11:44", icon: "phone", connected: false })
    ]
    readonly property QtObject devices: QtObject { readonly property var values: bt.list }
    readonly property QtObject defaultAdapter: QtObject {
        property bool enabled: true; property bool discovering: false; property bool discoverable: false; property string name: "golden-gate"
        readonly property QtObject devices: QtObject { readonly property var values: bt.list }
    }
    readonly property QtObject adapters: QtObject { readonly property var values: [bt.defaultAdapter] }
}
