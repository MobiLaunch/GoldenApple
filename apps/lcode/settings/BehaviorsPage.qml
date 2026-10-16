// Settings ▸ Behaviors: what LCode does as builds, tests and runs start and
// end — show or hide the debug area, switch navigator, jump to the first
// error, notify, play a sound.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../commands.js" as Commands

Item {
    id: page
    property var app
    property var backend
    property Item overlay: null
    property string selected: "buildFailed"
    readonly property var options: Commands.behavior(selected, app.settings.behaviors)

    function set(key, value) {
        const all = Object.assign({}, app.settings.behaviors || {})
        all[selected] = Object.assign({}, all[selected] || {}, { [key]: value })
        app.saveSettings({ behaviors: all })
    }

    Rectangle {
        id: list
        x: 20; y: 20
        width: 200
        height: parent.height - 40
        radius: 10
        color: Theme.dark ? "#14ffffff" : "#08000000"
        border { width: 1; color: Theme.separator }
        Column {
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: Commands.EVENTS
                delegate: Column {
                    required property var modelData
                    required property int index
                    width: parent.width
                    SidebarSection {
                        visible: index === 0 || Commands.EVENTS[index - 1].group !== modelData.group
                        text: modelData.group
                        topSpacing: index === 0 ? 4 : 10
                    }
                    SidebarRow {
                        width: parent.width
                        height: 28
                        text: modelData.title
                        symbol: modelData.id.endsWith("Failed") ? "xmark-circle" : modelData.id.endsWith("Succeeded") ? "checkmark" : modelData.id === "runStarted" ? "play" : "stop"
                        selected: page.selected === modelData.id
                        onClicked: page.selected = modelData.id
                    }
                }
            }
        }
    }

    Column {
        x: list.x + list.width + 24
        y: 24
        width: parent.width - x - 24
        spacing: 14
        Text {
            text: ({ buildSucceeded: "When a build succeeds", buildFailed: "When a build fails", testSucceeded: "When testing succeeds",
                     testFailed: "When testing fails", runStarted: "When running starts", runExited: "When running exits" })[page.selected] || ""
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
        }
        FormRow {
            labelWidth: 120
            label: "Debug Area"
            PopUpButton {
                options: ["Don't Change", "Show", "Hide"]
                current: Math.max(0, ["", "show", "hide"].indexOf(page.options.debug || ""))
                menuParent: page.overlay
                onPicked: (i) => page.set("debug", ["", "show", "hide"][i])
            }
        }
        FormRow {
            labelWidth: 120
            label: "Navigator"
            PopUpButton {
                options: ["Don't Change", "Project", "Issues", "Reports"]
                current: Math.max(0, ["", "project", "issues", "reports"].indexOf(page.options.navigator || ""))
                menuParent: page.overlay
                onPicked: (i) => page.set("navigator", ["", "project", "issues", "reports"][i])
            }
        }
        FormRow {
            labelWidth: 120
            label: "Also"
            labelHeight: 20
            Column {
                spacing: 8
                Checkbox {
                    width: 440
                    visible: page.selected.endsWith("Failed")
                    text: "Jump to the first error"
                    checked: !!page.options.reveal
                    onToggled: (on) => page.set("reveal", on)
                }
                Checkbox {
                    width: 440
                    text: "Show a notification"
                    checked: !!page.options.notify
                    onToggled: (on) => page.set("notify", on)
                }
                Checkbox {
                    width: 440
                    text: "Play a sound"
                    checked: !!page.options.sound
                    onToggled: (on) => page.set("sound", on)
                }
            }
        }
    }
}
