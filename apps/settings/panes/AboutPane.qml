// About: the computer, as About This Mac shows it.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var facts: ({})
    Component.onCompleted: sys.sh(
        ". /etc/os-release; echo \"os=$PRETTY_NAME\"; echo \"build=${BUILD_ID:-$VERSION_ID}\"; echo \"host=$(cat /etc/hostname 2>/dev/null || hostname)\";"
        + "echo \"cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')\"; echo \"cores=$(nproc)\";"
        + "echo \"mem=$(awk '/MemTotal/ {printf \"%.0f GB\", $2/1048576}' /proc/meminfo)\";"
        + "echo \"gpu=$( (lspci 2>/dev/null | grep -m1 -iE 'vga|3d|display' | sed 's/.*: //') || true)\";"
        + "echo \"kernel=$(uname -r)\"; echo \"disk=$(df -h / | awk 'NR==2 {print $4 \" available of \" $2}')\"",
        (o) => { const f = {}; for (const l of o.split("\n")) { const i = l.indexOf("="); if (i > 0) f[l.slice(0, i)] = l.slice(i + 1) } facts = f })

    Column {
        width: parent.width
        spacing: 6
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: Qt.resolvedUrl("../../lib/assets/symbols/logo" + (Theme.dark ? "" : "@dark") + ".svg")
            sourceSize: Qt.size(128, 128)
            width: 64; height: 64
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Golden Gate"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 22; weight: Font.Bold }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: pane.facts.build ? "Version " + pane.facts.build : ""
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
    }
    Group {
        Repeater {
            model: [["Name", pane.facts.host], ["Processor", pane.facts.cpu ? pane.facts.cpu + " (" + pane.facts.cores + " cores)" : ""],
                    ["Memory", pane.facts.mem], ["Graphics", pane.facts.gpu], ["Storage", pane.facts.disk],
                    ["Operating System", pane.facts.os], ["Kernel", pane.facts.kernel]].filter((r) => r[1])
            delegate: SetRow {
                required property var modelData
                title: modelData[0]
                Text { text: modelData[1]; color: Theme.secondaryLabel; elide: Text.ElideRight; width: Math.min(implicitWidth, 320); font { family: Theme.fontUi; pixelSize: 13 } }
            }
        }
    }
}
