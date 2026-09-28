// Playback: a queue of tracks (or one radio station), shuffle and repeat, on
// QtMultimedia (FFmpeg backend: every common format, and internet radio).
import QtQuick
import QtMultimedia

Item {
    id: player
    property var queue: []           // tracks as Library gives them, or [{title, artist, art, url, radio: true}]
    property int index: -1
    property bool shuffle: false
    property string repeat: "off"    // off | all | one
    readonly property var current: index >= 0 && index < queue.length ? queue[index] : null
    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState
    readonly property real position: media.position / 1000
    readonly property real duration: media.duration > 0 ? media.duration / 1000 : (current?.seconds ?? 0)
    property alias volume: out.volume
    property alias muted: out.muted
    property var order: []           // play order when shuffling

    function playList(list, start) {
        queue = list
        order = list.map((_, i) => i)
        if (shuffle) shuffleOrder(start ?? 0)
        index = start ?? 0
        load()
    }
    function shuffleOrder(first) {
        const rest = order.filter((i) => i !== first)
        for (let i = rest.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [rest[i], rest[j]] = [rest[j], rest[i]] }
        order = [first].concat(rest)
    }
    function load() {
        if (!current) { media.stop(); return }
        media.source = current.radio ? current.url : "file://" + current.path
        media.play()
    }
    function toggle() {
        if (!current) return
        playing ? media.pause() : media.play()
    }
    function step(d) {
        if (!queue.length) return
        const pos = order.indexOf(index)
        let n = pos + d
        if (n >= order.length) { if (repeat === "all") n = 0; else { media.stop(); return } }
        if (n < 0) n = 0
        index = order[n]
        load()
    }
    function next() { step(1) }
    function previous() {
        if (media.position > 3000) { media.position = 0; return }
        step(-1)
    }
    function seek(seconds) { media.position = seconds * 1000 }
    function playNext(t) {
        if (!current) { playList([t], 0); return }
        const q = queue.slice(); q.splice(index + 1, 0, t)
        const o = order.map((i) => i > index ? i + 1 : i)
        o.splice(o.indexOf(index) + 1, 0, index + 1)
        queue = q; order = o
    }
    onShuffleChanged: {
        order = queue.map((_, i) => i)
        if (shuffle && index >= 0) shuffleOrder(index)
    }

    MediaPlayer {
        id: media
        audioOutput: AudioOutput { id: out; volume: 0.8 }
        onMediaStatusChanged: {
            if (mediaStatus !== MediaPlayer.EndOfMedia) return
            if (player.repeat === "one") { position = 0; play() } else player.next()
        }
    }
}
