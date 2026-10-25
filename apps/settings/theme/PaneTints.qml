// The colours of System Settings' pane icons: each pane's tile is the same
// colour in Light and Dark Mode, as on the Mac, so these don't follow the
// appearance or the accent colour.
pragma Singleton
import QtQuick

QtObject {
    readonly property color blue: "#0a84ff"         // Wi-Fi, Bluetooth, Network, Displays …
    readonly property color green: "#34c759"        // Battery
    readonly property color gray: "#8e8e93"         // General, Control Center, Keyboard …
    readonly property color steel: "#858890"        // Login Items
    readonly property color graphite: "#1d1d1f"     // Appearance, Menu Bar, Lock Screen
    readonly property color purple: "#9564e8"       // Citron Intelligence
    readonly property color slate: "#487bd9"        // Desktop & Dock, its Add to Dock, Default Applications
    readonly property color teal: "#30b0c7"         // Wallpaper
    readonly property color red: "#ff3b30"          // Notifications
    readonly property color indigo: "#5e5ce6"       // Focus
    readonly property color pink: "#ff2d55"         // Sound
    readonly property color rose: "#ff375f"         // Touch ID & Password
    readonly property color orange: "#ff9f0a"       // Finish Setting Up
}
