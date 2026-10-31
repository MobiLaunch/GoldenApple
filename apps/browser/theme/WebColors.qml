// Web's own chrome, as Safari draws its own: the window, toolbar, tab bar,
// Smart Search field and sidebar (each with the warmer tint of a private
// window), the page behind a loading site, and the panels Web puts over it.
// Hovers, selections, list fills and labels are the system's (Theme).
pragma Singleton
import QtQuick
import "../../lib/theme"

QtObject {
    readonly property bool dark: Theme.dark

    readonly property color window: dark ? "#1d1d20" : "#f5f5f7"
    readonly property color frame: dark ? "#45000000" : "#22000000"
    readonly property color toolbar: dark ? "#e22b2b2f" : "#f0f1f1f3"
    readonly property color toolbarPrivate: dark ? "#e22d2737" : "#f1ece8f4"
    readonly property color field: dark ? "#b63b3b40" : "#eaffffff"
    readonly property color fieldPrivate: dark ? "#88443a52" : "#cfe9e2ef"
    readonly property color tabBar: dark ? "#f1242428" : "#f1ededf0"
    readonly property color activeTab: dark ? "#993b3b40" : "#deffffff"
    readonly property color sidebar: dark ? "#f128282c" : "#f4ececf0"
    readonly property color sidebarPrivate: dark ? "#ee2b2732" : "#f5ece8f2"

    readonly property color page: dark ? "#1d1d20" : "#ffffff"
    readonly property color library: dark ? "#1d1d20" : "#f8f8fa"
    readonly property color overview: dark ? "#f31b1b20" : "#f5f2f3f6"
    readonly property color card: dark ? "#ca303035" : "#ecffffff"

    readonly property color popover: dark ? "#f3323237" : "#fcf7f7f9"    // suggestions, Downloads, the find bar
    readonly property color sheet: dark ? "#fc303034" : "#fff8f8fa"
    readonly property color banner: dark ? "#f2303034" : "#f7fbfbfd"     // Save Password?
    readonly property color hud: dark ? "#ee35353a" : "#eef8f8fa"        // the toast, the keyring's wait
    readonly property color shadow: "#40000000"
}
