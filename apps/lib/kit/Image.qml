// A picture from the app's Assets folder (or a file or web address).
import QtQuick
import "kit.js" as K
import ".." as Lib

Box {
    id: root
    property string source: ""
    property string fit: "fill"               // fill | fit
    contentWidth: 160
    contentHeight: 120

    Rectangle {
        anchors.fill: parent
        visible: !root.source || picture.status !== Image.Ready
        radius: root.cornerRadius
        color: root.dark ? "#2c2c2e" : "#eeeef2"
        Text {
            anchors.centerIn: parent
            text: root.source ? "" : "Image"
            color: root.c("tertiaryLabel")
            font.pixelSize: 12
        }
    }
    Lib.RoundedImage {
        id: picture
        anchors.fill: parent
        visible: !!root.source
        radius: root.cornerRadius
        source: root.resolveAsset(root.source)
        fillMode: root.fit === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
    }
}
