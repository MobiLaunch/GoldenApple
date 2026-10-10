// Precipitation map: CARTO's light OpenStreetMap tiles (close to Apple's map
// style) with RainViewer's latest radar on top, and the place marked with its
// temperature. Drawn in a Canvas so the corners stay round in any renderer.
import QtQuick
import "../lib/theme"

Card {
    id: card
    title: "Precipitation"; symbol: "drop"
    property real lat: 0
    property real lon: 0
    property string temperature: ""
    property string place: ""
    property string radarBase: ""        // host + path of the latest radar frame
    property bool online: true
    readonly property int zoom: 8

    function worldPx(z) {
        const n = 256 * Math.pow(2, z), la = lat * Math.PI / 180
        return Qt.point((lon + 180) / 360 * n, (1 - Math.log(Math.tan(la) + 1 / Math.cos(la)) / Math.PI) / 2 * n)
    }
    // [url, x, y, size] for every tile the map needs, base tiles first.
    readonly property var tiles: {
        const out = [], w = map.width, h = map.height
        if (w <= 0 || !online) return out
        const add = (z, tile, urlFor) => {
            const c = worldPx(z), scale = tile / 256
            const left = c.x * scale - w / 2, top = c.y * scale - h / 2
            const max = Math.pow(2, z)
            for (let ty = Math.floor(top / tile); ty <= Math.floor((top + h) / tile); ty++)
                for (let tx = Math.floor(left / tile); tx <= Math.floor((left + w) / tile); tx++)
                    if (ty >= 0 && ty < max)
                        out.push([urlFor(z, (tx % max + max) % max, ty), tx * tile - left, ty * tile - top, tile])
        }
        add(zoom, 256, (z, x, y) => "https://" + "abcd"[(x + y) % 4] + ".basemaps.cartocdn.com/light_all/" + z + "/" + x + "/" + y + "@2x.png")
        if (radarBase)
            add(zoom - 1, 512, (z, x, y) => radarBase + "/512/" + z + "/" + x + "/" + y + "/2/1_1.png")
        return out
    }
    onTilesChanged: { for (const t of tiles) map.loadImage(t[0]); map.requestPaint() }

    Canvas {
        id: map
        x: 4; y: 4
        width: parent.width - 8; height: parent.height - 8
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.beginPath(); ctx.roundedRect(0, 0, width, height, 14, 14); ctx.clip()
            ctx.fillStyle = "#e9edf1"; ctx.fillRect(0, 0, width, height)
            for (const t of card.tiles)
                if (isImageLoaded(t[0])) ctx.drawImage(t[0], t[1], t[2], t[3], t[3])
        }
    }
    Label {
        visible: !card.online
        anchors.centerIn: map
        text: "Map unavailable offline"
        color: "#8c000000"; px: 12
    }
    // The place, with its temperature.
    Rectangle {
        id: pin
        visible: card.online
        width: 30; height: 30; radius: 15
        x: map.x + map.width / 2 - 15; y: map.y + map.height / 2 - 15
        color: "#8aa3bb"
        border { width: 2.5; color: "#ffffff" }
        Label { anchors.centerIn: parent; text: card.temperature.replace("°", ""); px: 13; w: Font.Bold }
    }
    Label {
        visible: card.online
        anchors { horizontalCenter: pin.horizontalCenter; top: pin.bottom; topMargin: 2 }
        text: card.place
        color: "#d9000000"; px: 11; w: Font.DemiBold
        style: Text.Outline; styleColor: "#b3ffffff"
    }
    Label {
        anchors { right: map.right; bottom: map.bottom; margins: 5 }
        text: "© OpenStreetMap © CARTO"
        color: "#80000000"; px: 8
    }
}
