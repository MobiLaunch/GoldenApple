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
    property bool privacySheetOpen: false
    property var sitePrivacyReport: ({ enabled: true, blocked: 0, domains: [] })
    property bool findOpen: false
    property string findQuery: ""
    property int findMatches: 0
    property int findActive: 0
    property bool readerOpen: false
    property bool tabOverviewOpen: false
    property string readerTitle: ""
    property string readerText: ""
    property var downloads: []
    property var pendingPermission: null
    property var startPageData: JSON.parse(BrowserBackend.startPageJson())
    property var browserSettings: JSON.parse(BrowserBackend.settingsJson)
    property var suggestionData: []
    property var tabGroups: []
    property bool tabGroupEditorOpen: false
    property bool tabGroupsSheetOpen: false
    property string tabGroupName: ""
    property var profiles: []
    property bool profileSheetOpen: false
    property string newProfileName: ""
    property bool websitePermissionsOpen: false
    property bool webContextOpen: false
    property real webContextX: 0
    property real webContextY: 0
    property var webContextItems: []
    property string permissionOriginFilter: ""
    property var websitePermissions: []
    readonly property bool compactTabs: browserSettings.tabLayout === "compact"

    Binding { target: Theme; property: "dark"; value: BrowserBackend.dark }

    function openWebContext(request, view) {
        request.accepted = true
        const point = view.mapToItem(root.contentItem, request.position.x, request.position.y)
        const link = request.linkUrl ? request.linkUrl.toString() : ""
        const selected = request.selectedText || ""
        let items = []

        if (link) {
            items.push({ label: "Open Link in New Tab", action: () => root.newTab(link, true) })
            items.push({ label: "Copy Link", action: () => BrowserBackend.copyText(link) })
            items.push({ separator: true })
        }

        if (selected.length) {
            items.push({ label: "Copy", shortcut: "⌘C", action: () => BrowserBackend.copyText(selected) })
        }
        if (request.isContentEditable) {
            items.push({ label: "Cut", shortcut: "⌘X", action: () => view.triggerWebAction(WebEngineView.Cut) })
            items.push({ label: "Paste", shortcut: "⌘V", action: () => view.triggerWebAction(WebEngineView.Paste) })
        }
        if (selected.length || request.isContentEditable)
            items.push({ separator: true })

        items.push({ label: "Back", shortcut: "⌘[", enabled: view.canGoBack, action: () => view.goBack() })
        items.push({ label: "Forward", shortcut: "⌘]", enabled: view.canGoForward, action: () => view.goForward() })
        items.push({ label: "Reload", shortcut: "⌘R", action: () => view.reload() })

        webContextItems = items
        webContextX = point.x
        webContextY = point.y
        webContextOpen = true
        webContextMenu.popup(root.contentItem, point.x, point.y, items)
    }

    // Page zoom in tenths, 50–300%; 0 resets it.
    function zoomBy(step) {
        if (root.currentView) root.currentView.zoomFactor = step === 0 ? 1 : Math.max(0.5, Math.min(3, root.currentView.zoomFactor + step))
    }

    // Safari's page menu, as items for the shared menu.
    function pageMenuItems() {
        const page = root.currentUrl !== "about:blank"
        const blocked = page ? String(JSON.parse(BrowserBackend.privacyReportForUrl(root.currentUrl)).blocked || "") : ""
        return [
            { text: "Show Reader", enabled: page, action: () => root.enterReader() },
            { text: "Privacy Report", shortcut: blocked ? blocked + " blocked" : "", action: () => root.openPrivacyReport() },
            { separator: true },
            { text: "Add to Favorites", enabled: page, action: () => BrowserBackend.addBookmark(root.currentUrl, root.currentTitle) },
            { text: "Add to Reading List", enabled: page, action: () => BrowserBackend.addReadingList(root.currentUrl, root.currentTitle) },
            { text: "Copy Link", enabled: page, action: () => { BrowserBackend.copyText(root.currentUrl); BrowserBackend.notify("Link copied") } },
            { text: "Find on Page…", shortcut: "⌘F", enabled: page, action: () => root.openFind() },
            { separator: true },
            { header: "Zoom " + (root.currentView ? Math.round(root.currentView.zoomFactor * 100) : 100) + "%" },
            { text: "Zoom In", shortcut: "⌘+", enabled: page, action: () => root.zoomBy(0.1) },
            { text: "Actual Size", shortcut: "⌘0", enabled: page, action: () => root.zoomBy(0) },
            { text: "Zoom Out", shortcut: "⌘−", enabled: page, action: () => root.zoomBy(-0.1) },
            { separator: true },
            { text: "Website Settings…", enabled: page, action: () => root.showWebsitePermissions(true) },
            { text: "Web Settings…", action: () => root.settingsOpen = true }
        ]
    }
    onPageMenuOpenChanged: {
        if (pageMenuOpen && !pageMenu.visible) pageMenu.popup(smartField, 0, smartField.height + 5, pageMenuItems())
        else if (!pageMenuOpen && pageMenu.visible) pageMenu.close()
    }
    onWebContextOpenChanged: if (!webContextOpen && webContextMenu.visible) webContextMenu.close()

    function refreshStartPage() {
        startPageData = JSON.parse(BrowserBackend.startPageJson())
        tabGroups = JSON.parse(BrowserBackend.collectionJson("tabGroups"))
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

    function reorderTab(from, to) {
        if (from < 0 || to < 0 || from >= tabsModel.count || to >= tabsModel.count || from === to)
            return
        const active = currentIndex
        tabsModel.move(from, to, 1)
        if (active === from) currentIndex = to
        else if (from < active && to >= active) currentIndex = active - 1
        else if (from > active && to <= active) currentIndex = active + 1
        saveTabsSoon()
        Qt.callLater(syncAddress)
    }

    function activateUrl(url) {
        for (let i = 0; i < tabsModel.count; i++) {
            if (tabsModel.get(i).url === url) {
                currentIndex = i
                addressField.input.focus = false
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
        addressField.input.focus = false
        saveTabsSoon()
    }

    function syncAddress() {
        if (!addressField.input.activeFocus)
            addressField.input.text = BrowserBackend.displayAddress(currentUrl)
    }

    function focusAddress() {
        addressField.input.forceActiveFocus()
        addressField.input.text = currentUrl === "about:blank" ? "" : currentUrl
        addressField.input.selectAll()
        updateSuggestions()
    }

    function updateSuggestions() {
        if (!addressField.input.activeFocus) {
            suggestionData = []
            return
        }
        suggestionData = JSON.parse(BrowserBackend.suggestions(addressField.input.text, JSON.stringify(tabSnapshot())))
    }

    function reloadOrStop() {
        if (!currentView) return
        if (currentView.loading) currentView.stop()
        else currentView.reload()
    }

    function performFind(backward) {
        if (!currentView) return
        const query = findQuery.trim()
        if (!query) {
            currentView.findText("")
            findMatches = 0
            findActive = 0
            return
        }
        currentView.findText(query, backward ? WebEngineView.FindBackward : 0)
    }

    function openFind() {
        if (!currentView || currentUrl === "about:blank") return
        findOpen = true
        Qt.callLater(function() { findField.input.forceActiveFocus(); findField.input.selectAll() })
    }

    function closeFind() {
        if (currentView) currentView.findText("")
        findOpen = false
        findQuery = ""
        findMatches = 0
        findActive = 0
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

    function openPrivacyReport() {
        try { sitePrivacyReport = JSON.parse(BrowserBackend.privacyReportForUrl(currentUrl)) }
        catch (_) { sitePrivacyReport = ({ enabled: true, blocked: 0, domains: [] }) }
        pageMenuOpen = false
        privacySheetOpen = true
    }

    function refreshTabGroups() {
        try { tabGroups = JSON.parse(BrowserBackend.collectionJson("tabGroups")) }
        catch (_) { tabGroups = [] }
    }

    function saveCurrentTabGroup() {
        const name = tabGroupName.trim()
        if (!name) {
            BrowserBackend.notify("Give this Tab Group a name.")
            return
        }
        if (BrowserBackend.saveTabGroup(name, JSON.stringify(tabSnapshot()))) {
            tabGroupEditorOpen = false
            tabGroupName = ""
            refreshTabGroups()
        }
    }

    function openTabGroup(index) {
        if (index < 0 || index >= tabGroups.length) return
        const group = tabGroups[index]
        if (!group || !Array.isArray(group.tabs) || !group.tabs.length) return

        tabsModel.clear()
        for (let i = 0; i < group.tabs.length; i++) {
            const record = group.tabs[i]
            tabsModel.append({
                url: record.url || "about:blank",
                title: record.title || BrowserBackend.displayAddress(record.url || "") || "Start Page",
                icon: "",
                loading: false,
                progress: 0,
                audible: false,
                muted: false
            })
        }
        currentIndex = 0
        libraryOverlay.mode = ""
        saveTabsSoon()
        Qt.callLater(syncAddress)
    }

    function toggleMute(index) {
        const item = tabViews.itemAt(index)
        if (item && item.view)
            item.view.audioMuted = !item.view.audioMuted
    }

    function refreshProfiles() {
        try { profiles = JSON.parse(BrowserBackend.profilesJson) }
        catch (_) { profiles = ["Personal"] }
    }

    function createProfile() {
        const name = newProfileName.trim()
        if (!name) {
            BrowserBackend.notify("Enter a profile name.")
            return
        }
        if (BrowserBackend.createProfile(name)) {
            newProfileName = ""
            refreshProfiles()
        }
    }

    function permissionLabel(type) {
        switch (Number(type)) {
        case 1: return "Microphone"
        case 2: return "Camera"
        case 3: return "Camera & Microphone"
        case 4: return "Screen Capture"
        case 5: return "Screen & Audio Capture"
        case 6: return "Pointer Lock"
        case 7: return "Notifications"
        case 8: return "Location"
        case 9: return "Clipboard"
        case 10: return "Local Fonts"
        default: return "Website Permission"
        }
    }

    function permissionStateLabel(state) {
        switch (Number(state)) {
        case 2: return "Allowed"
        case 3: return "Blocked"
        default: return "Ask"
        }
    }

    function refreshWebsitePermissions() {
        try { websitePermissions = profile.listAllPermissions() }
        catch (_) { websitePermissions = [] }
    }

    function showWebsitePermissions(originOnly) {
        permissionOriginFilter = originOnly ? BrowserBackend.securityOrigin(currentUrl) : ""
        refreshWebsitePermissions()
        pageMenuOpen = false
        websitePermissionsOpen = true
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
        BrowserBackend.attachProfile(profile)
        let initial = JSON.parse(BrowserBackend.initialTabsJson)
        if (!initial.length) initial = ["about:blank"]
        for (let i = 0; i < initial.length; i++) newTab(initial[i], false)
        currentIndex = 0
        refreshTabGroups()
        refreshProfiles()
        Qt.callLater(syncAddress)
    }

    Connections {
        target: BrowserBackend
        function onDarkChanged() {
            Qt.callLater(root.syncAddress)
        }
        function onLibraryChanged() {
            root.refreshStartPage()
            root.refreshTabGroups()
            if (libraryOverlay.visible) libraryOverlay.reload()
        }
        function onProfilesChanged() { root.refreshProfiles() }
        function onPrivacyChanged() {
            root.refreshStartPage()
            if (root.privacySheetOpen) root.openPrivacyReport()
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
                    width: Math.min(parent.width, addressField.input.activeFocus ? 720 : 640)
                    radius: height / 2      // Safari's Smart Search field is a capsule
                    color: BrowserBackend.privateMode
                        ? (Theme.dark ? "#88443a52" : "#cfe9e2ef")
                        : (Theme.dark ? "#b63b3b40" : "#eaffffff")
                    border {
                        width: addressField.input.activeFocus ? 2 : 0.5
                        color: addressField.input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.separator
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

                    TextField {
                        id: addressField
                        anchors {
                            left: pageButton.right; leftMargin: 4
                            right: reloadInside.left; rightMargin: 5
                            verticalCenter: parent.verticalCenter
                        }
                        height: 26
                        bare: true
                        placeholder: "Search or enter website name"
                        placeholderOnlyWhenFocused: true
                        fontWeight: input.activeFocus ? Font.Normal : Font.Medium
                        input.selectedTextColor: Theme.label
                        input.Keys.onEscapePressed: {
                            addressField.input.focus = false
                            root.suggestionData = []
                            root.syncAddress()
                        }
                        onAccepted: root.navigateTo(text)
                        Connections {
                            target: addressField.input
                            function onActiveFocusChanged() {
                                if (addressField.input.activeFocus) {
                                    addressField.text = root.currentUrl === "about:blank" ? "" : root.currentUrl
                                    addressField.input.selectAll()
                                    root.updateSuggestions()
                                } else {
                                    root.suggestionData = []
                                    root.syncAddress()
                                }
                            }
                            function onTextChanged() { if (addressField.input.activeFocus) suggestionTimer.restart() }
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
                symbol: "apps"
                tooltip: "Tab Overview"
                selected: root.tabOverviewOpen
                onClicked: {
                    root.tabOverviewOpen = !root.tabOverviewOpen
                    root.pageMenuOpen = false
                    root.downloadsOpen = false
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
                        required property bool muted
                        readonly property bool active: index === root.currentIndex
                        property real dragOffset: 0
                        width: Math.max(132, Math.min(220, (tabScroller.width - 10) / Math.max(1, Math.min(6, tabsModel.count))))
                        height: 37
                        z: tabDrag.active ? 10 : 0
                        transform: Translate { x: tab.dragOffset }

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

                            BrowserButton {
                                visible: tab.audible && !closeButton.visible
                                anchors.verticalCenter: parent.verticalCenter
                                width: 23; height: 23
                                symbol: tab.muted ? "speaker" : "speaker-wave"
                                tooltip: tab.muted ? "Unmute Tab" : "Mute Tab"
                                onClicked: root.toggleMute(tab.index)
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
                        DragHandler {
                            id: tabDrag
                            target: null
                            xAxis.enabled: true
                            yAxis.enabled: false
                            onTranslationChanged: tab.dragOffset = translation.x
                            onActiveChanged: {
                                if (active) return
                                const from = tab.index
                                const step = tab.width + tabRow.spacing
                                const delta = Math.round(tab.dragOffset / Math.max(1, step))
                                const to = Math.max(0, Math.min(tabsModel.count - 1, from + delta))
                                tab.dragOffset = 0
                                root.reorderTab(from, to)
                            }
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

                    Column {
                        leftPadding: 8
                        topPadding: 8
                        bottomPadding: 10
                        spacing: 1
                        Text {
                            text: BrowserBackend.privateMode ? "Private Browsing" : "Web"
                            color: Theme.label
                            font { family: Theme.fontDisplay; pixelSize: 22; weight: Font.DemiBold; letterSpacing: -0.3 }
                        }
                        Text {
                            text: BrowserBackend.profileName
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11; weight: Font.Medium }
                        }
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
                        symbol: "doc"
                        label: "Reading List"
                        onActivated: libraryOverlay.showCollection("readingList", "Reading List")
                    }
                    SideRow {
                        symbol: "arrow-clockwise"
                        label: "Recently Closed"
                        detail: String(root.startPageData.recentlyClosed?.length ?? 0)
                        onActivated: libraryOverlay.showCollection("closedTabs", "Recently Closed")
                    }
                    SideRow {
                        visible: !BrowserBackend.privateMode
                        symbol: "shield"
                        label: "New Private Window"
                        onActivated: BrowserBackend.openPrivateWindow()
                    }

                    Text {
                        visible: !BrowserBackend.privateMode
                        text: "TAB GROUPS"
                        color: Theme.tertiaryLabel
                        leftPadding: 8
                        topPadding: 18
                        bottomPadding: 4
                        font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.8 }
                    }

                    Repeater {
                        model: root.tabGroups
                        delegate: SideRow {
                            required property int index
                            required property var modelData
                            visible: !BrowserBackend.privateMode
                            symbol: "folder"
                            label: modelData.name
                            detail: String(modelData.tabs?.length ?? 0)
                            onActivated: root.openTabGroup(index)
                        }
                    }

                    SideRow {
                        visible: !BrowserBackend.privateMode
                        symbol: "plus"
                        label: "Save Tabs as Group…"
                        onActivated: {
                            root.tabGroupName = ""
                            root.tabGroupEditorOpen = true
                        }
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
                        property int rendererRestarts: 0
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
                            if (info.status === WebEngineView.LoadSucceededStatus && url.toString() !== "about:blank") {
                                rendererRestarts = 0
                                BrowserBackend.visit(url.toString(), title || BrowserBackend.displayAddress(url.toString()))
                            }
                            if (info.status === WebEngineView.LoadFailedStatus && webTab.index === root.currentIndex)
                                BrowserBackend.notify(info.errorString || "This page could not be loaded.")
                        }
                        onLoadProgressChanged: tabsModel.setProperty(webTab.index, "progress", loadProgress)
                        onRecentlyAudibleChanged: tabsModel.setProperty(webTab.index, "audible", recentlyAudible)
                        onAudioMutedChanged: tabsModel.setProperty(webTab.index, "muted", audioMuted)
                    onFindTextFinished: function(result) {
                        if (webTab.index === root.currentIndex) {
                            root.findMatches = result.numberOfMatches
                            root.findActive = result.activeMatch
                        }
                    }
                        onNewWindowRequested: function(request) { root.requestNewWindow(request) }
                        onContextMenuRequested: function(request) {
                            root.openWebContext(request, web)
                        }
                        onPermissionRequested: function(permission) {
                            root.pendingPermission = permission
                        }
                        onFullScreenRequested: function(request) {
                            request.accept()
                            root.visibility = request.toggleOn ? Window.FullScreen : Window.Windowed
                        }
                        Timer {
                            id: rendererRetry
                            interval: 350
                            repeat: false
                            onTriggered: web.reload()
                        }
                        onRenderProcessTerminated: function(status, exitCode) {
                            rendererRestarts += 1
                            if (rendererRestarts === 1) {
                                if (webTab.index === root.currentIndex)
                                    BrowserBackend.notify("Web restarted this tab after a renderer failure.")
                                rendererRetry.restart()
                            } else if (webTab.index === root.currentIndex) {
                                BrowserBackend.notify("This tab's renderer stopped again. Web is using the safest live-boot graphics path.")
                            }
                        }
                    }

                    StartPage {
                        anchors.fill: parent
                        visible: webTab.visible && webTab.url === "about:blank" && !root.readerOpen
                        data: root.startPageData
                        onOpenUrl: function(value) { root.navigateTo(value) }
                        onAddFavoriteRequested: root.focusAddress()
                        onPrivacyRequested: root.openPrivacyReport()
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
        id: tabOverview
        z: 42
        visible: root.tabOverviewOpen
        anchors.fill: body
        color: Theme.dark ? "#f31b1b20" : "#f5f2f3f6"

        Column {
            anchors { fill: parent; margins: 26 }
            spacing: 18

            Row {
                width: parent.width
                Column {
                    width: parent.width - overviewClose.width
                    spacing: 2
                    Text {
                        text: "Tab Overview"
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: 26; weight: Font.DemiBold; letterSpacing: -0.4 }
                    }
                    Text {
                        text: tabsModel.count + (tabsModel.count === 1 ? " open tab" : " open tabs")
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                }
                BrowserButton {
                    id: overviewClose
                    symbol: "xmark"; tooltip: "Close Tab Overview"
                    onClicked: root.tabOverviewOpen = false
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 72
                contentHeight: overviewGrid.height + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: overviewGrid
                    width: parent.width
                    spacing: 14
                    columns: Math.max(1, Math.floor((width + spacing) / 244))

                    Repeater {
                        model: tabsModel
                        delegate: Rectangle {
                            id: overviewCard
                            required property int index
                            required property string title
                            required property string url
                            required property string icon
                            required property bool loading
                            readonly property bool selected: index === root.currentIndex
                            width: (overviewGrid.width - overviewGrid.spacing * (overviewGrid.columns - 1)) / overviewGrid.columns
                            height: 142
                            radius: 18
                            color: Theme.dark ? "#ca303035" : "#ecffffff"
                            border {
                                width: selected ? 2 : 0.5
                                color: selected ? Theme.accent : Theme.separator
                            }
                            scale: overviewArea.pressed && !Theme.reduceMotion ? 0.985 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 80; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: 86
                                radius: 18
                                color: Theme.dark ? "#16ffffff" : "#09000000"
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 18
                                    color: parent.color
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: 34; height: 34
                                    source: overviewCard.icon
                                    sourceSize: Qt.size(68, 68)
                                    visible: !!overviewCard.icon && !overviewCard.loading
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 34; height: 34; radius: 10
                                    visible: !overviewCard.icon && !overviewCard.loading
                                    color: Theme.dark ? "#18ffffff" : "#10000000"
                                    Text {
                                        anchors.centerIn: parent
                                        text: (overviewCard.title || "N").charAt(0).toUpperCase()
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 22; height: 22; radius: 11
                                    visible: overviewCard.loading
                                    color: "transparent"
                                    border { width: 2; color: Theme.accent }
                                    RotationAnimation on rotation {
                                        running: overviewCard.loading && !Theme.reduceMotion
                                        loops: Animation.Infinite
                                        from: 0; to: 360; duration: 750
                                    }
                                }
                            }

                            Column {
                                anchors { left: parent.left; right: overviewCardClose.left; bottom: parent.bottom; leftMargin: 12; rightMargin: 8; bottomMargin: 11 }
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: overviewCard.title || "Start Page"
                                    color: Theme.label
                                    elide: Text.ElideRight
                                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                                }
                                Text {
                                    width: parent.width
                                    text: overviewCard.url === "about:blank" ? "Start Page" : BrowserBackend.displayAddress(overviewCard.url)
                                    color: Theme.secondaryLabel
                                    elide: Text.ElideRight
                                    font { family: Theme.fontUi; pixelSize: 10 }
                                }
                            }

                            BrowserButton {
                                id: overviewCardClose
                                anchors { right: parent.right; rightMargin: 7; bottom: parent.bottom; bottomMargin: 8 }
                                width: 25; height: 25
                                symbol: "xmark"; tooltip: "Close Tab"
                                onClicked: root.closeTab(overviewCard.index)
                            }

                            MouseArea {
                                id: overviewArea
                                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: overviewCardClose.top }
                                hoverEnabled: true
                                onClicked: {
                                    root.currentIndex = overviewCard.index
                                    root.tabOverviewOpen = false
                                    root.syncAddress()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: searchPopover
        z: 50
        visible: addressField.input.activeFocus && root.suggestionData.length > 0
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
                                : modelData.kind === "reading" ? "doc" : "search"
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
                            addressField.input.focus = false
                            root.activateUrl(modelData.url)
                        }
                    }
                }
            }
        }
    }

    PopupMenu {
        id: webContextMenu
        onVisibleChanged: if (!visible) root.webContextOpen = false
    }

    Glass {
        id: findBar
        visible: root.findOpen
        z: 52
        anchors { top: webArea.top; right: webArea.right; topMargin: 12; rightMargin: 16 }
        width: 360
        height: 44
        radius: 14
        tint: Theme.dark ? "#f034343a" : "#f2f8f8fa"
        shadow: "#65000000"
        Row {
            anchors { fill: parent; margins: 6 }
            spacing: 5
            TextField {
                id: findField
                width: 210; height: 32
                search: true
                placeholder: "Find on Page"
                text: root.findQuery
                onTextChanged: { root.findQuery = text; root.performFind(false) }
                onAccepted: root.performFind(false)
            }
            Text {
                width: 50
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.findQuery ? (root.findMatches ? root.findActive + " of " + root.findMatches : "0 of 0") : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 10 }
            }
            BrowserButton { width: 26; height: 26; symbol: "chevron-left"; tooltip: "Previous Match"; enabled: root.findMatches > 0; onClicked: root.performFind(true) }
            BrowserButton { width: 26; height: 26; symbol: "chevron-right"; tooltip: "Next Match"; enabled: root.findMatches > 0; onClicked: root.performFind(false) }
            BrowserButton { width: 26; height: 26; symbol: "xmark"; tooltip: "Close Find"; onClicked: root.closeFind() }
        }
    }

    PopupMenu {
        id: pageMenu
        menuWidth: 240
        onVisibleChanged: if (!visible) root.pageMenuOpen = false
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
        height: Math.min(560, root.height - 80)
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
                    text: "Profile"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170
                    text: BrowserBackend.profileName
                    color: Theme.secondaryLabel
                    elide: Text.ElideRight
                    font { family: Theme.fontUi; pixelSize: 13 }
                }
                Button {
                    text: "Manage…"
                    onClicked: root.profileSheetOpen = true
                }
            }

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
                    text: "Tab Groups"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170
                    text: root.tabGroups.length + (root.tabGroups.length === 1 ? " group" : " groups")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Button {
                    text: "Manage…"
                    enabled: !BrowserBackend.privateMode
                    onClicked: root.tabGroupsSheetOpen = true
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
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Privacy Protection"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Switch {
                    checked: root.browserSettings.privacyProtection !== false
                    onToggled: function(on) { root.setBrowserSetting("privacyProtection", on) }
                }
            }

            Row {
                width: parent.width
                Text {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search Engine"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Segmented {
                    readonly property var keys: ["duckduckgo", "brave", "bing", "google"]
                    options: ["DuckDuckGo", "Brave", "Bing", "Google"]
                    current: Math.max(0, keys.indexOf(root.browserSettings.searchEngine ?? "duckduckgo"))
                    onPicked: function(index) { root.setBrowserSetting("searchEngine", keys[index]) }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Row {
                width: parent.width
                Text {
                    width: 190
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Website Permissions"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170
                    text: BrowserBackend.privateMode ? "This window only" : "Stored per website"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Button {
                    text: "Manage…"
                    onClicked: root.showWebsitePermissions(false)
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
        id: websitePermissionsSheet
        z: 67
        visible: root.websitePermissionsOpen
        anchors.centerIn: parent
        width: Math.min(570, root.width - 60)
        height: Math.min(520, root.height - 80)
        radius: 22
        color: Theme.dark ? "#fc303034" : "#fff8f8fa"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -14 }
            radius: 30
            color: "#40000000"
            opacity: 0.24
        }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 14

            Row {
                width: parent.width
                Column {
                    width: parent.width - closeWebsitePermissions.width
                    Text {
                        text: root.permissionOriginFilter ? "Website Settings" : "Website Permissions"
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: 21; weight: Font.DemiBold }
                    }
                    Text {
                        visible: !!root.permissionOriginFilter
                        text: BrowserBackend.displayAddress(root.permissionOriginFilter)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
                BrowserButton {
                    id: closeWebsitePermissions
                    symbol: "xmark"; tooltip: "Close"
                    onClicked: root.websitePermissionsOpen = false
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: BrowserBackend.privateMode
                    ? "Permission decisions in Private Browsing last only for this private profile."
                    : "Web remembers supported permission decisions per website. Forgetting one makes the site ask again."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }

            Flickable {
                width: parent.width
                height: parent.height - 112
                contentHeight: permissionList.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: permissionList
                    width: parent.width
                    spacing: 4

                    readonly property var filtered: root.websitePermissions.filter(function(permission) {
                        if (!root.permissionOriginFilter) return true
                        return permission.origin.toString() === root.permissionOriginFilter
                    })

                    Text {
                        visible: permissionList.filtered.length === 0
                        width: parent.width
                        topPadding: 18
                        text: root.permissionOriginFilter
                            ? "This website has no stored permission decisions."
                            : "No stored website permission decisions."
                        color: Theme.secondaryLabel
                        horizontalAlignment: Text.AlignHCenter
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }

                    Repeater {
                        model: permissionList.filtered
                        delegate: Rectangle {
                            required property var modelData
                            width: permissionList.width
                            height: 58
                            radius: 11
                            color: Theme.dark ? "#0dffffff" : "#08000000"
                            border { width: 0.5; color: Theme.separator }

                            Column {
                                anchors { left: parent.left; right: forgetPermission.left; leftMargin: 12; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: BrowserBackend.displayAddress(modelData.origin.toString())
                                    color: Theme.label
                                    elide: Text.ElideRight
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                                }
                                Text {
                                    width: parent.width
                                    text: root.permissionLabel(modelData.permissionType) + " · " + root.permissionStateLabel(modelData.state)
                                    color: Theme.secondaryLabel
                                    elide: Text.ElideRight
                                    font { family: Theme.fontUi; pixelSize: 11 }
                                }
                            }

                            Button {
                                id: forgetPermission
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                text: "Forget"
                                onClicked: {
                                    modelData.reset()
                                    Qt.callLater(root.refreshWebsitePermissions)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: privacySheet
        z: 67
        visible: root.privacySheetOpen
        anchors.centerIn: parent
        width: Math.min(500, root.width - 70)
        height: Math.min(480, Math.max(260, privacyContent.implicitHeight + 44))
        radius: 22
        color: Theme.dark ? "#fc303034" : "#fff8f8fa"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -14 }
            radius: 30
            color: "#40000000"
            opacity: 0.24
        }

        Column {
            id: privacyContent
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 14

            Row {
                width: parent.width
                Text {
                    text: "Privacy Report"
                    color: Theme.label
                    font { family: Theme.fontDisplay; pixelSize: 21; weight: Font.DemiBold }
                }
                Item { width: Math.max(0, parent.width - parent.children[0].width - closePrivacy.width); height: 1 }
                BrowserButton {
                    id: closePrivacy
                    symbol: "xmark"; tooltip: "Close"
                    onClicked: root.privacySheetOpen = false
                }
            }

            Text {
                width: parent.width
                text: root.currentUrl === "about:blank" ? "Start Page" : BrowserBackend.displayAddress(root.currentUrl)
                color: Theme.secondaryLabel
                elide: Text.ElideRight
                font { family: Theme.fontUi; pixelSize: 12 }
            }

            Row {
                spacing: 14
                Rectangle {
                    width: 50; height: 50; radius: 15
                    color: Theme.dark ? "#1dffffff" : "#120078ff"
                    Symbol { anchors.centerIn: parent; name: "shield"; tone: "accent"; size: 24 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: root.sitePrivacyReport.enabled
                            ? (root.sitePrivacyReport.blocked + " tracking request"
                               + (root.sitePrivacyReport.blocked === 1 ? "" : "s") + " blocked")
                            : "Privacy Protection is off"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 15; weight: Font.DemiBold }
                    }
                    Text {
                        text: "Known third-party tracker domains are blocked before Chromium sends the request."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Text {
                visible: root.sitePrivacyReport.enabled && root.sitePrivacyReport.domains.length === 0
                text: "No known tracker domains have been blocked for this site in this session."
                width: parent.width; wrapMode: Text.WordWrap
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }

            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: root.sitePrivacyReport.domains
                    delegate: Rectangle {
                        required property var modelData
                        width: privacyContent.width
                        height: 36; radius: 8
                        color: Theme.dark ? "#0cffffff" : "#07000000"
                        Text {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 70; elide: Text.ElideRight
                            text: modelData.domain
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 12 }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: String(modelData.count)
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11 }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Golden Gate Privacy Protection uses a conservative built-in tracker list. It is not Safari Intelligent Tracking Prevention."
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: 10 }
            }
        }
    }

    Rectangle {
        id: profileSheet
        z: 66
        visible: root.profileSheetOpen
        anchors.centerIn: parent
        width: 470
        height: Math.min(460, root.height - 90)
        radius: 22
        color: Theme.dark ? "#fc303034" : "#fff8f8fa"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -14 }
            radius: 30
            color: "#40000000"
            opacity: 0.24
        }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 14

            Row {
                width: parent.width
                Text {
                    text: "Profiles"
                    color: Theme.label
                    font { family: Theme.fontDisplay; pixelSize: 21; weight: Font.DemiBold }
                }
                Item { width: Math.max(0, parent.width - parent.children[0].width - closeProfiles.width); height: 1 }
                BrowserButton {
                    id: closeProfiles
                    symbol: "xmark"; tooltip: "Close"
                    onClicked: root.profileSheetOpen = false
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Each profile keeps its own cookies, website data, history, Favorites, Reading List, Tab Groups, and restored tabs."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: root.profiles
                    delegate: Rectangle {
                        required property var modelData
                        width: parent ? parent.width : 400
                        height: 44
                        radius: 10
                        color: modelData === BrowserBackend.profileName
                            ? (Theme.dark ? "#18ffffff" : "#0d000000") : "transparent"

                        Row {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                            spacing: 10
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 9
                                color: Theme.accent
                                opacity: modelData === BrowserBackend.profileName ? 1 : 0.70
                                Text {
                                    anchors.centerIn: parent
                                    text: String(modelData).charAt(0).toUpperCase()
                                    color: "#ffffff"
                                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 130
                                text: modelData
                                color: Theme.label
                                elide: Text.ElideRight
                                font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                            }
                            Button {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData !== BrowserBackend.profileName
                                text: "Open"
                                onClicked: BrowserBackend.openProfile(modelData)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData === BrowserBackend.profileName
                                text: "Current"
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 11 }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.separator }

            Text {
                text: "New Profile"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
            }
            Row {
                width: parent.width
                spacing: 8
                TextField {
                    id: profileNameField
                    width: parent.width - createProfileButton.width - 8
                    placeholder: "Profile Name"
                    text: root.newProfileName
                    onTextChanged: root.newProfileName = text
                    onAccepted: root.createProfile()
                }
                Button {
                    id: createProfileButton
                    text: "Create"
                    prominent: true
                    onClicked: root.createProfile()
                }
            }
        }
    }

    Rectangle {
        id: tabGroupsManager
        z: 65
        visible: root.tabGroupsSheetOpen
        anchors.centerIn: parent
        width: 500
        height: Math.min(480, root.height - 90)
        radius: 22
        color: Theme.dark ? "#fc303034" : "#fff8f8fa"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -14 }
            radius: 30
            color: "#40000000"
            opacity: 0.24
        }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 14

            Row {
                width: parent.width
                Column {
                    width: parent.width - closeGroups.width
                    Text {
                        text: "Tab Groups"
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: 21; weight: Font.DemiBold }
                    }
                    Text {
                        text: "Saved groups keep a reusable set of pages together."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
                BrowserButton {
                    id: closeGroups
                    symbol: "xmark"; tooltip: "Close"
                    onClicked: root.tabGroupsSheetOpen = false
                }
            }

            Flickable {
                width: parent.width
                height: parent.height - 120
                contentHeight: groupsManagerList.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: groupsManagerList
                    width: parent.width
                    spacing: 5

                    Text {
                        visible: root.tabGroups.length === 0
                        width: parent.width
                        topPadding: 18
                        text: "No saved Tab Groups yet."
                        color: Theme.secondaryLabel
                        horizontalAlignment: Text.AlignHCenter
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }

                    Repeater {
                        model: root.tabGroups
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: groupsManagerList.width
                            height: 56
                            radius: 11
                            color: Theme.dark ? "#0dffffff" : "#08000000"
                            border { width: 0.5; color: Theme.separator }

                            Row {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                                spacing: 8
                                Symbol { anchors.verticalCenter: parent.verticalCenter; name: "folder"; tone: "accent"; size: 17 }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - openGroup.width - deleteGroup.width - 72
                                    Text {
                                        width: parent.width
                                        text: modelData.name
                                        color: Theme.label
                                        elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
                                    }
                                    Text {
                                        text: String(modelData.tabs?.length ?? 0) + " tabs"
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: 10 }
                                    }
                                }
                                Button {
                                    id: openGroup
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Open"
                                    onClicked: {
                                        root.openTabGroup(index)
                                        root.tabGroupsSheetOpen = false
                                    }
                                }
                                Button {
                                    id: deleteGroup
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Delete"
                                    destructive: true
                                    onClicked: {
                                        BrowserBackend.removeTabGroup(index)
                                        root.refreshTabGroups()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Button {
                anchors.right: parent.right
                text: "Save Current Tabs…"
                prominent: true
                onClicked: {
                    root.tabGroupsSheetOpen = false
                    root.tabGroupName = ""
                    root.tabGroupEditorOpen = true
                }
            }
        }
    }

    Rectangle {
        id: tabGroupSheet
        z: 65
        visible: root.tabGroupEditorOpen
        anchors.centerIn: parent
        width: 430
        height: 206
        radius: 20
        color: Theme.dark ? "#fc303034" : "#fff7f7f9"
        border { width: 0.5; color: Theme.separator }

        Rectangle {
            z: -1
            anchors { fill: parent; margins: -14 }
            radius: 28
            color: "#40000000"
            opacity: 0.22
        }

        Column {
            anchors { fill: parent; margins: 22 }
            spacing: 14

            Text {
                text: "New Tab Group"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 20; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Save the tabs in this window as a named group you can return to from the sidebar."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            TextField {
                id: tabGroupField
                width: parent.width
                placeholder: "Tab Group Name"
                text: root.tabGroupName
                onTextChanged: root.tabGroupName = text
                onAccepted: root.saveCurrentTabGroup()
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button {
                    text: "Cancel"
                    onClicked: root.tabGroupEditorOpen = false
                }
                Button {
                    text: "Save"
                    prominent: true
                    onClicked: root.saveCurrentTabGroup()
                }
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
    Shortcut { sequence: "Ctrl+F"; onActivated: root.openFind() }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: root.zoomBy(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: root.zoomBy(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: root.zoomBy(0) }
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
            if (root.webContextOpen) root.webContextOpen = false
            else if (root.findOpen) root.closeFind()
            else if (root.readerOpen) root.readerOpen = false
            else if (root.tabOverviewOpen) root.tabOverviewOpen = false
            else if (root.websitePermissionsOpen) root.websitePermissionsOpen = false
            else if (root.privacySheetOpen) root.privacySheetOpen = false
            else if (root.profileSheetOpen) root.profileSheetOpen = false
            else if (root.settingsOpen) root.settingsOpen = false
            else if (root.tabGroupsSheetOpen) root.tabGroupsSheetOpen = false
            else if (root.tabGroupEditorOpen) root.tabGroupEditorOpen = false
            else if (root.pageMenuOpen) root.pageMenuOpen = false
            else if (root.downloadsOpen) root.downloadsOpen = false
            else if (root.pendingPermission) { root.pendingPermission.deny(); root.pendingPermission = null }
            else if (addressField.input.activeFocus) { addressField.input.focus = false; root.syncAddress() }
            else if (root.currentView && root.currentView.loading) root.currentView.stop()
        }
    }
}
