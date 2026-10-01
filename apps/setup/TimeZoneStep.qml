// Select Your Time Zone: every zone the system knows, searchable, with the
// one your region suggests chosen.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib"
import "../lib/theme"

StepFrame {
    id: step
    property string zone
    signal zoneChosen(string zone)
    symbol: "clock"
    title: "Select Your Time Zone"
    text: "Closest city: " + step.city(zone)

    property var zones: []
    function city(z) { return (z.split("/").pop() || z).replace(/_/g, " ") }
    function area(z) { return z.split("/").slice(0, -1).join(" › ").replace(/_/g, " ") }

    Process {
        running: true
        command: ["sh", "-c", "timedatectl list-timezones 2>/dev/null || (cd /usr/share/zoneinfo && find . -type f | sed 's|^./||' | grep -E '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/' | sort)"]
        stdout: StdioCollector { onStreamFinished: step.zones = text.split("\n").filter((z) => z.includes("/")) }
    }

    TextField {
        id: q
        width: parent.width
        height: 30
        search: true
        placeholder: "Search for a city"
    }
    ListView {
        id: list
        y: 40; width: parent.width; height: parent.height - 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: step.zones.filter((z) => z.toLowerCase().replace(/_/g, " ").includes(q.text.toLowerCase()))
        onCountChanged: if (!q.text) positionViewAtIndex(Math.max(0, model.indexOf(step.zone)), ListView.Center)
        delegate: Rectangle {
            required property string modelData
            readonly property bool chosen: modelData === step.zone
            width: list.width; height: 34; radius: 8
            color: chosen ? Theme.accent : "transparent"
            Text {
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: step.city(parent.modelData)
                color: parent.chosen ? "#ffffff" : Theme.label
                font { family: Theme.fontUi; pixelSize: 13 }
            }
            Text {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: step.area(parent.modelData)
                color: parent.chosen ? "#ccffffff" : Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            TapHandler { onTapped: step.zoneChosen(parent.modelData) }
        }
    }
}
