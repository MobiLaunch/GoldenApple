// Settings ▸ Locations: the toolchains LCode builds with.
import QtQuick
import "../../lib"
import "../../lib/theme"

Page {
    id: page
    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "LCode finds each toolchain on your PATH. Set a location to use another one, like a Swift you unpacked yourself or rustup's cargo."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 12 }
    }
    Repeater {
        model: [
            { id: "swift", key: "swiftPath", placeholder: "/usr/bin/swift" },
            { id: "python", key: "pythonPath", placeholder: "/usr/bin/python3" },
            { id: "cargo", key: "cargoPath", placeholder: "~/.cargo/bin/cargo" },
            { id: "meson", key: "mesonPath", placeholder: "/usr/bin/meson" },
            { id: "goldengate", key: "qsPath", placeholder: "/usr/bin/qs" },
        ]
        delegate: FormRow {
            id: loc
            required property var modelData
            readonly property var info: page.app.toolchains[modelData.id] || ({ name: modelData.id, path: "", version: "", hint: "" })
            label: modelData.id === "goldengate" ? "Quickshell" : info.name
            detail: info.path ? (info.version || "Installed") + "  ·  " + info.path : "Not installed. " + (info.hint || "")
            SettingField {
                width: 340
                value: page.app.settings[loc.modelData.key] || ""
                placeholder: loc.info.path || loc.modelData.placeholder
                onCommitted: (v) => page.app.saveSettings({ [loc.modelData.key]: v })
            }
        }
    }
    FormGap {}
    FormRow {
        label: "Settings File"
        detail: "LCode's settings live in ~/.config/golden-gate/lcode.json; your themes and key bindings too."
        Button { text: "Show in Files"; onClicked: page.app.revealSettingsFile() }
    }
}
