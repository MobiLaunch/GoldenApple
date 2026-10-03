// File ▸ New ▸ Project: choose a template, then options, then a location, as
// in Xcode. The App template is SwiftCrossUI, which builds for Linux, macOS,
// Windows and mobile from one SwiftUI-style codebase.
import QtQuick
import "../lib"
import "../lib/theme"

Sheet {
    id: sheet
    property var app
    property var backend
    property int step: 0
    property int platform: 0
    property string template: "app"
    property string error: ""
    property bool working: false
    signal created(string root)
    panelWidth: 700
    panelHeight: 500

    readonly property var templates: [
        { id: "app", title: "App", symbol: "smartphone", platforms: [0, 1],
          detail: "A SwiftUI-style app built with SwiftCrossUI. Runs in the Simulator and natively on Linux, macOS and Windows." },
        { id: "tool", title: "Command Line Tool", symbol: "terminal", platforms: [0],
          detail: "A command-line tool that runs in the console, on Linux and other Unix-like systems." },
        { id: "library", title: "Swift Package", symbol: "layers", platforms: [0, 1],
          detail: "A reusable library with unit tests, for any platform Swift supports." },
    ]
    readonly property var shownTemplates: templates.filter((t) => t.platforms.includes(platform))
    readonly property var currentTemplate: templates.find((t) => t.id === template) || templates[0]

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
        }, (r) => {
            sheet.working = false
            if (!r.ok) { sheet.error = r.error; return }
            sheet.close()
            sheet.created(r.root)
        })
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
            id: platformPicker
            anchors.horizontalCenter: parent.horizontalCenter
            options: ["Linux", "Multiplatform"]
            current: sheet.platform
            onPicked: (i) => {
                sheet.platform = i
                if (!sheet.currentTemplate.platforms.includes(i)) sheet.template = sheet.shownTemplates[0].id
            }
        }
        Text {
            id: section
            y: platformPicker.height + 18
            text: "Application"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
        }
        Row {
            y: section.y + section.height + 8
            spacing: 14
            Repeater {
                model: sheet.shownTemplates
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool chosen: sheet.template === modelData.id
                    width: 140
                    height: 128
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: tile.chosen ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : tileHover.hovered ? Theme.fill : "transparent"
                        border { width: tile.chosen ? 2 : 0; color: Theme.accent }
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 16
                        width: 60; height: 60
                        radius: 15
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#2f9bff" }
                            GradientStop { position: 1; color: "#0b4fd0" }
                        }
                        Symbol { anchors.centerIn: parent; name: tile.modelData.symbol; size: 30; tone: "white" }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 88
                        text: tile.modelData.title
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                    }
                    HoverHandler { id: tileHover }
                    TapHandler {
                        onTapped: sheet.template = tile.modelData.id
                        onDoubleTapped: { sheet.template = tile.modelData.id; sheet.step = 1; nameField.input.forceActiveFocus() }
                    }
                }
            }
        }
        Text {
            anchors.bottom: parent.bottom
            width: parent.width
            wrapMode: Text.WordWrap
            text: sheet.currentTemplate.detail
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }

    // -------------------------------------------------------------- options
    Column {
        visible: sheet.step === 1
        y: heading.height + 18
        x: 70
        width: parent.width - 140
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
            Item { id: slot; width: 300; height: 30 }
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
        Labeled { label: ""; Checkbox { id: tests; width: 300; checked: true; text: "Include Tests" } }
        Labeled { label: ""; Checkbox { id: git; width: 300; checked: true; text: "Create Git repository" } }
    }

    // ------------------------------------------------------------- location
    FolderBrowser {
        id: browser
        visible: sheet.step === 2
        y: heading.height + 14
        width: parent.width
        height: parent.height - y - footer.height - 30
        backend: sheet.backend
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
