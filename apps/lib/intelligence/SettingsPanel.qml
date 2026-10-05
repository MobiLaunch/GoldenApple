import Quickshell
import QtQuick
import ".." as Shared
import "../theme"

Column {
    id: panel
    objectName: "citronSettingsPanel"
    property Item menuParent: null
    property bool enabledSetting: false
    property bool hasKey: false
    property bool environmentKey: false
    property string status: "Loading settings…"
    property var models: []
    spacing: 14
    // The settings UI must remain usable even if the process adapter fails to
    // compile/load. Loading Service as a QML file isolates that failure.
    readonly property bool serviceAvailable: serviceLoader.status === Loader.Ready && !!serviceLoader.item
    readonly property bool busy: serviceAvailable && serviceLoader.item.busy
    readonly property string transportError: serviceAvailable ? serviceLoader.item.error : ""
    property string serviceError: ""
    function send(request) {
        if (!serviceAvailable) {
            status = serviceError || "The Citron Intelligence helper did not load."
            return false
        }
        return serviceLoader.item.send(request)
    }
    function reload() { send({ action: "status" }) }
    Loader {
        id: serviceLoader
        width: 0
        height: 0
        source: Qt.resolvedUrl("Service.qml")
        onLoaded: { panel.serviceError = ""; panel.reload() }
        onStatusChanged: {
            if (status === Loader.Error) {
                const probe = Qt.createComponent(Qt.resolvedUrl("Service.qml"), Component.PreferSynchronous)
                panel.serviceError = probe.status === Component.Error ? probe.errorString()
                    : "Citron Intelligence's process adapter failed to initialize."
                console.error("Citron Intelligence Service QML:", panel.serviceError)
                panel.status = panel.serviceError
            }
        }
    }
    Connections {
        target: serviceLoader.item
        ignoreUnknownSignals: true
        function onCompleted(action, result) {
            if (!result.ok) { panel.status = result.error; return }
            if (result.config) {
                panel.enabledSetting = result.config.enabled
                textModel.text = result.config.textModel
                imageModel.text = result.config.imageModel
            }
            if (action === "status") {
                panel.hasKey = result.hasKey
                panel.environmentKey = result.environmentKey
                panel.status = result.warning || (result.hasKey ? "API key is available." : "Add a Gemini API key to get started.")
            } else if (action === "models") {
                panel.models = result.models
                panel.status = result.models.length ? "Models refreshed. Choose a text model and an image model below." : "No compatible models were available for this key."
            } else {
                panel.status = action === "forget" ? "Saved key removed. Citron Intelligence is off." : "Settings saved."
                panel.hasKey = action !== "forget" && (panel.hasKey || apiKey.text.length > 0)
                apiKey.text = ""
            }
        }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: "Use Google Gemini to work with words and images. Only requests you send and photos you choose leave this computer. Your key is stored in the system keyring; conversations stay in this window and are cleared when you close it."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    Row {
        spacing: 12
        Shared.Switch { checked: panel.enabledSetting; enabled: !panel.busy && panel.serviceAvailable; onToggled: (value) => panel.enabledSetting = value }
        Text { text: "Enable Citron Intelligence"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
    }
    Text { text: "Gemini API key"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField {
        id: apiKey
        width: parent.width; height: 34; password: true
        enabled: !panel.busy && panel.serviceAvailable
        placeholder: panel.hasKey ? "Key saved — leave blank to keep it" : "Paste your Gemini API key"
    }
    Text {
        visible: panel.environmentKey
        width: parent.width; wrapMode: Text.Wrap
        text: "GEMINI_API_KEY is set for this session and takes precedence over the saved key."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 }
    }
    Text { text: "Text and questions model"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField { id: textModel; width: parent.width; height: 32; enabled: !panel.busy && panel.serviceAvailable; placeholder: "Gemini text model ID" }
    Shared.PopUpButton {
        visible: panel.models.length > 0
        width: parent.width; menuParent: panel.menuParent
        options: panel.models.filter(m => !m.includes("image") && !m.includes("tts") && !m.includes("audio") && !m.includes("live"))
        onPicked: (i) => textModel.text = options[i]
    }
    Text { text: "Image generation and editing model"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField { id: imageModel; width: parent.width; height: 32; enabled: !panel.busy && panel.serviceAvailable; placeholder: "Gemini image model ID" }
    Shared.PopUpButton {
        visible: panel.models.length > 0
        width: parent.width; menuParent: panel.menuParent
        options: panel.models.filter(m => m.includes("image"))
        onPicked: (i) => imageModel.text = options[i]
    }
    Flow {
        width: parent.width; spacing: 8
        Shared.Button {
            text: "Save Settings"; prominent: true; enabled: !panel.busy && panel.serviceAvailable
            onClicked: panel.send({ action: "configure", enabled: panel.enabledSetting, apiKey: apiKey.text,
                                      textModel: textModel.text.trim(), imageModel: imageModel.text.trim() })
        }
        Shared.Button { text: "Refresh Models"; enabled: !panel.busy && panel.serviceAvailable && panel.hasKey; onClicked: panel.send({ action: "models" }) }
        Shared.Button { text: "Remove Saved Key"; enabled: !panel.busy && panel.serviceAvailable && panel.hasKey; onClicked: { panel.enabledSetting = false; panel.send({ action: "forget" }) } }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: panel.serviceError || (panel.busy ? "Working…" : panel.transportError || panel.status)
        color: panel.serviceError || panel.transportError ? "#ff453a" : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 12 }
        Accessible.role: Accessible.StaticText
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: "Gemini requires internet access. API usage may be billed by Google, and Google's data terms apply. Model availability depends on your project."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 }
    }
    Shared.Button { text: "Get a Gemini API Key"; onClicked: Qt.openUrlExternally("https://aistudio.google.com/apikey") }
}
