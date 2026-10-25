// Calculator's own palette. The Mac's Calculator is dark in Light Mode too,
// in a graphite of its own rather than the system's window colours, so these
// stay fixed: the window, the keys, the labels and fills over them.
pragma Singleton
import QtQuick

QtObject {
    readonly property color window: "#24292d"
    readonly property color chrome: "#191d20"           // the toolbar buttons' glass
    readonly property color menu: "#fa2c2f33"

    readonly property color label: "#ffffff"
    readonly property color secondaryLabel: "#9a9c9d"
    readonly property color tertiaryLabel: "#6d7174"    // a bit that's off
    readonly property color mutedLabel: "#b0b3b5"       // a muted unit button
    readonly property color disabledLabel: "#66ffffff"

    readonly property color fill: "#1fffffff"
    readonly property color fillHover: "#33ffffff"
    readonly property color control: "#24ffffff"
    readonly property color controlMuted: "#14ffffff"
    readonly property color hairline: "#33ffffff"
    readonly property color separator: "#26ffffff"

    readonly property color orange: "#ff9500"
    readonly property color keyDigit: "#464a4c"
    readonly property color keyFunction: "#717577"
    readonly property color keyLit: "#c9cbcd"           // a switch that's on (2nd, Rad)
    readonly property color inkOnLit: "#1c1c1e"
}
