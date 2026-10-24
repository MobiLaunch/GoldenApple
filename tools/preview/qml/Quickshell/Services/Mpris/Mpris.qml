pragma Singleton
import QtQuick
QtObject {
    id: m
    readonly property var player: QtObject {
        property string identity: "Music"; property string trackTitle: "Golden Hour"; property string trackArtist: "JVKE"
        property string trackAlbum: "this is what ____ feels like"; property string trackArtUrl: ""
        property bool isPlaying: true; property int playbackState: 1; property real position: 74; property real length: 209
        property bool canGoNext: true; property bool canGoPrevious: true; property bool canPlay: true; property bool canPause: true; property bool canTogglePlaying: true
        property string desktopEntry: "org.goldengate.Music"
        function togglePlaying() {} function next() {} function previous() {} function play() {} function pause() {}
    }
    readonly property QtObject players: QtObject { readonly property var values: __preview.env["GG_PREVIEW_MEDIA"] === "1" ? [m.player] : [] }
}
