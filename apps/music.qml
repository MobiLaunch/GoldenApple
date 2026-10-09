//@ pragma AppId org.goldengate.Music
// Music, laid out like Music on macOS 27: a floating glass sidebar (Search, Home,
// Radio, your library and playlists), large-title pages, and the floating player
// over the bottom of the content.
//
// It plays your own files: everything under ~/Music (GG_MUSIC_DIR to change it),
// scanned in the background by music/scan.sh, plus .m3u playlists from
// ~/Music/Playlists, and internet radio from radio-browser.info.
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "music"

ShellRoot {
    AppWindow {
        id: win
        onBackRequested: app.back()
        closeAction: () => audio.requestClose()
        title: "Music"
        implicitWidth: Math.min(1180, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(760, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(760, 480)
        sidebarWidth: 200
        fullSizeContent: true
        background: Theme.contentBg

        // Back, once you've opened an album or playlist.
        toolbarLeft: [
            ToolbarButton {
                round: true; symbol: "chevron-left"
                visible: app.history.length > 0 && (app.page === "album" || app.page === "playlist")
                onClicked: app.back()
            },
            ToolbarButton {
                id: playbackOptions
                symbol: "ellipsis"; round: true
                Accessible.name: "Playback Options"
                onClicked: songMenuPopup.popup(playbackOptions, 0, height, [
                    { text: "Restore Queue on Next Launch", checked: audio.rememberPlayback, action: () => audio.rememberPlayback = !audio.rememberPlayback },
                    { text: "Forget Saved Queue", action: () => audio.forgetSavedQueue() },
                    { text: "Clear Queue", enabled: audio.queue.length > 0, action: () => audio.clearQueue() },
                    { separator: true },
                    { text: "Retry System Media Controls", enabled: !systemMedia.available, action: () => systemMedia.retry() },
                    { text: "Retry Saving Queue", action: () => audio.save() }
                ])
            }
        ]

        sidebar: [
            Flickable {
                anchors { fill: parent; bottomMargin: 44 }
                contentHeight: nav.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: nav
                    width: parent.width
                    // As in Music on the Mac: a neutral selection, the glyph in Music's red.
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "search"; text: "Search"; selected: app.page === "search"; onClicked: app.go("search") }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "house"; text: "Home"; selected: app.page === "home"; onClicked: app.go("home") }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "broadcast"; text: "Radio"; selected: app.page === "radio"; onClicked: app.go("radio") }
                    component Heading: SidebarSection {}
                    Heading { text: "Library" }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "clock"; text: "Recently Added"; selected: app.page === "recent"; onClicked: app.go("recent") }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "mic"; text: "Artists"; selected: app.page === "artists"; onClicked: app.go("artists") }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "gallery"; text: "Albums"; selected: app.page === "albums"; onClicked: app.go("albums") }
                    SidebarRow { symbolTone: "auto"; selectedSymbolTone: "red"; selectedTextColor: Theme.label; selectedFill: Theme.selection; symbol: "music"; text: "Songs"; selected: app.page === "songs"; onClicked: app.go("songs") }
                    Heading { text: "Playlists"; visible: musicLib.playlists.length > 0 }
                    Repeater {
                        model: musicLib.playlists
                        delegate: SidebarRow {
                            required property var modelData
                            symbolTone: "auto"
                            selectedSymbolTone: "red"
                            selectedTextColor: Theme.label
                            selectedFill: Theme.selection
                            symbol: "list"; text: modelData.name
                            selected: app.page === "playlist" && app.arg?.path === modelData.path
                            onClicked: app.go("playlist", modelData)
                        }
                    }
                }
            },
            AccountRow {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 36
                name: app.userName
            }
        ]

        Item {
            id: app
            anchors.fill: parent
            focus: true

            // GG_MUSIC_PAGE opens another page first (screenshots): home, radio,
            // albums, songs, artists, recent, search, or album (the newest one).
            property string page: Quickshell.env("GG_MUSIC_PAGE") || "home"
            readonly property string requestedPath: Quickshell.env("GG_MUSIC_OPEN") || ""
            property bool requestedOpened: false
            property var arg: null
            property var history: []
            property string userName: Quickshell.env("USER") ?? ""
            property bool queueOpen: false

            function go(p, a) {
                if (p === page && a === arg) return
                history = history.concat([{ page: page, arg: arg }]).slice(-30)
                page = p; arg = a ?? null
            }
            function back() {
                if (!history.length) return
                const h = history[history.length - 1]
                history = history.slice(0, -1)
                page = h.page; arg = h.arg
            }
            function openAlbum(a) { go("album", a) }
            function openRequestedTrack() {
                if (requestedOpened || !requestedPath || !musicLib.loaded || !audio.sessionReady)
                    return
                const i = musicLib.tracks.findIndex((t) => t.path === requestedPath)
                if (i < 0)
                    return
                requestedOpened = true
                page = "songs"
                audio.playList(musicLib.tracks, i)
            }
            function songMenu(t, list, from, x, y) {
                songMenuPopup.popup(from, x, y, [
                    { text: "Play", action: () => audio.playList(list, list.indexOf(t)) },
                    { text: "Play Next", action: () => audio.playNext(t) },
                    { separator: true },
                    { text: "Go to Album", action: () => { const a = musicLib.albumOf(t); if (a) app.openAlbum(a) } },
                    { text: "Go to Artist", action: () => { app.go("artists"); const i = musicLib.artists.findIndex((r) => r.name === t.albumArtist); if (i >= 0) Qt.callLater(() => { if (pages.item) pages.item.selected = i }) } },
                    { separator: true },
                    { text: "Show in Files", action: () => Quickshell.execDetached(["gg-files", "--select", t.path]) },
                ])
            }

            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Space && !(e.modifiers & Qt.ControlModifier)) { audio.toggle(); e.accepted = true }
                // ⌘→ ⌘← ⌘↑ ⌘↓ as keyd delivers them: End, Home, Ctrl+Home, Ctrl+End
                // (⌃← ⌃→ belong to Hyprland's Spaces).
                else if (e.key === Qt.Key_End && !(e.modifiers & Qt.ControlModifier)) { audio.next(); e.accepted = true }
                else if (e.key === Qt.Key_Home && !(e.modifiers & Qt.ControlModifier)) { audio.previous(); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Home) { audio.volume = Math.min(1, audio.volume + 0.1); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_End) { audio.volume = Math.max(0, audio.volume - 0.1); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) { go("search"); Qt.callLater(() => pages.item?.focusField?.()); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_BracketLeft) { back(); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_R) { musicLib.rescan(); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_P && !audio.current && musicLib.recentAlbums.length) {
                    audio.playList(musicLib.recentAlbums[0].tracks, 0); e.accepted = true
                }
            }

            // Media keys: Hyprland runs `qs -p …/music.qml ipc call music toggle` when
            // no MPRIS player takes playerctl's command.
            IpcHandler {
                target: "music"
                function toggle(): void {
                    if (!audio.current && musicLib.recentAlbums.length) audio.playList(musicLib.recentAlbums[0].tracks, 0)
                    else audio.toggle()
                }
                function next(): void { audio.next() }
                function previous(): void { audio.previous() }
            }

            Library { id: musicLib }
            Player {
                id: audio
                onSessionReadyChanged: app.openRequestedTrack()
                onCloseReady: Qt.quit()
            }
            Mpris {
                id: systemMedia
                player: audio
                onRaiseRequested: win.reopen()
                onQuitRequested: audio.requestClose()
                onOpenRequested: (path) => {
                    const i = musicLib.tracks.findIndex(t => t.path === path)
                    if (i >= 0) audio.playList(musicLib.tracks, i)
                    else audio.playList([{ path: path, title: path.split("/").pop(), artist: "", album: "", art: "", seconds: 0 }], 0)
                }
            }
            Connections {
                target: musicLib
                function onLoadedChanged() { app.openRequestedTrack() }
                function onTracksChanged() { app.openRequestedTrack() }
            }

            Process {
                running: true
                command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
                stdout: StdioCollector { onStreamFinished: if (text.trim()) app.userName = text.trim() }
            }

            // Pages
            Loader {
                id: pages
                anchors.fill: parent
                sourceComponent: ({
                    home: homePage, search: searchPage, radio: radioPage, recent: recentPage, artists: artistsPage,
                    albums: albumsPage, songs: songsPage, album: albumPage, playlist: playlistPage,
                })[app.page] ?? homePage
            }
            Component {
                id: homePage
                HomePage {
                    lib: musicLib; player: audio
                    topMargin: 14
                    onOpenAlbum: (a) => app.openAlbum(a)
                    onGo: (p) => app.go(p)
                    onSongMenu: (t, l, f, x, y) => app.songMenu(t, l, f, x, y)
                }
            }
            Component {
                id: searchPage
                SearchPage {
                    lib: musicLib; player: audio
                    topMargin: 14
                    onOpenAlbum: (a) => app.openAlbum(a)
                    onSongMenu: (t, l, f, x, y) => app.songMenu(t, l, f, x, y)
                    Component.onCompleted: focusField()
                }
            }
            Component { id: radioPage; RadioPage { player: audio } }
            Component {
                id: recentPage
                AlbumsPage { title: "Recently Added"; albums: musicLib.recentAlbums; player: audio; topMargin: 14; onOpenAlbum: (a) => app.openAlbum(a) }
            }
            Component {
                id: albumsPage
                AlbumsPage { title: "Albums"; albums: musicLib.albums; player: audio; topMargin: 14; onOpenAlbum: (a) => app.openAlbum(a) }
            }
            Component {
                id: artistsPage
                ArtistsPage { artists: musicLib.artists; player: audio; onOpenAlbum: (a) => app.openAlbum(a) }
            }
            Component {
                id: songsPage
                SongsPage { tracks: musicLib.tracks; player: audio; onSongMenu: (t, l, f, x, y) => app.songMenu(t, l, f, x, y) }
            }
            Component {
                id: albumPage
                AlbumPage {
                    readonly property var album: app.arg ?? musicLib.recentAlbums[0] ?? null
                    title: album?.title ?? ""; subtitle: album?.artist ?? ""
                    detail: album?.year ?? ""; art: album?.art ?? ""
                    tracks: album?.tracks ?? []
                    player: audio
                    topMargin: 22
                    onSongMenu: (t, l, f, x, y) => app.songMenu(t, l, f, x, y)
                }
            }
            Component {
                id: playlistPage
                AlbumPage {
                    readonly property var list: app.arg
                    title: list?.name ?? ""; subtitle: ""
                    detail: "PLAYLIST"
                    tracks: list ? musicLib.playlistTracks(list) : []
                    art: tracks[0]?.art ?? ""
                    numbered: false
                    player: audio
                    topMargin: 22
                    onSongMenu: (t, l, f, x, y) => app.songMenu(t, l, f, x, y)
                }
            }

            // Scroll edge: content fades out under the toolbar once scrolled.
            Rectangle {
                width: parent.width; height: win.toolbarHeight
                readonly property var flick: pages.item && pages.item.contentY !== undefined ? pages.item : null
                opacity: flick && flick.contentY > flick.originY - flick.topMargin + 2 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.contentBg }
                    GradientStop { position: 0.6; color: Qt.rgba(Theme.contentBg.r, Theme.contentBg.g, Theme.contentBg.b, 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.contentBg.r, Theme.contentBg.g, Theme.contentBg.b, 0) }
                }
            }


            // Playing Next
            Rectangle {
                id: queuePanel
                visible: app.queueOpen
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 8; topMargin: win.toolbarHeight; bottomMargin: miniPlayer.height + 28 + (playbackNotice.visible ? playbackNotice.height + 8 : 0) }
                width: 300
                radius: 16
                color: Theme.dark ? "#f22a2a2d" : "#f7fbfbfd"
                border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1f000000" }
                Rectangle { z: -1; anchors { fill: parent; topMargin: 4; bottomMargin: -6 } radius: parent.radius; color: "#14000000" }
                Text {
                    x: 16; y: 14
                    text: "Playing Next"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
                }
                ListView {
                    x: 8; y: 44; width: parent.width - 16; height: parent.height - 52
                    clip: true
                    readonly property int pos: audio.order.indexOf(audio.index)
                    model: audio.order.slice(pos + 1).map((i) => ({ i: i, t: audio.queue[i] }))
                    delegate: Item {
                        required property var modelData
                        width: ListView.view.width; height: 44
                        Rectangle { anchors.fill: parent; radius: 8; color: Theme.dark ? "#ffffff" : "#000000"; opacity: qh.hovered ? 0.05 : 0 }
                        Artwork { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4; maskColor: queuePanel.color; source: modelData.t.art }
                        Column {
                            x: 46; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.t.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.t.artist; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                        }
                        HoverHandler { id: qh }
                        TapHandler { onTapped: { audio.index = modelData.i; audio.load() } }
                    }
                    Text {
                        visible: parent.count === 0
                        anchors.horizontalCenter: parent.horizontalCenter; y: 20
                        text: "Nothing Playing Next"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                }
            }

            Rectangle {
                id: playbackNotice
                readonly property string message: audio.error || audio.sessionNotice || systemMedia.error
                visible: !!message
                anchors { left: parent.left; right: parent.right; margins: 20; bottom: miniPlayer.top; bottomMargin: 8 }
                height: noticeText.implicitHeight + noticeButtons.height + 22
                radius: 10; color: Theme.contentBg
                border { width: 1; color: Theme.separator }
                Text {
                    id: noticeText
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    text: playbackNotice.message; wrapMode: Text.Wrap
                    color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    Accessible.role: Accessible.StaticText
                }
                Row {
                    id: noticeButtons
                    anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                    spacing: 8
                    Button {
                        text: "Retry"
                        onClicked: {
                            if (audio.error) audio.play()
                            else if (audio.sessionNotice) { audio.sessionNotice = ""; audio.save() }
                            else systemMedia.retry()
                        }
                    }
                    Button {
                        text: "Dismiss"
                        onClicked: {
                            if (audio.error) audio.error = ""
                            else if (audio.sessionNotice) audio.sessionNotice = ""
                            else systemMedia.error = ""
                        }
                    }
                    Button { text: "Quit Without Saving"; visible: audio.saveFailed; onClicked: Qt.quit() }
                }
            }

            MiniPlayer {
                id: miniPlayer
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                width: Math.min(600, parent.width - 40)
                player: audio
                onShowQueue: app.queueOpen = !app.queueOpen
                onOpenAlbum: (t) => { const a = musicLib.albumOf(t); if (a) app.openAlbum(a) }
            }
        }

        PopupMenu { id: songMenuPopup; parent: win.overlay }
    }
}
