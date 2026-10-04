// Settings ▸ Themes: the code editor's colours. Pick a built-in theme for
// each appearance, or duplicate one and make every colour your own.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/syntax.js" as Syntax
import "../design"

Item {
    id: page
    property var app
    property var backend
    property Item overlay: null

    // Edits to your themes are shown at once and saved a moment later.
    property var draft: null
    readonly property var custom: draft || app.settings.customThemes || []
    readonly property var themes: Syntax.THEMES.filter((t) => !t.dark).concat(Syntax.THEMES.filter((t) => t.dark), custom)
    readonly property string lightId: app.settings.editorThemeLight || "default-light"
    readonly property string darkId: app.settings.editorThemeDark || "default-dark"
    property string selectedId: Theme.dark ? darkId : lightId
    readonly property var selected: Syntax.themeById(selectedId, custom) || Syntax.THEMES[0]

    readonly property string sample: "import Foundation\n\n/// Says hello to someone.\nstruct Greeter {\n    let name: String\n    var count = 3\n\n" +
        "    func greet() -> String {\n        // Hello, a few times over\n        return String(repeating: \"Hello, \\(name)! \", count: count)\n    }\n}\n\n" +
        "@main\nenum App {\n    static func main() {\n        #if DEBUG\n        print(Greeter(name: \"Golden Gate\").greet())\n        #endif\n    }\n}\n"

    function use(theme) {
        app.saveSettings(theme.dark ? { editorThemeDark: theme.id } : { editorThemeLight: theme.id })
    }
    function choose(theme) {
        selectedId = theme.id
        use(theme)
    }
    function saveCustom(list) {
        draft = list
        saveTimer.restart()
    }
    Timer {
        id: saveTimer
        interval: 350
        onTriggered: { page.app.saveSettings({ customThemes: page.draft }); }
    }
    Connections {
        target: page.app
        function onSettingsChanged() { if (!saveTimer.running) page.draft = null }
    }
    function duplicate(theme) {
        const copy = Syntax.duplicateTheme(theme, custom)
        saveCustom(custom.concat([copy]))
        selectedId = copy.id
        use(copy)
        Qt.callLater(() => list.positionViewAtEnd())
    }
    function update(key, value) {
        saveCustom(custom.map((t) => t.id === selectedId ? Object.assign({}, t, { [key]: value }) : t))
        if (key === "dark") {
            // Moving a theme to the other appearance uses it there.
            const t = Object.assign({}, selected, { dark: value })
            if (value && lightId === t.id) app.saveSettings({ editorThemeLight: "default-light", editorThemeDark: t.id })
            else if (!value && darkId === t.id) app.saveSettings({ editorThemeDark: "default-dark", editorThemeLight: t.id })
        }
    }
    function remove() {
        if (selected.builtIn) return
        const id = selected.id
        saveCustom(custom.filter((t) => t.id !== id))
        const values = {}
        if (lightId === id) values.editorThemeLight = "default-light"
        if (darkId === id) values.editorThemeDark = "default-dark"
        if (Object.keys(values).length) app.saveSettings(values)
        selectedId = Theme.dark ? "default-dark" : "default-light"
    }

    // ------------------------------------------------------------ the list
    Rectangle {
        id: listBox
        x: 20; y: 20
        width: 240
        height: parent.height - 40
        radius: 10
        color: Theme.dark ? "#14ffffff" : "#08000000"
        border { width: 1; color: Theme.separator }
        clip: true
        ListView {
            id: list
            x: 6; y: 6
            width: parent.width - 12
            height: parent.height - 12 - bar.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.themes
            delegate: Item {
                id: themeRow
                required property var modelData
                required property int index
                readonly property bool firstOfKind: index === 0 || (modelData.builtIn && page.themes[index - 1].dark !== modelData.dark) || (page.themes[index - 1].builtIn && !modelData.builtIn)
                width: list.width
                height: 40 + (firstOfKind ? 22 : 0)
                SidebarSection {
                    visible: themeRow.firstOfKind
                    text: !themeRow.modelData.builtIn ? "Your Themes" : themeRow.modelData.dark ? "Dark" : "Light"
                    topSpacing: 4
                }
                Rectangle {
                    y: themeRow.firstOfKind ? 22 : 0
                    width: parent.width
                    height: 38
                    radius: 7
                    color: page.selectedId === themeRow.modelData.id ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                         : rowHover.hovered ? (Theme.dark ? "#14ffffff" : "#0c000000") : "transparent"
                    Rectangle {
                        id: swatch
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 26
                        radius: 5
                        color: themeRow.modelData.background
                        border { width: 1; color: Theme.separator }
                        Row {
                            anchors.centerIn: parent
                            Text { text: "A"; color: themeRow.modelData.keyword; font { family: "monospace"; pixelSize: 13; weight: Font.Bold } }
                            Text { text: "a"; color: themeRow.modelData.string; font { family: "monospace"; pixelSize: 13 } }
                        }
                    }
                    Text {
                        x: swatch.x + swatch.width + 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 50
                        elide: Text.ElideRight
                        text: themeRow.modelData.name
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                    Symbol {
                        visible: page.lightId === themeRow.modelData.id || page.darkId === themeRow.modelData.id
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        name: "checkmark"
                        size: 13
                        tone: "accent"
                    }
                    HoverHandler { id: rowHover }
                    TapHandler { onTapped: page.choose(themeRow.modelData) }
                }
            }
        }
        // + duplicates the selected theme, − deletes one of yours.
        Row {
            id: bar
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 6; bottomMargin: 4 }
            height: 26
            spacing: 2
            ToolbarButton { symbol: "plus"; symbolSize: 13; Accessible.name: "Duplicate Theme"; onClicked: page.duplicate(page.selected) }
            ToolbarButton { symbol: "minus"; symbolSize: 13; enabled: !page.selected.builtIn; Accessible.name: "Delete Theme"; onClicked: page.remove() }
        }
    }

    // ------------------------------------------------------- the selection
    Flickable {
        x: listBox.x + listBox.width + 20
        y: 20
        width: parent.width - x - 20
        height: parent.height - 40
        clip: true
        contentHeight: detail.height + 8
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: detail
            width: parent.width
            spacing: 12
            Rectangle {
                width: parent.width
                height: 236
                radius: 10
                color: page.selected.background
                border { width: 1; color: Theme.separator }
                clip: true
                CodeEditor {
                    anchors { fill: parent; margins: 1 }
                    readOnly: true
                    language: "swift"
                    text: page.sample
                    colors: page.selected
                    showMinimap: false
                    fontFamily: page.app.settings.fontFamily || "monospace"
                    fontSize: Math.min(13, page.app.settings.fontSize || 13)
                    showLineNumbers: page.app.settings.showLineNumbers !== false
                }
            }
            Item {
                width: parent.width
                height: 28
                SettingField {
                    visible: !page.selected.builtIn
                    width: 220
                    value: page.selected.name
                    onCommitted: (v) => { if (v) page.update("name", v) }
                }
                Text {
                    visible: page.selected.builtIn
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.selected.name
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                }
                Button {
                    anchors.right: parent.right
                    text: page.selected.builtIn ? "Duplicate to Customize" : "Duplicate"
                    onClicked: page.duplicate(page.selected)
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: (page.lightId === page.selected.id ? "In use for the Light appearance. " : page.darkId === page.selected.id ? "In use for the Dark appearance. " : "")
                    + (page.selected.builtIn ? "Built-in themes stay as they are: duplicate one to change its colors." : "Click a color to change it.")
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Checkbox {
                width: 440
                visible: !page.selected.builtIn
                text: "A dark theme (used in the Dark appearance)"
                checked: !!page.selected.dark
                onToggled: (on) => page.update("dark", on)
            }
            Grid {
                visible: !page.selected.builtIn
                width: parent.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 6
                Repeater {
                    model: Syntax.THEME_KEYS
                    delegate: Rectangle {
                        id: tokenRow
                        required property string modelData
                        width: (detail.width - 12) / 2
                        height: 32
                        radius: 7
                        color: tokenHover.hovered ? (Theme.dark ? "#14ffffff" : "#0a000000") : "transparent"
                        Rectangle {
                            id: chip
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24
                            radius: 6
                            color: page.selected[tokenRow.modelData] || "transparent"
                            border { width: 1; color: Theme.separator }
                            Symbol {
                                visible: !page.selected[tokenRow.modelData]
                                anchors.centerIn: parent
                                name: "sparkles"
                                size: 12
                                tone: "accent"
                            }
                        }
                        Column {
                            x: chip.x + chip.width + 10
                            anchors.verticalCenter: parent.verticalCenter
                            Text { text: Syntax.THEME_TITLES[tokenRow.modelData]; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12 } }
                            Text {
                                text: page.selected[tokenRow.modelData] || "Accent color"
                                color: Theme.secondaryLabel
                                font { family: "monospace"; pixelSize: 10 }
                            }
                        }
                        HoverHandler { id: tokenHover }
                        TapHandler {
                            onTapped: {
                                colorPicker.key = tokenRow.modelData
                                colorPicker.allowNone = tokenRow.modelData === "selection"
                                colorPicker.show(chip, chip.width + 8, 0, page.selected[tokenRow.modelData] || "")
                            }
                        }
                    }
                }
            }
        }
    }

    ColorPicker {
        id: colorPicker
        parent: page.overlay
        property string key: ""
        customOnly: true
        onPicked: (value) => page.update(key, value)
    }
}
