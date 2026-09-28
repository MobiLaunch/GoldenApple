// General: the list of sub-pages, as on the Mac.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "gear"; headerTint: "#8e8e93"; headerTitle: "General"
    headerText: "Manage your overall setup and preferences for this computer, such as software updates, storage and date and time."
    Group {
        SetRow { title: "About"; symbol: "info"; symbolTint: "#8e8e93"; chevron: true; onClicked: pane.nav.push("about") }
        SetRow { title: "Software Update"; symbol: "arrow-clockwise"; symbolTint: "#8e8e93"; chevron: true; onClicked: pane.nav.push("update") }
        SetRow { title: "Storage"; symbol: "drive"; symbolTint: "#8e8e93"; chevron: true; onClicked: pane.nav.push("storage") }
    }
    Group {
        SetRow { title: "Date & Time"; symbol: "clock"; symbolTint: "#0a84ff"; chevron: true; onClicked: pane.nav.push("datetime") }
        SetRow { title: "Language & Region"; symbol: "globe"; symbolTint: "#0a84ff"; chevron: true; onClicked: pane.nav.push("language") }
    }
}
