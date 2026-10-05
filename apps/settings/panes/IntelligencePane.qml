// Load the optional Intelligence controls separately. A broken/missing UI
// component must not make the entire System Settings page disappear.
import QtQuick
import Quickshell.Io
import "../../lib/theme"
import "../../lib" as Shared
import ".."

Pane {
    id: pane
    headerSymbol: "wand"
    headerTint: "#9564e8"
    headerTitle: "Citron Intelligence"
    headerText: "Writing, ideas and images — with Google Gemini."

    Process { id: appLaunch; command: ["gg-intelligence"] }

    Loader {
        id: controls
        objectName: "citronSettingsLoader"
        width: parent.width
        height: status === Loader.Ready && item ? item.implicitHeight : 0
        source: Qt.resolvedUrl("../../lib/intelligence/SettingsPanel.qml")
        onLoaded: {
            if (item) item.menuParent = pane.nav ? pane.nav.overlay : null
        }
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("Citron Intelligence: could not load SettingsPanel.qml")
        }
    }
    Column {
        width: parent.width
        spacing: 12
        visible: controls.status === Loader.Error
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: "#ff453a"
            text: "Citron Intelligence settings couldn't load. This is a UI component error, not a Gemini API key error."
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.secondaryLabel
            text: "Open the app separately or retry loading this pane. If it continues, check the Settings/Quickshell log."
        }
        Row {
            spacing: 8
            Shared.Button {
                text: "Retry"
                onClicked: {
                    controls.active = false
                    controls.active = true
                }
            }
            Shared.Button {
                text: "Open Intelligence"
                onClicked: appLaunch.startDetached()
            }
        }
    }
}
