// The project editor, opened from the project at the top of the navigator, as
// in Xcode: General (identity, version, category, licence), App Icon (an icon
// designer), Capabilities (what a sandboxed copy may use) and Run (Xcode's
// Edit Scheme: configuration, arguments, environment). Changes save at once
// to .lcode/project.json.
import QtQuick
import "../lib"
import "../lib/theme"
import "design"
import "languages.js" as Languages

Item {
    id: pe
    property var app
    property var backend
    property Item overlay: null
    property var menu: null
    property int page: 0
    // EditorArea's interface for tabs.
    property string text: ""
    property string savedText: ""
    property int revision: 0
    readonly property var editor: null
    function goTo(l, c) {}

    readonly property var project: app ? app.project : null
    readonly property var meta: project && project.meta ? project.meta : ({})
    readonly property var icon: meta.icon || null
    property string iconLight: ""
    property string iconDark: ""
    property int iconRev: 0

    function save(values) {
        backend.call("saveMeta", { values: values }, (r) => {
            if (!r.ok) return
            pe.app.refreshProject()
            if ("icon" in values || "accent" in values) pe.refreshIcon()
        })
    }
    function refreshIcon() {
        backend.call("iconPreview", {}, (r) => {
            if (!r.ok) return
            pe.iconLight = "file://" + r.light
            pe.iconDark = "file://" + r.dark
            pe.iconRev++
        })
    }
    function setIcon(patch) { save({ icon: Object.assign({}, icon || {}, patch) }) }
    Component.onCompleted: refreshIcon()

    readonly property var categories: [
        ["Utility", "Utilities"], ["Development", "Developer Tools"], ["Education", "Education"], ["Game", "Games"],
        ["Graphics", "Graphics & Design"], ["AudioVideo", "Music & Video"], ["Network", "Internet"], ["Office", "Productivity"],
        ["Science", "Science"], ["Settings", "Settings"], ["System", "System"]]
    readonly property var licenses: ["MIT", "Apache-2.0", "GPL-3.0-or-later", "LGPL-2.1-or-later", "MPL-2.0", "BSD-3-Clause", "Unlicense", "Proprietary"]
    readonly property var capabilityList: [
        { id: "network", symbol: "globe", title: "Internet", detail: "Connect to the internet and the local network." },
        { id: "home", symbol: "house", title: "Home Folder", detail: "Read and write everything in your home folder." },
        { id: "documents", symbol: "doc", title: "Documents", detail: "Read and write the Documents folder." },
        { id: "downloads", symbol: "download", title: "Downloads", detail: "Read and write the Downloads folder." },
        { id: "pictures", symbol: "photo", title: "Pictures", detail: "Read and write the Pictures folder." },
        { id: "music", symbol: "music", title: "Music", detail: "Read and write the Music folder." },
        { id: "videos", symbol: "film", title: "Videos", detail: "Read and write the Videos folder." },
        { id: "notifications", symbol: "bell", title: "Notifications", detail: "Show notifications." },
        { id: "sound", symbol: "speaker-wave", title: "Sound", detail: "Play and record sound." },
        { id: "graphics", symbol: "gauge", title: "Graphics Acceleration", detail: "Draw with the GPU (games, 3D, video)." },
        { id: "devices", symbol: "smartphone", title: "Devices", detail: "Use cameras, game controllers and other USB devices." },
        { id: "location", symbol: "location", title: "Location", detail: "Ask where the computer is." },
        { id: "host", symbol: "terminal", title: "Run Commands on the Computer", detail: "Run programs outside the sandbox. Only for tools that must." },
    ]
    readonly property var capabilities: meta.capabilities || (project && project.kind === "app" ? ["network"] : [])

    // ------------------------------------------------------------- header
    Rectangle {
        id: header
        width: parent.width
        height: 64
        color: "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
        Image {
            id: headerIcon
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            sourceSize: Qt.size(80, 80)
            cache: false
            source: pe.iconLight ? pe.iconLight + "?" + pe.iconRev : ""
        }
        Column {
            x: 72
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: pe.project ? (pe.project.displayName || pe.project.name) : ""
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
            }
            Text {
                text: pe.project ? Languages.toolchain(pe.project.toolchain).name + "  ·  " + (pe.project.bundleId || "no bundle identifier") : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
            }
        }
        Segmented {
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            options: ["General", "App Icon", "Capabilities", "Run"]
            current: pe.page
            onPicked: (i) => pe.page = i
        }
    }

    // ------------------------------------------------------------- pieces
    component Section: Column {
        property string title
        property string note: ""
        default property alias items: body.data
        width: parent ? parent.width : 0
        spacing: 8
        Text { text: parent.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold } }
        Rectangle {
            width: parent.width
            height: body.height + 24
            radius: 12
            color: Theme.dark ? "#0fffffff" : "#08000000"
            border { width: 0.5; color: Theme.separator }
            Column { id: body; x: 16; y: 12; width: parent.width - 32; spacing: 10 }
        }
        Text {
            visible: !!parent.note
            width: parent.width
            wrapMode: Text.Wrap
            text: parent.note
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
    }
    component Field: Item {
        property string label
        default property alias control: slot.data
        width: parent ? parent.width : 0
        height: Math.max(28, slot.childrenRect.height)
        Text {
            width: 150
            height: 28
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            text: parent.label
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
        Item { id: slot; x: 162; width: parent.width - 162; height: childrenRect.height }
    }
    component MetaField: TextField {
        property string key
        property string fallback: ""
        width: parent ? Math.min(parent.width, 360) : 0
        height: 28
        text: pe.meta[key] !== undefined ? String(pe.meta[key]) : fallback
        onAccepted: pe.save({ [key]: text.trim() })
        input.onActiveFocusChanged: if (!input.activeFocus && text.trim() !== (pe.meta[key] !== undefined ? String(pe.meta[key]) : fallback)) pe.save({ [key]: text.trim() })
    }

    Flickable {
        y: header.height
        width: parent.width
        height: parent.height - y
        contentHeight: pages.height + 60
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Item {
            id: pages
            x: Math.max(20, (parent.width - width) / 2)
            y: 24
            width: Math.min(680, parent.width - 40)
            height: [general, iconPage, capsPage, runPage][pe.page].height

            // ================================================== General
            Column {
                id: general
                visible: pe.page === 0
                width: parent.width
                spacing: 22
                Section {
                    title: "Identity"
                    Field { label: "Display Name"; MetaField { key: "display_name"; fallback: pe.project ? pe.project.name : "" } }
                    Field { label: "Bundle Identifier"; MetaField { key: "bundle_identifier" } }
                    Field {
                        label: "Version"
                        Row {
                            spacing: 8
                            MetaField { key: "version"; fallback: "1.0"; width: 90 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Build"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                            MetaField { key: "build"; fallback: "1"; width: 70 }
                        }
                    }
                    Field { label: "Developer"; MetaField { key: "organization" } }
                }
                Section {
                    title: "App Store and Desktop"
                    note: "These describe your app in Applications, the App Store and the packages LCode exports."
                    Field { label: "Summary"; MetaField { key: "comment"; width: 360 } }
                    Field {
                        label: "Category"
                        PopUpButton {
                            options: pe.categories.map((c) => c[1])
                            current: Math.max(0, pe.categories.findIndex((c) => c[0] === (pe.meta.category || "Utility")))
                            menuParent: pe.overlay
                            onPicked: (i) => pe.save({ category: pe.categories[i][0] })
                        }
                    }
                    Field { label: "Keywords"; MetaField { key: "keywords" } }
                    Field { label: "Website"; MetaField { key: "homepage" } }
                    Field {
                        label: "License"
                        PopUpButton {
                            options: pe.licenses
                            current: Math.max(0, pe.licenses.indexOf(pe.meta.license || "MIT"))
                            menuParent: pe.overlay
                            onPicked: (i) => pe.save({ license: pe.licenses[i] })
                        }
                    }
                }
                Section {
                    title: "Product"
                    Field {
                        label: "Type"
                        PopUpButton {
                            options: ["App", "Command Line Tool", "Library"]
                            current: pe.project ? Math.max(0, ["app", "tool", "library"].indexOf(pe.project.kind)) : 0
                            menuParent: pe.overlay
                            onPicked: (i) => pe.save({ kind: ["app", "tool", "library"][i] })
                        }
                    }
                    Field {
                        label: "Language"
                        Text {
                            height: 28
                            verticalAlignment: Text.AlignVCenter
                            text: pe.project ? Languages.toolchain(pe.project.toolchain).name + (pe.app.projectToolchain && pe.app.projectToolchain.version ? "  —  " + pe.app.projectToolchain.version : "") : ""
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                    }
                    Field {
                        visible: !!pe.project && pe.project.toolchain === "goldengate"
                        label: "Interface"
                        Button {
                            text: "Open Interface.lcdesign"
                            onClicked: pe.app.revealLocation(pe.project.root + "/Interface.lcdesign", 0, 0, "")
                        }
                    }
                }
            }

            // ================================================= App Icon
            Column {
                id: iconPage
                visible: pe.page === 1
                width: parent.width
                spacing: 22
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 28
                    Repeater {
                        model: [{ src: "light", title: "Light" }, { src: "dark", title: "Dark" }]
                        delegate: Column {
                            id: variant
                            required property var modelData
                            readonly property string url: (modelData.src === "dark" ? pe.iconDark : pe.iconLight)
                            spacing: 8
                            Rectangle {
                                width: 168; height: 168; radius: 24
                                color: modelData.src === "dark" ? "#1c1c1e" : "#eeeef2"
                                Image {
                                    anchors.centerIn: parent
                                    width: 128; height: 128
                                    sourceSize: Qt.size(256, 256)
                                    cache: false
                                    source: variant.url ? variant.url + "?" + pe.iconRev : ""
                                }
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 10
                                Repeater {
                                    model: [16, 32, 48]
                                    delegate: Image {
                                        required property int modelData
                                        anchors.bottom: parent.bottom
                                        width: modelData; height: modelData
                                        sourceSize: Qt.size(modelData * 2, modelData * 2)
                                        cache: false
                                        source: variant.url ? variant.url + "?" + pe.iconRev : ""
                                    }
                                }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.title; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                        }
                    }
                }
                Section {
                    title: "Background"
                    Field {
                        label: "Colors"
                        Row {
                            spacing: 8
                            Repeater {
                                model: [0, 1]
                                delegate: Rectangle {
                                    id: well
                                    required property int modelData
                                    width: 44; height: 28; radius: 7
                                    color: pe.icon && pe.icon.background ? pe.icon.background[modelData] || "#0a84ff" : "#0a84ff"
                                    border { width: 1; color: "#33000000" }
                                    TapHandler {
                                        onTapped: {
                                            iconColorPicker.parent = pe.overlay
                                            iconColorPicker.target = well.modelData
                                            iconColorPicker.show(well, 0, well.height + 4, String(well.color))
                                        }
                                    }
                                }
                            }
                            ToolbarButton {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "⇄"
                                Accessible.name: "Swap colors"
                                onClicked: { const bg = (pe.icon.background || ["#5ea3e8", "#0a84ff"]).slice(); pe.setIcon({ background: [bg[1], bg[0]] }) }
                            }
                        }
                    }
                    Field {
                        label: "Angle"
                        Row {
                            spacing: 6
                            Repeater {
                                model: [0, 45, 90, 135, 160, 180, 225, 270]
                                delegate: ToolbarButton {
                                    required property int modelData
                                    text: modelData + "°"
                                    checked: pe.icon && Math.round(pe.icon.angle) === modelData
                                    onClicked: pe.setIcon({ angle: modelData })
                                }
                            }
                        }
                    }
                    Field {
                        label: "Presets"
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: [["#ffd84d", "#ff8a00"], ["#ff8f5e", "#e8382a"], ["#ff6b9a", "#bf5af2"], ["#64d2ff", "#0a84ff"], ["#7bed9f", "#2ea043"],
                                        ["#a29bfe", "#5e5ce6"], ["#3a3a3e", "#161618"], ["#ffffff", "#d8d8de"], ["#5ea3e8", "#2f5f99"], ["#f0a35e", "#a8461c"]]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 34; height: 34; radius: 9
                                    gradient: Gradient { GradientStop { position: 0; color: modelData[0] } GradientStop { position: 1; color: modelData[1] } }
                                    border { width: 0.5; color: "#33000000" }
                                    TapHandler { onTapped: pe.setIcon({ background: parent.modelData.slice() }) }
                                }
                            }
                        }
                    }
                }
                Section {
                    title: "Glyph"
                    Field {
                        label: "Kind"
                        Segmented {
                            options: ["Symbol", "Letters", "Image"]
                            current: Math.max(0, ["symbol", "text", "image"].indexOf(pe.icon && pe.icon.glyph ? pe.icon.glyph.kind : "symbol"))
                            onPicked: (i) => pe.setIcon({ glyph: Object.assign({}, (pe.icon || {}).glyph || {}, {
                                kind: ["symbol", "text", "image"][i],
                                value: ["sparkles", (pe.project ? (pe.project.displayName || pe.project.name) : "A").slice(0, 2), ""][i] }) })
                        }
                    }
                    Field {
                        label: pe.icon && pe.icon.glyph && pe.icon.glyph.kind === "text" ? "Letters" : pe.icon && pe.icon.glyph && pe.icon.glyph.kind === "image" ? "Image" : "Symbol"
                        Loader {
                            sourceComponent: !pe.icon || !pe.icon.glyph || pe.icon.glyph.kind === "symbol" ? symbolChoice : pe.icon.glyph.kind === "text" ? letters : imageChoice
                            Component {
                                id: symbolChoice
                                Button {
                                    id: symButton
                                    symbol: pe.icon && pe.icon.glyph ? pe.icon.glyph.value : "sparkles"
                                    text: pe.icon && pe.icon.glyph ? pe.icon.glyph.value : "sparkles"
                                    onClicked: { iconSymbolPicker.parent = pe.overlay; iconSymbolPicker.show(symButton, 0, symButton.height + 4, text) }
                                }
                            }
                            Component {
                                id: letters
                                TextField {
                                    width: 120; height: 28
                                    text: pe.icon.glyph.value || ""
                                    onAccepted: pe.setIcon({ glyph: Object.assign({}, pe.icon.glyph, { value: text.slice(0, 4) }) })
                                }
                            }
                            Component {
                                id: imageChoice
                                Button {
                                    id: imgButton
                                    text: pe.icon.glyph.value || "Choose Image…"
                                    onClicked: {
                                        iconImagePicker.parent = pe.overlay
                                        iconImagePicker.root = pe.project.root
                                        iconImagePicker.show(imgButton, 0, imgButton.height + 4, pe.icon.glyph.value)
                                    }
                                }
                            }
                        }
                    }
                    Field {
                        label: "Color"
                        Rectangle {
                            id: glyphWell
                            width: 44; height: 28; radius: 7
                            color: pe.icon && pe.icon.glyph ? pe.icon.glyph.color || "#ffffff" : "#ffffff"
                            border { width: 1; color: "#33000000" }
                            TapHandler {
                                onTapped: {
                                    iconColorPicker.parent = pe.overlay
                                    iconColorPicker.target = 2
                                    iconColorPicker.show(glyphWell, 0, glyphWell.height + 4, String(glyphWell.color))
                                }
                            }
                        }
                    }
                    Field {
                        label: "Size"
                        Slider {
                            width: 220
                            value: pe.icon ? ((pe.icon.scale || 1) - 0.4) / 1.2 : 0.5
                            onMoved: (v) => sizeTimer.restart()
                            Timer { id: sizeTimer; interval: 250; onTriggered: pe.setIcon({ scale: Math.round((0.4 + parent.value * 1.2) * 100) / 100 }) }
                        }
                    }
                    Field {
                        label: ""
                        Checkbox {
                            width: 300
                            text: "Liquid Glass rim and shine"
                            checked: !pe.icon || pe.icon.gloss !== false
                            onToggled: (c) => pe.setIcon({ gloss: c })
                        }
                    }
                }
                Button {
                    text: "Reset to Default Icon"
                    onClicked: pe.save({ icon: null })
                }
            }

            // ============================================== Capabilities
            Column {
                id: capsPage
                visible: pe.page === 2
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "When you export your app as a Flatpak it runs in a sandbox, like an App Store app. Turn on what it needs; everything else stays out of reach."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Grid {
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12
                    width: parent.width
                    Repeater {
                        model: pe.capabilityList
                        delegate: Rectangle {
                            id: capCard
                            required property var modelData
                            readonly property bool on: pe.capabilities.indexOf(modelData.id) >= 0
                            width: (capsPage.width - 12) / 2
                            height: 74
                            radius: 12
                            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.16 : 0.08) : (Theme.dark ? "#0fffffff" : "#08000000")
                            border { width: on ? 1 : 0.5; color: on ? Theme.accent : Theme.separator }
                            Symbol { x: 14; y: 14; name: capCard.modelData.symbol; size: 20; tone: "accent" }
                            Column {
                                x: 46; y: 12
                                width: parent.width - 46 - 60
                                spacing: 2
                                Text { text: capCard.modelData.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold } }
                                Text { width: parent.width; wrapMode: Text.Wrap; text: capCard.modelData.detail; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                            }
                            Switch {
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                checked: capCard.on
                                onToggled: (c) => pe.save({ capabilities: c ? pe.capabilities.concat([capCard.modelData.id])
                                                                                : pe.capabilities.filter((x) => x !== capCard.modelData.id) })
                            }
                        }
                    }
                }
            }

            // ======================================================= Run
            Column {
                id: runPage
                visible: pe.page === 3
                width: parent.width
                spacing: 22
                readonly property var scheme: pe.meta.scheme || ({})
                function setScheme(patch) { pe.save({ scheme: Object.assign({}, scheme, patch) }) }
                Section {
                    title: "Build Configuration"
                    note: "Debug builds quickly and keeps checks on; Release is optimised, for the apps you ship."
                    Field {
                        label: "Configuration"
                        Segmented {
                            options: ["Debug", "Release"]
                            current: runPage.scheme.configuration === "release" ? 1 : 0
                            onPicked: (i) => runPage.setScheme({ configuration: i ? "release" : "debug" })
                        }
                    }
                }
                Section {
                    title: "Arguments Passed on Launch"
                    OptionsEditor {
                        width: parent.width
                        newItem: "--argument"
                        values: runPage.scheme.arguments || []
                        onCommit: (list) => runPage.setScheme({ arguments: list.map((v) => String(v.title !== undefined ? v.title : v)) })
                    }
                }
                Section {
                    title: "Environment Variables"
                    note: "One per row, as NAME=value. LCode adds LCODE_SIMULATOR and LCODE_DEVICE_ID in the Simulator."
                    OptionsEditor {
                        width: parent.width
                        newItem: "NAME=value"
                        values: Object.keys(runPage.scheme.environment || {}).map((k) => k + "=" + runPage.scheme.environment[k])
                        onCommit: (list) => {
                            const env = {}
                            for (const row of list) {
                                const s = String(row)
                                const i = s.indexOf("=")
                                if (i > 0) env[s.slice(0, i).trim()] = s.slice(i + 1)
                                else if (s.trim()) env[s.trim()] = ""
                            }
                            runPage.setScheme({ environment: env })
                        }
                    }
                }
                Section {
                    title: "Options"
                    Field {
                        label: "Working Directory"
                        TextField {
                            width: Math.min(parent.width, 360)
                            height: 28
                            placeholder: "The project folder"
                            text: runPage.scheme.workingDirectory || ""
                            onAccepted: runPage.setScheme({ workingDirectory: text.trim() || undefined })
                        }
                    }
                }
            }
        }
    }

    // Pickers for the icon.
    ColorPicker {
        id: iconColorPicker
        property int target: 0
        customOnly: true
        onPicked: (v) => {
            if (target === 2) pe.setIcon({ glyph: Object.assign({}, (pe.icon || {}).glyph || { kind: "symbol", value: "sparkles" }, { color: v }) })
            else { const bg = ((pe.icon || {}).background || ["#5ea3e8", "#0a84ff"]).slice(); bg[target] = v; pe.setIcon({ background: bg }) }
        }
    }
    SymbolPicker {
        id: iconSymbolPicker
        Component.onCompleted: pe.backend.call("symbols", {}, (r) => { if (r.ok) iconSymbolPicker.names = r.symbols })
        onPicked: (v) => pe.setIcon({ glyph: Object.assign({}, (pe.icon || {}).glyph || {}, { kind: "symbol", value: v || "sparkles" }) })
    }
    ImagePicker {
        id: iconImagePicker
        backend: pe.backend
        onPicked: (v) => pe.setIcon({ glyph: Object.assign({}, (pe.icon || {}).glyph || {}, { kind: "image", value: v }) })
    }
}
