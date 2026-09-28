// Wallpaper: the current one, and the Golden Gate collection and your own
// (~/Pictures/Wallpapers) to choose from. The shell picks it up at once.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var walls: []
    readonly property string current: sys.prefs.wallpaper || Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/tide.png"
    Component.onCompleted: sys.sh("ls -1 /usr/share/backgrounds/golden-gate/*.png \"${XDG_DATA_HOME:-$HOME/.local/share}\"/backgrounds/golden-gate/*.png \"$HOME\"/Pictures/Wallpapers/*.jpg \"$HOME\"/Pictures/Wallpapers/*.png 2>/dev/null",
                                  (o) => walls = [...new Set(o.split("\n").filter((l) => l))])
    Group {
        SetRow {
            title: pane.current.split("/").pop().replace(/\.\w+$/, "").replace(/[-_]/g, " ").replace(/^\w/, (c) => c.toUpperCase())
            subtitle: "Current wallpaper"
            RoundedImage { width: 160; height: 100; radius: 8; source: "file://" + pane.current }
        }
    }
    Group {
        title: "Wallpapers"
        Flow {
            width: parent.width
            padding: 14
            spacing: 16
            Repeater {
                model: pane.walls
                delegate: Item {
                    id: tile
                    required property string modelData
                    readonly property bool chosen: modelData === pane.current
                    width: 128; height: 100
                    Item {
                        width: 128; height: 80
                        scale: wtap.pressed ? 0.95 : whover.hovered ? 1.03 : 1
                        Behavior on scale { Spring { spring: Theme.snappy } }
                        // The chosen one has an accent ring a little outside it.
                        Rectangle {
                            anchors { fill: parent; margins: -4 }
                            radius: 12
                            color: "transparent"
                            border { width: 3; color: Theme.accent }
                            opacity: tile.chosen ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 160 } }
                        }
                        RoundedImage { anchors.fill: parent; radius: 8; source: "file://" + tile.modelData }
                    }
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        text: tile.modelData.split("/").pop().replace(/\.\w+$/, "").replace(/[-_]/g, " ").replace(/^\w/, (c) => c.toUpperCase())
                        color: tile.chosen ? Theme.label : Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11; weight: tile.chosen ? Font.DemiBold : Font.Normal }
                    }
                    HoverHandler { id: whover }
                    TapHandler { id: wtap; onTapped: pane.sys.setPref(["wallpaper"], tile.modelData) }
                }
            }
        }
    }
}
