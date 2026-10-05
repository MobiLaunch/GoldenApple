import QtQuick
import "../../lib/intelligence" as AI
import ".."

Pane {
    id: pane
    headerSymbol: "wand"
    headerTint: "#9564e8"
    headerTitle: "Citron Intelligence"
    headerText: "Writing, ideas and images — with Google Gemini."
    AI.SettingsPanel { width: parent.width; menuParent: pane.nav ? pane.nav.overlay : null }
}
