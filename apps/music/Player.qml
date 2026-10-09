// QtMultimedia is the playback authority. Sessions reopen paused, and radio
// sources are only contacted after Play is requested.
import QtQuick
import Quickshell.Io
import "../lib/paths.js" as Paths
import QtMultimedia

Item {
    id: player
    objectName: "musicPlayer"
    property var queue: []
    property int index: -1
    property bool shuffle: false
    property string repeat: "off"
    property bool rememberPlayback: true
    property bool sessionReady: false
    property string sessionNotice: ""
    property bool saveFailed: false
    property string error: ""
    property string trackId: "/org/mpris/MediaPlayer2/TrackList/NoTrack"
    property int generation: 0
    property bool stopped: true
    property real pendingPosition: -1
    property bool restoring: true
    property bool closing: false
    property string savedPayload: ""
    property string writingPayload: ""
    property string writingChanges: ""
    property bool forgetPending: false
    readonly property var current: index >= 0 && index < queue.length ? queue[index] : null
    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState
    readonly property string playbackStatus: !current || stopped ? "Stopped" : playing ? "Playing" : "Paused"
    readonly property real position: pendingPosition >= 0 ? pendingPosition : media.position / 1000
    readonly property real duration: media.duration > 0 ? media.duration / 1000 : (current?.seconds ?? 0)
    readonly property bool seekable: media.seekable && !!current && !current.radio
    readonly property bool canNext: !!current && (order.indexOf(index) < order.length - 1 || repeat === "all")
    property alias volume: out.volume
    property alias muted: out.muted
    property var order: []
    signal seeked(real seconds)
    signal closeReady()

    function playList(list, start) {
        queue = list.slice()
        order = list.map((_, i) => i)
        const first = list.length ? Math.max(0, Math.min(list.length - 1, Math.floor(start ?? 0) || 0)) : -1
        if (shuffle && first >= 0) shuffleOrder(first)
        index = first
        load()
    }
    function shuffleOrder(first) {
        const rest = order.filter((i) => i !== first)
        for (let i = rest.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [rest[i], rest[j]] = [rest[j], rest[i]] }
        order = [first].concat(rest)
    }
    function load(autoplay = true, at = 0, asStopped = false) {
        media.stop()
        error = ""
        pendingPosition = -1
        stopped = !current || asStopped
        trackId = current ? "/org/goldengate/Music/track/t_" + Date.now() + "_" + (++generation) : "/org/mpris/MediaPlayer2/TrackList/NoTrack"
        if (!current) { media.source = ""; return }
        pendingPosition = current.radio ? -1 : Math.max(0, at)
        // A restored radio station must not open a stream before the user plays.
        media.source = current.radio && !autoplay ? "" : current.radio ? current.url : Paths.fileUrl(current.path)
        applyPosition()
        if (autoplay) media.play()
        scheduleSave()
    }
    function applyPosition() {
        if (pendingPosition < 0 || !media.seekable || media.mediaStatus === MediaPlayer.LoadingMedia || media.mediaStatus === MediaPlayer.NoMedia) return
        const at = Math.min(pendingPosition, media.duration > 0 ? media.duration / 1000 : pendingPosition)
        pendingPosition = -1
        media.position = at * 1000
    }
    function play() {
        if (!current) return
        if (error || media.error !== MediaPlayer.NoError || !String(media.source)) { load(true, position); return }
        stopped = false
        media.play()
    }
    function pause() { media.pause(); scheduleSave() }
    function stop() { media.stop(); pendingPosition = -1; media.position = 0; stopped = true; scheduleSave() }
    function toggle() { playing ? pause() : play() }
    function step(d, autoplay = playing) {
        if (!queue.length) return
        const wasStopped = stopped
        let n = order.indexOf(index) + d
        if (n >= order.length) { if (repeat === "all") n = 0; else { if (autoplay) stop(); return } }
        if (n < 0) n = repeat === "all" ? order.length - 1 : 0
        index = order[n]
        load(autoplay, 0, !autoplay && wasStopped)
    }
    function next() { step(1) }
    function previous() { if (position > 3 && seekable) seek(0); else step(-1) }
    function seek(seconds) {
        if (!Number.isFinite(seconds) || !seekable) return
        pendingPosition = -1
        media.position = Math.max(0, Math.min(duration, seconds)) * 1000
        seeked(media.position / 1000)
        scheduleSave()
    }
    // The visible queue is order[], not queue[] (shuffle can change it).
    // Edit the future playback order without reloading the current decoder.
    function futureOrder() {
        const pos = order.indexOf(index)
        return pos < 0 ? [] : order.slice(pos + 1)
    }
    function moveUpcoming(queueIndex, direction) {
        const pos = order.indexOf(queueIndex)
        const now = order.indexOf(index)
        const target = pos + direction
        if (pos <= now || target <= now || target >= order.length)
            return false
        const next = order.slice()
        next.splice(target, 0, next.splice(pos, 1)[0])
        order = next
        scheduleSave()
        return true
    }
    function removeUpcoming(queueIndex) {
        const pos = order.indexOf(queueIndex)
        if (pos <= order.indexOf(index) || queueIndex < 0 || queueIndex >= queue.length)
            return false
        const nextQueue = queue.slice()
        nextQueue.splice(queueIndex, 1)
        const nextOrder = order.filter(i => i !== queueIndex).map(i => i > queueIndex ? i - 1 : i)
        if (queueIndex < index) index--
        queue = nextQueue
        order = nextOrder
        scheduleSave()
        return true
    }
    function playLater(t) {
        if (!current) { playList([t], 0); return }
        const nextQueue = queue.concat([t])
        order = order.concat([queue.length])
        queue = nextQueue
        scheduleSave()
    }
    function playNext(t) {
        if (!current) { playList([t], 0); return }
        const nextQueue = queue.concat([t])
        const now = order.indexOf(index)
        const nextOrder = order.slice()
        nextOrder.splice(now + 1, 0, queue.length)
        queue = nextQueue
        order = nextOrder
        scheduleSave()
    }
    function clearQueue() { queue = []; order = []; index = -1; load(false) }
    function systemState() {
        return { status: playbackStatus, position: position, seekable: seekable, canNext: canNext,
            volume: volume, muted: muted, shuffle: shuffle, repeat: repeat,
            track: current ? { id: trackId, title: current.title, artist: current.artist, album: current.album,
                art: current.art, length: current.radio ? 0 : duration,
                url: current.radio ? current.url : Paths.fileUrl(current.path) } : null }
    }
    function sessionState() {
        return { version: 1, remember: rememberPlayback, queue: queue, order: order, index: index,
            position: current?.radio ? 0 : position, shuffle: shuffle, repeat: repeat, volume: volume, muted: muted }
    }
    function scheduleSave() { if (sessionReady && !restoring) saveDelay.restart() }
    function save() {
        if (!sessionReady || restoring || writer.running || forgetter.running || forgetPending) return
        const payload = JSON.stringify(sessionState())
        if (payload === savedPayload) { if (closing) closeReady(); return }
        writingPayload = payload
        writingChanges = sessionChanges
        writer.stdinEnabled = true
        writer.running = true
    }
    function requestClose() { pause(); closing = true; saveDelay.stop(); if (sessionReady) save() }
    function forgetSavedQueue() {
        closing = false
        if (forgetter.running) return
        if (writer.running) forgetPending = true
        else forgetter.running = true
    }
    readonly property string sessionChanges: JSON.stringify(Object.assign({}, sessionState(), { position: 0 }))
    onSessionChangesChanged: scheduleSave()
    onShuffleChanged: {
        if (restoring) return
        order = queue.map((_, i) => i)
        if (shuffle && index >= 0) shuffleOrder(index)
    }
    Timer { id: saveDelay; interval: 450; onTriggered: player.save() }
    // Checkpoint playback without writing on every decoder position update.
    Timer { interval: 5000; repeat: true; running: player.playing; onTriggered: player.save() }
    // Position changes alone use the checkpoint; all other controls save promptly.
    onPlayingChanged: if (!playing) scheduleSave()

    Process {
        id: reader
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("session.py").toString().replace("file://", "")), "read"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (!result.ok) { player.sessionNotice = result.error; return }
                    const s = result.session
                    player.rememberPlayback = s.remember
                    player.volume = s.volume; player.muted = s.muted
                    player.shuffle = s.shuffle; player.repeat = s.repeat
                    if (!player.queue.length) {
                        player.queue = s.queue; player.order = s.order; player.index = s.index
                        player.load(false, s.position)
                    }
                    if (s.skipped) player.sessionNotice = "Skipped " + s.skipped + " missing " + (s.skipped === 1 ? "file" : "files") + " from the saved queue."
                } catch (_) { player.sessionNotice = "Music couldn't read the saved queue. Your files are still in the library." }
            }
        }
        onExited: {
            player.restoring = false
            player.sessionReady = true
            player.scheduleSave()
            if (player.closing) player.save()
        }
    }
    Process {
        id: writer
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("session.py").toString().replace("file://", "")), "write"]
        onStarted: { write(player.writingPayload); stdinEnabled = false }
        property string resultText: ""
        stdout: StdioCollector { onStreamFinished: writer.resultText = text }
        onExited: (code) => {
            let result = null
            try { result = JSON.parse(resultText) } catch (_) {}
            if (code === 0 && result?.ok) {
                player.saveFailed = false
                player.savedPayload = player.writingPayload
                if (player.closing) Qt.callLater(player.save)
                else if (player.sessionChanges !== player.writingChanges || (!player.playing && JSON.stringify(player.sessionState()) !== player.writingPayload)) player.scheduleSave()
            } else {
                player.saveFailed = true
                player.sessionNotice = result?.error || "Music couldn't save the queue. Check that your home folder is writable."
                player.closing = false
            }
            resultText = ""
            if (player.forgetPending) { player.forgetPending = false; forgetter.running = true }
        }
    }
    Process {
        id: forgetter
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("session.py").toString().replace("file://", "")), "forget"]
        property string resultText: ""
        stdout: StdioCollector { onStreamFinished: forgetter.resultText = text }
        onExited: (code) => {
            let result = null
            try { result = JSON.parse(resultText) } catch (_) {}
            if (code === 0 && result?.ok) {
                player.sessionNotice = ""; player.saveFailed = false; player.savedPayload = ""
                player.clearQueue()
            } else player.sessionNotice = result?.error || "Music couldn't forget the saved queue."
            resultText = ""
        }
    }
    MediaPlayer {
        id: media
        objectName: "musicMedia"
        audioOutput: AudioOutput { id: out; volume: 0.8 }
        onSeekableChanged: player.applyPosition()
        onDurationChanged: player.applyPosition()
        onErrorOccurred: (code, message) => {
            player.pendingPosition = -1
            player.stopped = true
            player.error = "Couldn't play “" + (player.current?.title || "this track") + "”. " + (message || "The file or stream is unavailable.")
        }
        onMediaStatusChanged: {
            player.applyPosition()
            if (mediaStatus !== MediaPlayer.EndOfMedia) return
            if (player.repeat === "one") { position = 0; play(); player.seeked(0) }
            else player.step(1, true)
        }
    }
}
