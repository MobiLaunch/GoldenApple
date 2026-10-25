import Quickshell
import QtQuick
import ".."
import "../theme"

Column {
    id: panel
    objectName: "citronSettingsPanel"
    property Item menuParent: null
    property bool enabledSetting: false
    property bool hasKey: false
    property bool environmentKey: false
    property string status: "Loading settings…"
    // Aion Labs' text models ({ id, name }), listed without a key.
    property var models: []
    property string modelSetting: "aion-labs/aion-3.5-mini"
    // Citron's languages ({ code, name, voices: [{ id, name }] }), from the helper.
    property var languages: []
    property string systemLanguage: "English (US)"
    property string systemCode: "en-US"
    property string languageSetting: "auto"
    property string voiceSetting: ""
    property bool speakSetting: true
    property var speechModels: []
    property string speechSetting: "fast"
    property real voiceDownload: 0      // bytes still to fetch for voice
    readonly property var voices: {
        const code = languageSetting === "auto" ? systemCode : languageSetting
        const lang = languages.find((l) => l.code === code)
        return lang ? lang.voices : []
    }
    function megabytes(bytes) { return Math.max(1, Math.round(bytes / 1000000)) + " MB" }
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
                panel.modelSetting = result.config.textModel
                panel.speechSetting = result.config.speechModel || "fast"
                panel.languageSetting = result.config.voiceLanguage || "auto"
                panel.voiceSetting = result.config.voice || ""
                panel.speakSetting = result.config.speak !== false
            }
            if (result.languages) {
                panel.languages = result.languages
                panel.systemLanguage = result.systemLanguage || panel.systemLanguage
                const sys = result.languages.find((l) => l.name === panel.systemLanguage)
                panel.systemCode = sys ? sys.code : "en-US"
            }
            if (result.speechModels) panel.speechModels = result.speechModels
            if (result.voiceDownload !== undefined) panel.voiceDownload = result.voiceDownload
            if (action === "status") {
                panel.hasKey = result.hasKey
                panel.environmentKey = result.environmentKey
                panel.status = result.warning || (result.hasKey ? "API key is available." : "Add your Aion Labs API key to get started.")
                // Aion lists its models without a key: fill the picker now.
                Qt.callLater(() => panel.send({ action: "models" }))
            } else if (action === "models") {
                panel.models = result.models || []
            } else {
                panel.status = action === "forget" ? "Saved key removed. Citron Intelligence is off." : "Settings saved."
                panel.hasKey = action !== "forget" && (panel.hasKey || apiKey.text.length > 0)
                apiKey.text = ""
            }
        }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: "Citron works with words, using Aion Labs' models. Only what you ask, or what you say once it's turned into text on this computer, goes to Aion Labs; your voice itself never leaves the computer. Your key is stored in the system keyring; requests appear in the temporary desktop overlay and are cleared when you dismiss it."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
    }
    Row {
        spacing: 12
        Switch { checked: panel.enabledSetting; enabled: !panel.busy && panel.serviceAvailable; onToggled: (value) => panel.enabledSetting = value }
        Text { text: "Enable Citron Intelligence"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.headline.pixelSize; weight: Font.DemiBold } }
    }
    Text { text: "Aion Labs API key"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize; weight: Font.DemiBold } }
    TextField {
        id: apiKey
        objectName: "citronApiKey"
        width: parent.width; height: 34; password: true
        enabled: !panel.busy && panel.serviceAvailable
        placeholder: panel.hasKey ? "Key saved — leave blank to keep it" : "Paste your Aion Labs API key"
    }
    Text {
        visible: panel.environmentKey
        width: parent.width; wrapMode: Text.Wrap
        text: "AION_API_KEY is set for this session and takes precedence over the saved key."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
    }
    Text { text: "Model"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize; weight: Font.DemiBold } }
    PopUpButton {
        id: modelChooser
        objectName: "citronModel"
        width: Math.min(320, parent.width); menuParent: panel.menuParent
        enabled: !panel.busy && panel.serviceAvailable
        // The saved model stays on the list even before Aion's has loaded.
        readonly property var ids: panel.models.some((m) => m.id === panel.modelSetting)
            ? panel.models.map((m) => m.id) : [panel.modelSetting].concat(panel.models.map((m) => m.id))
        options: ids.map((id) => { const m = panel.models.find((x) => x.id === id); return m ? m.name.replace(/^AionLabs: /, "") : id })
        current: Math.max(0, ids.indexOf(panel.modelSetting))
        onPicked: (i) => panel.modelSetting = ids[i]
    }
    Text {
        width: parent.width
        text: "Voice conversations"
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.font.title3.pixelSize; weight: Font.DemiBold }
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Press ⇧⌘Space to start a voice conversation, or use Ask Citron for typing. Speech is recognised on this computer and only the words go to Aion Labs; no recordings are kept. The microphone listens only while voice mode is open and unmuted."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
    }
    Text { text: "Speech recognition"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize } }
    PopUpButton {
        id: speechChooser
        objectName: "citronSpeechModel"
        width: Math.min(280, parent.width)
        menuParent: panel.menuParent
        enabled: !panel.busy && panel.serviceAvailable
        readonly property var ids: panel.speechModels.map((m) => m.id)
        options: panel.speechModels.map((m) => m.name + " (" + panel.megabytes(m.size) + ")")
        current: Math.max(0, ids.indexOf(panel.speechSetting))
        onPicked: (i) => panel.speechSetting = ids[i]
    }
    Text { text: "Language"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize } }
    PopUpButton {
        id: languageChooser
        objectName: "citronLanguage"
        width: Math.min(280, parent.width)
        menuParent: panel.menuParent
        enabled: !panel.busy && panel.serviceAvailable
        readonly property var codes: ["auto"].concat(panel.languages.map((l) => l.code))
        options: ["Automatic (" + panel.systemLanguage + ")"].concat(panel.languages.map((l) => l.name))
        current: Math.max(0, codes.indexOf(panel.languageSetting))
        onPicked: (i) => { panel.languageSetting = codes[i]; panel.voiceSetting = "" }
    }
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Citron listens for this language and answers in it, unless you ask it to switch."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
    }
    Row {
        spacing: 12
        Switch { objectName: "citronSpeak"; checked: panel.speakSetting; enabled: !panel.busy && panel.serviceAvailable; onToggled: (value) => panel.speakSetting = value }
        Text { text: "Speak replies"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize } }
    }
    Text { visible: panel.speakSetting; text: "Voice"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize } }
    PopUpButton {
        id: voiceChooser
        objectName: "citronVoice"
        visible: panel.speakSetting
        width: Math.min(240, parent.width)
        menuParent: panel.menuParent
        enabled: !panel.busy && panel.serviceAvailable && panel.voices.length > 1
        options: panel.voices.map((v) => v.name)
        current: Math.max(0, panel.voices.findIndex((v) => v.id === panel.voiceSetting))
        onPicked: (i) => panel.voiceSetting = panel.voices[i].id
    }
    Text {
        visible: panel.voiceDownload > 0
        width: parent.width; wrapMode: Text.Wrap
        text: "The first voice conversation downloads Citron's voice files (" + panel.megabytes(panel.voiceDownload) + "). After that, voice works without downloading anything."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
    }
    Flow {
        width: parent.width; spacing: 8
        Button {
            text: "Save Settings"; prominent: true; enabled: !panel.busy && panel.serviceAvailable
            onClicked: panel.send({ action: "configure", enabled: panel.enabledSetting, apiKey: apiKey.text,
                                      textModel: panel.modelSetting, speechModel: panel.speechSetting,
                                      voiceLanguage: panel.languageSetting, voice: panel.voiceSetting,
                                      speak: panel.speakSetting })
        }
        Button { text: "Remove Saved Key"; enabled: !panel.busy && panel.serviceAvailable && panel.hasKey; onClicked: { panel.enabledSetting = false; panel.send({ action: "forget" }) } }
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: panel.serviceError || (panel.busy ? "Working…" : panel.transportError || panel.status)
        color: panel.serviceError || panel.transportError ? Theme.destructive : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
        Accessible.role: Accessible.StaticText
    }
    Text {
        width: parent.width; wrapMode: Text.Wrap
        text: "Aion Labs needs internet access; its terms apply to what you send, and usage beyond its free allowance may be billed. Aion's models are tuned for conversation and storytelling."
        color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
    }
    Button { text: "Get an Aion Labs API Key"; onClicked: Qt.openUrlExternally("https://www.aionlabs.ai/") }
}
