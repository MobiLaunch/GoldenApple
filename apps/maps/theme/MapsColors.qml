// What Maps lays over the map: the panel, the round controls and the toast,
// solid enough to read over any tiles, and the fills inside the panel. The
// colours that mean something (a route, a destination, a favourite) are the
// system's (Theme.system); the map's own palette is in maps/api.js.
pragma Singleton
import QtQuick
import "../../lib/theme"

QtObject {
    readonly property bool dark: Theme.dark

    readonly property color panel: dark ? "#eb28282b" : "#f0f6f6f8"
    readonly property color panelShadow: "#1a000000"
    readonly property color hud: dark ? "#e62c2c2e" : "#f2ffffff"      // the map controls, the toast
    readonly property color card: dark ? "#14ffffff" : "#ffffff"       // on the panel: details, from/to, routes
    readonly property color control: dark ? "#1fffffff" : "#e5e5ea"    // round actions, travel modes
}
