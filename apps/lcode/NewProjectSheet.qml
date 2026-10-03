// File ▸ New ▸ Project: choose a template, then options, then a location, as
// in Xcode. Templates are grouped like Xcode's platform tabs, by what you are
// making; each says which language it uses. The Golden Gate App is designed
// visually in the App Designer and needs no code; the others start from a
// small, working GTK (libadwaita) or SwiftCrossUI app you can make your own.
import QtQuick
import "../lib"
import "../lib/theme"
import "languages.js" as Languages

Sheet {
    id: sheet
    property var app
    property var backend
    property int step: 0
    property int category: 0
    property string template: "gg-app"
    property string error: ""
    property bool working: false
    property string accent: "#0a84ff"
    property int interfaceStyle: 0
    signal created(string root)
    panelWidth: 760
    panelHeight: 540

    readonly property var categories: ["Application", "Command Line", "Library"]
    readonly property var templates: [
        { id: "gg-app", category: 0, title: "App", toolchain: "goldengate", symbol: "sparkles",
          detail: "A Golden Gate app you design visually in the App Designer: drag in buttons, text, images and lists, style them, and make them work with actions. No code needed; it builds to QML you can extend." },
        { id: "python-app", category: 0, title: "Python App", toolchain: "python", symbol: "python",
          detail: "A GTK 4 and libadwaita app in Python. Runs right away with no build step; style it with CSS." },
        { id: "rust-app", category: 0, title: "Rust App", toolchain: "cargo", symbol: "rust",
          detail: "A GTK 4 and libadwaita app in Rust, built with cargo. Fast, safe and native." },
        { id: "c-app", category: 0, title: "C App", toolchain: "meson", symbol: "c-language",
          detail: "A GTK 4 and libadwaita app in C, built with Meson, the way GNOME apps are made." },
        { id: "app", category: 0, title: "Swift App", toolchain: "swift", symbol: "swift",
          detail: "A SwiftUI-style app built with SwiftCrossUI. Runs in the Simulator and natively on Linux, macOS and Windows." },
        { id: "python-tool", category: 1, title: "Python Script", toolchain: "python", symbol: "python",
          detail: "A Python program that runs in the console." },
        { id: "rust-tool", category: 1, title: "Rust Tool", toolchain: "cargo", symbol: "rust",
          detail: "A command-line tool in Rust, built with cargo." },
        { id: "c-tool", category: 1, title: "C Tool", toolchain: "meson", symbol: "c-language",
          detail: "A command-line tool in C, built with Meson." },
        { id: "tool", category: 1, title: "Swift Tool", toolchain: "swift", symbol: "swift",
          detail: "A command-line tool in Swift that runs in the console, on Linux and other Unix-like systems." },
        { id: "library", category: 2, title: "Swift Package", toolchain: "swift", symbol: "swift",
          detail: "A reusable Swift library with unit tests, for any platform Swift supports." },
        { id: "rust-library", category: 2, title: "Rust Library", toolchain: "cargo", symbol: "rust",
          detail: "A reusable Rust crate with unit tests." },
    ]
    readonly property var shownTemplates: templates.filter((t) => t.category === category)
    readonly property var currentTemplate: templates.find((t) => t.id === template) || templates[0]
    readonly property bool isApp: currentTemplate.category === 0
    readonly property bool designed: template === "gg-app"
    readonly property var toolchainInfo: app.toolchains[currentTemplate.toolchain] || null
    readonly property var accents: ["#0a84ff", "#5e5ce6", "#bf5af2", "#ff375f", "#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#40c8e0", "#8e8e93"]

    onShownChanged: if (shown) {
        step = 0
        error = ""
        working = false
        nameField.text = ""
        orgField.text = app.settings.organizationName || ""
        orgIdField.text = app.settings.organizationIdentifier || "com.example"
    }

    function bundleId() {
        const slug = nameField.text.replace(/[^A-Za-z0-9-]/g, "-")
        return orgIdField.text ? orgIdField.text + "." + slug : slug
    }

    function create() {
        working = true
        error = ""
        backend.call("create", {
            parent: browser.selected || browser.path, template: template, name: nameField.text.trim(),
            organization: orgField.text.trim(), organizationId: orgIdField.text.trim(),
            tests: tests.checked, git: git.checked,
            options: { accent: accent, style: ["sidebar", "window", "utility"][interfaceStyle] },
        }, (r) => {
            sheet.working = false
            if (!r.ok) { sheet.error = r.error; return }
            sheet.close()
            sheet.created(r.root)
        })
    }

    // A template's icon: the language's colours with its mark.
    component TemplateIcon: Rectangle {
        property var tmpl
        width: 60; height: 60
        radius: 15
        gradient: Gradient {
            GradientStop { position: 0; color: Languages.toolchain(tmpl.toolchain).colors[0] }
            GradientStop { position: 1; color: Languages.toolchain(tmpl.toolchain).colors[1] }
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border { width: 1; color: "#33ffffff" }
        }
        Symbol { anchors.centerIn: parent; name: tmpl.symbol; size: 32; tone: "white" }
    }

    Text {
        id: heading
        text: ["Choose a template for your new project:", "Choose options for your new project:", "Choose where to create your project:"][sheet.step]
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
    }

    // ------------------------------------------------------------ templates
    Item {
        visible: sheet.step === 0
        y: heading.height + 14
        width: parent.width
        height: parent.height - y - footer.height - 10
        Segmented {
            id: categoryPicker
            anchors.horizontalCenter: parent.horizontalCenter
            options: sheet.categories
            current: sheet.category
            onPicked: (i) => {
                sheet.category = i
                if (sheet.currentTemplate.category !== i) sheet.template = sheet.shownTemplates[0].id
            }
        }
        Text {
            id: section
            y: categoryPicker.height + 18
            text: sheet.categories[sheet.category]
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
        }
        Flow {
            id: tiles
            y: section.y + section.height + 8
            width: parent.width
            spacing: 12
            Repeater {
                model: sheet.shownTemplates
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool chosen: sheet.template === modelData.id
                    width: 132
                    height: 136
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: tile.chosen ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : tileHover.hovered ? Theme.fill : "transparent"
                        border { width: tile.chosen ? 2 : 0; color: Theme.accent }
                    }
                    TemplateIcon { anchors.horizontalCenter: parent.horizontalCenter; y: 14; tmpl: tile.modelData }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 84
                        width: parent.width - 12
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: tile.modelData.title
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 102
                        text: Languages.toolchain(tile.modelData.toolchain).name
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                    HoverHandler { id: tileHover }
                    TapHandler {
                        onTapped: sheet.template = tile.modelData.id
                        onDoubleTapped: { sheet.template = tile.modelData.id; sheet.step = 1; nameField.input.forceActiveFocus() }
                    }
                }
            }
        }
        Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: 4
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: sheet.currentTemplate.detail
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Text {
                // Building needs the language's tools; say so before you start.
                visible: sheet.currentTemplate.toolchain !== "goldengate" && !!sheet.toolchainInfo && !sheet.toolchainInfo.path
                width: parent.width
                wrapMode: Text.WordWrap
                text: visible ? sheet.toolchainInfo.name + " isn't installed yet. Install it with: " + sheet.toolchainInfo.hint : ""
                color: "#ff9f0a"
                font { family: Theme.fontUi; pixelSize: 12 }
            }
        }
    }

    // -------------------------------------------------------------- options
    Row {
        visible: sheet.step === 1
        y: heading.height + 18
        x: 24
        spacing: 26
        TemplateIcon { tmpl: sheet.currentTemplate }
        Column {
            spacing: 10
            component Labeled: Row {
                property string label
                default property alias field: slot.data
                spacing: 10
                Text {
                    width: 150
                    height: 30
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: parent.label
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
                Item { id: slot; width: 360; height: 30 }
            }
            Labeled { label: "Product Name:"; TextField { id: nameField; anchors.fill: parent; placeholder: "MyApp"; onAccepted: if (text.trim()) sheet.step = 2 } }
            Labeled { label: "Organization Name:"; TextField { id: orgField; anchors.fill: parent } }
            Labeled { label: "Organization Identifier:"; TextField { id: orgIdField; anchors.fill: parent; placeholder: "com.example" } }
            Labeled {
                label: "Bundle Identifier:"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: nameField.text ? sheet.bundleId() : "—"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
            }
            Labeled {
                label: "Language:"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Languages.toolchain(sheet.currentTemplate.toolchain).name + (sheet.designed ? " (App Designer, QML)" : "")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
            }
            Labeled {
                visible: sheet.designed
                label: "Interface:"
                Segmented {
                    anchors.verticalCenter: parent.verticalCenter
                    options: ["Sidebar", "Single Window", "Utility"]
                    current: sheet.interfaceStyle
                    onPicked: (i) => sheet.interfaceStyle = i
                }
            }
            Labeled {
                visible: sheet.isApp && sheet.template !== "app"
                label: "Accent Color:"
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Repeater {
                        model: sheet.accents
                        delegate: Rectangle {
                            required property string modelData
                            width: 20; height: 20; radius: 10
                            color: modelData
                            border { width: sheet.accent === modelData ? 2 : 1; color: sheet.accent === modelData ? Theme.label : "#22000000" }
                            Rectangle {
                                anchors.centerIn: parent
                                visible: sheet.accent === parent.modelData
                                width: 6; height: 6; radius: 3
                                color: "white"
                            }
                            TapHandler { onTapped: sheet.accent = parent.modelData }
                        }
                    }
                }
            }
            Labeled { visible: !sheet.designed; label: ""; Checkbox { id: tests; width: 300; checked: true; text: "Include Tests" } }
            Labeled { label: ""; Checkbox { id: git; width: 300; checked: true; text: "Create Git repository" } }
        }
    }

    // ------------------------------------------------------------- location
    FolderBrowser {
        id: browser
        visible: sheet.step === 2
        y: heading.height + 14
        width: parent.width
        height: parent.height - y - footer.height - 30
        backend: sheet.backend
        path: sheet.app.settings.projectsFolder || ""
    }
    Text {
        visible: sheet.step === 2
        anchors { bottom: footer.top; bottomMargin: 8 }
        width: parent.width
        elide: Text.ElideMiddle
        text: sheet.error || ("“" + nameField.text.trim() + "” will be created in " + (browser.selected || browser.path))
        color: sheet.error ? "#ff453a" : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 12 }
    }

    Row {
        id: footer
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: 8
        Button { text: "Cancel"; onClicked: sheet.close() }
        Button { visible: sheet.step > 0; text: "Previous"; onClicked: sheet.step-- }
        Button {
            text: sheet.step === 2 ? "Create" : "Next"
            prominent: true
            enabled: !sheet.working && (sheet.step !== 1 || nameField.text.trim().length > 0)
            onClicked: {
                if (sheet.step === 2) sheet.create()
                else { sheet.step++; if (sheet.step === 1) nameField.input.forceActiveFocus() }
            }
        }
    }
}
