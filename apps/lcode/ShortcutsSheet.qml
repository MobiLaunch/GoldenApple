// The keyboard shortcuts, Xcode's own: Golden Gate's keyd layer maps ⌘ to Ctrl
// inside apps, so the keys under your fingers are the ones you know.
import QtQuick
import "../lib"
import "../lib/theme"

Sheet {
    id: sheet
    panelWidth: 560
    panelHeight: 520

    readonly property var groups: [
        ["Product", [["Run", "⌘R"], ["Build", "⌘B"], ["Test", "⌘U"], ["Stop", "⌘."], ["Clean Build Folder", "⇧⌘K"]]],
        ["File", [["New File", "⌘N"], ["New Project", "⇧⌘N"], ["Open", "⌘O"], ["Open Quickly", "⇧⌘O"], ["Save", "⌘S"], ["Save All", "⌥⌘S"]]],
        ["Edit", [["Comment Selection", "⌘/"], ["Shift Right / Left", "⌘] / ⌘["], ["Go to Line", "⌘L"]]],
        ["Find", [["Find", "⌘F"], ["Find and Replace", "⌥⌘F"], ["Find Next / Previous", "⌘G / ⇧⌘G"], ["Find in Project", "⇧⌘F"]]],
        ["View", [["Navigator", "⌘0"], ["Project / Find / Issue / Report Navigator", "⌘1 / ⌘4 / ⌘5 / ⌘9"], ["Debug Area", "⇧⌘Y"], ["Inspectors", "⌥⌘0"], ["Clear Console", "⌘K"]]],
        ["Simulator", [["Home", "⇧⌘H"], ["Rotate Left / Right", "⌘← / ⌘→"], ["Save Screen", "⌘S"]]],
    ]

    Text {
        id: title
        text: "Keyboard Shortcuts"
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
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
                            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                            Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: modelData[1]; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } }
                        }
                    }
                }
            }
        }
    }
    Button { anchors { right: parent.right; bottom: parent.bottom } text: "Done"; prominent: true; onClicked: sheet.close() }
}
