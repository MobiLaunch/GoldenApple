// A compact folder browser for choosing where a project lives (New Project,
// Open, Clone): places on the left, the folders of the current one on the
// right, Swift packages marked. Double-click a folder to go into it.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: browser
    property var backend
    property string path: ""
    property var listing: ({ dirs: [], places: [], parent: "", isProject: false })
    property string selected: ""
    signal activated(string path, bool isProject)
    implicitHeight: 250

    function load(p) {
        backend.call("dirs", { path: p }, (r) => {
            if (!r.ok) return
            browser.listing = r
            browser.path = r.path
            browser.selected = ""
        })
    }
    Component.onCompleted: load(path || "~/Developer")

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.dark ? "#1affffff" : "#0a000000"
        border { width: 1; color: Theme.separator }
    }

    Column {
        id: places
        x: 6; y: 6
        width: 130
        Repeater {
            model: browser.listing.places
            delegate: SidebarRow {
                required property var modelData
                width: places.width
                height: 28
                text: modelData.name
                symbol: modelData.name === "Home" ? "house" : modelData.name === "Developer" ? "hammer" : modelData.name === "Desktop" ? "window" : "folder"
                selected: browser.path === modelData.path
                onClicked: browser.load(modelData.path)
            }
        }
    }
    Rectangle { x: places.x + places.width + 6; y: 6; width: 1; height: parent.height - 12; color: Theme.separator }

    Item {
        x: places.x + places.width + 14
        y: 6
        width: parent.width - x - 6
        height: parent.height - 12
        Row {
            id: pathRow
            spacing: 6
            ToolbarButton {
                symbol: "chevron-left"
                enabled: browser.listing.parent && browser.listing.parent !== browser.path
                onClicked: browser.load(browser.listing.parent)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: pathRow.parent.width - 40
                text: browser.path
                elide: Text.ElideMiddle
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
        }
        ListView {
            id: list
            anchors { top: pathRow.bottom; topMargin: 4; left: parent.left; right: parent.right; bottom: parent.bottom }
            clip: true
            model: browser.listing.dirs
            boundsBehavior: Flickable.StopAtBounds
            delegate: SidebarRow {
                required property var modelData
                width: list.width
                height: 28
                text: modelData.name
                symbol: modelData.isProject ? "hammer" : "folder"
                badge: modelData.isProject ? "Swift" : ""
                selected: browser.selected === modelData.path
                onClicked: browser.selected = modelData.path
                TapHandler {
                    onDoubleTapped: {
                        if (modelData.isProject) browser.activated(modelData.path, true)
                        else browser.load(modelData.path)
                    }
                }
            }
            EmptyState {
                anchors.fill: parent
                visible: list.count === 0
                symbol: "folder"
                title: "No Folders"
            }
        }
    }
}
