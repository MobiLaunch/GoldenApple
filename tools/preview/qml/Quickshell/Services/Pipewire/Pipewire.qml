pragma Singleton
import QtQuick
QtObject {
    id: pw
    property Component node: Component {
        QtObject {
            property string name; property string description; property string nickname
            property bool isSink: true; property bool isStream: false; property bool ready: true
            readonly property QtObject audio: QtObject { property real volume: 0.62; property bool muted: false }
        }
    }
    readonly property var speakers: node.createObject(pw, { name: "alsa_output.speakers", description: "MacBook Pro Speakers", nickname: "Speakers" })
    readonly property var headphones: node.createObject(pw, { name: "bluez_output.airpods", description: "AirPods Pro", nickname: "AirPods Pro" })
    readonly property QtObject nodes: QtObject { readonly property var values: [pw.speakers, pw.headphones] }
    readonly property var defaultAudioSink: speakers
    property var preferredDefaultAudioSink: null
    readonly property bool ready: true
}
