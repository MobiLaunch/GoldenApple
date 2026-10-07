// A tiled web map, drawn with plain Images so it runs in any renderer.
//
// Tiles come from a fixed pool of slots, each keeping the same column/row
// modulo the grid, so panning past a tile edge reloads one column, not every
// tile. Drag or two-finger scroll to pan; the mouse wheel, pinch or a double
// click zooms around the pointer. Overlays (routes, pins) go inside and place
// themselves with toScreen().
import QtQuick
import "../lib/theme"
import "api.js" as Api

Item {
    id: map
    property real lat: 37.7749
    property real lon: -122.4194
    property real zoom: 12
    property string style: "standard"
    property bool online: true
    default property alias overlays: overlayLayer.data
    signal tapped(real lat, real lon)
    signal longPressed(real lat, real lon)

    readonly property var styleDef: Api.STYLES[style] ?? Api.STYLES.standard
    readonly property int tz: Math.max(2, Math.min(19, Math.round(zoom)))
    readonly property real scale: Math.pow(2, zoom - tz)
    readonly property real ts: 256 * scale
    readonly property var c: Api.worldPx(lat, lon, tz)
    readonly property int firstX: Math.floor((c.x - width / 2 / scale) / 256)
    readonly property int firstY: Math.floor((c.y - height / 2 / scale) / 256)
    readonly property int cols: Math.ceil(width / ts) + 2
    readonly property int rows: Math.ceil(height / ts) + 2
    clip: true

    function toScreen(la, lo) {
        const p = Api.worldPx(la, lo, zoom), o = Api.worldPx(lat, lon, zoom)
        let dx = p.x - o.x
        const world = 256 * Math.pow(2, zoom)
        if (dx > world / 2) dx -= world; else if (dx < -world / 2) dx += world
        return Qt.point(width / 2 + dx, height / 2 + p.y - o.y)
    }
    function toCoord(x, y) {
        const o = Api.worldPx(lat, lon, zoom)
        return Api.fromWorldPx(o.x + x - width / 2, o.y + y - height / 2, zoom)
    }
    function wrapLon(l) { return ((l + 180) % 360 + 360) % 360 - 180 }
    function setCenter(la, lo) { lat = Math.max(-85, Math.min(85, la)); lon = wrapLon(lo) }
    function zoomAround(x, y, z) {
        z = Math.max(2, Math.min(19, z))
        const p = toCoord(x, y)
        zoom = z
        const w = Api.worldPx(p.lat, p.lon, z)
        const cc = Api.fromWorldPx(w.x - (x - width / 2), w.y - (y - height / 2), z)
        setCenter(cc.lat, cc.lon)
    }
    function flyTo(la, lo, z) {
        fly.stop()
        la = Math.max(-85, Math.min(85, la)); lo = wrapLon(lo)
        z = Math.max(2, Math.min(19, z ?? zoom))
        if (Theme.reduceMotion) { setCenter(la, lo); zoom = z; return }
        latAnim.to = la; lonAnim.to = lo; zoomAnim.to = z
        // Keep the short way round the date line.
        if (Math.abs(lo - lon) > 180) lon += lo > lon ? 360 : -360
        fly.start()
    }
    function fit(points, insetLeft) {
        const inset = insetLeft ?? 0
        const f = Api.fitZoom(points, Math.max(100, width - inset - 120), Math.max(100, height - 160))
        // Centre in the part of the map not covered by the panel.
        const zc = f.zoom
        const wc = Api.worldPx(f.center.lat, f.center.lon, zc)
        const cc = Api.fromWorldPx(wc.x - inset / 2, wc.y, zc)
        flyTo(cc.lat, cc.lon, zc)
    }
    ParallelAnimation {
        id: fly
        NumberAnimation { id: latAnim; target: map; property: "lat"; duration: 650; easing.type: Easing.InOutCubic }
        NumberAnimation { id: lonAnim; target: map; property: "lon"; duration: 650; easing.type: Easing.InOutCubic }
        NumberAnimation { id: zoomAnim; target: map; property: "zoom"; duration: 650; easing.type: Easing.InOutCubic }
        onFinished: map.lon = map.wrapLon(map.lon)
    }

    Rectangle { anchors.fill: parent; color: map.styleDef.bg }

    Repeater {
        model: map.cols * map.rows
        delegate: Image {
            required property int index
            readonly property int sc: index % map.cols
            readonly property int sr: Math.floor(index / map.cols)
            readonly property int tx: map.firstX + (((sc - map.firstX) % map.cols) + map.cols) % map.cols
            readonly property int ty: map.firstY + (((sr - map.firstY) % map.rows) + map.rows) % map.rows
            readonly property int n: 1 << map.tz
            x: map.width / 2 + (tx * 256 - map.c.x) * map.scale
            y: map.height / 2 + (ty * 256 - map.c.y) * map.scale
            width: Math.ceil(map.ts) + 1; height: width
            visible: ty >= 0 && ty < n
            source: visible && map.online ? map.styleDef.url(map.tz, ((tx % n) + n) % n, ty) : ""
            asynchronous: true
            smooth: true
        }
    }

    // Hybrid's names and roads, over the imagery.
    Repeater {
        model: map.styleDef.labels ? map.cols * map.rows : 0
        delegate: Image {
            required property int index
            readonly property int sc: index % map.cols
            readonly property int sr: Math.floor(index / map.cols)
            readonly property int tx: map.firstX + (((sc - map.firstX) % map.cols) + map.cols) % map.cols
            readonly property int ty: map.firstY + (((sr - map.firstY) % map.rows) + map.rows) % map.rows
            readonly property int n: 1 << map.tz
            x: map.width / 2 + (tx * 256 - map.c.x) * map.scale
            y: map.height / 2 + (ty * 256 - map.c.y) * map.scale
            width: Math.ceil(map.ts) + 1; height: width
            visible: ty >= 0 && ty < n
            source: visible && map.online ? map.styleDef.labels(map.tz, ((tx % n) + n) % n, ty) : ""
            asynchronous: true
            smooth: true
        }
    }

    Item { id: overlayLayer; anchors.fill: parent }

    // The scale, bottom left, as in Maps: a round distance and its length.
    property bool imperial: false
    property real scaleInset: 0                // where the map shows past the panel
    Item {
        id: scaleBar
        readonly property var bar: Api.scaleBar(map.lat, map.zoom, 110, map.imperial)
        readonly property bool dark: map.style === "dark" || map.style === "satellite" || map.style === "hybrid"
        x: map.scaleInset + 14; anchors { bottom: parent.bottom; bottomMargin: 14 }
        width: bar.px; height: 22
        Text {
            anchors { left: parent.left; bottom: line.top; bottomMargin: 2 }
            text: scaleBar.bar.label
            color: scaleBar.dark ? "#ffffff" : "#3a3a3c"
            font { family: Theme.fontUi; pixelSize: Theme.fs(10); weight: Font.DemiBold }
            style: Text.Outline; styleColor: scaleBar.dark ? "#80000000" : "#b3ffffff"
        }
        Rectangle {
            id: line
            anchors { left: parent.left; bottom: parent.bottom }
            width: scaleBar.bar.px; height: 4; radius: 2
            color: scaleBar.dark ? "#ffffff" : "#3a3a3c"
            border { width: 1; color: scaleBar.dark ? "#80000000" : "#ccffffff" }
        }
    }

    // Gestures
    DragHandler {
        id: drag
        target: null
        property var start
        onActiveChanged: if (active) { fly.stop(); start = Api.worldPx(map.lat, map.lon, map.zoom) }
        onTranslationChanged: if (active) {
            const p = Api.fromWorldPx(start.x - translation.x, start.y - translation.y, map.zoom)
            map.setCenter(p.lat, p.lon)
        }
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => {
            fly.stop()
            if (ev.pixelDelta.x !== 0 || ev.pixelDelta.y !== 0) {
                // Touchpad: two fingers pan, as in Maps.
                const o = Api.worldPx(map.lat, map.lon, map.zoom)
                const p = Api.fromWorldPx(o.x - ev.pixelDelta.x, o.y - ev.pixelDelta.y, map.zoom)
                map.setCenter(p.lat, p.lon)
            } else {
                map.zoomAround(ev.x, ev.y, map.zoom + ev.angleDelta.y / 120 * 0.5)
            }
        }
    }
    PinchHandler {
        target: null
        property real startZoom
        onActiveChanged: if (active) { fly.stop(); startZoom = map.zoom }
        onActiveScaleChanged: if (active) map.zoomAround(centroid.position.x, centroid.position.y, startZoom + Math.log2(activeScale))
    }
    TapHandler {
        onTapped: (p) => { const c = map.toCoord(p.position.x, p.position.y); map.tapped(c.lat, c.lon) }
        onDoubleTapped: (p) => {
            const x = p.position.x, y = p.position.y, z = Math.min(19, map.zoom + 1)
            const target = map.toCoord(x, y)
            // Animate: zoom in keeping the point under the pointer.
            const w = Api.worldPx(target.lat, target.lon, z)
            const cc = Api.fromWorldPx(w.x - (x - map.width / 2), w.y - (y - map.height / 2), z)
            map.flyTo(cc.lat, cc.lon, z)
        }
        onLongPressed: (p) => { const c = map.toCoord(p.position.x, p.position.y); map.longPressed(c.lat, c.lon) }
    }

    Text {
        anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
        text: map.styleDef.credit
        color: map.style === "dark" || map.style === "satellite" || map.style === "hybrid" ? "#b3ffffff" : "#8c000000"
        font { family: Theme.fontUi; pixelSize: Theme.fs(9) }
    }
}

