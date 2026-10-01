//@ pragma AppId org.goldengate.Software
// Golden Gate App Store: native QML storefront backed directly by Flatpak/Flathub.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "App Store"
        implicitWidth: Math.min(1120, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(760, (Quickshell.screens[0]?.height ?? 900) - 120)
        minimumSize: Qt.size(820, 540)
        sidebarWidth: 220
        background: Theme.contentBg

        toolbarItems: [
            Row {
                x: win.contentX + 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: store.pageTitle
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
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
                onTextChanged: store.query = text
                input.Keys.onEscapePressed: { text = ""; store.query = "" }
            },
            Flickable {
                y: 42
                width: parent.width
                height: parent.height - 42
                contentHeight: nav.height + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: nav
                    width: parent.width
                    spacing: 2

                    SidebarRow {
                        width: parent.width
                        text: "Discover"
                        symbol: "sparkles"
                        selected: store.page === "discover"
                        onClicked: store.page = "discover"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Productivity"
                        symbol: "briefcase"
                        selected: store.page === "productivity"
                        onClicked: store.page = "productivity"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Developer"
                        symbol: "code"
                        selected: store.page === "developer"
                        onClicked: store.page = "developer"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Graphics & Design"
                        symbol: "photo"
                        selected: store.page === "graphics"
                        onClicked: store.page = "graphics"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Music & Video"
                        symbol: "music"
                        selected: store.page === "media"
                        onClicked: store.page = "media"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Games"
                        symbol: "game"
                        selected: store.page === "games"
                        onClicked: store.page = "games"
                    }

                    Item { width: 1; height: 10 }

                    SidebarRow {
                        width: parent.width
                        text: "Updates"
                        symbol: "download"
                        selected: store.page === "updates"
                        badge: store.updateCount > 0 ? String(store.updateCount) : ""
                        onClicked: store.page = "updates"
                    }
                    SidebarRow {
                        width: parent.width
                        text: "Installed"
                        symbol: "checkmark"
                        selected: store.page === "installed"
                        onClicked: store.page = "installed"
                    }

                    Item { width: 1; height: 12 }

                    Text {
                        width: parent.width - 20
                        x: 10
                        visible: !!store.warning
                        text: store.warning
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                }
            }
        ]

        Item {
            id: store
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("software/helper.py").toString().replace("file://", "")
            property var catalog: []
            property string page: "discover"
            property string query: ""
            property bool loading: true
            property string loadError: ""
            property string warning: ""
            property bool busy: false
            property string activeId: ""
            property string activeAction: ""
            property real operationProgress: 0
            property string operationMessage: ""
            property string operationError: ""

            readonly property int updateCount: catalog.filter((a) => a.update).length
            readonly property string pageTitle: query.trim()
                ? "Search"
                : page === "discover" ? "Discover"
                : page === "productivity" ? "Productivity"
                : page === "developer" ? "Developer"
                : page === "graphics" ? "Graphics & Design"
                : page === "media" ? "Music & Video"
                : page === "games" ? "Games"
                : page === "updates" ? "Updates"
                : "Installed"

            function containsCategory(app, names) {
                const cats = (app.categories ?? []).map((x) => String(x).toLowerCase())
                return names.some((n) => cats.some((c) => c.includes(n)))
            }

            function pageMatches(app) {
                if (query.trim()) {
                    const q = query.trim().toLowerCase()
                    const hay = [
                        app.name ?? "", app.summary ?? "", app.id ?? "",
                        ...(app.keywords ?? []), ...(app.categories ?? [])
                    ].join(" ").toLowerCase()
                    return hay.includes(q)
                }

                if (page === "installed") return app.installed
                if (page === "updates") return app.update
                if (page === "productivity")
                    return containsCategory(app, ["office", "productivity", "utility"])
                if (page === "developer")
                    return containsCategory(app, ["development", "developer"])
                if (page === "graphics")
                    return containsCategory(app, ["graphics", "photography"])
                if (page === "media")
                    return containsCategory(app, ["audio", "video", "music"])
                if (page === "games")
                    return containsCategory(app, ["game"])
                return true
            }

            readonly property var shownApps: {
                page
                query
                catalog
                let list = catalog.filter((app) => pageMatches(app))
                if (page === "discover" && !query.trim()) {
                    const installedFirst = list.filter((a) => a.installed).slice(0, 6)
                    const rest = list.filter((a) => !a.installed)
                    list = installedFirst.concat(rest)
                }
                return list.slice(0, 240)
            }

            function patch(id, changes) {
                catalog = catalog.map((app) => {
                    if (app.id !== id)
                        return app
                    const copy = Object.assign({}, app)
                    Object.keys(changes).forEach((key) => copy[key] = changes[key])
                    return copy
                })
            }

            function reload(forceRefresh) {
                if (busy || catalogLoad.running)
                    return
                loading = true
                loadError = ""
                catalogLoad.command = ["python3", helper, forceRefresh ? "refresh" : "catalog"]
                catalogLoad.running = true
            }

            function transact(action, appId) {
                if (busy || !appId)
                    return
                busy = true
                activeId = appId
                activeAction = action
                operationProgress = 0.04
                operationError = ""
                operationMessage = action === "install" ? "Preparing installation…"
                    : action === "update" ? "Preparing update…"
                    : action === "remove" ? "Preparing removal…"
                    : "Opening…"
                transaction.command = ["python3", helper, action, appId]
                transaction.running = true
            }

            function consumeTransaction(line) {
                if (!line || !line.trim())
                    return
                try {
                    const event = JSON.parse(line)
                    if (event.event === "progress") {
                        operationProgress = event.progress ?? operationProgress
                        operationMessage = event.message ?? operationMessage
                    } else if (event.event === "done") {
                        operationProgress = 1
                        if (activeAction === "install")
                            patch(activeId, { installed: true })
                        else if (activeAction === "update")
                            patch(activeId, { update: false, installed: true })
                        else if (activeAction === "remove")
                            patch(activeId, { installed: false, update: false })
                        operationMessage = "Done"
                    } else if (event.event === "error") {
                        operationError = event.message ?? "The App Store operation failed."
                        operationMessage = operationError
                    }
                } catch (e) {}
            }

            Component.onCompleted: reload(false)

            Process {
                id: catalogLoad
                command: ["python3", store.helper, "catalog"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const event = JSON.parse(text)
                            if (event.event === "catalog") {
                                store.catalog = event.apps ?? []
                                store.warning = event.warning ?? ""
                                store.loadError = ""
                            } else if (event.event === "error") {
                                store.loadError = event.message ?? "The App Store catalog could not be loaded."
                            }
                        } catch (e) {
                            store.loadError = "The App Store catalog returned an unreadable response."
                        }
                    }
                }
                onExited: (code) => {
                    store.loading = false
                    if (code !== 0 && !store.loadError)
                        store.loadError = "The App Store could not connect to Flathub. Cached applications will appear when available."
                }
            }

            Process {
                id: transaction
                stdout: SplitParser { onRead: (line) => store.consumeTransaction(line) }
                onExited: (code) => {
                    const action = store.activeAction
                    const id = store.activeId
                    store.busy = false
                    store.activeId = ""
                    store.activeAction = ""
                    if (code === 0 && action !== "launch")
                        Qt.callLater(() => store.reload(false))
                    else if (code !== 0 && !store.operationError)
                        store.operationError = store.operationMessage && store.operationMessage !== "Done"
                            ? store.operationMessage
                            : "The App Store operation did not complete."
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            Flickable {
                id: scroll
                anchors { fill: parent; leftMargin: 24; rightMargin: 14; topMargin: 12; bottomMargin: 12 }
                contentWidth: width
                contentHeight: content.implicitHeight + 32
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: content
                    width: scroll.width
                    spacing: 18

                    Rectangle {
                        visible: store.page === "discover" && !store.query.trim() && !store.loading && !store.loadError
                        width: parent.width
                        height: visible ? 190 : 0
                        radius: 24
                        clip: true

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Theme.dark ? "#244c8f" : "#75aaf5" }
                            GradientStop { position: 1; color: Theme.dark ? "#6d3f7f" : "#d48ad2" }
                        }

                        Column {
                            anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                            width: parent.width * 0.58
                            spacing: 7

                            Text {
                                text: "DISCOVER"
                                color: "#d9ffffff"
                                font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold; letterSpacing: 1.2 }
                            }
                            Text {
                                text: "Apps that feel at home on Golden Gate."
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: 28; weight: Font.Bold }
                            }
                            Text {
                                text: "Open-source software from Flathub, installed into your account."
                                width: parent.width
                                wrapMode: Text.WordWrap
                                color: "#e8ffffff"
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }
                        }

                        Symbol {
                            anchors { right: parent.right; rightMargin: 44; verticalCenter: parent.verticalCenter }
                            name: "apps"
                            size: 88
                            tone: "white"
                            opacity: 0.86
                        }
                    }

                    Text {
                        visible: !store.loading && !store.loadError
                        text: store.query.trim() ? "Results"
                            : store.page === "discover" ? "Apps"
                            : store.pageTitle
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 21; weight: Font.Bold }
                    }

                    EmptyState {
                        visible: store.loading
                        width: parent.width
                        height: 260
                        symbol: "arrow-clockwise"
                        title: "Loading the App Store"
                        text: "Refreshing Flathub metadata and your installed applications."
                    }

                    ProgressBar {
                        visible: store.loading
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 260
                        indeterminate: true
                    }

                    EmptyState {
                        visible: !!store.loadError && !store.loading
                        width: parent.width
                        height: 300
                        symbol: "wifi"
                        title: "App Store Unavailable"
                        text: store.loadError
                    }

                    Button {
                        visible: !!store.loadError && !store.loading
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Try Again"
                        prominent: true
                        onClicked: store.reload(true)
                    }

                    GridView {
                        id: grid
                        visible: !store.loading && !store.loadError
                        width: parent.width
                        height: visible ? Math.ceil(store.shownApps.length / Math.max(1, Math.floor(width / 330))) * 116 : 0
                        interactive: false
                        clip: false
                        cellWidth: Math.max(300, width / Math.max(1, Math.floor(width / 330)))
                        cellHeight: 116
                        model: store.shownApps

                        delegate: Item {
                            id: card
                            required property var modelData
                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors { fill: parent; margins: 5 }
                                radius: 16
                                color: cardHover.hovered
                                    ? (Theme.dark ? "#14ffffff" : "#09000000")
                                    : (Theme.dark ? "#0bffffff" : "#05000000")
                                border { width: 0.5; color: Theme.separator }
                                Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 100 } }

                                Image {
                                    id: appIcon
                                    x: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 66
                                    height: 66
                                    source: card.modelData.icon
                                        ? "file://" + card.modelData.icon
                                        : Quickshell.iconPath(card.modelData.id, "application-x-executable")
                                    sourceSize: Qt.size(132, 132)
                                    smooth: true
                                    mipmap: true
                                }

                                Column {
                                    x: 94
                                    y: 17
                                    width: parent.width - x - 100
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        text: card.modelData.name
                                        elide: Text.ElideRight
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                                    }

                                    Text {
                                        width: parent.width
                                        text: card.modelData.summary || card.modelData.id
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        wrapMode: Text.Wrap
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 11 }
                                    }

                                    Text {
                                        visible: card.modelData.update
                                        text: "Update available"
                                        color: Theme.accent
                                        font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold }
                                    }
                                }

                                Button {
                                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                    width: 72
                                    enabled: !store.busy || store.activeId === card.modelData.id
                                    text: card.modelData.update ? "Update"
                                        : card.modelData.installed ? "Open"
                                        : "Get"
                                    prominent: !card.modelData.installed || card.modelData.update
                                    onClicked: {
                                        if (card.modelData.update)
                                            store.transact("update", card.modelData.id)
                                        else if (card.modelData.installed)
                                            store.transact("launch", card.modelData.id)
                                        else
                                            store.transact("install", card.modelData.id)
                                    }
                                }
                            }

                            HoverHandler { id: cardHover }
                        }
                    }

                    EmptyState {
                        visible: !store.loading && !store.loadError && store.shownApps.length === 0
                        width: parent.width
                        height: 260
                        symbol: "magnifyingglass"
                        title: store.query.trim() ? "No Results" : "Nothing Here Yet"
                        text: store.query.trim()
                            ? "No Flathub applications match “" + store.query.trim() + "”."
                            : "There are no applications in this section."
                    }
                }
            }

            Glass {
                visible: store.busy || !!store.operationError
                anchors {
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: 24; rightMargin: 24; bottomMargin: 18
                }
                height: 64
                radius: 18
                tint: Theme.glassRegular.tint
                z: 20

                Column {
                    anchors { left: parent.left; right: parent.right; leftMargin: 18; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    spacing: 7

                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - progressText.width - closeError.width
                            text: store.operationError || store.operationMessage
                            elide: Text.ElideRight
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                        }
                        Text {
                            id: progressText
                            visible: store.busy
                            text: Math.round(store.operationProgress * 100) + "%"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11 }
                        }
                        Button {
                            id: closeError
                            visible: !!store.operationError && !store.busy
                            text: "Dismiss"
                            onClicked: store.operationError = ""
                        }
                    }

                    ProgressBar {
                        visible: store.busy
                        width: parent.width
                        value: store.operationProgress
                        indeterminate: store.operationProgress < 0.1
                    }
                }
            }
        }
    }
}
