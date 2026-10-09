//@ pragma AppId org.goldengate.Messages
// CitronOS Messages: iMessage and SMS through your iPhone, as Messages on
// the Mac shows them. The iPhone is connected over Bluetooth by BlueFerry
// (github.com/erikwb/blueferry): messages come over MAP, contacts over PBAP,
// and group details from notifications (ANCS). The standard Bluetooth path
// remains text-only. Media has a separate, OPTIONAL BlueBubbles Mac relay;
// FaceTime web links and Jitsi-compatible video calls use a real WebRTC browser.
// Never claim that Bluetooth MAP delivered a photo or an Apple FaceTime call.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import QtQuick.Dialogs
import "lib"
import "lib/theme"
import "messages"

ShellRoot {
    AppWindow {
        id: win
        title: "Messages"
        implicitWidth: Math.min(1040, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(720, (Quickshell.screens[0]?.height ?? 900) - 120)
        minimumSize: Qt.size(720, 480)
        sidebarWidth: app.connected ? 290 : 0
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton {
                visible: app.connected
                round: true
                symbol: "compose"
                onClicked: app.newMessage()
            }
        ]

        toolbarItems: [
            // The conversation's title, centred over the transcript.
            Row {
                visible: app.connected && (!!app.current || app.composing)
                x: win.contentX + (win.width - win.contentX - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Avatar {
                    visible: !!app.current && !app.composing
                    anchors.verticalCenter: parent.verticalCenter
                    size: 24
                    photoPath: app.current?.photo_path || app.current?.contact_photo_path || ""
                    name: app.current ? app.current.name : ""
                    group: !!app.current && app.current.is_group
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: app.composing ? "New Message" : app.current ? app.current.name : ""
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                }
                TapHandler { onTapped: app.showContactCard() }
            },
            ToolbarButton {
                visible: app.connected && !!app.current && !app.composing
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                round: true
                symbol: "info"
                onClicked: app.showContactCard()
            }
        ]

        sidebar: [
            TextField {
                id: search
                width: parent.width
                height: 30
                search: true
                placeholder: "Search"
                input.Keys.onEscapePressed: text = ""
            },
            Flickable {
                y: 40
                width: parent.width
                height: parent.height - 40
                contentHeight: list.height + 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: list
                    width: parent.width
                    spacing: 2

                    // Pinned conversations, as large avatars across the top.
                    Grid {
                        visible: app.pinned.length > 0 && !search.text
                        width: parent.width
                        columns: 3
                        bottomPadding: 6
                        Repeater {
                            model: app.pinned
                            delegate: Item {
                                required property var modelData
                                width: list.width / 3; height: 92
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 2
                                    radius: 12
                                    color: app.currentKey === modelData.key && !app.composing ? Theme.selection : "transparent"
                                }
                                Avatar {
                                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                                    size: 54; name: modelData.name; group: modelData.is_group
                                    photoPath: modelData.photo_path || modelData.contact_photo_path || ""
                                    Rectangle {
                                        visible: modelData.unread
                                        anchors { right: parent.right; top: parent.top }
                                        width: 13; height: 13; radius: 6.5
                                        color: Theme.accentBlue
                                        border { width: 2; color: Theme.sidebarBg }
                                    }
                                }
                                Text {
                                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
                                    width: parent.width - 8
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                }
                                TapHandler {
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onTapped: (p, button) => button === Qt.RightButton
                                        ? app.threadMenu(parent, p.position.x, p.position.y, modelData) : app.open(modelData)
                                }
                            }
                        }
                    }

                    // New Message, while composing.
                    Rectangle {
                        visible: app.composing
                        width: parent.width; height: 64
                        radius: 10
                        color: Theme.accent
                        Row {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Avatar { size: 40; name: app.recipientName || ""; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: app.recipientName ? app.recipientName : "New Message"
                                color: "#ffffff"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                            }
                        }
                    }

                    Repeater {
                        model: app.listed
                        delegate: ConversationRow {
                            required property var modelData
                            width: list.width
                            thread: modelData
                            selected: app.currentKey === modelData.key && !app.composing
                            onClicked: app.open(modelData)
                            onMenuRequested: (item, x, y) => app.threadMenu(item, x, y, modelData)
                        }
                    }

                    Text {
                        visible: app.listed.length === 0 && app.pinned.length === 0 && !app.composing
                        width: parent.width
                        topPadding: 60
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: search.text ? "No Results" : app.loaded ? "No Conversations" : ""
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent

            // ------------------------------------------------------- state
            readonly property bool connected: pairing.configured && bridge.available
            property var threads: []
            property bool loaded: false
            property string currentKey: ""
            readonly property var current: threads.find((t) => t.key === currentKey) ?? null
            property var status: ({})
            property bool composing: false
            property string recipient: ""          // address of a new message
            property string recipientName: ""
            property var suggestions: []
            property bool sending: false
            property string error: ""
            property string mediaPath: ""
            property var mediaInfo: ({})
            property bool mediaReady: false
            property bool mediaSettingsOpen: false
            property string mediaReason: "Media needs a configured iMessage attachment relay."
            property bool faceTimeDialog: false
            property string videoInvite: ""
            property var cardThread: null
            readonly property string mediaHelper: Qt.resolvedUrl("messages/media.py").toString().replace("file://", "")
            readonly property string videoHelper: Qt.resolvedUrl("messages/call-links.py").toString().replace("file://", "")
            property var pendingGroupSend: null
            property bool unlocking: false
            property bool unlockFailed: false
            property bool autoUnlockTried: false

            // Encrypted history lives under a key in the desktop keyring;
            // this asks the keyring to open (it may show its password prompt).
            function unlockStorage() {
                unlocking = true
                bridge.call("unlock_storage", {}, (ok, result) => {
                    unlocking = false
                    const state = ok && result ? result.storage_state : ""
                    if (!ok || (state && state !== "ready")) {
                        unlockFailed = true
                        app.error = ok ? "The keyring didn't unlock" + (result.storage_detail ? " (" + result.storage_detail + ")" : "") + ". You can keep messages without it."
                                       : "Couldn't unlock: " + String(result)
                    } else unlockFailed = false
                    app.refreshStatus(); app.reload()
                })
            }

            readonly property var pinned: threads.filter((t) => t.starred)
            readonly property var listed: {
                const q = search.text.trim().toLowerCase()
                return threads.filter((t) => q ? (t.name.toLowerCase().includes(q)
                        || (t.messages || []).some((m) => String(m.body).toLowerCase().includes(q)))
                    : !t.starred)
            }
            readonly property string phoneState: !status.daemon ? "starting"
                : status.storage_state === "locked" ? "locked"
                : status.map_connection_refused ? "busy"
                : status.map ? "connected" : "connecting"

            function reload() {
                bridge.call("threads", { limit: 200 }, (ok, result) => {
                    if (!ok) { app.loaded = true; return }
                    app.threads = (result || []).slice().sort((a, b) => String(b.last_ts).localeCompare(String(a.last_ts)))
                    app.loaded = true
                    // Like Messages, open on the most recent conversation.
                    if (!app.currentKey && !app.composing && app.threads.length) app.currentKey = app.threads[0].key
                    if (app.current && app.current.unread && win.active) app.markRead(app.current)
                })
            }
            function refreshStatus() {
                bridge.call("status", {}, (ok, s) => {
                    if (!ok) return
                    app.status = s || {}
                    // Opening Messages is the moment to open the keyring, as
                    // BlueFerry's own app does: the first time, this creates the
                    // history key; with the login keyring already open it's silent.
                    if (app.status.storage_state === "locked" && !app.autoUnlockTried) {
                        app.autoUnlockTried = true
                        app.unlockStorage()
                    }
                })
            }
            function open(thread) {
                composing = false
                currentKey = thread.key
                mediaPath = ""
                mediaInfo = ({})
                draft.text = ""
                if (thread.unread) markRead(thread)
                Qt.callLater(() => draft.input.forceActiveFocus())
            }
            function markRead(thread) { bridge.call("mark_thread_read", { thread_key: thread.key }, () => app.reload()) }
            function newMessage() {
                composing = true
                mediaPath = ""
                mediaInfo = ({})
                recipient = ""; recipientName = ""
                to.text = ""
                suggestions = []
                Qt.callLater(() => to.input.forceActiveFocus())
            }
            function chooseRecipient(name, address) {
                recipient = address
                recipientName = name || address
                to.text = recipientName
                suggestions = []
                Qt.callLater(() => draft.input.forceActiveFocus())
            }
            function directAddress(t) {
                if (!t || t.is_group) return ""
                const list = t.recipients || []
                if (list.length === 1) return String(list[0])
                const ms = (t.messages || []).slice().reverse()
                const incoming = ms.find((m) => !m.outgoing && !!m.handle)
                return String(incoming?.handle || t.reply_address || t.reply_to || t.address || "")
            }
            function showContactCard(thread) {
                cardThread = thread || current
                if (!cardThread) return
                details.address = directAddress(cardThread)
                details.contact = cardThread
                details.shown = true
            }
            function pickMedia() { if (!sending) attachmentPicker.open() }
            function attach(path) {
                mediaPath = path
                mediaInfo = ({})
                inspectMedia.command = ["python3", mediaHelper, "inspect", path]
                inspectMedia.running = true
            }
            function sendMedia() {
                const t = current
                const address = composing ? (recipient || to.text.trim()) : directAddress(t)
                if (!address || (!composing && t?.is_group)) {
                    error = "Choose one contact's phone number or email. Group media is not supported yet."
                    return
                }
                if (!mediaReady) {
                    error = mediaReason + " Your photo or video has not been sent."
                    return
                }
                sending = true
                mediaSender.command = ["python3", mediaHelper, "send", mediaPath, address, draft.text.trim()]
                mediaSender.running = true
            }
            function createVideoCall() {
                callHelper.command = ["python3", videoHelper, "create"]
                callHelper.running = true
            }
            function joinFaceTimeLink() {
                callHelper.command = ["python3", videoHelper, "join", faceTimeInput.text.trim()]
                callHelper.running = true
            }
            function send() {
                const body = draft.text.trim()
                if ((!body && !mediaPath) || sending) return
                if (mediaPath) { sendMedia(); return }
                if (composing) {
                    const address = recipient || to.text.trim()
                    if (!address) return
                    sending = true
                    bridge.call("send", { recipient: address, body: body }, (ok, result) => {
                        app.sending = false
                        if (!ok) { app.error = result; return }
                        draft.text = ""
                        app.composing = false
                        app.reload()
                    })
                    return
                }
                const t = current
                if (!t || !t.reply_ready) return
                // The first reply to a group says who it goes to, as BlueFerry
                // can only address a group by its member list.
                if (t.is_group && !t.group_confirmed && !pendingGroupSend) {
                    pendingGroupSend = { key: t.key, body: body, token: t.confirmation_token || "" }
                    return
                }
                sendToThread(t.key, body, t.confirmation_token || "", false)
            }
            function sendToThread(key, body, token, confirm) {
                sending = true
                bridge.call("send_to_thread", { thread_key: key, body: body, confirm_group: confirm, expected_group_token: token }, (ok, result) => {
                    app.sending = false
                    if (!ok) { app.error = result; return }
                    draft.text = ""
                    app.reload()
                })
            }
            function threadMenu(item, x, y, thread) {
                const t = thread || current
                if (!t) return
                menu.popup(item, x, y, [
                    { text: t.starred ? "Unpin" : "Pin", action: () => bridge.call("set_thread_starred", { thread_key: t.key, starred: !t.starred }, () => app.reload()) },
                    { text: "Mark as Read", enabled: !!t.unread, action: () => app.markRead(t) },
                    { text: "Contact Info", action: () => app.showContactCard(t) },
                    { text: "Media Relay Settings…", action: () => app.mediaSettingsOpen = true },
                    { text: "Start Video Meeting", action: () => app.createVideoCall() },
                    { text: "Join FaceTime Link…", action: () => app.faceTimeDialog = true },
                    { separator: true },
                    { text: "Delete Conversation…", destructive: true, action: () => app.confirmDelete = t }
                ])
            }
            property var confirmDelete: null
            function copy(text) { Quickshell.execDetached(["wl-copy", "--", String(text)]) }

            // Times as Messages shows them: the time today, "Yesterday", the
            // weekday this week, else the date.
            function listTime(iso) {
                const d = new Date(iso); if (isNaN(d)) return ""
                const now = new Date(), day = 86400000
                const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
                if (d.getTime() >= start) return Qt.formatTime(d, "h:mm AP")
                if (d.getTime() >= start - day) return "Yesterday"
                if (d.getTime() >= start - 6 * day) return Qt.formatDate(d, "dddd")
                return Qt.formatDate(d, "M/d/yy")
            }
            function separatorTime(iso) {
                const d = new Date(iso); if (isNaN(d)) return ""
                const label = listTime(iso)
                return label === Qt.formatTime(d, "h:mm AP") ? "Today " + label
                    : label.includes("/") ? Qt.formatDate(d, "ddd, MMM d") + " at " + Qt.formatTime(d, "h:mm AP")
                    : label + " " + Qt.formatTime(d, "h:mm AP")
            }

            FileDialog {
                id: attachmentPicker
                title: "Add Photos or Videos"
                fileMode: FileDialog.OpenFile
                nameFilters: ["Photos and Videos (*.jpg *.jpeg *.png *.gif *.heic *.webp *.mp4 *.mov *.m4v *.webm)"]
                onAccepted: app.attach(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")))
            }
            Process {
                id: mediaStatus
                running: true
                command: ["python3", app.mediaHelper, "status"]
                stdout: StdioCollector { id: mediaStatusOut }
                onExited: {
                    try {
                        const r = JSON.parse(mediaStatusOut.text)
                        app.mediaReady = !!r.ok && !!r.ready
                        app.mediaReason = r.reason || r.error || "Configure the iMessage media relay before sending."
                    } catch (e) { app.mediaReady = false }
                }
            }
            Process {
                id: saveMediaSettings
                command: ["python3", app.mediaHelper, "configure"]
                stdinEnabled: true
                stdout: StdioCollector { id: mediaConfigOut }
                onStarted: {
                    write(JSON.stringify({url: mediaServer.text.trim(), password: mediaPassword.text}))
                    stdinEnabled = false
                }
                onExited: (code) => {
                    stdinEnabled = true
                    try {
                        const r = JSON.parse(mediaConfigOut.text)
                        if (code !== 0 || !r.ok) {
                            app.error = r.error || "Cannot save media relay settings."
                            return
                        }
                        app.mediaReady = true
                        app.mediaSettingsOpen = false
                        mediaPassword.text = ""
                        app.error = "Media relay configured. Attachments can now be submitted through your Mac."
                    } catch (e) { app.error = "Media relay settings could not be saved." }
                }
            }
            Process {
                id: inspectMedia
                stdout: StdioCollector { id: inspectedMediaOut }
                onExited: (code) => {
                    try {
                        const r = JSON.parse(inspectedMediaOut.text)
                        if (!r.ok) { app.error = r.error; app.mediaPath = ""; return }
                        app.mediaInfo = r
                    } catch (e) { app.error = "Could not inspect the selected attachment."; app.mediaPath = "" }
                }
            }
            Process {
                id: mediaSender
                stdout: StdioCollector { id: mediaSendOut }
                onExited: (code) => {
                    app.sending = false
                    try {
                        const r = JSON.parse(mediaSendOut.text)
                        if (code !== 0 || !r.ok) { app.error = r.error || "The relay rejected the attachment."; return }
                        app.mediaPath = ""; app.mediaInfo = ({})
                        draft.text = ""
                        app.error = "Media accepted by BlueBubbles. Final delivery depends on Apple Messages; it may not appear in BlueFerry history."
                        app.composing = false
                    } catch (e) { app.error = "The media relay did not confirm the transfer." }
                }
            }
            Process {
                id: callHelper
                stdout: StdioCollector { id: callOutput }
                onExited: (code) => {
                    try {
                        const r = JSON.parse(callOutput.text)
                        if (code !== 0 || !r.ok) { app.error = r.error || "Could not open this call."; return }
                        app.faceTimeDialog = false
                        Quickshell.execDetached(["gg-web", r.url])
                        if (r.type === "webrtc") {
                            draft.text = "Join my video call: " + r.url
                            app.error = "Video meeting opened. Send the invitation to your contact when ready."
                        }
                    } catch (e) { app.error = "Could not create a valid video call link." }
                }
            }
            Bridge {
                id: bridge
                onEvent: (name, data) => {
                    if (name === "history-changed") app.reload()
                    else if (name === "status-changed") app.refreshStatus()
                    // A notification was clicked: show the conversation it's from.
                    else if (name === "open-message") {
                        const t = app.threads.find((th) => (th.messages || []).some((m) => m.handle === data))
                        if (t) app.open(t)
                    }
                }
                onFailed: (message) => app.error = message
            }
            Pairing {
                id: pairing
                onPaired: { app.reload(); app.refreshStatus() }
                onForgotten: { app.threads = []; app.currentKey = "" }
            }
            // Probe the optional BlueFerry bridge first. Launching its CLI
            // before availability is known leaves two failed Process jobs
            // pending on machines without BlueFerry and can appear as a
            // permanently blank/loading Messages window.
            Connections {
                target: bridge
                function onCheckedChanged() {
                    if (bridge.checked && bridge.available) pairing.start()
                }
            }
            Component.onCompleted: { app.reload(); app.refreshStatus() }
            Timer { interval: 15000; running: app.connected; repeat: true; onTriggered: app.refreshStatus() }
            Timer {
                id: suggest
                interval: 180
                onTriggered: bridge.call("contacts", { query: to.text.trim() }, (ok, r) => {
                    if (ok && app.composing && !app.recipient) app.suggestions = (r || []).slice(0, 8)
                })
            }

            Rectangle { anchors.fill: parent; color: Theme.contentBg }

            // --------------------------------------------- connect an iPhone
            Onboarding {
                visible: !app.connected
                anchors.fill: parent
                pairing: pairing
                installed: bridge.available || !bridge.checked
            }

            // ------------------------------------------------- the iPhone
            // A thin bar while the phone isn't reachable; sending waits for it.
            Rectangle {
                id: phoneBar
                visible: app.connected && app.phoneState !== "connected"
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: win.toolbarHeight }
                height: visible ? 30 : 0
                color: Theme.dark ? "#2a2a2c" : "#f2f2f4"
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Symbol { name: "phone"; size: 12; tone: "gray"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: app.phoneState === "busy" ? "Your iPhone is connected to another computer. Messages will reconnect when it's free."
                            : app.phoneState === "locked" ? "Your messages are locked."
                            : app.phoneState === "starting" ? "Starting…"
                            : "Connecting to your iPhone… Keep it nearby with Bluetooth on."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Button {
                        visible: app.phoneState === "locked"
                        height: 20
                        text: app.unlocking ? "Unlocking…" : "Unlock"
                        enabled: !app.unlocking
                        onClicked: app.unlockStorage()
                    }
                    // No keyring to open (or it refused): keep messages in a
                    // private file in your home folder instead.
                    Button {
                        visible: app.phoneState === "locked" && app.unlockFailed
                        height: 20
                        text: "Keep Without Keyring"
                        onClicked: bridge.call("set_storage_policy", { policy: "plaintext" }, (ok, result) => {
                            if (!ok) app.error = String(result)
                            app.unlockFailed = false
                            app.refreshStatus(); app.reload()
                        })
                    }
                }
            }

            // ------------------------------------------------ new message
            Item {
                id: toBar
                visible: app.connected && app.composing
                anchors { left: parent.left; right: parent.right; top: phoneBar.bottom; topMargin: phoneBar.visible ? 0 : win.toolbarHeight }
                height: 40
                Text {
                    id: toLabel
                    anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                    text: "To:"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                }
                TextField {
                    id: to
                    anchors { left: toLabel.right; leftMargin: 6; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                    bare: true
                    placeholder: "Name, phone number or email"
                    onTextChanged: {
                        if (app.recipientName && text !== app.recipientName) { app.recipient = ""; app.recipientName = "" }
                        if (!app.recipient && text.trim().length >= 2) suggest.restart(); else app.suggestions = []
                    }
                    onAccepted: if (app.suggestions.length) app.chooseRecipient(app.suggestions[0].name, app.suggestions[0].address)
                        else Qt.callLater(() => draft.input.forceActiveFocus())
                }
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
            }

            // ------------------------------------------------- transcript
            ListView {
                id: transcript
                visible: app.connected && !!app.current && !app.composing
                anchors {
                    left: parent.left; right: parent.right; top: toBar.visible ? toBar.bottom : phoneBar.visible ? phoneBar.bottom : parent.top
                    topMargin: toBar.visible || phoneBar.visible ? 0 : win.toolbarHeight
                    bottom: composer.top
                    leftMargin: 14; rightMargin: 14
                }
                clip: true
                // Newest at the bottom, and the view starts there.
                verticalLayoutDirection: ListView.BottomToTop
                spacing: 0
                model: app.current ? (app.current.messages || []).slice().reverse() : []
                delegate: Bubble {
                    required property var modelData
                    required property int index
                    width: transcript.width
                    message: modelData
                    // Neighbours in time order (the list is reversed).
                    readonly property var older: transcript.model[index + 1] ?? null
                    readonly property var newer: transcript.model[index - 1] ?? null
                    group: !!app.current && app.current.is_group
                    separator: !older || (new Date(modelData.timestamp) - new Date(older.timestamp)) > 15 * 60000
                        ? app.separatorTime(modelData.timestamp) : ""
                    firstInRun: !older || older.outgoing !== modelData.outgoing || older.sender !== modelData.sender || !!separator
                    lastInRun: !newer || newer.outgoing !== modelData.outgoing || newer.sender !== modelData.sender
                        || (new Date(newer.timestamp) - new Date(modelData.timestamp)) > 15 * 60000
                    footnote: index === 0 && modelData.outgoing ? "Sent" : ""
                    onMenuRequested: (target, x, y) => menu.popup(target, x, y, [
                        { text: "Copy", action: () => app.copy(modelData.body) }
                    ])
                }
            }
            Scroller { flickable: transcript }

            // Suggestions for the To: field.
            Rectangle {
                visible: app.composing && app.suggestions.length > 0
                anchors { left: toBar.left; leftMargin: 44; top: toBar.bottom }
                width: 320
                height: suggestionColumn.height + 10
                radius: 10
                color: Theme.dark ? "#2c2c2e" : "#ffffff"
                border { width: 0.5; color: Theme.separator }
                z: 5
                Column {
                    id: suggestionColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
                    Repeater {
                        model: app.suggestions
                        delegate: Rectangle {
                            required property var modelData
                            width: suggestionColumn.width; height: 40; radius: 7
                            color: pick.hovered ? Theme.accent : "transparent"
                            Row {
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 9
                                Avatar { size: 28; name: modelData.name; photoPath: modelData.photo_path || ""; anchors.verticalCenter: parent.verticalCenter }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { text: modelData.name; color: pick.hovered ? "#ffffff" : Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } }
                                    Text { text: modelData.address; color: pick.hovered ? "#d9ffffff" : Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                                }
                            }
                            HoverHandler { id: pick }
                            TapHandler { onTapped: app.chooseRecipient(modelData.name, modelData.address) }
                        }
                    }
                }
            }

            Text {
                visible: app.connected && !app.current && !app.composing
                anchors.centerIn: parent
                text: app.threads.length ? "" : "Messages you send and receive on your iPhone appear here."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }

            // ---------------------------------------------------- composer
            Item {
                id: composer
                visible: app.connected && (!!app.current || app.composing)
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: visible ? Math.max(54, draftBox.height + (app.mediaPath ? 80 : 0) + 20) : 0
                readonly property bool canReply: app.composing ? !!(app.recipient || to.text.trim()) : !!app.current && app.current.reply_ready

                Text {
                    visible: !app.composing && !!app.current && !app.current.reply_ready
                    anchors.centerIn: parent
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Reply to this group from your iPhone. Your iPhone doesn't say who's in it."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
                Glass {
                    id: draftBox
                    visible: app.composing || (!!app.current && app.current.reply_ready)
                    role: "control"
                    anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    height: Math.min(120, Math.max(34, draft.input.contentHeight + 16))
                    anchors.verticalCenter: undefined
                    anchors { bottom: parent.bottom; bottomMargin: 10 }
                    radius: 17
                    ToolbarButton {
                        id: attachButton
                        anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
                        symbol: "plus"
                        round: true
                        enabled: !app.sending
                        onClicked: app.pickMedia()
                        Accessible.name: "Add photo or video"
                    }
                    TextField {
                        id: draft
                        anchors { left: attachButton.right; leftMargin: 4; right: sendButton.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        bare: true
                        placeholder: app.composing ? "Message" : "iMessage"
                        input.wrapMode: TextInput.Wrap
                        enabled: composer.canReply && !app.sending
                        onAccepted: app.send()
                    }
                    // The send arrow appears once there's something to send.
                    Rectangle {
                        id: sendButton
                        anchors { right: parent.right; rightMargin: 4; bottom: parent.bottom; bottomMargin: 4 }
                        width: 26; height: 26; radius: 13
                        color: Theme.accentBlue
                        scale: draft.text.trim() || app.mediaPath ? 1 : 0
                        Behavior on scale { Spring { spring: Theme.snappy } }
                        Symbol { anchors.centerIn: parent; name: "arrow-up"; size: 13; tone: "white" }
                        TapHandler { onTapped: app.send() }
                    }
                }
                Rectangle {
                    id: mediaPreview
                    visible: !!app.mediaPath
                    anchors { left: draftBox.left; right: draftBox.right; bottom: draftBox.top; bottomMargin: 8 }
                    height: 66
                    radius: 14
                    color: Theme.fill
                    border.color: Theme.separator
                    clip: true
                    Image {
                        id: selectedImage
                        visible: app.mediaInfo.type === "image"
                        x: 6; y: 6; width: 54; height: 54
                        source: visible && app.mediaPath ? "file://" + app.mediaPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 160; sourceSize.height: 160
                    }
                    Symbol {
                        visible: app.mediaInfo.type !== "image"
                        x: 15; y: 18; name: "film"; size: 27; tone: "gray"
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: 68; right: removeMedia.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 3
                        Text {
                            width: parent.width
                            text: app.mediaInfo.name || app.mediaPath.split("/").pop()
                            elide: Text.ElideMiddle
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                        }
                        Text {
                            text: !app.mediaReady ? "Media relay not configured — tap Setup" :
                                app.mediaInfo.type === "video" ? "Video attachment" : "Photo attachment"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                    }
                    Button {
                        visible: !app.mediaReady
                        anchors { right: removeMedia.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        text: "Setup"
                        onClicked: app.mediaSettingsOpen = true
                    }
                    ToolbarButton {
                        id: removeMedia
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        symbol: "xmark"; round: true
                        onClicked: { app.mediaPath = ""; app.mediaInfo = ({}) }
                    }
                }
            }

            // -------------------------------------------- confirmations
            Sheet {
                visible: !!app.pendingGroupSend
                title: "Send to This Group?"
                text: app.current ? "This reply goes to " + (app.current.recipients || []).join(", ") + ", the people your iPhone listed for this group." : ""
                confirmText: "Send"
                onConfirmed: {
                    const p = app.pendingGroupSend
                    app.pendingGroupSend = null
                    app.sendToThread(p.key, p.body, p.token, true)
                }
                onCancelled: app.pendingGroupSend = null
            }
            Sheet {
                visible: !!app.confirmDelete
                title: "Delete This Conversation?"
                text: "It's deleted from this computer only; it stays on your iPhone."
                confirmText: "Delete"
                destructive: true
                onConfirmed: {
                    const t = app.confirmDelete
                    app.confirmDelete = null
                    if (app.currentKey === t.key) app.currentKey = ""
                    bridge.call("delete_threads", { thread_keys: [t.key] }, () => app.reload())
                }
                onCancelled: app.confirmDelete = null
            }

            ContactCard {
                id: details
                anchors.fill: parent
                onMessageRequested: { if (app.current) app.open(app.current); else app.newMessage() }
                onVideoRequested: app.createVideoCall()
                onFaceTimeRequested: {
                    app.faceTimeDialog = true
                    Qt.callLater(() => faceTimeInput.input.forceActiveFocus())
                }
                onCopyRequested: (value) => app.copy(value)
            }

            Item {
                visible: app.faceTimeDialog
                anchors.fill: parent
                z: 80
                Rectangle {
                    anchors.fill: parent
                    color: "#66000000"
                    TapHandler { onTapped: app.faceTimeDialog = false }
                }
                Glass {
                    anchors.centerIn: parent
                    role: "menu"
                    width: Math.min(390, parent.width - 32)
                    height: 205
                    radius: 24
                    Column {
                        anchors { fill: parent; margins: 22 }
                        spacing: 12
                        Text {
                            text: "Join a FaceTime Call"
                            color: Theme.label
                            font { family: Theme.fontDisplay; pixelSize: Theme.fs(19); weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Paste an invitation made on an Apple device. The host must admit you."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        TextField {
                            id: faceTimeInput
                            width: parent.width
                            placeholder: "https://facetime.apple.com/…"
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Button { text: "Cancel"; onClicked: app.faceTimeDialog = false }
                            Button {
                                text: "Join in Web"
                                prominent: true
                                enabled: faceTimeInput.text.trim() !== ""
                                onClicked: app.joinFaceTimeLink()
                            }
                        }
                    }
                }
            }

            Item {
                visible: app.mediaSettingsOpen
                anchors.fill: parent
                z: 82
                Rectangle {
                    anchors.fill: parent
                    color: "#66000000"
                    TapHandler { onTapped: app.mediaSettingsOpen = false }
                }
                Glass {
                    anchors.centerIn: parent
                    role: "menu"
                    width: Math.min(420, parent.width - 36)
                    height: 305
                    radius: 24
                    Column {
                        anchors { fill: parent; margins: 22 }
                        spacing: 11
                        Text {
                            text: "iMessage Media Relay"
                            color: Theme.label
                            font { family: Theme.fontDisplay; pixelSize: Theme.fs(20); weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "BlueFerry cannot send photo or video attachments. To enable them, connect a BlueBubbles server on a Mac you control. Your photo/video is uploaded to that Mac."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                        Text {
                            text: "Server URL (HTTPS)"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                        TextField {
                            id: mediaServer
                            width: parent.width
                            placeholder: "https://your-mac.example"
                        }
                        Text {
                            text: "Server Password"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                        TextField {
                            id: mediaPassword
                            width: parent.width
                            password: true
                            placeholder: "BlueBubbles API password"
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Button { text: "Cancel"; onClicked: app.mediaSettingsOpen = false }
                            Button {
                                text: "Save Relay"
                                prominent: true
                                enabled: mediaServer.text.trim() !== "" && mediaPassword.text !== "" && !saveMediaSettings.running
                                onClicked: saveMediaSettings.running = true
                            }
                        }
                    }
                }
            }

            // Errors appear briefly over the composer.
            Glass {
                visible: !!app.error
                role: "menu"
                anchors { horizontalCenter: composer.horizontalCenter; bottom: composer.top; bottomMargin: 8 }
                width: Math.min(460, parent.width - 40)
                height: errorText.implicitHeight + 20
                radius: 14
                Text {
                    id: errorText
                    anchors.centerIn: parent
                    width: parent.width - 28
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: app.error
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Timer { running: parent.visible; interval: 6000; onTriggered: app.error = "" }
            }
        }

        PopupMenu { id: menu; parent: win.overlay }
    }
}
