//@ pragma AppId org.goldengate.Software
// CitronOS App Store, laid out like the Mac's: Discover with an editorial
// card and shelves, Create / Work / Play / Develop, a page for each app, and
// Updates and Installed. Two sources:
//   Linux apps  Flathub, installed into your account (software/helper.py)
//   Mac apps    downloaded from their developers and opened with Darling, the
//               macOS translation layer (software/macapps.py; experimental:
//               many Mac apps with windows don't open yet, and the store says so)
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "App Store"
        implicitWidth: Math.min(1180, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(800, (Quickshell.screens[0]?.height ?? 900) - 110)
        minimumSize: Qt.size(860, 560)
        sidebarWidth: 220
        background: Theme.contentBg
        fullSizeContent: true

        toolbarItems: [
            Row {
                x: win.contentX + 14
                anchors.verticalCenter: parent.verticalCenter
                visible: !!store.detail
                ToolbarPill {
                    ToolbarButton { symbol: "chevron-left"; onClicked: store.detail = null }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                ToolbarButton {
                    round: true
                    symbol: "arrow-clockwise"
                    enabled: !store.loading && !store.busy
                    onClicked: store.reload(true)
                }
            }
        ]

        sidebar: [
            TextField {
                id: search
                width: parent.width
                height: 30
                search: true
                placeholder: "Search"
                onTextChanged: { store.query = text; if (text) store.detail = null }
                input.Keys.onEscapePressed: { text = ""; store.query = "" }
            },
            Column {
                y: 42
                width: parent.width
                spacing: 2
                Repeater {
                    model: [
                        { page: "discover", text: "Discover", symbol: "sparkles" },
                        { page: "mac", text: "Mac Apps", symbol: "window" },
                        { page: "create", text: "Create", symbol: "brush" },
                        { page: "work", text: "Work", symbol: "briefcase" },
                        { page: "play", text: "Play", symbol: "game" },
                        { page: "develop", text: "Develop", symbol: "hammer" },
                        { gap: true },
                        { page: "updates", text: "Updates", symbol: "download" },
                        { page: "installed", text: "Installed", symbol: "checkmark" }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: modelData.gap ? 12 : row.height
                        SidebarRow {
                            id: row
                            visible: !parent.modelData.gap
                            width: parent.width
                            text: parent.modelData.text ?? ""
                            symbol: parent.modelData.symbol ?? ""
                            selected: store.page === parent.modelData.page && !store.query.trim()
                            badge: parent.modelData.page === "updates" && store.updates.length ? String(store.updates.length) : ""
                            onClicked: { store.page = parent.modelData.page; store.detail = null; search.text = "" }
                        }
                    }
                }
            }
        ]

        Item {
            id: store
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("software/helper.py").toString().replace("file://", "")
            readonly property string macHelper: Qt.resolvedUrl("software/macapps.py").toString().replace("file://", "")
            readonly property string darlingSetup: Qt.resolvedUrl("software/darling-setup.sh").toString().replace("file://", "")

            property string page: Quickshell.env("GG_STORE_PAGE") || "discover"
            property string query: ""
            property var detail: null
            property string pendingDetail: Quickshell.env("GG_STORE_APP") || ""
            property bool installerSheetVisible: false
            property var installerApp: null
            property bool installerSucceeded: false
            function openPending() {
                if (!pendingDetail) return
                const app = macApps.concat(linuxApps).find((a) => a.id === pendingDetail)
                if (app) { detail = app; pendingDetail = "" }
            }

            property var catalog: []
            property bool loading: true
            property string loadError: ""
            property var mac: []
            property var macFeatured: []
            property var macInstalled: ({})
            property bool darling: false
            property bool macLoading: true
            property string macError: ""

            property bool busy: false
            property string activeId: ""
            property string activeAction: ""
            property real progress: 0
            property string message: ""
            property string error: ""
            property string errorDetails: ""
            property bool askDarling: false
            property var queue: []

            readonly property var linuxApps: catalog.map((a) => Object.assign({ source: "linux" }, a))
            function macEntry(c) {
                const r = macInstalled[c.token]
                const iconValue = r?.icon || c.icon || ""
                return {
                    source: "mac", id: c.token, name: c.name, summary: c.desc, icon: iconValue,
                    installed: !!r, update: !!r && !!c.version && r.catalogVersion !== c.version,
                    homepage: c.homepage, version: r?.version ?? c.version, minMacOS: c.minMacOS ?? "", checksum: !!c.checksum,
                    opened: r?.opened ?? null, lastError: r?.lastError ?? "", arch: r?.arch ?? []
                }
            }
            readonly property var macApps: mac.map((c) => macEntry(c))
            readonly property var macOrphans: Object.keys(macInstalled).filter((t) => !mac.some((c) => c.token === t))
                .map((t) => Object.assign(macEntry({ token: t, name: macInstalled[t].name, desc: "", version: "", icon: macInstalled[t].icon || "" }), { update: false }))
            readonly property var featuredMac: macFeatured.map((t) => macApps.find((a) => a.id === t)).filter((a) => !!a)

            function hasCategory(app, names) {
                const cats = (app.categories ?? []).map((x) => String(x).toLowerCase())
                return names.some((n) => cats.some((c) => c.includes(n)))
            }
            readonly property var categoryNames: ({
                create: ["graphics", "photography", "audiovideo", "audio", "video", "music"],
                work: ["office", "productivity", "finance", "viewer"],
                play: ["game"],
                develop: ["development", "ide", "texteditor"]
            })
            function inCategory(page) { return linuxApps.filter((a) => hasCategory(a, categoryNames[page] ?? [])) }

            readonly property var updates: linuxApps.filter((a) => a.update).concat(macApps.filter((a) => a.update))
            readonly property var installed: linuxApps.filter((a) => a.installed).concat(macApps.filter((a) => a.installed), macOrphans)
            function matches(app, q) {
                return [app.name ?? "", app.summary ?? "", app.id ?? "", ...(app.keywords ?? [])].join(" ").toLowerCase().includes(q)
            }
            readonly property var results: {
                const q = query.trim().toLowerCase()
                if (!q) return ({ linux: [], mac: [] })
                return { linux: linuxApps.filter((a) => matches(a, q)).slice(0, 60), mac: macApps.filter((a) => matches(a, q)).slice(0, 60) }
            }
            function live(app) {
                if (!app) return null
                const list = app.source === "mac" ? macApps.concat(macOrphans) : linuxApps
                return list.find((a) => a.id === app.id) ?? app
            }

            function reload(refresh) {
                if (catalogLoad.running || busy) return
                loading = true
                loadError = ""
                catalogLoad.command = ["python3", helper, refresh ? "refresh" : "catalog"]
                catalogLoad.running = true
                reloadMac(refresh)
            }
            function reloadMac(refresh) {
                if (macLoad.running) return
                macLoading = true
                macLoad.command = ["python3", macHelper, "all"].concat(refresh ? ["--refresh"] : [])
                macLoad.running = true
            }
            Component.onCompleted: reload(false)

            Process {
                id: catalogLoad
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const e = JSON.parse(text)
                            if (e.event === "catalog") { store.catalog = e.apps ?? []; store.loadError = ""; store.openPending() }
                            else if (e.event === "error") store.loadError = e.message ?? "The catalog couldn't be loaded."
                        } catch (err) { store.loadError = "Flathub's catalog couldn't be read." }
                    }
                }
                onExited: (code) => {
                    store.loading = false
                    if (code !== 0 && !store.loadError) store.loadError = "Flathub couldn't be reached. Apps appear once it can."
                }
            }
            Process {
                id: macLoad
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const e = JSON.parse(text.trim().split("\n").pop())
                            if (e.event !== "mac-all") return
                            store.mac = e.apps ?? []
                            store.macFeatured = e.featured ?? []
                            store.macInstalled = e.installed ?? {}
                            store.darling = !!e.darling
                            store.macError = e.error ?? ""
                            store.openPending()
                        } catch (err) { store.macError = "The Mac app catalog couldn't be read." }
                    }
                }
                onExited: store.macLoading = false
            }
            Process {
                id: darlingCheck
                command: ["python3", store.macHelper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: { try { store.darling = !!JSON.parse(text).darling } catch (err) {} }
                }
            }
            Timer { interval: 15000; repeat: true; running: !store.darling && store.page === "mac"; onTriggered: darlingCheck.running = true }
            function setUpDarling() {
                askDarling = false
                Quickshell.execDetached(["ghostty", "-e", darlingSetup])
            }

            function showInstaller(app) {
                store.installerApp = app
                store.installerSheetVisible = true
                store.installerSucceeded = false
            }

            function transact(action, app) {
                if (busy || !app) return
                busy = true
                activeId = app.id
                activeAction = action
                progress = 0.03
                error = ""
                errorDetails = ""
                message = action === "launch" ? "Opening " + app.name + "…" : "Preparing…"
                if (app.source === "mac") {
                    const verb = action === "launch" ? "open" : action === "update" ? "install" : action
                    transaction.command = ["python3", macHelper, verb, app.id]
                } else {
                    transaction.command = ["python3", helper, action, app.id]
                }
                transaction.running = true
            }
            function act(app) {
                app = live(app)
                if (app.update) transact("update", app)
                else if (app.installed) {
                    if (app.source === "mac" && !darling) askDarling = true
                    else transact("launch", app)
                } else {
                    const current = live(app)
                    const isMac = current && current.source === "mac"
                    if (isMac) {
                        showInstaller(current)
                        Qt.callLater(() => transact("install", current))
                    } else {
                        transact("install", current)
                    }
                }
            }
            function consume(line) {
                if (!line || !line.trim()) return
                try {
                    const e = JSON.parse(line)
                    if (e.event === "progress") { progress = e.progress ?? progress; message = e.message ?? message }
                    else if (e.event === "done") progress = 1
                    else if (e.event === "error") {
                        if (e.code === "no-darling") askDarling = true
                        else { error = e.message ?? "That didn't work."; errorDetails = e.details ?? "" }
                    }
                } catch (err) {}
            }
            Process {
                id: transaction
                stdout: SplitParser { onRead: (line) => store.consume(line) }
                onExited: (code) => {
                    const id = store.activeId, action = store.activeAction, wasMac = transaction.command[1] === store.macHelper
                    store.busy = false
                    store.activeId = ""
                    store.activeAction = ""
                    if (code !== 0 && !store.error && !store.askDarling) store.error = store.message || "That didn't complete."
                    if (code === 0 && store.queue.length) {
                        const next = store.queue[0]
                        store.queue = store.queue.slice(1)
                        Qt.callLater(() => store.transact("update", next))
                        return
                    }
                    store.queue = []
                    if (code === 0 && store.installerSheetVisible && store.installerApp) {
                        store.installerSucceeded = true
                        Qt.callLater(() => { store.installerSheetVisible = false; store.installerApp = null })
                    }
                    if (action !== "launch") Qt.callLater(() => store.reload(false))
                    else if (wasMac) store.reloadMac(false)
                }
            }

            component AppIcon: Item {
                id: icon
                property var app
                property real size: 56
                width: size; height: size
                readonly property string path: app?.icon ? "file://" + app.icon : (app?.source === "linux" ? Quickshell.iconPath(app.id, true) : "")
                readonly property var hues: [["#5e9cf8", "#2f5fd6"], ["#ff9f5a", "#e8613c"], ["#7bd88f", "#2f9e57"], ["#c88cf5", "#7c4bd8"], ["#ff7d9b", "#d93d6a"], ["#5ad1d6", "#1f8fa6"], ["#f7c948", "#d9922b"], ["#9aa5b8", "#5d6880"]]
                readonly property var hue: hues[Array.from(app?.name ?? "?").reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7) % hues.length]
                Image {
                    anchors.fill: parent
                    visible: !!icon.path && status === Image.Ready
                    source: icon.path
                    sourceSize: Qt.size(icon.size * 2, icon.size * 2)
                    smooth: true; mipmap: true
                    asynchronous: true
                }
                Rectangle {
                    anchors { fill: parent; margins: icon.size * 0.06 }
                    visible: !icon.path
                    radius: width * 0.225
                    gradient: Gradient {
                        GradientStop { position: 0; color: icon.hue[0] }
                        GradientStop { position: 1; color: icon.hue[1] }
                    }
                    border { width: 0.5; color: "#26000000" }
                    Text {
                        anchors.centerIn: parent
                        text: (icon.app?.name ?? "?").replace(/^the /i, "").charAt(0).toUpperCase()
                        color: "#ffffff"
                        font { family: Theme.fontDisplay; pixelSize: icon.size * 0.46; weight: Font.Bold }
                    }
                }
            }

            component GetButton: Item {
                id: get
                property var app
                property bool large: false
                readonly property var current: store.live(app)
                readonly property bool working: store.busy && store.activeId === app?.id
                readonly property string label: current?.update ? "UPDATE" : current?.installed ? "OPEN" : "GET"
                signal pressed()
                implicitWidth: working ? implicitHeight : Math.max(large ? 84 : 66, text.implicitWidth + 28)
                implicitHeight: large ? 32 : 28
                width: implicitWidth; height: implicitHeight
                Behavior on implicitWidth { NumberAnimation { duration: Theme.reduceMotion ? 1 : 155; easing.type: Easing.OutCubic } }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    visible: !get.working
                    color: get.large ? Theme.accent : tap.pressed ? (Theme.dark ? "#4a4a4e" : "#dcdce0") : (Theme.dark ? "#3a3a3c" : "#e9e9ec")
                    opacity: store.busy && !get.working ? 0.55 : 1
                    Text {
                        id: text
                        anchors.centerIn: parent
                        text: get.label
                        color: get.large ? "#ffffff" : Theme.accent
                        font { family: Theme.fontUi; pixelSize: get.large ? 14 : 13; weight: Font.Bold; letterSpacing: 0.3 }
                    }
                }
                Shape {
                    anchors.fill: parent
                    visible: get.working
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.dark ? "#3a3a3c" : "#e3e3e6"; strokeWidth: 2.5; fillColor: "transparent"
                        PathAngleArc { centerX: get.width / 2; centerY: get.height / 2; radiusX: get.height / 2 - 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Theme.accent; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                        PathAngleArc { centerX: get.width / 2; centerY: get.height / 2; radiusX: get.height / 2 - 2; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * Math.max(0.03, store.progress) }
                    }
                }
                Rectangle { anchors.centerIn: parent; visible: get.working; width: 8; height: 8; radius: 1.5; color: Theme.accent }
                TapHandler { id: tap; enabled: !store.busy; onTapped: get.pressed() }
                Accessible.role: Accessible.Button
                Accessible.name: get.label + " " + (app?.name ?? "")
            }

            component Lockup: Item {
                id: lockup
                property var app
                implicitHeight: 76
                Rectangle {
                    anchors { fill: parent; margins: 2 }
                    radius: 12
                    color: lockHover.hovered ? (Theme.dark ? "#0dffffff" : "#08000000") : "transparent"
                }
                AppIcon { id: lockIcon; x: 6; anchors.verticalCenter: parent.verticalCenter; app: lockup.app; size: 58 }
                Column {
                    anchors { left: lockIcon.right; leftMargin: 12; right: lockGet.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Row {
                        spacing: 6
                        width: parent.width
                        Text {
                            width: Math.min(implicitWidth, parent.width - (macTag.visible ? macTag.width + 6 : 0))
                            text: lockup.app?.name ?? ""
                            elide: Text.ElideRight
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                        }
                        Rectangle {
                            id: macTag
                            visible: lockup.app?.source === "mac"
                            anchors.verticalCenter: parent.verticalCenter
                            width: macText.implicitWidth + 8; height: 15; radius: 4
                            color: "transparent"
                            border { width: 1; color: Theme.tertiaryLabel }
                            Text { id: macText; anchors.centerIn: parent; text: "MAC"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(9); weight: Font.Bold; letterSpacing: 0.2 } }
                        }
                    }
                    Text {
                        width: parent.width
                        text: lockup.app?.summary || ""
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                }
                GetButton { id: lockGet; anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    app: lockup.app; onPressed: store.act(lockup.app) }
                Rectangle { anchors { left: lockIcon.right; leftMargin: 12; right: parent.right; bottom: parent.bottom }
                    height: 1; color: Theme.separator; opacity: 0.6 }
                HoverHandler { id: lockHover }
                TapHandler { onTapped: store.detail = lockup.app }
            }

            component Shelf: Column {
                id: shelf
                property string title
                property string subtitle
                property var apps: []
                property int rows: 2
                property string seeAll: ""
                readonly property int columns: Math.max(1, Math.floor(width / 320))
                visible: apps.length > 0
                spacing: 6
                Item {
                    width: parent.width; height: 30
                    Column {
                        anchors.bottom: parent.bottom
                        Text { text: shelf.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(20); weight: Font.Bold } }
                    }
                    Text {
                        anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 3 }
                        visible: !!shelf.seeAll
                        text: "See All"
                        color: Theme.accent
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        TapHandler { onTapped: { store.page = shelf.seeAll; scroll.contentY = 0 } }
                    }
                }
                Text {
                    visible: !!shelf.subtitle
                    width: parent.width
                    text: shelf.subtitle
                    wrapMode: Text.WordWrap
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                }
                Grid {
                    width: parent.width
                    columns: shelf.columns
                    columnSpacing: 18
                    Repeater {
                        model: shelf.apps.slice(0, shelf.rows > 0 ? shelf.columns * shelf.rows : shelf.apps.length)
                        Lockup { required property var modelData; app: modelData; width: (shelf.width - 18 * (shelf.columns - 1)) / shelf.columns }
                    }
                }
            }

            component PageTitle: Text {
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 30; weight: Font.Bold }
            }

            Rectangle { anchors.fill: parent; color: Theme.contentBg }

            Flickable {
                id: scroll
                visible: !store.detail
                anchors { fill: parent; leftMargin: 28; rightMargin: 24 }
                topMargin: win.toolbarHeight + 4
                bottomMargin: 30
                contentWidth: width
                contentHeight: pages.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: pages
                    width: scroll.width
                    spacing: 28

                    Column {
                        visible: !!store.query.trim()
                        width: parent.width
                        spacing: 22
                        PageTitle { text: "Results for “" + store.query.trim() + "”" }
                        Shelf { width: parent.width; title: "Linux Apps"; apps: store.results.linux; rows: 0 }
                        Shelf { width: parent.width; title: "Mac Apps"; apps: store.results.mac; rows: 0 }
                        EmptyState {
                            visible: !store.results.linux.length && !store.results.mac.length
                            width: parent.width; height: 240
                            symbol: "search"; title: "No Results"
                            text: "Nothing in the App Store matches “" + store.query.trim() + "”."
                        }
                    }

                    Column {
                        visible: !store.query.trim() && store.page === "discover"
                        width: parent.width
                        spacing: 30
                        PageTitle { text: "Discover" }

                        Rectangle {
                            width: parent.width
                            height: 270
                            radius: 22
                            clip: true
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#1b2a6b" }
                                GradientStop { position: 0.55; color: "#3b3fb4" }
                                GradientStop { position: 1; color: "#8b5cf6" }
                            }
                            Column {
                                anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
                                width: Math.min(440, parent.width * 0.52)
                                spacing: 10
                                Text { text: "NEW ON CITRONOS"; color: "#b3ffffff"; font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Bold; letterSpacing: 1.2 } }
                                Text {
                                    width: parent.width
                                    text: "Mac apps, right here."
                                    wrapMode: Text.WordWrap
                                    color: "#ffffff"
                                    font { family: Theme.fontDisplay; pixelSize: 30; weight: Font.Bold }
                                }
                                Text {
                                    width: parent.width
                                    text: "Get apps made for the Mac straight from their developers. They install cleanly with Darling, open in your Applications folder, and show their native Mac-style icon once downloaded."
                                    wrapMode: Text.WordWrap
                                    color: "#e6ffffff"
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                                    lineHeight: 1.1
                                }
                                Item { width: 1; height: 4 }
                                Button { text: "Explore Mac Apps"; onClicked: store.page = "mac" }
                            }
                            Repeater {
                                model: store.featuredMac.slice(0, 5)
                                AppIcon {
                                    required property var modelData
                                    required property int index
                                    app: modelData
                                    size: 92
                                    x: parent.width - 150 - index * 70 + (index % 2) * 10
                                    y: 40 + (index % 2) * 96
                                    rotation: [-8, 6, -4, 9, -6][index]
                                    visible: parent.width > 720 || index < 2
                                }
                            }
                        }

                        Shelf {
                            width: parent.width
                            title: "Popular Mac Apps"
                            subtitle: "Downloaded from each developer, checked against the published checksum where available."
                            apps: store.featuredMac
                            seeAll: "mac"
                        }
                        Shelf { width: parent.width; title: "Create"; apps: store.inCategory("create"); seeAll: "create" }
                        Shelf { width: parent.width; title: "Work"; apps: store.inCategory("work"); seeAll: "work" }
                        Shelf { width: parent.width; title: "Play"; apps: store.inCategory("play"); seeAll: "play"; rows: 1 }
                        Shelf { width: parent.width; title: "Essentials"; apps: store.linuxApps.filter((a) => !a.installed); rows: 2 }
                    }

                    Column {
                        visible: !store.query.trim() && store.page === "mac"
                        width: parent.width
                        spacing: 26
                        PageTitle { text: "Mac Apps" }
                        Rectangle {
                            width: parent.width
                            height: darlingCard.implicitHeight + 36
                            radius: 18
                            color: Theme.dark ? "#14ffffff" : "#08000000"
                            border { width: 0.5; color: Theme.separator }
                            RowLayout {
                                id: darlingCard
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 20; rightMargin: 20 }
                                spacing: 16
                                Rectangle {
                                    Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: 23
                                    color: store.darling ? "#2f9e57" : Theme.accent
                                    Symbol { anchors.centerIn: parent; name: store.darling ? "checkmark" : "window"; size: 22; tone: "white" }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Text {
                                        text: store.darling ? "Mac app support is ready" : "Set up Mac app support"
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                        text: (store.darling
                                            ? "Mac apps open with Darling, the macOS translation layer."
                                            : "Mac apps open with Darling, the macOS translation layer. Setting it up installs Darling's official release in a Terminal window. Darling runs Intel Mac apps; many apps with windows still need manual testing and you can see the result per app.")
                                    }
                                }
                                Button {
                                    visible: !store.darling
                                    text: "Set Up…"
                                    prominent: true
                                    onClicked: store.setUpDarling()
                                }
                            }
                        }
                        EmptyState {
                            visible: !!store.macError && !store.mac.length
                            width: parent.width; height: 220
                            symbol: "wifi"; title: "Mac Apps Unavailable"; text: store.macError
                            actionText: "Try Again"
                            onAction: store.reloadMac(true)
                        }
                        Shelf { width: parent.width; title: "Popular on the Mac"; apps: store.featuredMac; rows: 3 }
                        Shelf {
                            width: parent.width
                            title: "All Mac Apps"
                            subtitle: store.mac.length > 90 ? store.mac.length.toLocaleString(Qt.locale(), "f", 0) + " apps. Search to find any of them." : ""
                            apps: store.macApps
                            rows: 30
                        }
                    }

                    Column {
                        visible: !store.query.trim() && ["create", "work", "play", "develop"].includes(store.page)
                        width: parent.width
                        spacing: 22
                        PageTitle { text: ({ create: "Create", work: "Work", play: "Play", develop: "Develop" })[store.page] ?? "" }
                        Shelf { width: parent.width; title: ""; apps: store.inCategory(store.page); rows: 0 }
                        EmptyState {
                            visible: !store.loading && !store.inCategory(store.page).length
                            width: parent.width; height: 240
                            symbol: store.loadError ? "wifi" : "apps"
                            title: store.loadError ? "Flathub Unavailable" : "Nothing Here Yet"
                            text: store.loadError || "No apps in this section yet."
                            actionText: store.loadError ? "Try Again" : ""
                            onAction: store.reload(true)
                        }
                    }

                    Column {
                        visible: !store.query.trim() && (store.page === "updates" || store.page === "installed")
                        width: parent.width
                        spacing: 22
                        RowLayout {
                            width: parent.width
                            PageTitle { text: store.page === "updates" ? "Updates" : "Installed"; Layout.fillWidth: true }
                            Button {
                                visible: store.page === "updates" && store.updates.length > 1
                                text: "Update All"
                                enabled: !store.busy
                                onClicked: { store.queue = store.updates.slice(1); store.transact("update", store.updates[0]) }
                            }
                        }
                        Shelf { width: parent.width; title: ""; apps: store.page === "updates" ? store.updates : store.installed; rows: 0 }
                        EmptyState {
                            visible: !(store.page === "updates" ? store.updates : store.installed).length
                            width: parent.width; height: 240
                            symbol: store.page === "updates" ? "checkmark" : "apps"
                            title: store.page === "updates" ? "You're Up to Date" : "Nothing Installed Yet"
                            text: store.page === "updates" ? "Updates to your apps show up here." : "Apps you get from the App Store show up here."
                        }
                    }

                    EmptyState {
                        visible: store.loading && store.macLoading
                        width: parent.width; height: 220
                        symbol: "arrow-clockwise"; title: "Loading the App Store"; text: "Getting the latest apps…"
                    }
                }
            }
            Scroller { flickable: scroll }

            Flickable {
                id: page
                visible: !!store.detail
                readonly property var app: store.live(store.detail)
                anchors { fill: parent; leftMargin: 36; rightMargin: 32 }
                topMargin: win.toolbarHeight + 18
                bottomMargin: 30
                contentWidth: width
                contentHeight: detailColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onAppChanged: contentY = -topMargin

                Column {
                    id: detailColumn
                    width: page.width
                    spacing: 22
                    RowLayout {
                        width: parent.width
                        spacing: 24
                        AppIcon { app: page.app; size: 128; Layout.alignment: Qt.AlignTop }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: page.app?.name ?? ""
                                wrapMode: Text.WordWrap
                                color: Theme.label
                                font { family: Theme.fontDisplay; pixelSize: 28; weight: Font.Bold }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: page.app?.summary ?? ""
                                wrapMode: Text.WordWrap
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(15) }
                            }
                            Item { Layout.preferredHeight: 8; Layout.preferredWidth: 1 }
                            Row {
                                spacing: 14
                                GetButton { app: page.app; large: true; onPressed: store.act(page.app) }
                                Text {
                                    visible: !!page.app?.installed && !store.busy
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Remove"
                                    color: Theme.accentRed
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                                    TapHandler { onTapped: store.transact("remove", page.app) }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.separator }

                    Row {
                        id: facts
                        width: parent.width
                        readonly property var items: !page.app ? [] : page.app.source === "mac" ? [
                            ["SOURCE", "Developer", "download"],
                            ["VERSION", page.app.version || "—", ""],
                            ["REQUIRES", page.app.minMacOS ? "macOS " + page.app.minMacOS + "+" : "Intel Mac app", "on the Mac"],
                            ["RUNS WITH", "Darling", store.darling ? "ready" : "not set up"],
                            ["ON THIS COMPUTER", page.app.opened === true ? "Opens" : page.app.opened === false ? "Didn't open" : page.app.installed ? "Not opened yet" : "Not tried", ""]
                        ] : [
                            ["SOURCE", "Flathub", "Linux app"],
                            ["CATEGORY", (page.app.categories ?? [])[0] ?? "App", ""],
                            ["STATUS", page.app.update ? "Update" : page.app.installed ? "Installed" : "Not installed", ""]
                        ]
                        Repeater {
                            model: facts.items
                            Item {
                                required property var modelData
                                required property int index
                                width: facts.width / Math.max(1, facts.items.length); height: 64
                                Rectangle { visible: index > 0; width: 1; height: 40; anchors.verticalCenter: parent.verticalCenter; color: Theme.separator }
                                Column {
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                                    spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; color: Theme.tertiaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(10); weight: Font.Bold } }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.DemiBold } }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; visible: !!modelData[2]; text: modelData[2]; color: Theme.tertiaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(10) } }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.separator }

                    Rectangle {
                        visible: page.app?.source === "mac"
                        width: parent.width
                        height: macNote.implicitHeight + 32
                        radius: 14
                        color: page.app?.opened === false ? (Theme.dark ? "#33ff9f0a" : "#1aff9f0a") : (Theme.dark ? "#0fffffff" : "#07000000")
                        Column {
                            id: macNote
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                            spacing: 8
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                                text: page.app?.opened === false ? "This app didn't open under Darling last time." : page.app?.opened === true ? "This app opened under Darling on this computer." : "A Mac app, run with Darling"
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                text: "It's downloaded from " + (page.app?.homepage ? page.app.homepage.replace(/^https?:\/\//, "").replace(/\/.*$/, "") : "its developer") + (page.app?.checksum ? ", checked against its published checksum," : " (its developer doesn't publish a checksum for it),") + " and installed in Applications in your home folder. Darling runs Intel Mac apps; apps built only for Apple silicon are refused before anything is installed."
                            }
                            Text {
                                visible: !!page.app?.lastError
                                width: parent.width
                                wrapMode: Text.WrapAnywhere
                                text: page.app?.lastError ?? ""
                                color: Theme.secondaryLabel
                                font { family: "SF Mono"; pixelSize: Theme.fs(11) }
                            }
                        }
                    }

                    Text {
                        visible: !!page.app?.homepage
                        text: "Developer Website"
                        color: Theme.accent
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        TapHandler { onTapped: Quickshell.execDetached(["xdg-open", page.app.homepage]) }
                    }
                }
            }
            Scroller { flickable: page }

            Rectangle {
                anchors.fill: parent
                visible: store.askDarling
                color: "#40000000"
                z: 30
                MouseArea { anchors.fill: parent; onClicked: store.askDarling = false }
                Glass {
                    anchors.centerIn: parent
                    width: 380; height: sheet.implicitHeight + 40
                    radius: 22
                    tint: Theme.glassRegular.tint
                    MouseArea { anchors.fill: parent }
                    Column {
                        id: sheet
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                        spacing: 10
                        Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: "window"; size: 36; tone: "accent" }
                        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Mac app support isn't set up"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold } }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: "Mac apps open with Darling. Setting it up builds it on this computer, which takes about an hour, in a Terminal window."
                            color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        Item { width: 1; height: 4 }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            Button { width: 150; text: "Not Now"; onClicked: store.askDarling = false }
                            Button { width: 150; text: "Set Up…"; prominent: true; onClicked: store.setUpDarling() }
                        }
                    }
                }
            }

            Glass {
                visible: store.busy || !!store.error
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                width: Math.min(parent.width - 48, 560)
                height: notice.implicitHeight + 24
                radius: 16
                tint: Theme.glassRegular.tint
                z: 20
                ColumnLayout {
                    id: notice
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 12 }
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            Layout.fillWidth: true
                            text: store.error || store.message
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                        }
                        Button { visible: !!store.error && !store.busy; text: "OK"; onClicked: { store.error = ""; store.errorDetails = "" } }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!store.errorDetails
                        text: store.errorDetails
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        color: Theme.secondaryLabel
                        font { family: "SF Mono"; pixelSize: Theme.fs(10) }
                    }
                    ProgressBar { visible: store.busy; Layout.fillWidth: true; value: store.progress; indeterminate: store.progress < 0.05 }
                }
            }

            Glass {
                visible: store.installerSheetVisible
                anchors.centerIn: parent
                width: 430
                height: installerColumn.implicitHeight + 36
                radius: 22
                tint: Theme.glassRegular.tint
                z: 35
                Column {
                    id: installerColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
                    spacing: 12
                    Row {
                        width: parent.width
                        spacing: 14
                        AppIcon { app: store.installerApp; size: 64 }
                        Column {
                            width: parent.width - 78
                            spacing: 3
                            Text {
                                text: store.installerSucceeded ? "Installed" : "Download complete"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(18); weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: store.installerSucceeded ? (store.installerApp?.name ?? "App") + " is ready in Applications." : "We’ve downloaded the package and are unpacking it into your Applications folder."
                                wrapMode: Text.WordWrap
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 106
                        radius: 18
                        color: Theme.dark ? "#14151a" : "#f2f2f5"
                        border { width: 0.5; color: Theme.separator }
                        Row {
                            anchors.centerIn: parent
                            spacing: 22
                            Column {
                                width: 98
                                height: 86
                                spacing: 8
                                Rectangle {
                                    width: 74; height: 74; anchors.horizontalCenter: parent.horizontalCenter; radius: 18
                                    color: Theme.dark ? "#1f2430" : "#eef1f5"
                                    border { width: 1; color: Theme.separator }
                                    AppIcon { app: store.installerApp; anchors.centerIn: parent; size: 52 }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Apps"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                            }
                            Rectangle {
                                width: 52; height: 52; radius: 26; color: Theme.accent; opacity: 0.9
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "→"; color: "#fff"; font { family: Theme.fontUi; pixelSize: Theme.fs(22); weight: Font.Bold } }
                            }
                            Column {
                                width: 98
                                height: 86
                                spacing: 8
                                Rectangle {
                                    width: 74; height: 74; anchors.horizontalCenter: parent.horizontalCenter; radius: 18
                                    color: Theme.dark ? "#1f2430" : "#eef1f5"
                                    border { width: 1; color: Theme.separator }
                                    Symbol { anchors.centerIn: parent; name: "folder"; size: 28; tone: Theme.accent }
                                }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Applications"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: "Drag the app to Applications to finish installation."
                        color: Theme.secondaryLabel
                        horizontalAlignment: Text.AlignHCenter
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Open Folder"; onClicked: { if (store.installerApp) Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/Applications"]) ; store.installerSheetVisible = false } }
                        Button { text: "Done"; prominent: true; onClicked: store.installerSheetVisible = false }
                    }
                }
            }
        }
    }
}
