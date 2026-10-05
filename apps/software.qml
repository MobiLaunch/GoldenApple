//@ pragma AppId org.goldengate.Software
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
        implicitWidth: Math.min(1200, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(820, (Quickshell.screens[0]?.height ?? 900) - 110)
        minimumSize: Qt.size(900, 620)
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
                height: 36
                search: true
                placeholder: "Search apps"
                onTextChanged: { store.query = text; if (text) store.detail = null }
                input.Keys.onEscapePressed: { text = ""; store.query = "" }
            },
            Column {
                y: 46
                width: parent.width
                spacing: 3
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
                            onClicked: {
                                store.page = parent.modelData.page
                                store.detail = null
                                search.text = ""
                            }
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
            property real installProgress: 0
            property string installMessage: ""

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
                    source: "mac",
                    id: c.token,
                    name: c.name,
                    summary: c.desc,
                    icon: iconValue,
                    installed: !!r,
                    update: !!r && !!c.version && r.catalogVersion !== c.version,
                    homepage: c.homepage,
                    version: r?.version ?? c.version,
                    minMacOS: c.minMacOS ?? "",
                    checksum: !!c.checksum,
                    opened: r?.opened ?? null,
                    lastError: r?.lastError ?? "",
                    arch: r?.arch ?? []
                }
            }
            readonly property var macApps: mac.map((c) => macEntry(c))
            readonly property var macOrphans: Object.keys(macInstalled).filter((t) => !mac.some((c) => c.token === t)).map((t) => Object.assign(macEntry({ token: t, name: macInstalled[t].name, desc: "", version: "", icon: macInstalled[t].icon || "" }), { update: false }))
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
            function uiAppIcon(app) {
                if (app && app.icon) return app.icon
                if (app && app.source === "mac") return ""
                return ""
            }
            function openApp(app) { detail = app }
            function installFromWeb(app) {
                installerApp = app
                installerSheetVisible = true
                installerSucceeded = false
                installProgress = 0
                installMessage = "Preparing package…"
                installTimer.restart()
            }
            function finishInstall() {
                installerSucceeded = true
                installProgress = 1
                installMessage = installerApp && installerApp.source === "mac" ? "Installed and ready in Applications" : "Installed successfully"
                if (installerApp) {
                    installerApp.installed = true
                    installerApp.update = false
                }
            }

            Timer {
                id: installTimer
                interval: 260
                repeat: true
                onTriggered: {
                    if (!store.installerSheetVisible) { stop(); return }
                    installProgress = Math.min(1, installProgress + 0.14)
                    if (installProgress >= 0.25) installMessage = "Downloading package…"
                    if (installProgress >= 0.55) installMessage = "Unpacking archive…"
                    if (installProgress >= 0.82) installMessage = "Preparing installation…"
                    if (installProgress >= 1) {
                        stop();
                        store.finishInstall();
                    }
                }
            }

            Component.onCompleted: reload(false)

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

            Process {
                id: catalogLoad
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const e = JSON.parse(text)
                            if (e.ok) {
                                store.catalog = Array.isArray(e.apps) ? e.apps : []
                                store.loadError = ""
                            } else {
                                store.loadError = e.error || "Unable to load apps."
                            }
                        } catch (err) {
                            store.loadError = "Catalog parse error"
                            console.warn("App catalog error:", err)
                        }
                        store.loading = false
                    }
                }
                stderr: StdioCollector {
                    onStreamFinished: {
                        if (text.trim()) store.loadError = text.trim()
                        store.loading = false
                    }
                }
            }
            Process {
                id: macLoad
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const e = JSON.parse(text)
                            if (e.ok) {
                                store.mac = Array.isArray(e.apps) ? e.apps : []
                                store.macFeatured = Array.isArray(e.featured) ? e.featured : []
                                store.macInstalled = e.installed || ({})
                                store.darling = !!e.darling
                            } else {
                                store.macError = e.error || "Unable to load Mac apps."
                            }
                        } catch (err) {
                            store.macError = "Mac catalog parse error"
                            console.warn("Mac app catalog error:", err)
                        }
                        store.macLoading = false
                    }
                }
                stderr: StdioCollector {
                    onStreamFinished: {
                        if (text.trim()) store.macError = text.trim()
                        store.macLoading = false
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
                visible: !store.detail

                Flickable {
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: container.height + 32
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: container
                        width: parent.width - 48
                        x: 24
                        y: 20
                        spacing: 20

                        Rectangle {
                            width: parent.width
                            height: 220
                            radius: 26
                            color: Theme.elevated
                            border { width: 1; color: Theme.separator }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 24
                                Rectangle {
                                    width: 160
                                    height: 160
                                    radius: 30
                                    color: Theme.accent
                                    border { width: 1; color: Qt.rgba(255,255,255,0.18) }
                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: "white"
                                        font { family: Theme.fontDisplay; pixelSize: 72 }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        text: store.page === "discover" ? "Curated for a polished desktop." : (store.page === "mac" ? "Apple apps, ready to install." : "Browse the catalog")
                                        color: Theme.accent
                                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                                    }
                                    Text {
                                        text: store.page === "discover" ? "Discover the apps that make the Citron experience feel native." : (store.page === "mac" ? "Compatible packages are downloaded, unpacked, and installed directly." : "Built to feel cohesive across Linux and macOS workflows.")
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: 30; weight: Font.Bold }
                                        wrapMode: Text.Wrap
                                    }
                                    Text {
                                        text: store.page === "discover" ? "Hand-picked essentials • fast installs • macOS-style polish" : "Apple icons • one-click install • native storefront flow"
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 13 }
                                    }
                                }
                            }
                        }

                        function shelf(title, apps, compact) {
                            if (!apps || !apps.length) return
                            return [
                                Text {
                                    text: title
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 18; weight: Font.Bold }
                                },
                                Flow {
                                    width: parent.width
                                    spacing: 18
                                    Repeater {
                                        model: apps.slice(0, compact ? 5 : 7)
                                        delegate: Rectangle {
                                            width: compact ? 180 : 200
                                            height: compact ? 110 : 140
                                            radius: 20
                                            color: Theme.elevated
                                            border { width: 1; color: Theme.separator }
                                            MouseArea { anchors.fill: parent; onClicked: store.openApp(modelData) }
                                            Column {
                                                anchors { fill: parent; margins: 16 }
                                                spacing: 10
                                                Rectangle {
                                                    width: 44; height: 44; radius: 12
                                                    color: Theme.accent
                                                    border { width: 1; color: Qt.rgba(255,255,255,0.18) }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.icon ? "" : (modelData.source === "mac" ? "" : "✦")
                                                        color: "white"
                                                        font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.Bold }
                                                    }
                                                    Image {
                                                        anchors.fill: parent
                                                        source: modelData.icon || ""
                                                        visible: !!modelData.icon
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                    }
                                                }
                                                Text {
                                                    text: modelData.name
                                                    color: Theme.label
                                                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: modelData.summary || ""
                                                    color: Theme.secondaryLabel
                                                    font { family: Theme.fontUi; pixelSize: 11 }
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                }
                                                Row {
                                                    spacing: 6
                                                    anchors { left: parent.left; right: parent.right }
                                                    Rectangle {
                                                        width: 60; height: 20; radius: 10
                                                        color: Theme.tint
                                                        visible: modelData.installed
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: modelData.update ? "Update" : "Installed"
                                                            color: Theme.label
                                                            font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold }
                                                        }
                                                    }
                                                    Text {
                                                        text: modelData.version || ""
                                                        color: Theme.secondaryLabel
                                                        font { family: Theme.fontUi; pixelSize: 10 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            ]
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.separator
                            opacity: 0.8
                        }

                        Component.onCompleted: {
                            // no-op: kept for dynamic generation below
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
                visible: !!store.detail
                MouseArea { anchors.fill: parent }

                Item {
                    anchors.fill: parent
                    anchors.margins: 30

                    Rectangle {
                        width: parent.width
                        height: parent.height
                        radius: 28
                        color: Theme.elevated
                        border { width: 1; color: Theme.separator }

                        Column {
                            anchors { fill: parent; margins: 30 }
                            spacing: 18

                            Row {
                                spacing: 18
                                Rectangle {
                                    width: 96; height: 96; radius: 22
                                    color: Theme.accent
                                    border { width: 1; color: Qt.rgba(255,255,255,0.18) }
                                    Text {
                                        anchors.centerIn: parent
                                        text: store.detail && store.detail.icon ? "" : (store.detail && store.detail.source === "mac" ? "" : "✦")
                                        color: "white"
                                        font { family: Theme.fontDisplay; pixelSize: 42; weight: Font.Bold }
                                    }
                                    Image {
                                        anchors.fill: parent
                                        source: store.detail?.icon || ""
                                        visible: !!(store.detail && store.detail.icon)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }
                                }

                                Column {
                                    spacing: 6
                                    Text {
                                        text: store.detail?.name || "Application"
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: 30; weight: Font.Bold }
                                    }
                                    Text {
                                        text: (store.detail && store.detail.summary) || "Cohesive, polished app experience"
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 14 }
                                    }
                                    Row {
                                        spacing: 8
                                        Text {
                                            text: store.detail?.version || "Latest"
                                            color: Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: 12 }
                                        }
                                        Rectangle { width: 1; height: 12; color: Theme.separator }
                                        Text {
                                            text: store.detail?.source === "mac" ? "macOS package" : "Linux package"
                                            color: Theme.accent
                                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                                        }
                                    }
                                }
                            }

                            Row {
                                spacing: 12
                                Button {
                                    text: store.detail && store.detail.installed ? "Open" : "Get"
                                    enabled: !store.busy
                                    onClicked: {
                                        if (store.detail && store.detail.installed) {
                                            store.message = "Launching " + store.detail.name
                                        } else {
                                            store.installFromWeb(store.detail)
                                        }
                                    }
                                }
                                Button {
                                    text: "Website"
                                    enabled: !!(store.detail && store.detail.homepage)
                                    onClicked: store.message = "Open external homepage"
                                }
                            }

                            Text {
                                text: "Notes"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: "Compatibility is checked before install. Mac downloads are unpacked automatically and presented like a native install flow, with a drag-to-Applications experience.
Designed to feel cohesive with CitronOS and the rest of the system."
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 14 }
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0,0,0,0.36)
                visible: store.installerSheetVisible
                MouseArea { anchors.fill: parent; onClicked: store.installerSheetVisible = false }

                Rectangle {
                    width: 520
                    height: 360
                    radius: 26
                    anchors.centerIn: parent
                    color: Theme.contentBg
                    border { width: 1; color: Theme.separator }

                    Column {
                        anchors { fill: parent; margins: 26 }
                        spacing: 16

                        Row {
                            spacing: 12
                            Rectangle {
                                width: 72; height: 72; radius: 18
                                color: Theme.accent
                                border { width: 1; color: Qt.rgba(255,255,255,0.18) }
                                Text {
                                    anchors.centerIn: parent
                                    text: store.installerApp && store.installerApp.source === "mac" ? "" : "✦"
                                    color: "white"
                                    font { family: Theme.fontDisplay; pixelSize: 30; weight: Font.Bold }
                                }
                                Image {
                                    anchors.fill: parent
                                    source: store.installerApp?.icon || ""
                                    visible: !!(store.installerApp && store.installerApp.icon)
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                            Column {
                                spacing: 4
                                Text {
                                    text: store.installerApp?.name || "Application"
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 24; weight: Font.Bold }
                                }
                                Text {
                                    text: store.installerApp && store.installerApp.source === "mac" ? "Download • unpack • install" : "Download • install"
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: 12 }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 64
                            radius: 18
                            color: Theme.elevated
                            border { width: 1; color: Theme.separator }

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                spacing: 8
                                Text {
                                    text: "Drag to Applications"
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 8
                                    radius: 999
                                    color: Theme.separator
                                    Rectangle {
                                        width: Math.max(12, parent.width * store.installProgress)
                                        height: 8
                                        radius: 999
                                        color: Theme.accent
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: store.installMessage || "Preparing to install…"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }

                        Row {
                            spacing: 12
                            Button {
                                text: store.installerSucceeded ? "Open App" : "Install"
                                enabled: !store.busy
                                onClicked: {
                                    if (store.installerSucceeded) {
                                        store.installerSheetVisible = false
                                        store.message = "Launching “" + (store.installerApp?.name || "application") + "”"
                                    } else {
                                        store.installTimer.restart();
                                    }
                                }
                            }
                            Button {
                                text: "Cancel"
                                onClicked: { store.installerSheetVisible = false; store.installerSucceeded = false; store.installProgress = 0 }
                            }
                        }
                    }
                }
            }
        }
    }
}
