// A contact's picture as Messages draws one without a photo: their initials
// in white on a grey gradient circle, or people for a group.
import QtQuick
import "../lib"
import "../lib/theme"

Rectangle {
    id: avatar
    property string name: ""
    property string photoPath: ""
    readonly property bool hasPhoto: photoPath.startsWith("/") || photoPath.startsWith("file://")
    property bool group: false
    property real size: 40
    width: size; height: size; radius: size / 2
    gradient: Gradient {
        GradientStop { position: 0; color: Theme.dark ? "#8e929b" : "#a8adb7" }
        GradientStop { position: 1; color: Theme.dark ? "#6b6f78" : "#878c97" }
    }
    clip: true
    Image {
        id: contactPhoto
        anchors.fill: parent
        source: avatar.hasPhoto ? (avatar.photoPath.startsWith("file://") ? avatar.photoPath : "file://" + avatar.photoPath) : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.round(avatar.size * 2)
        sourceSize.height: Math.round(avatar.size * 2)
        asynchronous: true
        visible: status === Image.Ready
    }
    readonly property bool pictureReady: contactPhoto.visible
    readonly property string initials: {
        // Letters only: a phone number or email gets the person glyph.
        if (/^[+\d(]/.test(String(name || "").trim()) || String(name).includes("@")) return ""
        const words = String(name || "").replace(/[^\p{L}\s]/gu, "").trim().split(/\s+/).filter((w) => w)
        return words.length ? (words[0][0] + (words.length > 1 ? words[words.length - 1][0] : "")).toUpperCase() : ""
    }
    Text {
        visible: !avatar.pictureReady && !avatar.group && avatar.initials !== ""
        anchors.centerIn: parent
        text: avatar.initials
        color: "#ffffff"
        font { family: Theme.fontUi; pixelSize: Math.round(avatar.size * 0.4); weight: Font.DemiBold }
    }
    Symbol {
        visible: !avatar.pictureReady && (avatar.group || avatar.initials === "")
        anchors.centerIn: parent
        name: avatar.group ? "people" : "person"
        size: Math.round(avatar.size * 0.5)
        tone: "white"
    }
}
