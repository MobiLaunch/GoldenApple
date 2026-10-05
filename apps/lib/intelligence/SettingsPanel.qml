import Quickshell
import QtQuick
import ".." as Shared
import "../theme"

Column {
    id: panel
    property Item menuParent: null
    property bool enabledSetting: false
    property bool hasKey: false
    property bool environmentKey: false
    property string status: "Loading settings…"
    property var models: []
    spacing: 14
    function reload() { service.send({ action: "status" }) }
    Component.onCompleted: reload()
    Service {
        id: service
        onCompleted: (action, result) => {
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
        Shared.Switch { checked: panel.enabledSetting; enabled: !service.busy; onToggled: (value) => panel.enabledSetting = value }
        Text { text: "Enable Citron Intelligence"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold } }
    }
    Text { text: "Gemini API key"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField {
        id: apiKey
        width: parent.width; height: 34; password: true
        enabled: !service.busy
        placeholder: panel.hasKey ? "Key saved — leave blank to keep it" : "Paste your Gemini API key"
    }
    Text {
        visible: panel.environmentKey
        width: parent.width; wrapMode: Text.Wrap
        text: "GEMINI_API_KEY is set for this session and takes precedence over the saved key."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 12 }
    }
    Text { text: "Text and questions model"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField { id: textModel; width: parent.width; height: 32; enabled: !service.busy; placeholder: "Gemini text model ID" }
    Shared.PopUpButton {
        visible: panel.models.length > 0
        width: parent.width; menuParent: panel.menuParent
        options: panel.models.filter(m => !m.includes("image") && !m.includes("tts") && !m.includes("audio") && !m.includes("live"))
        onPicked: (i) => textModel.text = options[i]
    }
    Text { text: "Image generation and editing model"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold } }
    Shared.TextField { id: imageModel; width: parent.width; height: 32; enabled: !service.busy; placeholder: "Gemini image model ID" }
    Shared.PopUpButton {
        visible: panel.models.length > 0
        width: parent.width; menuParent: panel.menuParent
        options: panel.models.filter(m => m.includes("image"))
        onPicked: (i) => imageModel.text = options[i]
    }
    Flow {
        width: parent.width; spacing: 8
        Shared.Button {
            text: "Save Settings"; prominent: true; enabled: !service.busy
            onClicked: service.send({ action: "configure", enabled: panel.enabledSetting, apiKey: apiKey.text,
                                      textModel: textModel.text.trim(), imageModel: imageModel.text.trim() })
        }
        Shared.Button { text: "Refresh Models"; enabled: !service.busy && panel.hasKey; onClicked: service.send({ action: "models" }) }
        Shared.Button { text: "Remove Saved Key"; enabled: !service.busy && panel.hasKey; onClicked: { panel.enabledSetting = false; service.send({ action: "forget" }) } }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: service.busy ? "Working…" : service.error || panel.status
        color: service.error ? "#ff453a" : Theme.secondaryLabel
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
