// The music library: ~/Music (or $GG_MUSIC_DIR) scanned by scan.sh into
// ~/.cache/golden-gate/music/library.tsv, loaded at once from the last scan and
// refreshed in the background. Albums and artists are derived from the tracks;
// playlists are the .m3u/.m3u8 files in ~/Music/Playlists.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/paths.js" as Paths

Item {
    id: lib
    readonly property string home: Quickshell.env("HOME")
    readonly property string musicDir: Quickshell.env("GG_MUSIC_DIR") || (Quickshell.env("XDG_MUSIC_DIR") || home + "/Music")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/golden-gate/music"
    readonly property string scanner: Qt.resolvedUrl("scan.sh").toString().replace("file://", "")

    property var tracks: []          // {path, mtime, title, artist, album, albumArtist, track, year, seconds, art}
    property var albums: []          // {key, title, artist, year, art, tracks, added}
    property var artists: []         // {name, albums, art}
    property var playlists: []       // {name, path, paths, revision}
    property var deletedPlaylists: []
    property bool deletedBusy: false
    property string playlistError: ""
    property bool playlistBusy: false
    property var playlistRequest: ({})
    property var postCreateAdd: null
    readonly property string playlistHelper: decodeURIComponent(Qt.resolvedUrl("playlists.py").toString().replace("file://", ""))
    signal playlistOperationDone(var result)
    property bool scanning: scanProc.running
    property bool loaded: false

    function parse(text) {
        const out = []
        for (const line of text.split("\n")) {
            const c = line.split("\t")
            if (c.length < 10) continue
            out.push({ path: c[0], mtime: Number(c[1]), title: c[2], artist: c[3], album: c[4], albumArtist: c[5],
                       track: Number(c[6]) || 0, year: c[7], seconds: Number(c[8]) || 0, art: c[9] ? Paths.fileUrl(c[9]) : "" })
        }
        tracks = out
        const byAlbum = Object.create(null)
        for (const t of out) {
            const k = t.albumArtist + "\u0001" + t.album
            const a = byAlbum[k] ?? (byAlbum[k] = { key: k, title: t.album, artist: t.albumArtist, year: t.year, art: t.art, tracks: [], added: 0 })
            a.tracks.push(t)
            a.added = Math.max(a.added, t.mtime)
            if (!a.art && t.art) a.art = t.art
        }
        const as = Object.values(byAlbum)
        for (const a of as) a.tracks.sort((x, y) => x.track - y.track || x.title.localeCompare(y.title))
        albums = as.sort((x, y) => x.title.localeCompare(y.title))
        const byArtist = Object.create(null)
        for (const a of as) {
            const r = byArtist[a.artist] ?? (byArtist[a.artist] = { name: a.artist, albums: [], art: a.art })
            r.albums.push(a)
        }
        artists = Object.values(byArtist).sort((x, y) => x.name.localeCompare(y.name))
        loaded = true
    }
    readonly property var recentAlbums: albums.slice().sort((x, y) => y.added - x.added)
    readonly property var recentTracks: tracks.slice().sort((x, y) => y.mtime - x.mtime || x.track - y.track)
    function album(key) { return albums.find((a) => a.key === key) ?? null }
    function albumOf(t) { return album(t.albumArtist + "\u0001" + t.album) }
    function rescan() { if (!scanProc.running) scanProc.running = true }

    FileView {
        id: file
        path: lib.cacheDir + "/library.tsv"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: lib.parse(text())
        onLoadFailed: lib.loaded = true
    }
    Process {
        id: scanProc
        command: ["bash", lib.scanner, lib.musicDir, lib.cacheDir]
        onExited: file.reload()
    }
    Component.onCompleted: rescan()

    function refreshPlaylists() {
        if (!playlistBusy && !listProc.running) listProc.running = true
    }
    function refreshDeleted() {
        if (!deletedBusy && !playlistBusy) deletedProc.running = true
    }

    function mutatePlaylist(command, data) {
        if (playlistBusy || listProc.running) {
            playlistError = "Music is updating playlists; please retry when finished."
            return false
        }
        playlistRequest = Object.assign({}, data, {command:command})
        playlistError = ""
        playlistBusy = true
        updateProc.command = ["python3", playlistHelper, command]
        updateProc.stdinEnabled = true
        updateProc.running = true
        return true
    }

    Process {
        id: listProc
        running: true
        command: ["python3", lib.playlistHelper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text) } catch (e) {}
                if (r?.ok && Array.isArray(r.playlists)) {
                    lib.playlists = r.playlists
                    lib.playlistError = ""
                } else lib.playlistError = r?.error || "Couldn't read the playlists directory."
            }
        }
    }
    Process {
        id: deletedProc
        command: ["python3", lib.playlistHelper, "deleted"]
        onStarted: lib.deletedBusy = true
        onExited: lib.deletedBusy = false
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text) } catch (e) {}
                if (r?.ok && Array.isArray(r.deleted)) {
                    lib.deletedPlaylists = r.deleted
                    lib.playlistError = ""
                } else {
                    lib.playlistError = r?.error || "Couldn't load recently deleted playlists."
                }
            }
        }
    }
    Process {
        id: updateProc
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify(lib.playlistRequest))
            stdinEnabled = false
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text) } catch (e) {}
                if (r?.ok && Array.isArray(r.playlists)) {
                    lib.playlists = r.playlists
                    if (Array.isArray(r.deleted)) lib.deletedPlaylists = r.deleted
                    lib.playlistError = ""
                    lib.playlistOperationDone(r)
                } else {
                    lib.playlistError = r?.error || "Couldn't update this playlist."
                }
            }
        }
        onExited: {
            lib.playlistBusy = false
            stdinEnabled = true
            if (lib.postCreateAdd) {
                const next = lib.postCreateAdd
                lib.postCreateAdd = null
                Qt.callLater(() => lib.mutatePlaylist("add", next))
            }
            if (lib.refreshAfterMutation) {
                lib.refreshAfterMutation = false
                Qt.callLater(() => lib.refreshPlaylists())
            }
        }
    }
    property bool refreshAfterMutation: false

    function playlistTracks(p) {
        return (p?.paths || []).map(x => tracks.find(t => t.path === x)).filter(t => t)
    }
}
