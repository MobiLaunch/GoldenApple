// One desktop widget's content, by kind and size, drawn from the shared Feeds.
// The desktop and the gallery's previews both use it. Kinds and the sizes each
// comes in are listed in `catalog`; `app` is what a click opens.
import Quickshell
import QtQuick
import QtQuick.Shapes
import "../ui/theme"
import "../ui" as Shared
import "../components"

Item {
    id: face
    property string kind: "calendar"
    property string size: "small"
    property var feeds
    readonly property bool medium: size !== "small"
    // The weather draws its own sky; everything else sits on glass.
    readonly property bool ownBackground: kind === "weather"
    readonly property real r: 22

    readonly property color red: Theme.dark ? "#ff453a" : "#ff3b30"
    readonly property date now: feeds ? feeds.now : new Date()

    Loader {
        anchors.fill: parent
        sourceComponent: ({ calendar: calendarFace, clock: clockFace, weather: weatherFace, music: musicFace,
                            notes: notesFace, battery: batteryFace })[face.kind] ?? null
    }

    component Label: Text {
        color: Theme.label
        font.family: Theme.fontUi
        font.pixelSize: Theme.fs(12)
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // ------------------------------------------------------------- calendar
    // The month, today ringed in red, as Calendar's widget shows it.
    component Month: Column {
        id: month
        property date day: new Date()
        property color red: "#ff3b30"
        readonly property int first: new Date(day.getFullYear(), day.getMonth(), 1).getDay()
        readonly property int days: new Date(day.getFullYear(), day.getMonth() + 1, 0).getDate()
        spacing: 3
        Label {
            text: Qt.formatDate(month.day, "MMMM").toUpperCase()
            color: month.red
            font { pixelSize: Theme.fs(11); weight: Font.Bold; letterSpacing: 0.3 }
            leftPadding: 3
        }
        Grid {
            columns: 7
            rowSpacing: 1
            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                Label {
                    required property string modelData
                    width: 19; height: 13
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Theme.secondaryLabel
                    font { pixelSize: Theme.fs(9); weight: Font.DemiBold }
                }
            }
            Repeater {
                model: 42
                Item {
                    required property int index
                    readonly property int date: index - month.first + 1
                    readonly property bool today: date === month.day.getDate()
                    visible: index < Math.ceil((month.first + month.days) / 7) * 7
                    width: 19; height: 17
                    Rectangle {
                        anchors.centerIn: parent
                        width: 17; height: 17; radius: 8.5
                        color: month.red
                        visible: parent.today
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: parent.date >= 1 && parent.date <= month.days
                        text: parent.date
                        color: parent.today ? "white" : Theme.label
                        font { pixelSize: Theme.fs(10); weight: parent.today ? Font.Bold : Font.Medium }
                    }
                }
            }
        }
    }
    Component {
        id: calendarFace
        Item {
            Month {
                id: grid
                day: face.now
                red: face.red
                anchors { right: parent.right; rightMargin: 13; top: parent.top; topMargin: 13 }
            }
            Column {
                visible: face.medium
                anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: 14; right: grid.left; rightMargin: 14 }
                spacing: 0
                Label { text: Qt.formatDate(face.now, "dddd").toUpperCase(); color: face.red; font { pixelSize: Theme.fs(11); weight: Font.Bold; letterSpacing: 0.3 } }
                Label { text: face.now.getDate(); font { family: Theme.fontDisplay; pixelSize: 38; weight: Font.Light } }
                Item { width: 1; height: 6 }
                Repeater {
                    model: (face.feeds?.upNext ?? []).slice(0, 2)
                    Item {
                        required property var modelData
                        width: parent.width; height: 36
                        Rectangle { width: 3; height: 28; radius: 1.5; y: 2; color: modelData.calendar === "Work" ? "#0a84ff" : face.red }
                        Column {
                            x: 9; width: parent.width - 9
                            Label { width: parent.width; text: modelData.title; font { pixelSize: Theme.fs(12); weight: Font.DemiBold } }
                            Label { width: parent.width; text: modelData.time || "All-Day"; color: Theme.secondaryLabel; font.pixelSize: Theme.fs(11) }
                        }
                    }
                }
                Label {
                    visible: !(face.feeds?.upNext ?? []).length
                    text: "No more events today"
                    color: Theme.secondaryLabel
                    font.pixelSize: Theme.fs(12)
                }
            }
        }
    }

    // A clock hand from the centre (cx, cy), turned clockwise to `angle`.
    component Hand: Rectangle {
        id: hand
        property real cx
        property real cy
        property real angle
        property real length
        property real thickness: 3
        x: cx - thickness / 2
        y: cy - length
        width: thickness; height: length + 6; radius: thickness / 2
        antialiasing: true
        transform: Rotation {
            origin.x: hand.thickness / 2; origin.y: hand.length
            angle: hand.angle
            Behavior on angle { RotationAnimation { duration: Theme.reduceMotion ? 0 : 140; direction: RotationAnimation.Clockwise; easing.type: Easing.OutBack } }
        }
    }

    // ---------------------------------------------------------------- clock
    Component {
        id: clockFace
        Item {
            id: dial
            readonly property real d: Math.min(width, height) - 16
            readonly property int h: face.now.getHours() % 12
            readonly property int m: face.now.getMinutes()
            readonly property int s: face.now.getSeconds()
            Rectangle {
                id: disc
                anchors.centerIn: parent
                width: dial.d; height: dial.d; radius: dial.d / 2
                color: Theme.dark ? "#1c1c1e" : "#ffffff"
                border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#14000000" }
            }
            Repeater {
                model: 12
                Text {
                    required property int index
                    readonly property real a: (index + 1) * Math.PI / 6
                    x: dial.width / 2 + Math.sin(a) * dial.d * 0.385 - width / 2
                    y: dial.height / 2 - Math.cos(a) * dial.d * 0.385 - height / 2
                    text: index + 1
                    color: Theme.label
                    font { family: Theme.fontDisplay; pixelSize: Theme.fs(15); weight: Font.Medium }
                }
            }
            Repeater {   // the minute ticks
                model: 60
                Rectangle {
                    required property int index
                    visible: index % 5 !== 0
                    x: dial.width / 2 - 0.5; y: dial.height / 2 - dial.d / 2 + 3
                    width: 1; height: 3
                    color: Theme.tertiaryLabel
                    transform: Rotation { origin.x: 0.5; origin.y: dial.d / 2 - 3; angle: index * 6 }
                }
            }
            Label {
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 22 }
                text: Qt.formatDate(face.now, "ddd").toUpperCase()
                color: Theme.secondaryLabel
                font { pixelSize: Theme.fs(10); weight: Font.DemiBold }
            }
            Hand { cx: dial.width / 2; cy: dial.height / 2; angle: (dial.h + dial.m / 60) * 30; length: dial.d * 0.24; thickness: 4; color: Theme.label }
            Hand { cx: dial.width / 2; cy: dial.height / 2; angle: (dial.m + dial.s / 60) * 6; length: dial.d * 0.36; thickness: 3; color: Theme.label }
            Hand { cx: dial.width / 2; cy: dial.height / 2; angle: dial.s * 6; length: dial.d * 0.40; thickness: 1.2; color: "#ff9500" }
            Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: "#ff9500" }
            Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 1.5; color: Theme.dark ? "#1c1c1e" : "white" }
        }
    }

    // -------------------------------------------------------------- weather
    Component {
        id: weatherFace
        Item {
            readonly property var w: face.feeds?.weather ?? null
            Rectangle {
                anchors.fill: parent
                radius: face.r
                gradient: Gradient {
                    GradientStop { position: 0; color: w ? w.sky[0] : "#3a7bc8" }
                    GradientStop { position: 1; color: w ? w.sky[1] : "#86acd6" }
                }
                border { width: 0.5; color: "#1fffffff" }
            }
            Column {
                anchors { left: parent.left; top: parent.top; margins: 15 }
                spacing: -2
                Row {
                    spacing: 4
                    Label { text: face.feeds?.place?.name ?? "Weather"; color: "white"; font { pixelSize: Theme.fs(14); weight: Font.DemiBold } }
                    Shared.Symbol { anchors.verticalCenter: parent.verticalCenter; name: "location"; tone: "white"; size: 10 }
                }
                Label { text: w ? w.temp : "--"; color: "white"; font { family: Theme.fontDisplay; pixelSize: 42; weight: Font.Light } }
            }
            Column {
                id: now
                x: face.medium ? parent.width - width - 15 : 15
                y: face.medium ? 15 : parent.height - height - 13
                spacing: 2
                Image {
                    x: face.medium ? now.width - width : 0
                    width: 22; height: 22
                    source: w ? Qt.resolvedUrl("weather/" + w.icon + ".svg") : ""
                    sourceSize: Qt.size(44, 44)
                }
                Label {
                    x: face.medium ? now.width - width : 0
                    text: w ? w.condition : (face.feeds?.place ? "Updating…" : "Finding your location…")
                    color: "white"; font { pixelSize: Theme.fs(12); weight: Font.DemiBold }
                }
                Label {
                    x: face.medium ? now.width - width : 0
                    visible: !!w
                    text: w ? "H:" + w.high + " L:" + w.low : ""
                    color: "white"; font { pixelSize: Theme.fs(12); weight: Font.DemiBold }
                }
            }
            Row {
                visible: face.medium && !!w
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 15; bottomMargin: 12 }
                Repeater {
                    model: w ? w.hours : []
                    Column {
                        required property var modelData
                        width: (parent.width) / 6
                        spacing: 3
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: "#d9ffffff"; font { pixelSize: Theme.fs(11); weight: Font.DemiBold } }
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 20; height: 20
                            source: Qt.resolvedUrl("weather/" + modelData.icon + ".svg")
                            sourceSize: Qt.size(40, 40)
                        }
                        Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp; color: "white"; font { pixelSize: Theme.fs(13); weight: Font.DemiBold } }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- music
    Component {
        id: musicFace
        Item {
            readonly property var p: face.feeds?.player ?? null
            readonly property string art: p?.trackArtUrl ?? ""
            readonly property real side: face.medium ? height - 30 : 64
            Item {
                id: cover
                x: 15; y: 15
                width: parent.side; height: parent.side
                Rectangle {
                    anchors.fill: parent; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#fc5c7d" }
                        GradientStop { position: 1; color: "#fa233b" }
                    }
                    visible: !parent.parent.art
                    Shared.Symbol { anchors.centerIn: parent; name: "music"; tone: "white"; size: Math.round(parent.width * 0.42) }
                }
                Shared.RoundedImage {
                    anchors.fill: parent; radius: 10
                    visible: !!parent.parent.art
                    source: parent.parent.art
                }
            }
            Rectangle {   // play/pause, top right on the small widget
                visible: !face.medium
                anchors { right: parent.right; top: parent.top; margins: 15 }
                width: 30; height: 30; radius: 15
                color: face.red
                Shared.Symbol { anchors.centerIn: parent; name: parent.parent.p?.isPlaying ? "pause" : "play"; tone: "white"; size: 13 }
                TapHandler { onTapped: parent.parent.p?.togglePlaying() }
            }
            Column {
                anchors { left: face.medium ? cover.right : parent.left; leftMargin: 15; right: parent.right; rightMargin: 15
                          bottom: face.medium ? undefined : parent.bottom; bottomMargin: 14
                          top: face.medium ? parent.top : undefined; topMargin: 18 }
                spacing: 1
                Label {
                    visible: face.medium
                    text: parent.parent.p?.isPlaying ? "NOW PLAYING" : "MUSIC"
                    color: face.red
                    font { pixelSize: Theme.fs(10); weight: Font.Bold; letterSpacing: 0.3 }
                    bottomPadding: 3
                }
                Label { width: parent.width; text: parent.parent.p?.trackTitle || "Not Playing"; font { pixelSize: face.medium ? 15 : 13; weight: Font.DemiBold } }
                Label { width: parent.width; text: parent.parent.p?.trackArtist || (parent.parent.p ? "" : "Music"); color: Theme.secondaryLabel; font.pixelSize: face.medium ? 13 : 12 }
            }
            Row {
                visible: face.medium
                anchors { left: cover.right; leftMargin: 9; bottom: parent.bottom; bottomMargin: 12 }
                spacing: 2
                Repeater {
                    model: [["backward", () => face.feeds?.player?.previous()], ["play", () => face.feeds?.player?.togglePlaying()],
                            ["forward", () => face.feeds?.player?.next()]]
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: 40; height: 36; radius: 18
                        color: hover.hovered ? Theme.fill : "transparent"
                        Shared.Symbol {
                            anchors.centerIn: parent
                            name: index === 1 && face.feeds?.player?.isPlaying ? "pause" : modelData[0]
                            size: index === 1 ? 20 : 16
                        }
                        HoverHandler { id: hover }
                        TapHandler { onTapped: modelData[1]() }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- notes
    Component {
        id: notesFace
        Column {
            readonly property var n: face.feeds?.note ?? null
            padding: 15
            spacing: 3
            Row {
                spacing: 5
                Image {
                    width: 16; height: 16
                    visible: status === Image.Ready
                    source: Quickshell.iconPath(DesktopEntries.byId("org.goldengate.Notes")?.icon ?? "", true) || ""
                    sourceSize: Qt.size(32, 32)
                }
                Label { text: "Notes"; color: Theme.dark ? "#ffd60a" : "#c79a00"; font { pixelSize: Theme.fs(13); weight: Font.Bold } }
            }
            Item { width: 1; height: 3 }
            Label { width: face.width - 30; text: parent.n?.title ?? "No Notes"; font { pixelSize: Theme.fs(14); weight: Font.Bold } }
            Label {
                width: face.width - 30
                text: parent.n?.body || (parent.n ? "No additional text" : "Notes you write show here.")
                color: Theme.secondaryLabel
                wrapMode: Text.WordWrap
                maximumLineCount: face.medium ? 4 : 3
                font.pixelSize: Theme.fs(12)
                lineHeight: 1.08
            }
        }
    }

    // -------------------------------------------------------------- battery
    Component {
        id: batteryFace
        Item {
            id: power
            readonly property real level: face.feeds?.battery ?? 1
            readonly property color tint: level <= 0.2 && !(face.feeds?.charging) ? "#ff453a" : "#30d158"
            Shape {
                id: ring
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 18 }
                width: 92; height: 92
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.dark ? "#26ffffff" : "#17000000"; strokeWidth: 9; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 46; centerY: 46; radiusX: 41; radiusY: 41; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: power.tint; strokeWidth: 9; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 46; centerY: 46; radiusX: 41; radiusY: 41; startAngle: -90; sweepAngle: 360 * Math.max(0.01, power.level) }
                }
            }
            Shared.Symbol {
                anchors.centerIn: ring
                name: face.feeds?.charging ? "bolt" : "power"
                size: 24
            }
            Label {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                text: face.feeds?.hasBattery === false ? "Power Adapter" : Math.round(parent.level * 100) + "%"
                font { pixelSize: Theme.fs(15); weight: Font.DemiBold }
            }
        }
    }
}
