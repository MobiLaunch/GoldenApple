// Citron's own look: smoky indigo glass over the desktop, its chips and round
// buttons, the deep blue of a live microphone and a ready Send, and the pale
// link and error tints that read on it. Its text is the system's vibrant
// labels (Theme.vibrant), the same in Light and Dark, as the glass is.
pragma Singleton
import QtQuick

QtObject {
    readonly property color answer: "#e9171b26"         // the response, unfolded
    readonly property color answerShadow: "#44000000"
    readonly property color composer: "#e81c202a"       // the capsule you type in
    readonly property color composerShadow: "#5c000000"
    readonly property color field: "#dc121620"          // text to rewrite, the attached photo
    readonly property color fieldBorder: "#35ffffff"
    readonly property color chip: "#b71a1d27"
    readonly property color chipBorder: "#37c2cbd9"
    readonly property color chipOn: "#db34415a"
    readonly property color chipOnBorder: "#7f9fbb"
    readonly property color button: "#30ffffff"
    readonly property color live: "#b01b4576"           // the microphone, listening
    readonly property color send: "#15579a"             // Send, with something to send
    readonly property color link: "#b8d7ff"
    readonly property color error: "#ffd0ce"
    readonly property color selection: "#5a79a9"
}
