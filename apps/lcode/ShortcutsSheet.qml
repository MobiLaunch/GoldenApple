// The keyboard shortcuts, Xcode's own: CitronOS's keyd layer maps ⌘ to Ctrl
// inside apps, so the keys under your fingers are the ones you know.
import QtQuick
import "../lib"
import "../lib/theme"
import "commands.js" as Commands

Sheet {
    id: sheet
    panelWidth: 560
    panelHeight: 520

    property var app
    // Your key bindings (Settings ▸ Key Bindings), menu by menu, and the fixed
    // editing and Simulator keys.
    readonly property var groups: {
        const out = Commands.MENUS.map((m) => [m, Commands.COMMANDS.filter((c) => c.menu === m && app && app.keysFor(c.id).length)
            .map((c) => [c.title.replace("…", ""), app.keysFor(c.id).map(Commands.display).join("  ")])]).filter((g) => g[1].length)
        out.push(["Editing", [["Shift Right / Left", "⌘] / ⌘["], ["Indent / Outdent", "⇥ / ⇧⇥"]]])
        out.push(["Simulator", [["Home", "⇧⌘H"], ["Rotate Left / Right", "⌘← / ⌘→"], ["Save Screen", "⌘S"]]])
        return out
    }

    Text {
        id: title
        text: "Keyboard Shortcuts"
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
    }
    Flickable {
        y: title.height + 10
        width: parent.width
        height: parent.height - y - 44
        clip: true
        contentHeight: list.height
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: list
            width: parent.width
            Repeater {
                model: sheet.groups
                delegate: Column {
                    required property var modelData
                    width: list.width
                    SidebarSection { text: modelData[0]; leftPadding: 0 }
                    Repeater {
                        model: modelData[1]
                        delegate: Item {
                            required property var modelData
                            width: list.width
                            height: 24
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                            Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: modelData[1]; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                        }
                    }
                }
            }
        }
    }
    Row {
        anchors { right: parent.right; bottom: parent.bottom }
        spacing: 8
        Button { text: "Customize…"; onClicked: { sheet.close(); sheet.app.openSettings(6) } }
        Button { text: "Done"; prominent: true; onClicked: sheet.close() }
    }
}
