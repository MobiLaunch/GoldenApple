// Pick an image from the app's Assets folder, or bring one in.
import QtQuick
import "../../lib"
import "../../lib/theme"

Popover {
    id: picker
    property var backend: null
    property string root: ""                   // the project folder
    property string value: ""
    property var assets: []
    property string error: ""
    signal picked(string value)
    panelWidth: 300
    panelHeight: 380

    function show(from, x, y, current) {
        value = current || ""
        error = ""
        importField.text = ""
        refresh()
        openAt(from, x, y)
    }
    function refresh() {
        if (backend) backend.call("assets", {}, (r) => { if (r.ok) picker.assets = r.assets })
    }

    Column {
        width: parent.width
        spacing: 8
        Text {
            text: "Assets"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
        }
        GridView {
            width: parent.width
            height: 220
            clip: true
            cellWidth: width / 3
            cellHeight: 92
            model: [""].concat(picker.assets)
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                required property string modelData
                width: GridView.view.cellWidth
                height: 92
                Rectangle {
                    anchors { fill: parent; margins: 3 }
                    radius: 8
                    color: picker.value === parent.modelData ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : imgHover.hovered ? Theme.fill : "transparent"
                    border { width: picker.value === parent.modelData ? 2 : 0; color: Theme.accent }
                    RoundedImage {
                        visible: !!parent.parent.modelData
                        x: 8; y: 6
                        width: parent.width - 16; height: 56
                        radius: 6
                        source: parent.parent.modelData ? "file://" + picker.root + "/" + parent.parent.modelData : ""
                    }
                    Text {
                        anchors { bottom: parent.bottom; bottomMargin: 6; horizontalCenter: parent.horizontalCenter }
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: parent.parent.modelData ? parent.parent.modelData.split("/").pop() : "None"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                    }
                }
                HoverHandler { id: imgHover }
                TapHandler { onTapped: { picker.value = parent.modelData; picker.picked(parent.modelData); picker.close() } }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: picker.error || "Add an image: type its path (or a web address) and press Return."
            color: picker.error ? "#ff453a" : Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
        TextField {
            id: importField
            width: parent.width
            height: 28
            placeholder: "~/Pictures/photo.jpg"
            onAccepted: {
                const t = text.trim()
                if (!t) return
                if (/^https?:/.test(t)) { picker.picked(t); picker.close(); return }
                picker.backend.call("importAsset", { path: t }, (r) => {
                    if (!r.ok) { picker.error = r.error; return }
                    picker.refresh()
                    picker.picked(r.path)
                    picker.close()
                })
            }
        }
    }
}
