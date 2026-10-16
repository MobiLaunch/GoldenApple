// Open: pick a project folder (any project LCode can build, or any folder).
import QtQuick
import "../lib"
import "../lib/theme"

Sheet {
    id: panel
    property var backend
    signal chosen(string path)
    panelWidth: 620

    function choose(path) { close(); chosen(path) }

    Column {
        width: parent.width
        spacing: 12
        Text {
            text: "Open a Project"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Choose a project folder (Package.swift, Cargo.toml, meson.build, main.py or an LCode app). Double-click to go into a folder."
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
        }
        FolderBrowser {
            id: browser
            width: parent.width
            height: 280
            backend: panel.backend
            onActivated: (path) => panel.choose(path)
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            Button { text: "Cancel"; onClicked: panel.close() }
            Button {
                text: "Open"
                prominent: true
                onClicked: panel.choose(browser.selected || browser.path)
            }
        }
    }
}
