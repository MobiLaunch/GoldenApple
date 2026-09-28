// The sky behind Weather: a gradient for the condition and time of day, soft
// clouds in proportion to the cover, and stars on clear nights. Painted once per
// change (a Canvas), so it costs nothing while the window just sits there.
import QtQuick

Item {
    id: sky
    property string kind: "cloudy"      // clear | partly | cloudy | fog | rain | snow | storm, + "-night"
    property real radius: 0
    property int seed: 7

    readonly property var palettes: ({
        "clear":        ["#2a78cf", "#7db8ea", 0.0],
        "partly":       ["#4a8acb", "#a2c6e6", 0.35],
        "cloudy":       ["#86a4c0", "#c3d3e1", 0.85],
        "fog":          ["#a6b2bc", "#d6dce1", 1.0],
        "rain":         ["#57687a", "#8c9aa8", 0.9],
        "snow":         ["#8ea2b7", "#d5dee7", 0.8],
        "storm":        ["#363e4b", "#666f7e", 1.0],
        "clear-night":  ["#06112a", "#213863", 0.0],
        "partly-night": ["#0f1a31", "#2d3e5f", 0.35],
        "cloudy-night": ["#232a36", "#434c5a", 0.85],
        "fog-night":    ["#2b3137", "#4d555d", 1.0],
        "rain-night":   ["#1b222d", "#394351", 0.9],
        "snow-night":   ["#2d3747", "#58667c", 0.8],
    })
    readonly property var palette: palettes[kind] ?? palettes["cloudy"]
    readonly property bool night: kind.endsWith("-night")
    // The glass cards take their tint from the sky.
    readonly property color cardTint: night ? Qt.rgba(0.02, 0.05, 0.12, 0.30)
                                    : kind === "clear" || kind === "partly" ? Qt.rgba(0.05, 0.25, 0.50, 0.24)
                                    : kind === "rain" || kind === "storm" ? Qt.rgba(0.08, 0.12, 0.18, 0.28)
                                    : Qt.rgba(0.14, 0.26, 0.40, 0.26)

    Rectangle {
        anchors.fill: parent
        radius: sky.radius
        gradient: Gradient {
            GradientStop { position: 0; color: sky.palette[0] }
            GradientStop { position: 1; color: sky.palette[1] }
        }
    }

    Canvas {
        id: clouds
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: sky; function onKindChanged() { clouds.requestPaint() } }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height, r = sky.radius
            if (w <= 0 || h <= 0) return
            // Stay inside the window's rounded corners.
            ctx.beginPath()
            ctx.roundedRect(0, 0, w, h, r, r)
            ctx.clip()
            let s = sky.seed
            const rand = () => { s = (s * 16807) % 2147483647; return s / 2147483647 }
            if (sky.night && sky.palette[2] < 0.5) {
                for (let i = 0; i < w * h / 2600; i++) {
                    const a = 0.25 + rand() * 0.6
                    ctx.fillStyle = Qt.rgba(1, 1, 1, a)
                    const d = rand() < 0.1 ? 1.6 : 1
                    ctx.fillRect(rand() * w, rand() * h * 0.8, d, d)
                }
            }
            const cover = sky.palette[2]
            if (cover <= 0) return
            const grey = sky.kind.startsWith("rain") || sky.kind.startsWith("storm") ? 0.55
                       : sky.night ? 0.45 : 1
            // Clouds are clusters of soft blobs, thicker towards the top of the sky.
            const clusters = Math.round(6 + cover * 22) * Math.max(1, w / 900)
            for (let c = 0; c < clusters; c++) {
                const cx = rand() * w * 1.1 - w * 0.05
                const cy = Math.pow(rand(), 1.4) * h * (sky.kind.startsWith("fog") ? 1 : 0.85)
                const size = 60 + rand() * 170
                const blobs = 5 + Math.floor(rand() * 7)
                for (let b = 0; b < blobs; b++) {
                    const bx = cx + (rand() - 0.5) * size * 2.2
                    const by = cy + (rand() - 0.5) * size * 0.5
                    const br = size * (0.35 + rand() * 0.5)
                    const a = (0.05 + rand() * 0.12) * (0.5 + cover)
                    const g = ctx.createRadialGradient(bx, by, 0, bx, by, br)
                    g.addColorStop(0, Qt.rgba(grey, grey, grey * 1.02, a))
                    g.addColorStop(0.6, Qt.rgba(grey, grey, grey * 1.02, a * 0.45))
                    g.addColorStop(1, Qt.rgba(grey, grey, grey, 0))
                    ctx.fillStyle = g
                    ctx.fillRect(bx - br, by - br, br * 2, br * 2)
                }
            }
        }
    }
}
