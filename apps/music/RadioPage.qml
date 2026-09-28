// Radio: internet radio from radio-browser.info, the community station
// directory (no account needed). Top stations, or search by name.
// GG_MUSIC_RADIO_FIXTURE=<file.json> reads stations from a file (tests).
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: page
    property var player
    property var stations: []
    property bool loading: false
    property bool failed: false
    readonly property string fixture: Quickshell.env("GG_MUSIC_RADIO_FIXTURE") ?? ""
    readonly property string api: "https://de1.api.radio-browser.info/json/stations/"

    function load(q) {
        loading = true; failed = false
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            loading = false
            try { stations = JSON.parse(x.responseText).filter((s) => s.url_resolved) } catch (e) { stations = []; failed = true }
        }
        x.open("GET", fixture ? "file://" + fixture
               : q ? api + "search?limit=60&hidebroken=true&order=clickcount&reverse=true&name=" + encodeURIComponent(q)
               : api + "topclick/60?hidebroken=true")
        x.send()
    }
    Component.onCompleted: load("")
    function play(s) {
        player.playList([{ title: s.name, artist: [s.country, (s.tags || "").split(",").slice(0, 2).join(", ")].filter((x) => x).join(" · "),
                           album: "", art: s.favicon || "", url: s.url_resolved, radio: true }], 0)
    }

    GridView {
        id: grid
        anchors.fill: parent
        readonly property int columns: Math.max(1, Math.floor((width - 56 + 20) / 170))
        cellWidth: (width - 56) / columns
        cellHeight: cellWidth - 20 + 58
        leftMargin: 28; rightMargin: 28; bottomMargin: 90; topMargin: 14
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.stations
        header: Item {
            width: grid.width - 56; height: 112
            Text {
                y: 22
                text: "Radio"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
            }
            Rectangle {
                anchors { right: parent.right; top: parent.top; topMargin: 24 }
                width: 240; height: 30; radius: 15
                color: Theme.fill
                border { width: 0.5; color: Theme.separator }
                Symbol { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; tone: "gray"; size: 13 }
                TextInput {
                    id: q
                    x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13 }
                    clip: true
                    onAccepted: page.load(text)
                    Text { visible: !q.text; text: "Search stations"; color: Theme.tertiaryLabel; font: q.font }
                }
            }
            Text {
                y: 78
                text: page.loading ? "Loading stations…" : page.failed ? "Radio isn't available right now." : q.text ? "Stations" : "Top Stations"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 17; weight: Font.Bold }
            }
        }
        delegate: Item {
            id: st
            required property var modelData
            width: grid.cellWidth; height: grid.cellHeight
            readonly property real size: grid.cellWidth - 20
            readonly property bool current: page.player.current?.url === modelData.url_resolved
            Rectangle {
                width: st.size; height: st.size; radius: 10
                color: Theme.dark ? "#2c2c2e" : "#f2f2f7"
                border { width: 0.5; color: Theme.separator }
                Image {
                    anchors { fill: parent; margins: parent.width * 0.18 }
                    source: st.modelData.favicon || ""
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(st.size * 2, st.size * 2)
                    asynchronous: true
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !st.modelData.favicon
                    text: (st.modelData.name || "?").trim().charAt(0).toUpperCase()
                    color: "#fa2d48"
                    font { family: Theme.fontUi; pixelSize: st.size * 0.36; weight: Font.Bold }
                }
                Rectangle {
                    anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                    width: 28; height: 28; radius: 14
                    visible: stHover.hovered || st.current
                    color: "#fa2d48"
                    Symbol { anchors.centerIn: parent; anchors.horizontalCenterOffset: st.current ? 0 : 1; name: st.current ? "speaker-wave" : "play"; tone: "white"; size: 12 }
                }
            }
            Text {
                y: st.size + 6; width: st.size; elide: Text.ElideRight
                text: st.modelData.name.trim()
                color: st.current ? "#fa2d48" : Theme.label
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
            }
            Text {
                y: st.size + 23; width: st.size; elide: Text.ElideRight
                text: [st.modelData.country, (st.modelData.tags || "").split(",")[0]].filter((x) => x).join(" · ")
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            HoverHandler { id: stHover }
            TapHandler { onTapped: page.play(st.modelData) }
        }
    }
}
