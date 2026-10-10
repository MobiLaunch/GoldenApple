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
        property bool showMobileNavigation: false
        sidebarWidth: win.tabletCompact ? (showMobileNavigation ? Math.min(290, win.width * 0.50) : 0) : 200
        fullSizeContent: true
        background: Theme.contentBg

        // Back, once you've opened an album or playlist.
        toolbarLeft: [
            ToolbarButton {
                visible: win.tabletCompact
                round: true; symbol: "sidebar"
                checked: win.showMobileNavigation
                Accessible.name: win.showMobileNavigation ? "Hide Music Navigation" : "Show Music Navigation"
                onClicked: win.showMobileNavigation = !win.showMobileNavigation
            },
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
                    { text: "New Playlist…", action: () => app.openPlaylistName("create") },
                    { text: "Recently Deleted Playlists…", action: () => app.openDeletedPlaylists() },
                    { text: "Refresh Playlists", action: () => musicLib.refreshPlaylists() },
                    { text: "Manage This Playlist…", enabled: app.page === "playlist", action: () => app.openPlaylistManager() },
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
                    Heading { text: "Playlists" }
                    SidebarRow {
                        symbol: "trash"; text: "Recently Deleted"
                        symbolTone: "auto"; selectedSymbolTone: "red"
                        selectedTextColor: Theme.label; selectedFill: Theme.selection
                        onClicked: app.openDeletedPlaylists()
                    }
                    SidebarRow {
                        symbol: "plus"; text: "New Playlist…"
                        symbolTone: "auto"; selectedSymbolTone: "red"
                        selectedTextColor: Theme.label; selectedFill: Theme.selection
                        onClicked: app.openPlaylistName("create")
                    }
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
            property string playlistNameMode: "create"
            property string playlistDraftName: ""
            property var playlistTarget: null
            property var pendingTrack: null
            property string managePath: ""
            readonly property var managedPlaylist: musicLib.playlists.find(p => p.path === managePath) || null
            readonly property var managedEntries: managedPlaylist
                ? managedPlaylist.paths.map((path, i) => ({
                    path:path, index:i,
                    track:musicLib.tracks.find(t => t.path === path) || null
                })) : []
            property bool deletingPlaylist: false

            function go(p, a) {
                if (win.tabletCompact) win.showMobileNavigation = false
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
            function openPlaylistName(mode, playlist) {
                if (mode === "create" && !pickerSheet.visible && !app.pendingTrack?.path)
                    pendingTrack = null
                playlistNameMode = mode
                playlistTarget = playlist || null
                playlistDraftName = mode === "rename" ? (playlist?.name || "") : ""
                nameSheet.visible = true
                Qt.callLater(() => playlistNameField.input.forceActiveFocus())
            }

            function savePlaylistName() {
                const name = playlistDraftName.trim()
                if (!name || musicLib.playlistBusy) return
                const request = playlistNameMode === "rename"
                    ? {name:name, path:playlistTarget.path, expected:playlistTarget.revision}
                    : {name:name}
                musicLib.mutatePlaylist(playlistNameMode, request)
            }

            function openDeletedPlaylists() {
                deletedSheet.visible = true
                musicLib.refreshDeleted()
            }

            function restorePlaylist(item) {
                if (!item || musicLib.playlistBusy) return
                musicLib.mutatePlaylist("restore",
                    {path:item.path, expected:item.revision})
            }

            function openPlaylistManager() {
                const selected = musicLib.playlists.find(p => p.path === app.arg?.path)
                if (!selected) { musicLib.playlistError = "Choose a playlist to manage."; return }
                managePath = selected.path
                managerSheet.visible = true
            }

            function playlistEdit(command, data) {
                const source = managedPlaylist
                if (!source) return false
                return musicLib.mutatePlaylist(command,
                    Object.assign({path:source.path, expected:source.revision}, data || {}))
            }

            function choosePlaylist(t) {
                pendingTrack = t
                pickerSheet.visible = true
            }

            function addSelectedTrack(playlist) {
                if (!pendingTrack || !playlist || musicLib.playlistBusy) return
                musicLib.mutatePlaylist("add",
                    {path:playlist.path, expected:playlist.revision, track:pendingTrack.path})
            }

            function songMenu(t, list, from, x, y) {
                songMenuPopup.popup(from, x, y, [
                    { text: "Play", action: () => audio.playList(list, list.indexOf(t)) },
                    { text: "Play Next", action: () => audio.playNext(t) },
                    { text: "Play Last", action: () => audio.playLater(t) },
                    { text: "Add to Playlist…", enabled: !t.radio, action: () => app.choosePlaylist(t) },
                    ...(app.page === "playlist" && app.arg?.path && !t.radio ? [
                        { text: "Remove from This Playlist", action: () => {
                            const p = musicLib.playlists.find(p => p.path === app.arg?.path)
                            if (!p) return
                            const at = p.paths.indexOf(t.path)
                            if (at >= 0) musicLib.mutatePlaylist("remove", {path:p.path, expected:p.revision, index:at})
                        } }
                    ] : []),
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
            Connections {
                target: musicLib
                function onPlaylistOperationDone(r) {
                    if (musicLib.playlistRequest.command === "create" ||
                        musicLib.playlistRequest.command === "rename") nameSheet.visible = false
                    if (musicLib.playlistRequest.command === "add") pickerSheet.visible = false
                    if (r.playlist) {
                        const selected = musicLib.playlists.find(p => p.path === r.playlist)
                        if (selected) {
                            if (musicLib.playlistRequest.command === "add") app.pendingTrack = null
                            if (app.page === "playlist" && app.arg?.path === musicLib.playlistRequest.path)
                                app.arg = selected
                            if (app.managePath === musicLib.playlistRequest.path)
                                app.managePath = selected.path
                            if (musicLib.playlistRequest.command === "restore") {
                                deletedSheet.visible = false
                                app.go("playlist", selected)
                            }
                            if (musicLib.playlistRequest.command === "create") {
                                app.go("playlist", selected)
                                if (app.pendingTrack?.path) {
                                    const track = app.pendingTrack
                                    app.pendingTrack = null
                                    musicLib.postCreateAdd = {path:selected.path, expected:selected.revision, track:track.path}
                                }
                            }
                        }
                    } else if (musicLib.playlistRequest.command === "delete") {
                        if (app.page === "playlist" && app.arg?.path === musicLib.playlistRequest.path)
                            app.go("songs")
                        managerSheet.visible = false
                        app.managePath = ""
                    }
                }
            }
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
                    readonly property var list: musicLib.playlists.find(p => p.path === app.arg?.path) || app.arg
                    title: list?.name ?? ""; subtitle: ""
                    detail: "PLAYLIST"
                    tracks: list ? musicLib.playlistTracks(list) : []
                    art: tracks[0]?.art ?? ""
                    numbered: false
                    editablePlaylist: true
                    onManagePlaylist: app.openPlaylistManager()
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
                    model: audio.futureOrder().map((i) => ({ i: i, t: audio.queue[i] }))
                    delegate: Item {
                        required property var modelData
                        width: ListView.view.width; height: 44
                        Rectangle { anchors.fill: parent; radius: 8; color: Theme.dark ? "#ffffff" : "#000000"; opacity: qh.hovered ? 0.05 : 0 }
                        Artwork { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4; maskColor: queuePanel.color; source: modelData.t.art }
                        Column {
                            x: 46; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 150
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.t.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                            Text { width: parent.width; elide: Text.ElideRight; text: modelData.t.artist; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            spacing: 0
                            ToolbarButton {
                                symbol: "chevron-up"
                                Accessible.name: "Move track earlier in queue"
                                enabled: audio.order.indexOf(modelData.i) > audio.order.indexOf(audio.index) + 1
                                onClicked: audio.moveUpcoming(modelData.i, -1)
                            }
                            ToolbarButton {
                                symbol: "chevron-down"
                                Accessible.name: "Move track later in queue"
                                enabled: audio.order.indexOf(modelData.i) < audio.order.length - 1
                                onClicked: audio.moveUpcoming(modelData.i, 1)
                            }
                            ToolbarButton {
                                symbol: "trash"
                                Accessible.name: "Remove track from queue"
                                onClicked: audio.removeUpcoming(modelData.i)
                            }
                        }
                        HoverHandler { id: qh }
                        TapHandler { onDoubleTapped: { audio.index = modelData.i; audio.load() } }
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

            Glass {
                id: nameSheet
                objectName: "musicPlaylistNameSheet"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(430, parent.width - 32)
                height: 204
                radius: 20
                tint: Theme.glassRegular.tint
                z: 130
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 14
                    Text {
                        text: app.playlistNameMode === "create" ? "New Playlist" : "Rename Playlist"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    TextField {
                        id: playlistNameField
                        width: parent.width
                        placeholder: "Playlist name"
                        text: app.playlistDraftName
                        onTextChanged: app.playlistDraftName = text
                        onAccepted: app.savePlaylistName()
                    }
                    Text {
                        width: parent.width
                        text: musicLib.playlistError || "Playlists are saved to your Music/Playlists folder."
                        color: musicLib.playlistError ? "#ff453a" : Theme.secondaryLabel
                        wrapMode: Text.WordWrap
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: { nameSheet.visible = false; app.pendingTrack = null } }
                        Button {
                            text: app.playlistNameMode === "create" ? "Create" : "Rename"
                            prominent: true
                            enabled: !musicLib.playlistBusy && app.playlistDraftName.trim().length > 0
                            onClicked: app.savePlaylistName()
                        }
                    }
                }
            }

            Glass {
                id: pickerSheet
                objectName: "musicAddToPlaylist"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 30)
                height: Math.min(450, parent.height - 40)
                radius: 20
                tint: Theme.glassRegular.tint
                z: 105
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12
                    Text {
                        width: parent.width
                        text: "Add to Playlist"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        text: app.pendingTrack?.title || ""
                        elide: Text.ElideRight
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        width: parent.width
                        visible: !!musicLib.playlistError
                        text: musicLib.playlistError
                        wrapMode: Text.WordWrap
                        color: "#ff453a"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Flickable {
                        width: parent.width
                        height: Math.max(90, parent.height - 144)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentHeight: pickerRows.implicitHeight
                        Column {
                            id: pickerRows
                            width: parent.width
                            spacing: 7
                            Repeater {
                                model: musicLib.playlists
                                delegate: Button {
                                    required property var modelData
                                    width: pickerRows.width
                                    text: modelData.name
                                    enabled: !musicLib.playlistBusy && !modelData.error
                                    onClicked: app.addSelectedTrack(modelData)
                                }
                            }
                            Text {
                                visible: musicLib.playlists.length === 0
                                width: parent.width
                                text: "No playlists yet. Create one to organize your music."
                                wrapMode: Text.WordWrap
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: { pickerSheet.visible = false; app.pendingTrack = null } }
                        Button {
                            text: "New Playlist…"
                            onClicked: {
                                pickerSheet.visible = false
                                app.openPlaylistName("create")
                            }
                        }
                    }
                }
            }

            Glass {
                id: managerSheet
                objectName: "musicPlaylistEditor"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(540, parent.width - 28)
                height: Math.min(540, parent.height - 32)
                radius: 20
                tint: Theme.glassRegular.tint
                z: 105
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12
                    Text {
                        width: parent.width
                        text: app.managedPlaylist?.name || "Edit Playlist"
                        elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Row {
                        spacing: 8
                        Button {
                            text: "Rename"
                            enabled: !!app.managedPlaylist && !musicLib.playlistBusy
                            onClicked: app.openPlaylistName("rename", app.managedPlaylist)
                        }
                        Button {
                            text: "Duplicate"
                            enabled: !!app.managedPlaylist && !musicLib.playlistBusy
                            onClicked: app.playlistEdit("duplicate")
                        }
                        Button {
                            text: "Show in Files"
                            enabled: !!app.managedPlaylist
                            onClicked: if (app.managedPlaylist)
                                Quickshell.execDetached(["gg-files", "--select", app.managedPlaylist.path])
                        }
                        Button {
                            text: "Delete"
                            destructive: true
                            enabled: !!app.managedPlaylist && !musicLib.playlistBusy
                            onClicked: deletePlaylistConfirm.visible = true
                        }
                    }
                    Text {
                        width: parent.width
                        text: "Move songs up or down, or remove them. Audio files are never deleted."
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Text {
                        width: parent.width
                        visible: !!musicLib.playlistError
                        text: musicLib.playlistError
                        wrapMode: Text.WordWrap
                        color: "#ff453a"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    ListView {
                        id: playlistEditorList
                        width: parent.width
                        height: Math.max(80, parent.height - 172)
                        model: app.managedEntries
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        spacing: 4
                        delegate: Rectangle {
                            id: playlistEntry
                            required property var modelData
                            width: playlistEditorList.width
                            height: 42
                            radius: 8
                            color: Theme.dark ? "#14ffffff" : "#08000000"
                            Text {
                                x: 8
                                width: parent.width - 128
                                anchors.verticalCenter: parent.verticalCenter
                                text: (playlistEntry.modelData.index + 1) + ". " +
                                    (playlistEntry.modelData.track?.title || playlistEntry.modelData.path.split("/").pop() + " (Missing)")
                                elide: Text.ElideRight
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                            Row {
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                spacing: 0
                                ToolbarButton {
                                    symbol: "chevron-up"
                                    Accessible.name: "Move song up"
                                    enabled: !musicLib.playlistBusy && playlistEntry.modelData.index > 0
                                    onClicked: app.playlistEdit("move",
                                        {index:playlistEntry.modelData.index, to:playlistEntry.modelData.index - 1})
                                }
                                ToolbarButton {
                                    symbol: "chevron-down"
                                    Accessible.name: "Move song down"
                                    enabled: !musicLib.playlistBusy && playlistEntry.modelData.index < app.managedEntries.length - 1
                                    onClicked: app.playlistEdit("move",
                                        {index:playlistEntry.modelData.index, to:playlistEntry.modelData.index + 1})
                                }
                                ToolbarButton {
                                    symbol: "trash"
                                    Accessible.name: "Remove song from playlist"
                                    enabled: !musicLib.playlistBusy
                                    onClicked: app.playlistEdit("remove",{index:playlistEntry.modelData.index})
                                }
                            }
                        }
                    }
                    Button {
                        text: "Done"
                        enabled: !musicLib.playlistBusy
                        onClicked: managerSheet.visible = false
                    }
                }
            }

            Glass {
                id: deletedSheet
                objectName: "musicRecentlyDeletedPlaylists"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(510, parent.width - 30)
                height: Math.min(485, parent.height - 32)
                radius: 20
                tint: Theme.glassRegular.tint
                z: 125
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12
                    Text {
                        text: "Recently Deleted Playlists"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Restore a playlist without changing any music files. If its name is already in use, Music restores it with a new name."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        width: parent.width
                        visible: !!musicLib.playlistError
                        text: musicLib.playlistError
                        wrapMode: Text.WordWrap
                        color: "#ff453a"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Flickable {
                        id: deletedScroller
                        width: parent.width
                        height: Math.max(80, parent.height - 150)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentHeight: deletedRows.implicitHeight
                        Column {
                            id: deletedRows
                            width: deletedScroller.width
                            spacing: 8
                            Text {
                                width: parent.width
                                visible: !musicLib.deletedBusy && musicLib.deletedPlaylists.length === 0
                                text: "There are no deleted playlists."
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                            Text {
                                visible: musicLib.deletedBusy
                                text: "Checking for deleted playlists…"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                            Repeater {
                                model: musicLib.deletedPlaylists
                                delegate: Rectangle {
                                    id: deletedRow
                                    required property var modelData
                                    width: deletedRows.width
                                    height: 54
                                    radius: 9
                                    color: Theme.dark ? "#14ffffff" : "#08000000"
                                    Column {
                                        anchors { left: parent.left; leftMargin: 12; right: restoreButton.left
                                                  rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            text: deletedRow.modelData.name
                                            elide: Text.ElideRight
                                            color: Theme.label
                                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                                        }
                                        Text {
                                            width: parent.width
                                            text: "Deleted " + Qt.formatDateTime(new Date(deletedRow.modelData.deletedAt), "MMM d, yyyy h:mm AP")
                                            elide: Text.ElideRight
                                            color: Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                                        }
                                    }
                                    Button {
                                        id: restoreButton
                                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        text: "Restore"
                                        enabled: !musicLib.playlistBusy && !musicLib.deletedBusy
                                        onClicked: app.restorePlaylist(deletedRow.modelData)
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button {
                            text: "Refresh"
                            enabled: !musicLib.deletedBusy && !musicLib.playlistBusy
                            onClicked: musicLib.refreshDeleted()
                        }
                        Button {
                            text: "Done"
                            enabled: !musicLib.playlistBusy
                            onClicked: deletedSheet.visible = false
                        }
                    }
                }
            }

            Glass {
                id: deletePlaylistConfirm
                objectName: "musicDeletePlaylistConfirm"
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: Math.min(400, parent.width - 30)
                height: 180
                radius: 20
                tint: Theme.glassRegular.tint
                z: 115
                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 14
                    Text {
                        text: "Delete Playlist?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        text: "The playlist moves into Playlists/.Deleted so it can be recovered. Your songs stay on disk."
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: deletePlaylistConfirm.visible = false }
                        Button {
                            text: "Delete Playlist"
                            destructive: true
                            enabled: !musicLib.playlistBusy
                            onClicked: {
                                if (app.playlistEdit("delete"))
                                    deletePlaylistConfirm.visible = false
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: playlistNotice
                visible: !!musicLib.playlistError
                anchors { left: parent.left; right: parent.right; margins: 18
                          bottom: miniPlayer.top; bottomMargin: playbackNotice.visible ? playbackNotice.height + 12 : 8 }
                height: Math.max(46, playlistNoticeText.implicitHeight + 18)
                radius: 10
                color: Theme.contentBg
                border { width: 1; color: "#ff453a" }
                z: 90
                Text {
                    id: playlistNoticeText
                    anchors { left: parent.left; leftMargin: 10; right: noticeDismiss.left
                              rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: musicLib.playlistError
                    color: Theme.label
                    wrapMode: Text.WordWrap
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Button {
                    id: noticeDismiss
                    text: "Dismiss"
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    onClicked: musicLib.playlistError = ""
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
