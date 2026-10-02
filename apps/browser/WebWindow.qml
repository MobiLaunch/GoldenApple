import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtWebEngine
import "../lib"
import "../lib/theme"

Window {
    id: root
    width: 1180
    height: 780
    minimumWidth: 720
    minimumHeight: 500
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: currentView && currentView.title ? currentView.title + " — Web" : "Web"

    property int currentIndex: -1
    property var views: []
    property var suggestions: []
    property var downloads: []
    property var pendingPermission: null
    property bool sidebarOpen: width >= 980
    property bool pageMenuOpen: false
    property bool downloadsOpen: false
    property bool readerOpen: false
    property bool tabOverview: false
    property string toastText: ""
    property var startData: ({ favorites: [], frequent: [], readingList: [], recentlyClosed: [], private: false })

    readonly property var currentView: currentIndex >= 0 && currentIndex < views.length ? views[currentIndex] : null
    readonly property bool currentStartPage: !currentView || isStartUrl(String(currentView.url))
    readonly property bool currentLoading: currentView ? currentView.loading : false

    function isStartUrl(url) {
        return !url || url === "about:blank" || url === "about:blank#start"
    }

    function tabSnapshot() {
        const out = []
        for (let i = 0; i < tabsModel.count; i++)
            out.push({ title: tabsModel.get(i).title, url: tabsModel.get(i).url })
        return JSON.stringify(out)
    }

    function urlsSnapshot() {
        const out = []
        for (let i = 0; i < tabsModel.count; i++)
            out.push(tabsModel.get(i).url || "about:blank")
        return JSON.stringify(out)
    }

    function refreshStartPage() {
        try { startData = JSON.parse(backend.startPageJson()) } catch (_) {}
    }

    function refreshSuggestions() {
        if (!addressInput.activeFocus) {
            suggestions = []
            return
        }
        try {
            suggestions = JSON.parse(backend.suggestions(addressInput.text, tabSnapshot()))
        } catch (_) { suggestions = [] }
    }

    function syncAddress() {
        if (!currentView || addressInput.activeFocus) return
        addressInput.text = backend.displayAddress(String(currentView.url))
    }

    function openUrl(url) {
        if (!currentView) return
        currentView.url = url
        currentView.visible = true
    }

    function navigateAddress() {
        const url = backend.resolveAddress(addressInput.text)
        if (!url) return
        suggestions = []
        addressInput.focus = false
        openUrl(url)
    }

    function addTab(url, activate) {
        const target = url || "about:blank"
        const view = viewComponent.createObject(pageHost, {
            "tabIndex": views.length,
            "profile": webProfile,
            "url": target
        })
        if (!view) return null
        views = views.concat([view])
        tabsModel.append({ title: "Start Page", url: target, iconUrl: "", loading: false })
        if (activate === undefined || activate)
            selectTab(views.length - 1)
        saveTabsTimer.restart()
        return view
    }

    function selectTab(index) {
        if (index < 0 || index >= views.length) return
        currentIndex = index
        for (let i = 0; i < views.length; i++)
            views[i].visible = i === currentIndex && !isStartUrl(String(views[i].url))
        syncAddress()
        pageMenuOpen = false
        downloadsOpen = false
    }

    function closeTab(index) {
        if (index < 0 || index >= views.length) return
        const view = views[index]
        backend.rememberClosedTab(String(view.url), view.title || backend.displayAddress(String(view.url)))
        view.stop()
        view.destroy()
        let next = views.slice()
        next.splice(index, 1)
        views = next
        tabsModel.remove(index)
        for (let i = 0; i < views.length; i++)
            views[i].tabIndex = i
        if (!views.length) {
            currentIndex = -1
            addTab("about:blank", true)
            return
        }
        selectTab(Math.min(index, views.length - 1))
        refreshStartPage()
        saveTabsTimer.restart()
    }

    function reopenClosed() {
        let records = []
        try { records = JSON.parse(backend.collectionJson("closedTabs")) } catch (_) {}
        if (records.length) addTab(records[0].url, true)
    }

    function showToast(message) {
        toastText = message
        toast.opacity = 1
        toastTimer.restart()
    }

    function enterReader() {
        if (!currentView || currentStartPage) return
        const script = `(() => {
            const candidate = document.querySelector('article') || document.querySelector('main') || document.body;
            const title = (document.querySelector('h1')?.innerText || document.title || '').trim();
            const text = (candidate?.innerText || '').replace(/\\n{3,}/g, '\\n\\n').trim();
            return { title, text: text.slice(0, 80000) };
        })()`
        currentView.runJavaScript(script, result => {
            if (!result || !result.text || result.text.length < 120) {
                showToast("Reader isn't available for this page.")
                return
            }
            reader.articleTitle = result.title || currentView.title
            reader.articleText = result.text
            readerOpen = true
            pageMenuOpen = false
        })
    }

    Binding { target: Theme; property: "dark"; value: backend.dark }

    WebEngineProfile {
        id: webProfile
        offTheRecord: backend.privateMode
        storageName: backend.privateMode ? "" : "GoldenGate"
        persistentStoragePath: backend.dataDir + "/profile"
        cachePath: backend.cacheDir + "/web"
        downloadPath: backend.downloadDir
        spellCheckEnabled: true

        onDownloadRequested: download => {
            download.downloadDirectory = backend.downloadDir
            downloads = downloads.concat([download])
            downloadsOpen = true
            download.accept()
        }
    }

    ListModel { id: tabsModel }

    Timer {
        id: saveTabsTimer
        interval: 300
        onTriggered: backend.saveTabs(root.urlsSnapshot())
    }

    Component {
        id: viewComponent
        WebEngineView {
            id: webView
            property int tabIndex: -1
            anchors.fill: parent
            visible: false
            focus: visible
            backgroundColor: Theme.dark ? "#1a1a1e" : "#ffffff"

            settings.fullScreenSupportEnabled: true
            settings.scrollAnimatorEnabled: true

            onTitleChanged: {
                if (tabIndex >= 0 && tabIndex < tabsModel.count)
                    tabsModel.setProperty(tabIndex, "title", title || backend.displayAddress(String(url)) || "Start Page")
            }
            onUrlChanged: {
                if (tabIndex >= 0 && tabIndex < tabsModel.count) {
                    tabsModel.setProperty(tabIndex, "url", String(url))
                    tabsModel.setProperty(tabIndex, "title", title || backend.displayAddress(String(url)) || "Start Page")
                }
                if (tabIndex === root.currentIndex) root.syncAddress()
                saveTabsTimer.restart()
            }
            onIconChanged: {
                if (tabIndex >= 0 && tabIndex < tabsModel.count)
                    tabsModel.setProperty(tabIndex, "iconUrl", String(icon))
            }
            onLoadingChanged: info => {
                if (tabIndex >= 0 && tabIndex < tabsModel.count)
                    tabsModel.setProperty(tabIndex, "loading", loading)
                if (!loading && info.status === WebEngineLoadingInfo.LoadSucceededStatus) {
                    backend.visit(String(url), title || backend.displayAddress(String(url)))
                    root.refreshStartPage()
                }
            }
            onNewWindowRequested: request => {
                const destination = root.addTab("about:blank", true)
                if (destination) destination.acceptAsNewWindow(request)
            }
            onPermissionRequested: permission => {
                root.pendingPermission = permission
            }
            onFullScreenRequested: request => {
                request.accept()
                if (request.toggleOn) {
                    toolbar.visible = false
                    tabStrip.visible = false
                    sidebarContainer.visible = false
                    root.showFullScreen()
                } else {
                    toolbar.visible = true
                    tabStrip.visible = true
                    sidebarContainer.visible = root.sidebarOpen
                    root.showNormal()
                }
            }
            onRenderProcessTerminated: (status, exitCode) => {
                if (tabIndex === root.currentIndex)
                    root.showToast("This tab stopped unexpectedly. Reload to continue.")
            }
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: root.visibility === Window.Maximized || root.visibility === Window.FullScreen ? 0 : 14
        clip: true
        color: Theme.dark ? "#202024" : "#f5f5f7"
        border { width: root.visibility === Window.Maximized || root.visibility === Window.FullScreen ? 0 : 0.5; color: Theme.dark ? "#4affffff" : "#30000000" }

        Rectangle {
            id: toolbar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 58
            color: backend.privateMode
                ? (Theme.dark ? "#2b2632" : "#eee8f2")
                : (Theme.dark ? "#2b2b30" : "#ececf0")

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onPressed: mouse => {
                    if (mouse.y < toolbar.height && root.visibility !== Window.FullScreen)
                        root.startSystemMove()
                }
                onDoubleClicked: root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }

            Row {
                id: trafficLights
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                Repeater {
                    model: [
                        { color: "#ff5f57", action: () => root.close() },
                        { color: "#febc2e", action: () => root.showMinimized() },
                        { color: "#28c840", action: () => root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized() }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 13; height: 13; radius: 6.5
                        color: modelData.color
                        border { width: 0.5; color: "#28000000" }
                        MouseArea { anchors.fill: parent; onClicked: modelData.action() }
                    }
                }
            }

            Row {
                anchors { left: trafficLights.right; leftMargin: 20; verticalCenter: parent.verticalCenter }
                spacing: 4
                BrowserButton { symbol: "sidebar"; tooltip: "Show Sidebar"; selected: root.sidebarOpen; onClicked: root.sidebarOpen = !root.sidebarOpen }
                BrowserButton { symbol: "chevron-left"; tooltip: "Back  ⌘["; enabled: root.currentView ? root.currentView.canGoBack : false; onClicked: root.currentView.goBack() }
                BrowserButton { symbol: "chevron-right"; tooltip: "Forward  ⌘]"; enabled: root.currentView ? root.currentView.canGoForward : false; onClicked: root.currentView.goForward() }
            }

            Glass {
                id: smartField
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
                width: Math.min(590, Math.max(300, root.width * 0.48))
                height: 36
                radius: 11
                tint: backend.privateMode
                    ? (Theme.dark ? "#a642364c" : "#d7f0e8f4")
                    : (Theme.dark ? "#8f3b3b40" : "#e8ffffff")
                lens: 5
                shadow: "#24000000"

                BrowserButton {
                    id: pageButton
                    x: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    symbol: backend.privateMode ? "shield" : "info"
                    tooltip: "Page Menu"
                    selected: root.pageMenuOpen
                    onClicked: {
                        root.pageMenuOpen = !root.pageMenuOpen
                        root.downloadsOpen = false
                    }
                }

                TextInput {
                    id: addressInput
                    x: 38
                    width: parent.width - 76
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.label
                    selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                    selectByMouse: true
                    activeFocusOnTab: true
                    clip: true
                    horizontalAlignment: activeFocus ? Text.AlignLeft : Text.AlignHCenter
                    font { family: Theme.fontUi; pixelSize: 13; weight: activeFocus ? Font.Normal : Font.Medium }
                    onActiveFocusChanged: {
                        if (activeFocus && root.currentView) {
                            text = root.currentStartPage ? "" : String(root.currentView.url)
                            selectAll()
                        } else root.syncAddress()
                        root.refreshSuggestions()
                    }
                    onTextChanged: if (activeFocus) root.refreshSuggestions()
                    Keys.onReturnPressed: root.navigateAddress()
                    Keys.onEnterPressed: root.navigateAddress()

                    Text {
                        visible: !addressInput.text && addressInput.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search or enter website name"
                        color: Theme.tertiaryLabel
                        font: addressInput.font
                    }
                }

                BrowserButton {
                    anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30
                    symbol: root.currentLoading ? "xmark" : "arrow-clockwise"
                    tooltip: root.currentLoading ? "Stop" : "Reload  ⌘R"
                    onClicked: {
                        if (!root.currentView) return
                        root.currentLoading ? root.currentView.stop() : root.currentView.reload()
                    }
                }
            }

            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 3
                BrowserButton {
                    symbol: "bookmark"; tooltip: "Add Favorite  ⌘D"
                    onClicked: {
                        if (root.currentView && !root.currentStartPage)
                            backend.addBookmark(String(root.currentView.url), root.currentView.title)
                    }
                }
                BrowserButton {
                    symbol: "download"; tooltip: "Downloads"
                    visible: root.downloads.length > 0
                    selected: root.downloadsOpen
                    onClicked: { root.downloadsOpen = !root.downloadsOpen; root.pageMenuOpen = false }
                }
                BrowserButton { symbol: "plus"; tooltip: "New Tab  ⌘T"; onClicked: root.addTab("about:blank", true) }
            }
        }

        Rectangle {
            id: tabStrip
            anchors { top: toolbar.bottom; left: parent.left; right: parent.right }
            height: 39
            color: Theme.dark ? "#27272c" : "#e7e7eb"
            border { width: 0; color: "transparent" }

            Flickable {
                anchors { fill: parent; leftMargin: root.sidebarOpen ? 260 : 0; rightMargin: 42 }
                contentWidth: tabsRow.width
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: tabsRow
                    height: parent.height
                    spacing: 2

                    Repeater {
                        model: tabsModel
                        delegate: Item {
                            id: tab
                            required property int index
                            required property string title
                            required property string url
                            required property string iconUrl
                            required property bool loading
                            width: Math.max(132, Math.min(228, (tabStrip.width - (root.sidebarOpen ? 300 : 84)) / Math.max(1, tabsModel.count)))
                            height: 36

                            Rectangle {
                                anchors { fill: parent; margins: 3 }
                                radius: 9
                                color: index === root.currentIndex
                                    ? (Theme.dark ? "#45454c" : "#f9f9fb")
                                    : tabArea.containsMouse ? (Theme.dark ? "#18ffffff" : "#0d000000") : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 100 } }
                            }

                            Image {
                                id: favicon
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16
                                visible: iconUrl !== "" && !loading
                                source: iconUrl
                                sourceSize: Qt.size(32, 32)
                            }
                            Rectangle {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14; height: 14; radius: 7
                                visible: loading
                                color: "transparent"
                                border { width: 1.5; color: Theme.accent }
                                RotationAnimation on rotation {
                                    running: loading
                                    loops: Animation.Infinite
                                    from: 0; to: 360
                                    duration: 850
                                }
                            }
                            Text {
                                x: 36
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 67
                                elide: Text.ElideRight
                                text: title || backend.displayAddress(url) || "Start Page"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 12; weight: index === root.currentIndex ? Font.Medium : Font.Normal }
                            }
                            BrowserButton {
                                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                                width: 25; height: 25
                                symbol: "xmark"; tooltip: "Close Tab"
                                opacity: tabArea.containsMouse || index === root.currentIndex ? 1 : 0
                                onClicked: root.closeTab(index)
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) root.closeTab(index)
                                    else root.selectTab(index)
                                }
                            }
                        }
                    }
                }
            }

            BrowserButton {
                anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                symbol: "apps"; tooltip: "Tab Overview"; selected: root.tabOverview
                onClicked: root.tabOverview = !root.tabOverview
            }
        }

        Item {
            id: contentArea
            anchors { top: tabStrip.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

            Item {
                id: sidebarContainer
                visible: root.sidebarOpen
                width: 260
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.dark ? "#ef26262c" : "#eef1f1f4"
                    border { width: 0; color: "transparent" }

                    Flickable {
                        anchors.fill: parent
                        contentHeight: sideColumn.height + 30
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: sideColumn
                            x: 12; y: 16; width: parent.width - 24
                            spacing: 4

                            Text {
                                text: backend.privateMode ? "Private" : "Web"
                                color: Theme.label
                                leftPadding: 8
                                bottomPadding: 9
                                font { family: Theme.fontDisplay; pixelSize: 19; weight: Font.DemiBold }
                            }

                            component SideItem: Rectangle {
                                id: sideItem
                                property string label
                                property string symbol
                                property string badge
                                signal activated()
                                width: sideColumn.width
                                height: 34
                                radius: 8
                                color: sideArea.pressed ? (Theme.dark ? "#1cffffff" : "#12000000")
                                    : sideArea.containsMouse ? (Theme.dark ? "#12ffffff" : "#0b000000") : "transparent"
                                Symbol { x: 8; anchors.verticalCenter: parent.verticalCenter; name: sideItem.symbol; size: 16; tone: "auto" }
                                Text {
                                    x: 34; anchors.verticalCenter: parent.verticalCenter
                                    text: sideItem.label
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                                }
                                Text {
                                    visible: sideItem.badge !== ""
                                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                                    text: sideItem.badge
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: 11 }
                                }
                                MouseArea { id: sideArea; anchors.fill: parent; hoverEnabled: true; onClicked: sideItem.activated() }
                            }

                            SideItem { label: "Start Page"; symbol: "home"; onActivated: root.openUrl("about:blank") }
                            SideItem { label: "Favorites"; symbol: "bookmark"; badge: String(root.startData.favorites.length); onActivated: library.showCollection("bookmarks", "Favorites") }
                            SideItem { label: "Reading List"; symbol: "notes"; badge: String(root.startData.readingList.length); onActivated: library.showCollection("readingList", "Reading List") }
                            SideItem { label: "History"; symbol: "clock"; onActivated: library.showCollection("history", "History") }

                            Text {
                                text: "TABS"
                                color: Theme.tertiaryLabel
                                topPadding: 18; leftPadding: 8; bottomPadding: 4
                                font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.8 }
                            }

                            Repeater {
                                model: tabsModel
                                delegate: Rectangle {
                                    required property int index
                                    required property string title
                                    required property string url
                                    width: sideColumn.width; height: 34; radius: 8
                                    color: index === root.currentIndex ? (Theme.dark ? "#20ffffff" : "#10000000") : "transparent"
                                    Text {
                                        x: 12; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 34; elide: Text.ElideRight
                                        text: title || backend.displayAddress(url) || "Start Page"
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: 12; weight: index === root.currentIndex ? Font.Medium : Font.Normal }
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: root.selectTab(index) }
                                }
                            }

                            SideItem {
                                label: "New Private Window"; symbol: "shield"
                                visible: !backend.privateMode
                                onActivated: backend.openPrivateWindow()
                            }
                        }
                    }
                }
            }

            Item {
                id: pageHost
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: root.sidebarOpen ? sidebarContainer.right : parent.left
                    right: parent.right
                }

                StartPage {
                    id: startPage
                    anchors.fill: parent
                    visible: root.currentStartPage && !root.readerOpen
                    data: root.startData
                    onOpenUrl: url => root.openUrl(url)
                    onAddFavoriteRequested: root.showToast("Open a website, then press ⌘D to add it to Favorites.")
                }

                ReaderOverlay {
                    id: reader
                    anchors.fill: parent
                    visible: root.readerOpen
                    z: 20
                    onClosed: root.readerOpen = false
                }

                Rectangle {
                    id: library
                    anchors.fill: parent
                    visible: false
                    z: 18
                    color: Theme.dark ? "#202024" : "#f7f7f9"
                    property string collectionKey: ""
                    property string heading: ""
                    property var records: []

                    function showCollection(key, title) {
                        collectionKey = key
                        heading = title
                        try { records = JSON.parse(backend.collectionJson(key)) } catch (_) { records = [] }
                        visible = true
                    }

                    Column {
                        anchors { fill: parent; margins: 34 }
                        spacing: 18
                        Row {
                            width: parent.width
                            Text { text: library.heading; color: Theme.label; font { family: Theme.fontDisplay; pixelSize: 26; weight: Font.DemiBold } }
                            Item { width: Math.max(0, parent.width - parent.children[0].width - closeLibrary.width); height: 1 }
                            BrowserButton { id: closeLibrary; symbol: "xmark"; tooltip: "Close"; onClicked: library.visible = false }
                        }
                        Flickable {
                            width: parent.width
                            height: parent.height - 60
                            contentHeight: libraryList.height
                            clip: true
                            Column {
                                id: libraryList
                                width: parent.width
                                spacing: 2
                                Repeater {
                                    model: library.records
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        width: libraryList.width; height: 54; radius: 10
                                        color: libArea.containsMouse ? (Theme.dark ? "#10ffffff" : "#09000000") : "transparent"
                                        Column {
                                            x: 12; anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 54
                                            Text { width: parent.width; text: modelData.title; color: Theme.label; elide: Text.ElideRight; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                                            Text { width: parent.width; text: backend.displayAddress(modelData.url); color: Theme.secondaryLabel; elide: Text.ElideRight; font { family: Theme.fontUi; pixelSize: 11 } }
                                        }
                                        BrowserButton {
                                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                            visible: library.collectionKey !== "history" || true
                                            symbol: "xmark"; tooltip: "Remove"
                                            onClicked: {
                                                backend.removeCollectionItem(library.collectionKey, index)
                                                library.showCollection(library.collectionKey, library.heading)
                                                root.refreshStartPage()
                                            }
                                        }
                                        HoverHandler { id: libArea }
                                        TapHandler {
                                            acceptedButtons: Qt.LeftButton
                                            onDoubleTapped: {
                                                root.openUrl(modelData.url)
                                                library.visible = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: root.tabOverview
                    anchors.fill: parent
                    z: 25
                    color: Theme.dark ? "#ed1d1d22" : "#edf2f2f5"

                    Grid {
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 70, 920)
                        columns: parent.width > 900 ? 3 : 2
                        spacing: 18
                        Repeater {
                            model: tabsModel
                            delegate: Glass {
                                required property int index
                                required property string title
                                required property string url
                                width: 270; height: 160; radius: 20
                                tint: Theme.dark ? "#ad333338" : "#d8ffffff"
                                Text {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                                    text: title || backend.displayAddress(url) || "Start Page"
                                    color: Theme.label; elide: Text.ElideRight
                                    font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                                }
                                MouseArea { anchors.fill: parent; onClicked: { root.selectTab(index); root.tabOverview = false } }
                            }
                        }
                    }
                    BrowserButton {
                        anchors { top: parent.top; right: parent.right; margins: 18 }
                        symbol: "xmark"; tooltip: "Close Tab Overview"
                        onClicked: root.tabOverview = false
                    }
                }
            }
        }

        Rectangle {
            id: loadProgress
            anchors { top: tabStrip.bottom; left: root.sidebarOpen ? parent.left : parent.left; right: parent.right }
            height: 2
            visible: root.currentLoading
            color: "transparent"
            Rectangle {
                height: parent.height
                width: root.currentView ? parent.width * Math.max(0.03, root.currentView.loadProgress / 100) : 0
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 100 } }
            }
        }

        Glass {
            id: suggestionPopover
            visible: addressInput.activeFocus && root.suggestions.length > 0
            z: 50
            x: smartField.x
            y: toolbar.height - 5
            width: smartField.width
            height: Math.min(340, suggestionColumn.height + 14)
            radius: 17
            tint: Theme.dark ? "#f034343a" : "#f2f7f7f9"
            shadow: "#65000000"

            Column {
                id: suggestionColumn
                x: 7; y: 7; width: parent.width - 14
                Repeater {
                    model: root.suggestions
                    delegate: Rectangle {
                        required property var modelData
                        width: suggestionColumn.width
                        height: 43
                        radius: 10
                        color: suggestArea.containsMouse ? Theme.accent : "transparent"

                        Symbol {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            name: modelData.kind === "search" ? "search"
                                : modelData.kind === "tab" ? "rectangle-fill"
                                : modelData.kind === "history" ? "clock"
                                : "bookmark"
                            size: 15
                            tone: suggestArea.containsMouse ? "white" : "gray"
                        }
                        Column {
                            x: 38; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 50
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: modelData.title
                                color: suggestArea.containsMouse ? "#ffffff" : Theme.label
                                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: modelData.subtitle
                                color: suggestArea.containsMouse ? "#cfffffff" : Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 10 }
                            }
                        }
                        MouseArea {
                            id: suggestArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                root.openUrl(modelData.url)
                                addressInput.focus = false
                                root.suggestions = []
                            }
                        }
                    }
                }
            }
        }

        Glass {
            id: pageMenu
            visible: root.pageMenuOpen
            z: 48
            x: smartField.x
            y: toolbar.height - 4
            width: 260
            height: pageMenuColumn.height + 16
            radius: 17
            tint: Theme.dark ? "#f034343a" : "#f2f7f7f9"
            shadow: "#65000000"

            Column {
                id: pageMenuColumn
                x: 8; y: 8; width: parent.width - 16
                spacing: 2

                component MenuItem: Rectangle {
                    id: menuItem
                    property string label
                    property string symbol
                    property string shortcut
                    signal activated()
                    width: pageMenuColumn.width; height: 34; radius: 9
                    color: menuArea.containsMouse ? Theme.accent : "transparent"
                    Symbol { x: 8; anchors.verticalCenter: parent.verticalCenter; name: menuItem.symbol; size: 15; tone: menuArea.containsMouse ? "white" : "auto" }
                    Text { x: 34; anchors.verticalCenter: parent.verticalCenter; text: menuItem.label; color: menuArea.containsMouse ? "#ffffff" : Theme.label; font { family: Theme.fontUi; pixelSize: 12 } }
                    Text { anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }; text: menuItem.shortcut; color: menuArea.containsMouse ? "#cfffffff" : Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
                    MouseArea { id: menuArea; anchors.fill: parent; hoverEnabled: true; onClicked: menuItem.activated() }
                }

                MenuItem { label: "Show Reader"; symbol: "notes"; onActivated: root.enterReader() }
                MenuItem {
                    label: "Add to Reading List"; symbol: "bookmark"
                    onActivated: {
                        if (root.currentView && !root.currentStartPage)
                            backend.addReadingList(String(root.currentView.url), root.currentView.title)
                        root.pageMenuOpen = false
                    }
                }
                MenuItem {
                    label: "Copy Link"; symbol: "square-and-arrow"
                    onActivated: {
                        if (root.currentView) backend.copyText(String(root.currentView.url))
                        root.pageMenuOpen = false
                        root.showToast("Link copied")
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Theme.separator }
                MenuItem {
                    label: "Zoom In"; symbol: "plus"; shortcut: "⌘+"
                    onActivated: if (root.currentView) root.currentView.zoomFactor = Math.min(5, root.currentView.zoomFactor + 0.1)
                }
                MenuItem {
                    label: "Zoom Out"; symbol: "minus"; shortcut: "⌘−"
                    onActivated: if (root.currentView) root.currentView.zoomFactor = Math.max(0.25, root.currentView.zoomFactor - 0.1)
                }
                MenuItem {
                    label: "Actual Size"; symbol: "rectangle-fill"; shortcut: "⌘0"
                    onActivated: if (root.currentView) root.currentView.zoomFactor = 1
                }
            }
        }

        Glass {
            id: downloadPopover
            visible: root.downloadsOpen
            z: 48
            anchors { top: toolbar.bottom; right: parent.right; topMargin: -4; rightMargin: 12 }
            width: 330
            height: Math.min(360, downloadColumn.height + 22)
            radius: 18
            tint: Theme.dark ? "#f034343a" : "#f2f7f7f9"
            shadow: "#65000000"

            Column {
                id: downloadColumn
                x: 11; y: 11; width: parent.width - 22
                spacing: 8
                Row {
                    width: parent.width
                    Text { text: "Downloads"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold } }
                    Item { width: Math.max(0, parent.width - parent.children[0].width - folderButton.width); height: 1 }
                    BrowserButton { id: folderButton; symbol: "folder"; tooltip: "Show Downloads Folder"; onClicked: backend.openDownloadsFolder() }
                }
                Repeater {
                    model: root.downloads
                    delegate: Rectangle {
                        required property var modelData
                        width: downloadColumn.width; height: 58; radius: 10
                        color: Theme.dark ? "#0dffffff" : "#08000000"
                        Column {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 48; spacing: 4
                            Text { width: parent.width; text: modelData.downloadFileName || modelData.suggestedFileName; color: Theme.label; elide: Text.ElideRight; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                            ProgressBar { width: parent.width; height: 5; value: modelData.totalBytes > 0 ? modelData.receivedBytes / modelData.totalBytes : 0; indeterminate: modelData.totalBytes <= 0 && !modelData.isFinished }
                            Text {
                                text: modelData.isFinished ? "Finished"
                                    : modelData.totalBytes > 0 ? Math.round(100 * modelData.receivedBytes / modelData.totalBytes) + "%"
                                    : "Downloading…"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 10 }
                            }
                        }
                        BrowserButton {
                            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            width: 26; height: 26
                            visible: !modelData.isFinished
                            symbol: "xmark"; tooltip: "Cancel Download"
                            onClicked: modelData.cancel()
                        }
                    }
                }
            }
        }

        Glass {
            id: permissionSheet
            visible: root.pendingPermission !== null
            z: 60
            anchors.centerIn: parent
            width: 410; height: permissionColumn.height + 34
            radius: 22
            tint: Theme.dark ? "#f036363c" : "#f6fbfbfd"
            shadow: "#8c000000"

            Column {
                id: permissionColumn
                x: 18; y: 18; width: parent.width - 36
                spacing: 12
                Text { text: "Website Permission"; color: Theme.label; font { family: Theme.fontDisplay; pixelSize: 18; weight: Font.DemiBold } }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: root.pendingPermission ? backend.displayAddress(String(root.pendingPermission.origin)) + " is requesting access to a device or browser capability." : ""
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Button {
                        text: "Don't Allow"
                        onClicked: {
                            root.pendingPermission.deny()
                            root.pendingPermission = null
                        }
                    }
                    Button {
                        text: "Allow"; prominent: true
                        onClicked: {
                            root.pendingPermission.grant()
                            root.pendingPermission = null
                        }
                    }
                }
            }
        }

        Glass {
            id: toast
            z: 70
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 26 }
            width: Math.min(460, toastLabel.implicitWidth + 30)
            height: 34
            radius: 17
            opacity: 0
            tint: Theme.dark ? "#e838383e" : "#eef8f8fa"
            shadow: "#60000000"
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
                id: toastLabel
                anchors.centerIn: parent
                text: root.toastText
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
            }
        }
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.opacity = 0 }
    }

    Connections {
        target: backend
        function onToastRequested(message) { root.showToast(message) }
        function onLibraryChanged() { root.refreshStartPage() }
        function onDarkChanged() { Theme.dark = backend.dark }
    }

    Shortcut { sequence: "Ctrl+L"; onActivated: addressInput.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.addTab("about:blank", true) }
    Shortcut { sequence: "Ctrl+W"; onActivated: root.closeTab(root.currentIndex) }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.reopenClosed() }
    Shortcut { sequence: "Ctrl+R"; onActivated: if (root.currentView) root.currentView.reload() }
    Shortcut { sequence: "Ctrl+D"; onActivated: if (root.currentView && !root.currentStartPage) backend.addBookmark(String(root.currentView.url), root.currentView.title) }
    Shortcut { sequence: "Ctrl+J"; onActivated: if (root.downloads.length) root.downloadsOpen = !root.downloadsOpen }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: backend.openPrivateWindow() }
    Shortcut { sequence: "Alt+Left"; onActivated: if (root.currentView && root.currentView.canGoBack) root.currentView.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (root.currentView && root.currentView.canGoForward) root.currentView.goForward() }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: if (root.views.length) root.selectTab((root.currentIndex + 1) % root.views.length) }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: if (root.views.length) root.selectTab((root.currentIndex - 1 + root.views.length) % root.views.length) }
    Shortcut { sequence: "Ctrl+0"; onActivated: if (root.currentView) root.currentView.zoomFactor = 1 }
    Shortcut { sequence: "Ctrl+="; onActivated: if (root.currentView) root.currentView.zoomFactor = Math.min(5, root.currentView.zoomFactor + 0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: if (root.currentView) root.currentView.zoomFactor = Math.max(0.25, root.currentView.zoomFactor - 0.1) }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.readerOpen) root.readerOpen = false
            else if (root.tabOverview) root.tabOverview = false
            else if (root.pageMenuOpen) root.pageMenuOpen = false
            else if (root.downloadsOpen) root.downloadsOpen = false
            else if (root.currentView && root.currentView.loading) root.currentView.stop()
        }
    }

    Component.onCompleted: {
        root.refreshStartPage()
        let initial = ["about:blank"]
        try { initial = JSON.parse(backend.initialTabsJson) } catch (_) {}
        for (let i = 0; i < initial.length; i++)
            root.addTab(initial[i], false)
        root.selectTab(0)
    }

    onClosing: backend.saveTabs(root.urlsSnapshot())
}
