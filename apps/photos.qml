//@ pragma AppId org.goldengate.Photos
// Photos, laid out like Photos on macOS 27: the library edge to edge in a
// square grid under a floating glass toolbar, a glass sidebar of media types,
// utilities and albums, and each photo or video opening in the window.
//
// The library is ~/Pictures and ~/Videos (GG_PHOTOS_DIRS, colon-separated, to
// change it); the folders in ~/Pictures are its albums. Favourites are kept in
// ~/.config/golden-gate/photos.json. Deleting moves to the Trash.
import Quickshell
import Quickshell.Io
import QtQuick
import "lib/paths.js" as Paths
import "lib"
import "lib/theme"
import "photos"

ShellRoot {
    AppWindow {
        id: win
        title: "Photos"
        implicitWidth: Math.min(1180, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(780, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(640, 420)
        sidebarWidth: app.sidebarOpen ? 200 : 0
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "sidebar"; checked: app.sidebarOpen; onClicked: app.sidebarOpen = !app.sidebarOpen }
        ]
        toolbarItems: [
            Row {
                x: win.sidebarWidth > 0 ? win.contentX + 12 : 130
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                ToolbarButton {
                    visible: app.viewing >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    round: true; symbol: "chevron-left"
                    onClicked: app.viewing = -1
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: app.viewing >= 0 ? app.dayText(app.shown[app.viewing]) : app.sectionTitle
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                    Text {
                        text: app.viewing >= 0 ? app.timeText(app.shown[app.viewing]) : app.countText
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                ToolbarPill {
                    visible: app.viewing < 0
                    ToolbarButton { symbol: "minus"; enabled: app.zoom > 0; onClicked: app.zoom-- }
                    ToolbarButton { symbol: "plus"; enabled: app.zoom < app.sizes.length - 1; onClicked: app.zoom++ }
                }
                ToolbarPill {
                    visible: app.viewing >= 0
                    ToolbarButton { symbol: "info"; checked: viewer.infoOpen; onClicked: viewer.infoOpen = !viewer.infoOpen }
                    ToolbarButton {
                        symbol: "heart"; tone: app.isFavorite(app.shown[app.viewing]?.path) ? "red" : "auto"
                        onClicked: app.toggleFavorite(app.shown[app.viewing]?.path)
                    }
                }
                ToolbarButton {
                    id: moreBtn
                    round: true; symbol: "ellipsis"
                    onClicked: menu.popup(moreBtn, 0, height + 6, app.viewing >= 0 || app.selected >= 0 ? [
                        { text: "Open With Default App", action: () => Qt.openUrlExternally(Paths.fileUrl(app.focusItem.path)) },
                        { text: "Show in Files", action: () => Quickshell.execDetached(["nautilus", "--select", app.focusItem.path]) },
                        { text: "Copy Path", action: () => Quickshell.clipboardText = app.focusItem.path },
                        { separator: true },
                        { text: "Delete " + (app.focusItem.kind === "video" ? "Video" : "Photo"), action: () => app.trash(app.focusItem) },
                    ] : [
                        { text: "Show Oldest First" + (app.oldestFirst ? "  ✓" : ""), action: () => app.oldestFirst = true },
                        { text: "Show Newest First" + (!app.oldestFirst ? "  ✓" : ""), action: () => app.oldestFirst = false },
                        { separator: true },
                        { text: "Refresh Library", action: () => app.rescan() },
                    ])
                }
                ToolbarButton {
                    visible: !searchBox.visible && app.viewing < 0
                    round: true; symbol: "search"
                    onClicked: { searchBox.visible = true; searchField.forceActiveFocus() }
                }
                Rectangle {
                    id: searchBox
                    visible: false
                    width: 200; height: 32; radius: 16
                    color: Theme.dark ? "#eb3a3a3e" : "#ebffffff"
                    border { width: 0.5; color: Theme.dark ? "#2effffff" : "#1f000000" }
                    Symbol { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "search"; tone: "gray"; size: 13 }
                    TextInput {
                        id: searchField
                        x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13 }
                        clip: true
                        Keys.onEscapePressed: { text = ""; searchBox.visible = false; app.forceActiveFocus() }
                        Text { visible: !searchField.text; text: "Search"; color: Theme.tertiaryLabel; font: searchField.font }
                    }
                }
            }
        ]

        sidebar: [
            Flickable {
                anchors.fill: parent
                contentHeight: nav.height + 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: nav
                    width: parent.width
                    component Heading: Text {
                        leftPadding: 10; topPadding: 12; bottomPadding: 4
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                    }
                    component NavItem: Item {
                        id: navItem
                        property string symbol
                        property string text
                        property string key
                        width: parent.width; height: 28
                        readonly property bool selected: app.section === key
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: Theme.dark ? "#ffffff" : "#000000"
                            opacity: navItem.selected ? (Theme.dark ? 0.12 : 0.07) : nh.hovered ? 0.04 : 0
                        }
                        Symbol { x: 10; anchors.verticalCenter: parent.verticalCenter; name: navItem.symbol; tone: "accent"; size: 15 }
                        Text {
                            x: 34; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 40; elide: Text.ElideRight
                            text: navItem.text
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }
                        HoverHandler { id: nh }
                        TapHandler { onTapped: { app.section = navItem.key; app.viewing = -1; app.selected = -1 } }
                    }
                    Heading { text: "Photos"; topPadding: 4 }
                    NavItem { symbol: "photo"; text: "Library"; key: "library" }
                    NavItem { symbol: "clock"; text: "Recently Saved"; key: "recent" }
                    Heading { text: "Media Types"; visible: app.counts.videos + app.counts.screenshots > 0 }
                    NavItem { symbol: "video"; text: "Videos"; key: "videos"; visible: app.counts.videos > 0 }
                    NavItem { symbol: "screenshot"; text: "Screenshots"; key: "screenshots"; visible: app.counts.screenshots > 0 }
                    Heading { text: "Utilities" }
                    NavItem { symbol: "heart"; text: "Favorites"; key: "favorites" }
                    Heading { text: "Albums"; visible: app.albums.length > 0 }
                    Repeater {
                        model: app.albums
                        delegate: NavItem {
                            required property var modelData
                            symbol: "folder"; text: modelData.name; key: "album:" + modelData.path
                        }
                    }
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent
            focus: true

            readonly property string home: Quickshell.env("HOME")
            readonly property var dirs: (Quickshell.env("GG_PHOTOS_DIRS") || [Quickshell.env("XDG_PICTURES_DIR") || home + "/Pictures", Quickshell.env("XDG_VIDEOS_DIR") || home + "/Videos"].join(":")).split(":").filter((d) => d)
            readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/golden-gate/photos"
            readonly property string configFile: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/golden-gate/photos.json"

            property bool sidebarOpen: true
            property var items: []           // {path, mtime, kind, seconds, thumb, name}
            property var favorites: []
            property string section: "library"
            property int zoom: 2
            readonly property var sizes: [80, 120, 180, 260, 380]
            property bool oldestFirst: true
            property int selected: -1        // index into shown
            property int viewing: -1         // index into shown, or -1 for the grid

            readonly property var albums: {
                const root = dirs[0] ?? ""
                const names = {}
                for (const it of items) {
                    if (!it.path.startsWith(root + "/")) continue
                    const rest = it.path.slice(root.length + 1)
                    const i = rest.indexOf("/")
                    if (i > 0 && rest.slice(0, i) !== "Screenshots") names[rest.slice(0, i)] = true
                }
                return Object.keys(names).sort().map((n) => ({ name: n, path: root + "/" + n }))
            }
            function isScreenshot(it) { return /\/Screenshots\//i.test(it.path) || /^Screen(shot| Recording)/i.test(it.name) }
            readonly property var counts: ({
                videos: items.filter((i) => i.kind === "video").length,
                screenshots: items.filter((i) => isScreenshot(i)).length,
            })
            readonly property var shown: {
                const q = searchField.text.trim().toLowerCase()
                const monthAgo = Date.now() / 1000 - 30 * 86400
                let list = items.filter((it) =>
                    section === "library" ? true
                  : section === "recent" ? it.mtime > monthAgo
                  : section === "videos" ? it.kind === "video"
                  : section === "screenshots" ? isScreenshot(it)
                  : section === "favorites" ? favorites.includes(it.path)
                  : section.startsWith("album:") ? it.path.startsWith(section.slice(6) + "/") : true)
                if (q) list = list.filter((it) => it.path.toLowerCase().includes(q) || dayText(it).toLowerCase().includes(q))
                return oldestFirst ? list : list.slice().reverse()
            }
            readonly property var focusItem: shown[viewing >= 0 ? viewing : selected] ?? null
            readonly property string sectionTitle: section === "library" ? "Library" : section === "recent" ? "Recently Saved"
                : section === "videos" ? "Videos" : section === "screenshots" ? "Screenshots" : section === "favorites" ? "Favorites"
                : section.split("/").pop()
            readonly property string countText: {
                const v = shown.filter((i) => i.kind === "video").length, p = shown.length - v
                const parts = []
                if (p || !v) parts.push(p + (p === 1 ? " Photo" : " Photos"))
                if (v) parts.push(v + (v === 1 ? " Video" : " Videos"))
                const last = shown[grid.lastVisible] ?? shown[shown.length - 1]
                return parts.join(", ") + (last ? " · " + new Date(last.mtime * 1000).toLocaleDateString(Qt.locale(), "MMMM yyyy") : "")
            }
            function dayText(it) { return it ? new Date(it.mtime * 1000).toLocaleDateString(Qt.locale(), "d MMMM yyyy") : "" }
            function timeText(it) { return it ? new Date(it.mtime * 1000).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : "" }

            function isFavorite(path) { return !!path && favorites.includes(path) }
            function toggleFavorite(path) {
                if (!path) return
                favorites = isFavorite(path) ? favorites.filter((p) => p !== path) : favorites.concat([path])
                Quickshell.execDetached(["mkdir", "-p", configFile.replace(/\/[^/]+$/, "")])
                store.setText(JSON.stringify({ favorites: favorites }, null, 1))
            }
            function trash(it) {
                if (!it) return
                Quickshell.execDetached(["gio", "trash", it.path])
                items = items.filter((i) => i.path !== it.path)
                if (viewing >= shown.length) viewing = shown.length - 1
            }
            function rescan() { scanner.running = true }
            function open(i) { selected = i; viewing = i }

            FileView {
                id: store
                path: app.configFile
                printErrors: false
                blockWrites: true
                onLoaded: { try { app.favorites = JSON.parse(text()).favorites ?? [] } catch (e) {} }
            }
            Process {
                id: scanner
                running: true
                command: ["bash", Qt.resolvedUrl("photos/scan.sh").toString().replace("file://", ""), app.cacheDir].concat(app.dirs)
                stdout: StdioCollector {
                    onStreamFinished: {
                        app.items = text.split("\n").filter((l) => l).map((l) => {
                            const c = l.split("\t")
                            return { path: c[0], mtime: Number(c[1]), kind: c[2], seconds: Number(c[3]) || 0, thumb: c[4] || "", name: c[0].split("/").pop() }
                        })
                        Qt.callLater(() => { if (app.oldestFirst) grid.positionViewAtEnd() })
                    }
                }
            }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier
                if (viewing >= 0) {
                    if (e.key === Qt.Key_Left && viewing > 0) viewing--
                    else if (e.key === Qt.Key_Right && viewing + 1 < shown.length) viewing++
                    else if (e.key === Qt.Key_Escape || e.key === Qt.Key_Space || e.key === Qt.Key_Return) { selected = viewing; viewing = -1 }
                    else if (e.key === Qt.Key_Period) toggleFavorite(shown[viewing]?.path)
                    else if (ctrl && e.key === Qt.Key_I) viewer.infoOpen = !viewer.infoOpen
                    else if (ctrl && e.key === Qt.Key_Backspace) trash(shown[viewing])
                    else return
                } else {
                    const cols = grid.columns
                    if (e.key === Qt.Key_Right) selected = Math.min(shown.length - 1, selected + 1)
                    else if (e.key === Qt.Key_Left) selected = Math.max(0, selected - 1)
                    else if (e.key === Qt.Key_Down) selected = Math.min(shown.length - 1, selected + cols)
                    else if (e.key === Qt.Key_Up) selected = Math.max(0, selected - cols)
                    else if ((e.key === Qt.Key_Space || e.key === Qt.Key_Return) && selected >= 0) viewing = selected
                    else if (e.key === Qt.Key_Period && selected >= 0) toggleFavorite(shown[selected]?.path)
                    else if (ctrl && (e.key === Qt.Key_Equal || e.key === Qt.Key_Plus)) zoom = Math.min(sizes.length - 1, zoom + 1)
                    else if (ctrl && e.key === Qt.Key_Minus) zoom = Math.max(0, zoom - 1)
                    else if (ctrl && e.key === Qt.Key_F) { searchBox.visible = true; searchField.forceActiveFocus() }
                    else if (ctrl && e.key === Qt.Key_Backspace && selected >= 0) trash(shown[selected])
                    else return
                    if (selected >= 0) grid.positionViewAtIndex(selected, GridView.Contain)
                }
                e.accepted = true
            }

            // ------------------------------------------------------------ grid
            GridView {
                id: grid
                anchors.fill: parent
                visible: app.viewing < 0
                readonly property int columns: Math.max(2, Math.round(width / app.sizes[app.zoom]))
                readonly property int lastVisible: indexAt(10, contentY + height - 10)
                cellWidth: width / columns
                cellHeight: cellWidth
                topMargin: win.toolbarHeight
                bottomMargin: 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                model: app.shown
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    width: grid.cellWidth; height: grid.cellHeight
                    Rectangle {
                        anchors { fill: parent; rightMargin: 2; bottomMargin: 2 }
                        color: Theme.dark ? "#2c2c2e" : "#ececf0"
                        Image {
                            anchors.fill: parent
                            source: tile.modelData.kind === "video" ? (tile.modelData.thumb ? Paths.fileUrl(tile.modelData.thumb) : "") : Paths.fileUrl(tile.modelData.path)
                            sourceSize: Qt.size(Math.ceil(width * 1.5), Math.ceil(height * 1.5))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            smooth: true
                        }
                        // Video length, bottom right
                        Text {
                            visible: tile.modelData.kind === "video"
                            anchors { right: parent.right; bottom: parent.bottom; margins: 6 }
                            text: Math.floor(tile.modelData.seconds / 60) + ":" + String(tile.modelData.seconds % 60).padStart(2, "0")
                            color: "#ffffff"
                            style: Text.Raised; styleColor: "#66000000"
                            font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                        }
                        Symbol {
                            visible: app.isFavorite(tile.modelData.path)
                            anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                            name: "heart"; tone: "white"; size: 12
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: app.selected === tile.index
                            color: "transparent"
                            border { width: 3; color: Theme.accent }
                        }
                    }
                    TapHandler {
                        onTapped: { app.selected = tile.index; app.forceActiveFocus() }
                        onDoubleTapped: app.open(tile.index)
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: grid.count === 0 && !scanner.running
                    text: app.section === "favorites" ? "No Favorites" : app.items.length ? "No Results" : "No Photos"
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
                }
            }

            // Scroll edge under the toolbar.
            Rectangle {
                width: parent.width; height: win.toolbarHeight + 10
                visible: app.viewing < 0 && grid.contentY > grid.originY - grid.topMargin + 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Theme.contentBg }
                    GradientStop { position: 0.55; color: Qt.rgba(Theme.contentBg.r, Theme.contentBg.g, Theme.contentBg.b, 0.75) }
                    GradientStop { position: 1; color: Qt.rgba(Theme.contentBg.r, Theme.contentBg.g, Theme.contentBg.b, 0) }
                }
            }

            Viewer {
                id: viewer
                anchors.fill: parent
                anchors.topMargin: win.toolbarHeight
                visible: app.viewing >= 0
                item: app.shown[app.viewing] ?? null
                canPrevious: app.viewing > 0
                canNext: app.viewing + 1 < app.shown.length
                onPrevious: app.viewing--
                onNext: app.viewing++
            }
        }

        PopupMenu { id: menu; parent: win.overlay }
    }
}

