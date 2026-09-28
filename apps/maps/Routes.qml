// Routes on the map: the chosen one in Maps blue over a white casing, the
// alternatives in light blue under it, each with its time in a callout (tap
// one to choose it).
import QtQuick
import QtQuick.Shapes
import "../lib/theme"
import "api.js" as Api

Item {
    id: overlay
    property var view
    property var routes: []
    property int selected: 0
    signal picked(int index)
    anchors.fill: parent

    Repeater {
        model: overlay.routes.length
        delegate: Shape {
            id: line
            required property int index
            readonly property bool chosen: index === overlay.selected
            z: chosen ? 2 : 1
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // Screen points, recomputed as the map moves.
            readonly property var pts: {
                const m = overlay.view, cs = overlay.routes[index]?.geometry?.coordinates ?? []
                void m.lat; void m.lon; void m.zoom; void m.width; void m.height
                const out = []
                let last = null
                for (const c of cs) {
                    const p = m.toScreen(c[1], c[0])
                    // Skip points closer than a pixel to the last one.
                    if (last && Math.abs(p.x - last.x) < 1 && Math.abs(p.y - last.y) < 1) continue
                    out.push(p); last = p
                }
                return out
            }
            ShapePath {
                strokeColor: "#ffffff"; strokeWidth: line.chosen ? 10 : 9
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathPolyline { path: line.pts }
            }
            ShapePath {
                strokeColor: line.chosen ? "#0a84ff" : "#98c4f5"; strokeWidth: line.chosen ? 6.5 : 5.5
                fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
                PathPolyline { path: line.pts }
            }
        }
    }
    // Time callouts, part-way along each route (staggered so they don't overlap).
    Repeater {
        model: overlay.routes.length
        delegate: Rectangle {
            id: callout
            required property int index
            readonly property bool chosen: index === overlay.selected
            readonly property var coords: overlay.routes[index]?.geometry?.coordinates ?? []
            readonly property var at: coords.length ? coords[Math.floor(coords.length * (0.45 + 0.12 * index)) % coords.length] : [0, 0]
            readonly property point p: { void overlay.view.lat; void overlay.view.lon; void overlay.view.zoom; return overlay.view.toScreen(at[1], at[0]) }
            z: chosen ? 4 : 3
            x: p.x - width / 2; y: p.y - height - 10
            width: col.width + 18; height: col.height + 10
            radius: 7
            color: chosen ? "#0a84ff" : "#ffffff"
            border { width: 0.5; color: "#26000000" }
            Column {
                id: col
                anchors.centerIn: parent
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Api.duration(overlay.routes[callout.index]?.duration ?? 0)
                    color: callout.chosen ? "#ffffff" : "#0a84ff"
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: callout.index === 0 && overlay.routes.length > 1
                    text: "Fastest"
                    color: callout.chosen ? "#e6ffffff" : "#0a84ff"
                    font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium }
                }
            }
            TapHandler { onTapped: overlay.picked(callout.index) }
        }
    }
}
