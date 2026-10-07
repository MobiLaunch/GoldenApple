// One message, as Messages draws it: blue on the right for yours, grey on the
// left for theirs, close together within a run, with the tail on a run's
// last bubble. A time separator heads messages after a pause, and in groups
// the sender's name sits above their first bubble.
import QtQuick
import QtQuick.Shapes
import "../lib"
import "../lib/theme"

Item {
    id: item
    property var message: ({})
    property bool group: false
    property string separator: ""
    property bool firstInRun: true
    property bool lastInRun: true
    property string footnote: ""
    signal menuRequested(Item target, real x, real y)
    readonly property bool mine: !!message.outgoing
    readonly property color fill: mine ? "#0a84ff" : Theme.dark ? "#3b3b3d" : "#e9e9eb"
    height: column.height + (lastInRun ? 8 : 2)

    Column {
        id: column
        width: parent.width

        Text {
            visible: item.separator !== ""
            width: parent.width
            topPadding: 14; bottomPadding: 8
            horizontalAlignment: Text.AlignHCenter
            text: item.separator
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium }
        }
        Text {
            visible: item.group && !item.mine && item.firstInRun && !!item.message.sender
            x: 14
            bottomPadding: 2
            text: item.message.sender || ""
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        Item {
            width: parent.width
            height: bubble.height
            Rectangle {
                id: bubble
                x: item.mine ? parent.width - width - 4 : 4
                width: Math.min(item.width * 0.7, body.implicitWidth + 26)
                height: body.height + 14
                radius: 17
                color: item.fill
                Text {
                    id: body
                    x: 13; y: 7
                    width: Math.min(item.width * 0.7 - 26, implicitWidth)
                    text: item.message.body || ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: item.mine ? "#ffffff" : Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: (p) => item.menuRequested(bubble, p.position.x, p.position.y)
                }
            }
            // The tail: a curl from the bubble's bottom corner.
            Shape {
                visible: item.lastInRun
                width: 16; height: 20
                x: item.mine ? bubble.x + bubble.width - 11 : bubble.x - 5
                y: bubble.y + bubble.height - height
                transform: Scale { origin.x: 8; xScale: item.mine ? 1 : -1 }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: item.fill
                    PathSvg { path: "M 0 0 L 9 0 C 9 9 11 15 16 20 C 10 20 4.5 18.5 0 15.5 Z" }
                }
            }
        }
        Text {
            visible: item.footnote !== ""
            width: parent.width - 8
            topPadding: 3
            horizontalAlignment: Text.AlignRight
            text: item.footnote
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium }
        }
    }
}
