import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtWebEngine
import "../lib"
import "../lib/theme"

Window {
    id: root
    objectName: "browserWindow"
    width: 1180
    height: 780
    minimumWidth: 720
    minimumHeight: 480
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.dark ? "#1d1d20" : "#f5f5f7"
    title: (BrowserBackend.privateMode ? "Private Browsing" : (currentTitle || "Web")) + " — Web"

    property int currentIndex: 0
    readonly property int tabCount: tabsModel.count
    readonly property var currentDelegate: tabViews.itemAt(currentIndex)
    readonly property var currentView: currentDelegate ? currentDelegate.view : null
    readonly property string currentUrl: currentView ? currentView.url.toString() : (tabsModel.count ? tabsModel.get(currentIndex).url : "about:blank")
    readonly property string currentTitle: currentView ? currentView.title : (tabsModel.count ? tabsModel.get(currentIndex).title : "Start Page")
    property bool sidebarOpen: width >= 900
    property bool pageMenuOpen: false
    property bool downloadsOpen: false
    property bool settingsOpen: false
    property bool readerOpen: false
    property string readerTitle: ""
    property string readerText: ""
    property var downloads: []
    property var pendingPermission: null
    property var startPageData: JSON.parse(BrowserBackend.startPageJson())
    property var browserSettings: JSON.parse(BrowserBackend.settingsJson)
    property var suggestionData: []
    readonly property bool compactTabs: browserSettings.tabLayout === "compact"

    Binding { target: Theme; property: "dark"; value: BrowserBackend.dark }

    function refreshStartPage() {
        startPageData = JSON.parse(BrowserBackend.startPageJson())
    }

    function tabSnapshot() {
        let out = []
        for (let i = 0; i < tabsModel.count; i++) {
            let t = tabsModel.get(i)
            out.push({ title: t.title, url: t.url })
        }
        return out
    }

    function saveTabsSoon() {
        saveTimer.restart()
    }

    function newTab(url, activate) {
        let target = url || "about:blank"
        tabsModel.append({
            url: target,
            title: target === "about:blank" ? "Start Page" : BrowserBackend.displayAddress(target),
            icon: "",
            loading: false,
            progress: 0,
            audible: false,
            muted: false
        })
        let index = tabsModel.count - 1
        if (activate === undefined || activate) {
            currentIndex = index
            Qt.callLater(function() {
                syncAddress()
                if (target === "about:blank") focusAddress()
            })
        }
        saveTabsSoon()
        return index
    }

    function closeTab(index) {
        if (index < 0 || index >= tabsModel.count) return
        let record = tabsModel.get(index)
        BrowserBackend.rememberClosedTab(record.url, record.title)
        if (tabsModel.count === 1) {
            tabsModel.setProperty(0, "url", "about:blank")
            tabsModel.setProperty(0, "title", "Start Page")
            tabsModel.setProperty(0, "icon", "")
            currentIndex = 0
        } else {
            tabsModel.remove(index)
            if (currentIndex >= tabsModel.count) currentIndex = tabsModel.count - 1
            else if (index < currentIndex) currentIndex--
        }
        refreshStartPage()
        saveTabsSoon()
        Qt.callLater(syncAddress)
    }

    function activateUrl(url) {
        for (let i = 0; i < tabsModel.count; i++) {
            if (tabsModel.get(i).url === url) {
                currentIndex = i
                addressInput.focus = false
                syncAddress()
                return
            }
        }
        navigateTo(url)
    }

    function navigateTo(value) {
        let target = value
        if (!target || target === "about:blank") target = "about:blank"
        else if (!String(target).startsWith("http://") && !String(target).startsWith("https://"))
            target = BrowserBackend.resolveAddress(String(target))
        if (!target) return
        pageMenuOpen = false
        suggestionData = []
        if (tabsModel.count === 0) newTab(target, true)
        else tabsModel.setProperty(currentIndex, "url", target)
        addressInput.focus = false
        saveTabsSoon()
    }

    function syncAddress() {
        if (!addressInput.activeFocus)
            addressInput.text = BrowserBackend.displayAddress(currentUrl)
    }

    function focusAddress() {
        addressInput.forceActiveFocus()
        addressInput.text = currentUrl === "about:blank" ? "" : currentUrl
        addressInput.selectAll()
        updateSuggestions()
    }

    function updateSuggestions() {
        if (!addressInput.activeFocus) {
            suggestionData = []
            return
        }
        suggestionData = JSON.parse(BrowserBackend.suggestions(addressInput.text, JSON.stringify(tabSnapshot())))
    }

    function reloadOrStop() {
        if (!currentView) return
        if (currentView.loading) currentView.stop()
        else currentView.reload()
    }

    function reopenLastClosed() {
        let closed = JSON.parse(BrowserBackend.collectionJson("closedTabs"))
        if (closed.length) newTab(closed[0].url, true)
    }

    function enterReader() {
        if (!currentView || currentUrl === "about:blank") return
        currentView.runJavaScript(
            "(function(){const a=document.querySelector('article,main,[role=main]')||document.body;" +
            "return JSON.stringify({title:document.title||'',text:(a.innerText||'').replace(/\\n{3,}/g,'\\n\\n').trim()});})()",
            function(value) {
                try {
                    let article = JSON.parse(value)
                    if (!article.text) {
                        BrowserBackend.notify("Reader couldn't find readable text on this page.")
                        return
                    }
                    readerTitle = article.title
                    readerText = article.text
                    readerOpen = true
                    pageMenuOpen = false
                } catch (_) {
                    BrowserBackend.notify("Reader couldn't open this page.")
                }
            }
        )
    }

    function requestNewWindow(request) {
        if (!request.userInitiated) {
            BrowserBackend.notify("A pop-up was blocked.")
            return
        }
        let background = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab
        let index = newTab("about:blank", !background)
        Qt.callLater(function() {
            let item = tabViews.itemAt(index)
            if (item) request.openIn(item.view)
        })
    }

    function acceptDownload(download) {
        download.downloadDirectory = BrowserBackend.downloadDir
        download.downloadFileName = download.suggestedFileName
        downloads = [download].concat(downloads)
        download.accept()
        downloadsOpen = true
    }

    function setBrowserSetting(key, value) {
        let copy = JSON.parse(JSON.stringify(browserSettings))
        copy[key] = value
        browserSettings = copy
        BrowserBackend.setSetting(key, JSON.stringify(value))
    }

    Timer {
        id: saveTimer
        interval: 350
        repeat: false
        onTriggered: {
            let values = []
            for (let i = 0; i < tabsModel.count; i++) values.push(tabsModel.get(i).url)
            BrowserBackend.saveTabs(JSON.stringify(values))
        }
    }

    ListModel { id: tabsModel }

    WebEngineProfile {
        id: profile
        storageName: BrowserBackend.privateMode ? "" : "GoldenGateWeb"
        offTheRecord: BrowserBackend.privateMode
        persistentStoragePath: BrowserBackend.privateMode ? "" : BrowserBackend.dataDir + "/profile"
        cachePath: BrowserBackend.privateMode ? "" : BrowserBackend.cacheDir + "/web"
        downloadPath: BrowserBackend.downloadDir
        persistentCookiesPolicy: BrowserBackend.privateMode ? WebEngineProfile.NoPersistentCookies : WebEngineProfile.AllowPersistentCookies
        persistentPermissionsPolicy: BrowserBackend.privateMode ? WebEngineProfile.StoreInMemory : WebEngineProfile.StoreOnDisk
        spellCheckEnabled: true
        onDownloadRequested: function(download) { root.acceptDownload(download) }
    }

    Component.onCompleted: {
        let initial = JSON.parse(BrowserBackend.initialTabsJson)
        if (!initial.length) initial = ["about:blank"]
        for (let i = 0; i < initial.length; i++) newTab(initial[i], false)
        currentIndex = 0
        Qt.callLater(syncAddress)
    }

    Connections {
        target: BrowserBackend
        function onDarkChanged() {
            Qt.callLater(root.syncAddress)
        }
        function onLibraryChanged() {
            root.refreshStartPage()
            if (libraryOverlay.visible) libraryOverlay.reload()
        }
        function onToastRequested(message) {
            toastLabel.text = message
            toast.opacity = 1
            toastTimer.restart()
        }
        function onExternalUrls(json) {
            let values = JSON.parse(json)
            for (let i = 0; i < values.length; i++) root.newTab(values[i], true)
            root.showNormal()
            root.raise()
            root.requestActivate()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#1d1d20" : "#f5f5f7"
        border { width: 0.5; color: Theme.dark ? "#45000000" : "#22000000" }
    }

    Rectangle {
        id: toolbar
        z: 20
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 56
        color: BrowserBackend.privateMode
            ? (Theme.dark ? "#e22d2737" : "#f1ece8f4")
            : (Theme.dark ? "#e22b2b2f" : "#f0f1f1f3")
        border { width: 0; color: "transparent" }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: function(mouse) {
                if (mouse.button === Qt.LeftButton) root.startSystemMove()
            }
            onDoubleClicked: root.visibility = root.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 7

            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                Repeater {
                    model: [
                        ["#ff5f57", "Close"],
                        ["#febc2e", "Minimize"],
                        ["#28c840", "Zoom"]
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: 13; height: 13; radius: 6.5
                        color: modelData[0]
                        border { width: 0.5; color: "#33000000" }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData[1] === "Close") root.close()
                                else if (modelData[1] === "Minimize") root.showMinimized()
                                else root.visibility = root.visibility === Window.Maximized ? Window.Windowed : Window.Maximized
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredWidth: 8 }

            BrowserButton {
                symbol: "sidebar"
                tooltip: "Show Sidebar"
                selected: root.sidebarOpen
                onClicked: root.sidebarOpen = !root.sidebarOpen
            }
            BrowserButton {
                symbol: "chevron-left"
                tooltip: "Back  ⌘["
                enabled: root.currentView ? root.currentView.canGoBack : false
                onClicked: root.currentView.goBack()
            }
            BrowserButton {
                symbol: "chevron-right"
                tooltip: "Forward  ⌘]"
                enabled: root.currentView ? root.currentView.canGoForward : false
                onClicked: root.currentView.goForward()
            }

            Item {
                id: smartArea
                Layout.fillWidth: true
                Layout.minimumWidth: 250
                Layout.preferredWidth: root.compactTabs ? 480 : 680
                Layout.maximumWidth: root.compactTabs ? 620 : 760
                height: 40

                Rectangle {
                    id: smartField
                    anchors.centerIn: parent
                    height: 34
                    width: Math.min(parent.width, addressInput.activeFocus ? 720 : 640)
                    radius: 10
                    color: BrowserBackend.privateMode
                        ? (Theme.dark ? "#88443a52" : "#cfe9e2ef")
                        : (Theme.dark ? "#b63b3b40" : "#eaffffff")
                    border {
                        width: addressInput.activeFocus ? 2 : 0.5
                        color: addressInput.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.separator
                    }
                    Behavior on width { NumberAnimation { duration: Theme.reduceMotion ? 1 : 180; easing.type: Easing.OutCubic } }

                    BrowserButton {
                        id: pageButton
                        anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        symbol: BrowserBackend.privateMode ? "shield" : "gear"
                        tooltip: "Page Menu"
                        selected: root.pageMenuOpen
                        onClicked: {
                            root.pageMenuOpen = !root.pageMenuOpen
                            root.downloadsOpen = false
                            root.settingsOpen = false
                        }
                    }

                    TextInput {
                        id: addressInput
                        anchors {
                            left: pageButton.right; leftMargin: 4
                            right: reloadInside.left; rightMargin: 5
                            verticalCenter: parent.verticalCenter
                        }
                        height: 26
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.label
                        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
                        selectedTextColor: Theme.label
                        selectByMouse: true
                        clip: true
                        activeFocusOnTab: true
                        font { family: Theme.fontUi; pixelSize: 13; weight: activeFocus ? Font.Normal : Font.Medium }
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                text = root.currentUrl === "about:blank" ? "" : root.currentUrl
                                selectAll()
                                root.updateSuggestions()
                            } else {
                                root.suggestionData = []
                                root.syncAddress()
                            }
                        }
                        onTextChanged: if (activeFocus) suggestionTimer.restart()
                        onAccepted: root.navigateTo(text)
                        Keys.onEscapePressed: {
                            focus = false
                            root.suggestionData = []
                            root.syncAddress()
                        }

                        Text {
                            visible: !addressInput.text && addressInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search or enter website name"
                            color: Theme.tertiaryLabel
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }
                    }

                    Timer {
                        id: suggestionTimer
                        interval: 55
                        onTriggered: root.updateSuggestions()
                    }

                    BrowserButton {
                        id: reloadInside
                        anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28
                        symbol: root.currentView && root.currentView.loading ? "xmark" : "arrow-clockwise"
                        tooltip: root.currentView && root.currentView.loading ? "Stop" : "Reload  ⌘R"
                        onClicked: root.reloadOrStop()
                    }

                    Rectangle {
                        visible: root.currentView && root.currentView.loading
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 2
                        radius: 1
                        color: "transparent"
                        Rectangle {
                            height: parent.height
                            width: parent.width * ((root.currentView ? root.currentView.loadProgress : 0) / 100)
                            radius: 1
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 90 } }
                        }
                    }
                }
            }

            Flickable {
                visible: root.compactTabs
                Layout.preferredWidth: root.compactTabs ? Math.min(330, Math.max(120, root.width * 0.27)) : 0
                Layout.maximumWidth: 330
                height: 34
                contentWidth: compactTabRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: compactTabRow
                    spacing: 4
                    Repeater {
                        model: tabsModel
                        delegate: Rectangle {
                            required property int index
                            required property string title
                            required property string icon
                            visible: index !== root.currentIndex
                            width: visible ? 112 : 0
                            height: 32
                            radius: 9
                            color: compactArea.containsMouse ? (Theme.dark ? "#12ffffff" : "#0d000000") : "transparent"
                            Row {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                spacing: 6
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 15; height: 15
                                    source: icon
                                    sourceSize: Qt.size(30, 30)
                                    visible: !!icon
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 24
                                    text: title || "New Tab"
                                    elide: Text.ElideRight
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: 12 }
                                }
                            }
                            MouseArea {
                                id: compactArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.MiddleButton) root.closeTab(index)
                                    else { root.currentIndex = index; root.syncAddress() }
                                }
                            }
                        }
                    }
                }
            }

            BrowserButton {
                symbol: "bookmark"
                tooltip: "Add Favorite  ⌘D"
                enabled: root.currentUrl !== "about:blank"
                onClicked: BrowserBackend.addBookmark(root.currentUrl, root.currentTitle)
            }
            BrowserButton {
                symbol: "download"
                tooltip: "Downloads"
                selected: root.downloadsOpen
                onClicked: {
                    root.downloadsOpen = !root.downloadsOpen
                    root.pageMenuOpen = false
                    root.settingsOpen = false
                }
            }
            BrowserButton {
                symbol: "plus"
                tooltip: "New Tab  ⌘T"
                onClicked: root.newTab("about:blank", true)
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 0.5
            color: Theme.separator
        }
    }

    Rectangle {
        id: separateTabs
        z: 15
        visible: !root.compactTabs
        anchors { top: toolbar.bottom; left: parent.left; right: parent.right }
        height: visible ? 39 : 0
        color: Theme.dark ? "#f1242428" : "#f1ededf0"

        Flickable {
            id: tabScroller
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            contentWidth: tabRow.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: tabRow
                height: parent.height
                spacing: 2

                Repeater {
                    model: tabsModel
                    delegate: Item {
                        id: tab
                        required property int index
                        required property string title
                        required property string icon
                        required property bool loading
                        required property bool audible
                        readonly property bool active: index === root.currentIndex
                        width: Math.max(132, Math.min(220, (tabScroller.width - 10) / Math.max(1, Math.min(6, tabsModel.count))))
                        height: 37

                        Rectangle {
                            anchors { fill: parent; topMargin: 3; bottomMargin: 3 }
                            radius: 9
                            color: tab.active
                                ? (Theme.dark ? "#993b3b40" : "#deffffff")
                                : tabHover.hovered ? (Theme.dark ? "#10ffffff" : "#0d000000") : "transparent"
                            border { width: tab.active ? 0.5 : 0; color: Theme.separator }
                        }

                        Row {
                            anchors { fill: parent; leftMargin: 9; rightMargin: 7 }
                            spacing: 7

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18; height: 18
                                Image {
                                    anchors.fill: parent
                                    source: tab.icon
                                    sourceSize: Qt.size(36, 36)
                                    visible: !!tab.icon && !tab.loading
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 5
                                    visible: !tab.icon && !tab.loading
                                    color: Theme.dark ? "#18ffffff" : "#0d000000"
                                    Text {
                                        anchors.centerIn: parent
                                        text: (tab.title || "N").charAt(0).toUpperCase()
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold }
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 12; height: 12
                                    radius: 6
                                    visible: tab.loading
                                    color: "transparent"
                                    border { width: 2; color: Theme.accent }
                                    RotationAnimation on rotation {
                                        running: tab.loading && !Theme.reduceMotion
                                        loops: Animation.Infinite
                                        from: 0; to: 360; duration: 750
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(20, parent.width - 65)
                                text: tab.title || "New Tab"
                                color: Theme.label
                                elide: Text.ElideRight
                                font { family: Theme.fontUi; pixelSize: 12; weight: tab.active ? Font.Medium : Font.Normal }
                            }

                            Symbol {
                                visible: tab.audible && !closeButton.visible
                                anchors.verticalCenter: parent.verticalCenter
                                name: "speaker"
                                size: 12
                                tone: "gray"
                            }

                            BrowserButton {
                                id: closeButton
                                visible: tab.active || tabHover.hovered
                                anchors.verticalCenter: parent.verticalCenter
                                width: 23; height: 23
                                symbol: "xmark"
                                tooltip: "Close Tab  ⌘W"
                                onClicked: root.closeTab(tab.index)
                            }
                        }
                        HoverHandler { id: tabHover }
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: {
                                root.currentIndex = tab.index
                                root.syncAddress()
                            }
                        }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: root.closeTab(tab.index)
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 0.5
            color: Theme.separator
        }
    }

    Item {
        id: body
        anchors {
            top: root.compactTabs ? toolbar.bottom : separateTabs.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        Rectangle {
            id: sidebar
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: root.sidebarOpen ? 252 : 0
            visible: width > 0
            clip: true
            color: BrowserBackend.privateMode
                ? (Theme.dark ? "#ee2b2732" : "#f5ece8f2")
                : (Theme.dark ? "#f128282c" : "#f4ececf0")
            border { width: 0; color: "transparent" }
            Behavior on width { NumberAnimation { duration: Theme.reduceMotion ? 1 : 200; easing.type: Easing.OutCubic } }

            Flickable {
                anchors { fill: parent; margins: 10 }
                contentHeight: sideColumn.height + 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: sideColumn
                    width: parent.width
                    spacing: 4

                    Text {
                        text: BrowserBackend.privateMode ? "Private Browsing" : "Web"
                        color: Theme.label
                        leftPadding: 8
                        topPadding: 8
                        bottomPadding: 10
                        font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold; letterSpacing: -0.3 }
                    }

                    component SideRow: Rectangle {
                        id: row
                        property string symbol
                        property string label
                        property string detail
                        property bool selected: false
                        signal activated()
                        width: sideColumn.width
                        height: 34
                        radius: 8
                        color: selected ? (Theme.dark ? "#22ffffff" : "#14000000")
                            : sideArea.containsMouse ? (Theme.dark ? "#12ffffff" : "#09000000") : "transparent"
                        Row {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 9
                            Symbol { anchors.verticalCenter: parent.verticalCenter; name: row.symbol; size: 15; tone: row.selected ? "accent" : "auto" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 58
                                text: row.label
                                color: Theme.label
                                elide: Text.ElideRight
                                font { family: Theme.fontUi; pixelSize: 13; weight: row.selected ? Font.Medium : Font.Normal }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.detail
                                visible: !!row.detail
                                color: Theme.tertiaryLabel
                                font { family: Theme.fontUi; pixelSize: 11 }
                            }
                        }
                        MouseArea { id: sideArea; anchors.fill: parent; hoverEnabled: true; onClicked: row.activated() }
                    }

                    SideRow {
                        symbol: "apps"
                        label: "Start Page"
                        selected: root.currentUrl === "about:blank" && !libraryOverlay.visible
                        onActivated: { libraryOverlay.mode = ""; root.navigateTo("about:blank") }
                    }
                    SideRow {
                        symbol: "bookmark"
                        label: "Favorites"
                        onActivated: libraryOverlay.showCollection("bookmarks", "Favorites")
                    }
                    SideRow {
                        symbol: "clock"
                        label: "History"
                        onActivated: libraryOverlay.showCollection("history", "History")
                    }
                    SideRow {
                        symbol: "notes"
                        label: "Reading List"
                        onActivated: libraryOverlay.showCollection("readingList", "Reading List")
                    }
                    SideRow {
                        visible: !BrowserBackend.privateMode
                        symbol: "shield"
                        label: "New Private Window"
                        onActivated: BrowserBackend.openPrivateWindow()
                    }

                    Text {
                        text: "TABS"
                        color: Theme.tertiaryLabel
                        leftPadding: 8
                        topPadding: 18
                        bottomPadding: 4
                        font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.8 }
                    }

                    Repeater {
                        model: tabsModel
                        delegate: SideRow {
                            required property int index
                            required property string title
                            required property string url
                            detail: ""
                            symbol: url === "about:blank" ? "plus" : "globe"
                            label: title || BrowserBackend.displayAddress(url) || "New Tab"
                            selected: index === root.currentIndex && !libraryOverlay.visible
                            onActivated: {
                                libraryOverlay.mode = ""
                                root.currentIndex = index
                                root.syncAddress()
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: 0.5
                color: Theme.separator
            }
        }

        Item {
            id: webArea
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: sidebar.right
                right: parent.right
            }

            Repeater {
                id: tabViews
                model: tabsModel
                delegate: Item {
                    id: webTab
                    required property int index
                    required property string url
                    property alias view: web
                    anchors.fill: parent
                    visible: index === root.currentIndex

                    WebEngineView {
                        id: web
                        anchors.fill: parent
                        profile: profile
                        visible: webTab.visible && webTab.url !== "about:blank" && !root.readerOpen
                        url: webTab.url
                        backgroundColor: Theme.dark ? "#1d1d20" : "#ffffff"
                        settings.fullScreenSupportEnabled: true
                        settings.scrollAnimatorEnabled: true
                        lifecycleState: visible ? WebEngineView.LifecycleState.Active : recommendedState

                        onTitleChanged: {
                            tabsModel.setProperty(webTab.index, "title", title || BrowserBackend.displayAddress(url.toString()) || "New Tab")
                            if (webTab.index === root.currentIndex) root.syncAddress()
                        }
                        onIconChanged: tabsModel.setProperty(webTab.index, "icon", icon.toString())
                        onUrlChanged: {
                            let value = url.toString()
                            tabsModel.setProperty(webTab.index, "url", value)
                            if (webTab.index === root.currentIndex) root.syncAddress()
                            root.saveTabsSoon()
                        }
                        onLoadingChanged: function(info) {
                            tabsModel.setProperty(webTab.index, "loading", loading)
                            tabsModel.setProperty(webTab.index, "progress", loadProgress)
                            if (info.status === WebEngineView.LoadSucceededStatus && url.toString() !== "about:blank")
                                BrowserBackend.visit(url.toString(), title || BrowserBackend.displayAddress(url.toString()))
                            if (info.status === WebEngineView.LoadFailedStatus && webTab.index === root.currentIndex)
                                BrowserBackend.notify(info.errorString || "This page could not be loaded.")
                        }
                        onLoadProgressChanged: tabsModel.setProperty(webTab.index, "progress", loadProgress)
                        onRecentlyAudibleChanged: tabsModel.setProperty(webTab.index, "audible", recentlyAudible)
                        onAudioMutedChanged: tabsModel.setProperty(webTab.index, "muted", audioMuted)
                        onNewWindowRequested: function(request) { root.requestNewWindow(request) }
                        onPermissionRequested: function(permission) {
                            root.pendingPermission = permission
                        }
                        onFullScreenRequested: function(request) {
                            request.accept()
                            root.visibility = request.toggleOn ? Window.FullScreen : Window.Windowed
                        }
                        onRenderProcessTerminated: function(status, exitCode) {
                            if (webTab.index === root.currentIndex)
                                BrowserBackend.notify("This tab stopped unexpectedly. Reload to continue.")
                        }
                    }

                    StartPage {
                        anchors.fill: parent
                        visible: webTab.visible && webTab.url === "about:blank" && !root.readerOpen
                        data: root.startPageData
                        onOpenUrl: function(value) { root.navigateTo(value) }
                        onAddFavoriteRequested: root.focusAddress()
                    }
                }
            }

            ReaderOverlay {
                anchors.fill: parent
                visible: root.readerOpen
                z: 12
                articleTitle: root.readerTitle
                articleText: root.readerText
                onClosed: root.readerOpen = false
            }

            Rectangle {
                id: libraryOverlay
                property string mode: ""
                property string heading: ""
                property var records: []
                visible: mode !== ""
                anchors.fill: parent
                color: Theme.dark ? "#1d1d20" : "#f8f8fa"
                z: 10

                function showCollection(key, title) {
                    mode = key
                    heading = title
                    reload()
                }
                function reload() {
                    if (mode) records = JSON.parse(BrowserBackend.collectionJson(mode))
                }

                Flickable {
                    anchors.fill: parent
                    contentHeight: libraryColumn.height + 100
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: libraryColumn
                        width: Math.min(820, parent.width - 70)
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 48
                        spacing: 14

                        Row {
                            width: parent.width
                            Text {
                                text: libraryOverlay.heading
                                color: Theme.label
                                font { family: Theme.fontDisplay; pixelSize: 28; weight: Font.DemiBold }
                            }
                            Item { width: Math.max(0, parent.width - parent.children[0].width - closeLibrary.width); height: 1 }
                            BrowserButton {
                                id: closeLibrary
                                symbol: "xmark"; tooltip: "Close"
                                onClicked: libraryOverlay.mode = ""
                            }
                        }

                        Text {
                            visible: libraryOverlay.records.length === 0
                            text: "Nothing here yet."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }

                        Repeater {
                            model: libraryOverlay.records
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: libraryColumn.width
                                height: 60
                                radius: 12
                                color: libArea.containsMouse ? (Theme.dark ? "#12ffffff" : "#0b000000") : "transparent"
                                border { width: 0.5; color: Theme.separator }

                                Column {
                                    anchors { left: parent.left; right: removeButton.left; leftMargin: 14; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    Text {
                                        width: parent.width
                                        text: modelData.title || BrowserBackend.displayAddress(modelData.url)
                                        color: Theme.label; elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                                    }
                                    Text {
                                        width: parent.width
                                        text: BrowserBackend.displayAddress(modelData.url)
                                        color: Theme.secondaryLabel; elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: 11 }
                                    }
                                }
                                BrowserButton {
                                    id: removeButton
                                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    visible: libraryOverlay.mode !== "history" || true
                                    width: 28; height: 28
                                    symbol: "xmark"; tooltip: "Remove"
                                    onClicked: {
                                        BrowserBackend.removeCollectionItem(libraryOverlay.mode, index)
                                        libraryOverlay.reload()
                                    }
                                }
                                MouseArea {
                                    id: libArea
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: removeButton.left }
                                    hoverEnabled: true
                                    onClicked: {
                                        libraryOverlay.mode = ""
                                        root.activateUrl(modelData.url)
                                    }
                                }
                            }
                        }

                        Button {
                            visible: libraryOverlay.mode === "history" && libraryOverlay.records.length > 0
                            text: "Clear History"
                            destructive: true
                            onClicked: BrowserBackend.clearHistory()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: searchPopover
        z: 50
        visible: addressInput.activeFocus && root.suggestionData.length > 0
        x: {
            let p = smartField.mapToItem(root, 0, smartField.height + 5)
            return Math.max(10, Math.min(root.width - width - 10, p.x))
        }
        y: {
            let p = smartField.mapToItem(root, 0, smartField.height + 5)
            return p.y
        }
        width: smartField.width
        height: Math.min(350, suggestionColumn.height + 12)
        radius: 16
        color: Theme.dark ? "#f3323237" : "#fcf7f7f9"
        border { width: 0.5; color: Theme.separator }

        Column {
            id: suggestionColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2
            Repeater {
                model: root.suggestionData
                delegate: Rectangle {
                    required property var modelData
                    width: suggestionColumn.width
                    height: 42
                    radius: 10
                    color: suggestionArea.containsMouse ? (Theme.dark ? "#16ffffff" : "#0d000000") : "transparent"
                    Row {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 10
                        Symbol {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.kind === "tab" ? "apps"
                                : modelData.kind === "favorite" ? "bookmark"
                                : modelData.kind === "history" ? "clock"
                                : modelData.kind === "reading" ? "notes" : "search"
                            tone: modelData.kind === "search" ? "accent" : "gray"
                            size: 15
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 34
                            Text {
                                width: parent.width
                                text: modelData.title
                                color: Theme.label
                                elide: Text.ElideRight
                                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                            }
                            Text {
                                width: parent.width
                                text: modelData.subtitle
                                color: Theme.secondaryLabel
                                elide: Text.ElideRight
                                font { family: Theme.fontUi; pixelSize: 10 }
                            }
                        }
                    }
                    MouseArea {
                        id: suggestionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            addressInput.focus = false
                            root.activateUrl(modelData.url)
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: pageMenu
        z: 48
        visible: root.pageMenuOpen
        x: {
            let p = smartField.mapToItem(root, 0, smartField.height + 5)
            return Math.max(10, p.x)
        }
        y: {
            let p = smartField.mapToItem(root, 0, smartField.height + 5)
            return p.y
        }
        width: 252
        height: pageMenuColumn.height + 12
        radius: 16
        color: Theme.dark ? "#f3323237" : "#fcf7f7f9"
        border { width: 0.5; color: Theme.separator }

        Column {
            id: pageMenuColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            spacing: 2

            component MenuRow: Rectangle {
                id: mr
                property string symbol
                property string label
                property string trailing
                property bool destructive: false
                property bool enabled: true
                signal activated()
                width: pageMenuColumn.width
                height: 34
                radius: 9
                opacity: enabled ? 1 : 0.35
                color: menuArea.containsMouse && enabled ? (Theme.dark ? "#16ffffff" : "#0d000000") : "transparent"
                Row {
                    anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                    spacing: 9
                    Symbol { anchors.verticalCenter: parent.verticalCenter; name: mr.symbol; tone: mr.destructive ? "red" : "auto"; size: 14 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 58
                        text: mr.label
                        color: mr.destructive ? "#ff453a" : Theme.label
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: mr.trailing
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
                MouseArea { id: menuArea; anchors.fill: parent; hoverEnabled: true; enabled: mr.enabled; onClicked: mr.activated() }
            }

            MenuRow { symbol: "notes"; label: "Reader"; enabled: root.currentUrl !== "about:blank"; onActivated: root.enterReader() }
            MenuRow { symbol: "bookmark"; label: "Add to Favorites"; enabled: root.currentUrl !== "about:blank"; onActivated: { BrowserBackend.addBookmark(root.currentUrl, root.currentTitle); root.pageMenuOpen = false } }
            MenuRow { symbol: "clock"; label: "Add to Reading List"; enabled: root.currentUrl !== "about:blank"; onActivated: { BrowserBackend.addReadingList(root.currentUrl, root.currentTitle); root.pageMenuOpen = false } }
            MenuRow { symbol: "globe"; label: "Copy Link"; enabled: root.currentUrl !== "about:blank"; onActivated: { BrowserBackend.copyText(root.currentUrl); root.pageMenuOpen = false; BrowserBackend.notify("Link copied") } }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Row {
                width: parent.width
                height: 36
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    leftPadding: 9
                    text: "Page Zoom"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                BrowserButton {
                    width: 30; height: 30; symbol: "minus"; tooltip: "Zoom Out"
                    onClicked: if (root.currentView) root.currentView.zoomFactor = Math.max(0.5, root.currentView.zoomFactor - 0.1)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentView ? Math.round(root.currentView.zoomFactor * 100) + "%" : "100%"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
                BrowserButton {
                    width: 30; height: 30; symbol: "plus"; tooltip: "Zoom In"
                    onClicked: if (root.currentView) root.currentView.zoomFactor = Math.min(3, root.currentView.zoomFactor + 0.1)
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            MenuRow {
                symbol: "gear"; label: "Web Settings…"
                onActivated: { root.pageMenuOpen = false; root.settingsOpen = true }
            }
        }
    }

    Rectangle {
        id: downloadsPopover
        z: 48
        visible: root.downloadsOpen
        x: root.width - width - 16
        y: toolbar.height + 5
        width: 360
        height: Math.min(420, Math.max(110, downloadsColumn.height + 18))
        radius: 16
        color: Theme.dark ? "#f3323237" : "#fcf7f7f9"
        border { width: 0.5; color: Theme.separator }

        Column {
            id: downloadsColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
            spacing: 8

            Row {
                width: parent.width
                Text {
                    text: "Downloads"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                }
                Item { width: Math.max(0, parent.width - parent.children[0].width - openDownloads.width); height: 1 }
                Text {
                    id: openDownloads
                    text: "Show in Files"
                    color: Theme.accent
                    font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium }
                    TapHandler { onTapped: BrowserBackend.openDownloadsFolder() }
                }
            }

            Text {
                visible: root.downloads.length === 0
                text: "No downloads yet."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }

            Repeater {
                model: root.downloads
                delegate: Rectangle {
                    required property var modelData
                    width: downloadsColumn.width
                    height: 64
                    radius: 11
                    color: Theme.dark ? "#0dffffff" : "#09000000"
                    Row {
                        anchors { fill: parent; margins: 10 }
                        spacing: 10
                        Symbol { anchors.verticalCenter: parent.verticalCenter; name: "download"; tone: "accent"; size: 18 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - cancelDownload.width - 44
                            spacing: 4
                            Text {
                                width: parent.width
                                text: modelData.downloadFileName || modelData.suggestedFileName
                                color: Theme.label; elide: Text.ElideMiddle
                                font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                            }
                            ProgressBar {
                                width: parent.width
                                height: 5
                                value: modelData.totalBytes > 0 ? modelData.receivedBytes / modelData.totalBytes : 0
                                indeterminate: modelData.totalBytes <= 0 && !modelData.isFinished
                            }
                            Text {
                                width: parent.width
                                text: modelData.isFinished ? "Finished"
                                    : modelData.totalBytes > 0 ? Math.round(modelData.receivedBytes / modelData.totalBytes * 100) + "%"
                                    : "Downloading…"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 10 }
                            }
                        }
                        BrowserButton {
                            id: cancelDownload
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !modelData.isFinished
                            width: 26; height: 26
                            symbol: "xmark"; tooltip: "Cancel Download"
                            onClicked: modelData.cancel()
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: settingsSheet
        z: 60
        visible: root.settingsOpen
        anchors.centerIn: parent
        width: Math.min(560, root.width - 60)
        height: Math.min(500, root.height - 80)
        radius: 22
        color: Theme.dark ? "#fa2c2c30" : "#fdf8f8fa"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -18 }
            radius: 30
            color: "#40000000"
            opacity: 0.28
        }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 18

            Row {
                width: parent.width
                Text {
                    text: "Web Settings"
                    color: Theme.label
                    font { family: Theme.fontDisplay; pixelSize: 23; weight: Font.DemiBold }
                }
                Item { width: Math.max(0, parent.width - parent.children[0].width - closeSettings.width); height: 1 }
                BrowserButton {
                    id: closeSettings
                    symbol: "xmark"; tooltip: "Close"
                    onClicked: root.settingsOpen = false
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Row {
                width: parent.width
                Text {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Tab Layout"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Segmented {
                    options: ["Separate", "Compact"]
                    current: root.browserSettings.tabLayout === "compact" ? 1 : 0
                    onPicked: function(index) { root.setBrowserSetting("tabLayout", index === 1 ? "compact" : "separate") }
                }
            }

            Row {
                width: parent.width
                Text {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Restore previous session"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Switch {
                    checked: root.browserSettings.restoreSession !== false
                    onToggled: function(on) { root.setBrowserSetting("restoreSession", on) }
                }
            }

            Row {
                width: parent.width
                Text {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Favorites when searching"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Switch {
                    checked: root.browserSettings.showFavoritesOnFocus !== false
                    onToggled: function(on) { root.setBrowserSetting("showFavoritesOnFocus", on) }
                }
            }

            Row {
                width: parent.width
                Text {
                    width: 190
                    text: "Search Engine"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    text: "DuckDuckGo"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: BrowserBackend.privateMode
                    ? "Private windows keep history, cookies and permissions in memory for this window only."
                    : "Website permissions are stored per origin by Qt WebEngine. Use the prompt shown by Web when a site requests access."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
        }
    }

    Rectangle {
        id: permissionSheet
        z: 70
        visible: root.pendingPermission !== null
        anchors.centerIn: parent
        width: 420
        height: 190
        radius: 20
        color: Theme.dark ? "#fc303034" : "#fff7f7f9"
        border { width: 0.5; color: Theme.separator }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 12
            Text {
                width: parent.width
                text: "Website Permission"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.pendingPermission
                    ? BrowserBackend.displayAddress(root.pendingPermission.origin.toString()) + " is requesting access to a protected browser feature."
                    : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Item { width: 1; height: 8 }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button {
                    text: "Don't Allow"
                    onClicked: {
                        if (root.pendingPermission) root.pendingPermission.deny()
                        root.pendingPermission = null
                    }
                }
                Button {
                    text: "Allow"
                    prominent: true
                    onClicked: {
                        if (root.pendingPermission) root.pendingPermission.grant()
                        root.pendingPermission = null
                    }
                }
            }
        }
    }

    Rectangle {
        id: toast
        z: 100
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 }
        width: Math.min(root.width - 40, toastLabel.implicitWidth + 32)
        height: 34
        radius: 17
        color: Theme.dark ? "#ee35353a" : "#eef8f8fa"
        border { width: 0.5; color: Theme.separator }
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 160 } }

        Text {
            id: toastLabel
            anchors.centerIn: parent
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
        }
        Timer {
            id: toastTimer
            interval: 2200
            onTriggered: toast.opacity = 0
        }
    }

    Shortcut { sequence: "Ctrl+L"; onActivated: root.focusAddress() }
    Shortcut { sequence: "Ctrl+T"; onActivated: root.newTab("about:blank", true) }
    Shortcut { sequence: "Ctrl+W"; onActivated: root.closeTab(root.currentIndex) }
    Shortcut { sequence: "Ctrl+R"; onActivated: root.reloadOrStop() }
    Shortcut { sequence: "F5"; onActivated: root.reloadOrStop() }
    Shortcut { sequence: "Alt+Left"; onActivated: if (root.currentView) root.currentView.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (root.currentView) root.currentView.goForward() }
    Shortcut { sequence: "Ctrl+D"; onActivated: if (root.currentUrl !== "about:blank") BrowserBackend.addBookmark(root.currentUrl, root.currentTitle) }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: root.reopenLastClosed() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: BrowserBackend.openPrivateWindow() }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: {
            if (tabsModel.count > 1) {
                root.currentIndex = (root.currentIndex + 1) % tabsModel.count
                root.syncAddress()
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            if (tabsModel.count > 1) {
                root.currentIndex = (root.currentIndex - 1 + tabsModel.count) % tabsModel.count
                root.syncAddress()
            }
        }
    }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (root.readerOpen) root.readerOpen = false
            else if (root.settingsOpen) root.settingsOpen = false
            else if (root.pageMenuOpen) root.pageMenuOpen = false
            else if (root.downloadsOpen) root.downloadsOpen = false
            else if (root.pendingPermission) { root.pendingPermission.deny(); root.pendingPermission = null }
            else if (addressInput.activeFocus) { addressInput.focus = false; root.syncAddress() }
            else if (root.currentView && root.currentView.loading) root.currentView.stop()
        }
    }
}
