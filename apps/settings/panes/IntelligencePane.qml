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

    Process { id: appLaunch; command: ["qs", "-c", "golden-gate", "ipc", "call", "citron", "ask"] }
    property string panelError: ""
    property var settingsComponent: null
    function reloadPanel() {
        controls.sourceComponent = null
        const component = Qt.createComponent(
            Qt.resolvedUrl("../../lib/intelligence/SettingsPanel.qml"),
            Component.PreferSynchronous)
        settingsComponent = component
        if (component.status === Component.Error) {
            panelError = component.errorString()
            console.error("Citron Intelligence SettingsPanel:", panelError)
            return
        }
        panelError = ""
        controls.sourceComponent = component
    }
    Component.onCompleted: reloadPanel()

    Loader {
        id: controls
        objectName: "citronSettingsLoader"
        width: parent.width
        height: status === Loader.Ready && item ? item.implicitHeight : 0
        // The explicit component lets us surface the actual Qt errorString.
        onLoaded: {
            if (item) item.menuParent = pane.nav ? pane.nav.overlay : null
        }
        onStatusChanged: {
            if (status === Loader.Error)
                {
                    pane.panelError = pane.settingsComponent && pane.settingsComponent.errorString
                        ? pane.settingsComponent.errorString()
                        : "SettingsPanel was created but could not be instantiated."
                    console.error("Citron Intelligence SettingsPanel:", pane.panelError)
                }
        }
    }
    Column {
        width: parent.width
        spacing: 12
        visible: !!pane.panelError || controls.status === Loader.Error
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: "#ff453a"
            text: "Citron Intelligence settings couldn't load. The QML diagnostic is shown below."
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            color: Theme.secondaryLabel
            text: pane.panelError || "The system overlay is independent of this Settings component. Check the Quickshell log for details."
        }
        Row {
            spacing: 8
            Shared.Button {
                text: "Retry"
                onClicked: {
                    pane.reloadPanel()
                }
            }
            Shared.Button {
                text: "Open Intelligence"
                onClicked: appLaunch.startDetached()
            }
        }
    }
}
