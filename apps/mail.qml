//@ pragma AppId org.goldengate.Mail
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Mail"
        closeAction: () => mail.requestClose()
        implicitWidth: Math.min(1100, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(730, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(760, 500)
        property bool sidebarShown: true
        sidebarWidth: mail.configured && sidebarShown ? 205 : 0
        fullSizeContent: false
        background: Theme.contentBg

        // A system Mail toolbar: controls stay clear of the traffic lights
        // even while the sidebar's presentation width is animating.
        toolbarSidebar: [
            ToolbarButton {
                visible: mail.configured
                round: true; symbol: "sidebar"; checked: win.sidebarShown
                Accessible.name: win.sidebarShown ? "Hide Mailboxes" : "Show Mailboxes"
                onClicked: win.sidebarShown = !win.sidebarShown
            },
            ToolbarButton {
                visible: mail.configured
                round: true; symbol: "compose"
                Accessible.name: "New Message"
                onClicked: { mail.composing = true; mail.selectedFolder = "drafts" }
            }
        ]

        toolbarItems: [
            Row {
                visible: mail.configured
                x: Math.max(win.contentX + 14, win.toolbarLeadingEnd)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                ToolbarPill {
                    visible: mail.compactReading && !!mail.selectedUid && !mail.composing
                    ToolbarButton {
                        symbol: "chevron-left"
                        text: "Inbox"
                        onClicked: mail.selectedUid = ""
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: mail.composing ? "New Message" :
                          mail.selectedFolder === "drafts" ? "Drafts" : "Inbox"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
                }
            },
            Row {
                visible: mail.configured
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                spacing: 8
                ToolbarButton {
                    round: true; symbol: "arrow-clockwise"
                    enabled: !mail.loading && !mail.sending && !mail.composing
                    Accessible.name: "Check for Mail"
                    onClicked: mail.refresh()
                }
                TextField {
                    id: mailSearch
                    visible: !mail.composing
                    width: Math.max(112, Math.min(220, win.width * 0.20))
                    height: 32; search: true
                    placeholder: "Search Mail"
                    text: mail.query
                    onTextChanged: mail.query = text
                }
            }
        ]

        sidebar: [
            Column {
                width: parent.width
                spacing: 6
                Text {
                    x: 12; width: parent.width - 24; height: 25
                    verticalAlignment: Text.AlignBottom
                    text: "FAVORITES"; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold; letterSpacing: 0.7 }
                }
                SidebarRow {
                    width: parent.width; text: "Inbox"; symbol: "tray"
                    selected: mail.selectedFolder === "inbox" && !mail.composing
                    badge: mail.unreadCount ? String(mail.unreadCount) : ""
                    onClicked: { mail.selectedFolder = "inbox"; mail.composing = false }
                }
                SidebarRow {
                    width: parent.width; text: "Drafts"; symbol: "doc"
                    selected: mail.selectedFolder === "drafts" || mail.composing
                    badge: mail.hasDraft ? "1" : ""
                    onClicked: {
                        mail.selectedFolder = "drafts"
                        mail.composing = false
                        mail.selectedUid = ""
                    }
                }
                Rectangle {
                    width: parent.width - 20; x: 10; height: 1
                    color: Theme.separator
                }
                Text {
                    x: 12; width: parent.width - 24; height: 24
                    verticalAlignment: Text.AlignBottom
                    text: "ACCOUNTS"; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold; letterSpacing: 0.7 }
                }
                SidebarRow {
                    width: parent.width
                    text: mail.account || "Mail Account"
                    symbol: "envelope"
                    selected: false
                    onClicked: { mail.selectedFolder = "inbox"; mail.composing = false }
                }
            }
        ]

        Item {
            id: mail
            objectName: "mailApp"
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("mail/helper.py").toString().replace("file://", "")
            property bool configured: false
            property string account: ""
            property bool loading: false
            property bool sending: false
            property bool composing: false
            property string selectedFolder: "inbox"
            property string query: ""
            property bool unreadOnly: false
            property real preferredListWidth: 336
            readonly property bool compactReading: width < 700
            property string queuedUid: ""
            readonly property var filteredMessages: {
                const q = query.trim().toLocaleLowerCase()
                return messages.filter((m) => {
                    if (unreadOnly && !m.unread) return false
                    return !q || [m.from, m.subject, m.date].some((value) =>
                        String(value || "").toLocaleLowerCase().includes(q))
                })
            }
            function senderName(sender) {
                const text = String(sender || "Unknown Sender")
                return text.replace(/\\s*<[^>]+>\\s*$/, "").replace(/^"|"$/g, "").trim() || text
            }
            function address(sender) {
                const text = String(sender || "")
                const tagged = /<([^>]+@[^>]+)>/.exec(text)
                return tagged ? tagged[1] : /[^\\s<>]+@[^\\s<>]+/.exec(text)?.[0] || ""
            }
            function initials(sender) {
                const parts = senderName(sender).split(/\\s+/).filter(Boolean)
                return (parts.length > 1 ? parts[0][0] + parts[parts.length - 1][0]
                    : (parts[0] || "?").slice(0, 2)).toUpperCase()
            }
            function conciseDate(value) {
                const date = new Date(String(value || ""))
                if (!Number.isFinite(date.getTime())) return String(value || "").slice(0, 18)
                const now = new Date()
                if (date.toDateString() === now.toDateString())
                    return Qt.formatDateTime(date, "h:mm AP")
                if (date.getFullYear() === now.getFullYear())
                    return Qt.formatDateTime(date, "MMM d")
                return Qt.formatDateTime(date, "MMM d, yyyy")
            }
            function forward() {
                if (!selectedMessage.uid) return
                composeTo = ""
                composeSubject = /^fwd?:/i.test(selectedMessage.subject || "") ?
                    selectedMessage.subject : "Fwd: " + (selectedMessage.subject || "")
                composeBody = "\\n\\n---------- Forwarded message ----------\\n" +
                    "From: " + (selectedMessage.from || "") + "\\n" +
                    "Date: " + (selectedMessage.date || "") + "\\n" +
                    "Subject: " + (selectedMessage.subject || "") + "\\n\\n" +
                    (selectedMessage.body || "")
                selectedFolder = "drafts"
                composing = true
            }
            function reply() {
                if (!selectedMessage.uid) return
                composeTo = address(selectedMessage.from)
                composeSubject = /^re:/i.test(selectedMessage.subject || "") ?
                    selectedMessage.subject : "Re: " + (selectedMessage.subject || "")
                composeBody = "\\n\\nOn " + (selectedMessage.date || "an earlier date") +
                    ", " + (selectedMessage.from || "someone") + " wrote:\\n" +
                    String(selectedMessage.body || "").split("\\n").map((line) => "> " + line).join("\\n")
                selectedFolder = "drafts"
                composing = true
            }
            readonly property bool hasDraft: !!(composeTo || composeSubject || composeBody)
            property string error: ""
            property var messages: []
            property string selectedUid: ""
            property var selectedMessage: ({})
            readonly property int unreadCount: messages.filter((m) => m.unread).length

            property string setupEmail: ""
            property string setupUsername: ""
            property string imapHost: ""
            property string imapPort: "993"
            property int imapSecurity: 0
            property string smtpHost: ""
            property string smtpPort: "465"
            property int smtpSecurity: 0
            property string setupPassword: ""

            property string composeTo: ""
            property string composeSubject: ""
            property string composeBody: ""
            property bool draftReady: false
            property bool closing: false
            property string draftSaved: ""
            property string draftPending: ""
            readonly property string draftText: JSON.stringify({ to: composeTo, subject: composeSubject, body: composeBody })
            onDraftTextChanged: if (draftReady) draftDebounce.restart()
            function requestClose() {
                if (sending) { error = "Wait for your message to finish sending before closing Mail."; return }
                if (!draftReady) {
                    if (!composeTo && !composeSubject && !composeBody) { Qt.quit(); return }
                    error = "Mail hasn't restored your draft yet. Resolve the draft error before closing."; return
                }
                closing = true; draftDebounce.stop()
                saveDraft()
            }
            function saveDraft() {
                if (!draftReady || draftWriter.running) return
                if (draftText === draftSaved) { if (closing) Qt.quit(); return }
                draftPending = draftText
                draftWriter.running = true
            }
            Timer { id: draftDebounce; interval: 500; onTriggered: mail.saveDraft() }
            Process {
                id: draftReader
                running: true
                command: ["python3", mail.helper, "draft-load"]
                stdout: StdioCollector { id: draftReadOut }
                onExited: (code) => {
                    try {
                        const r = JSON.parse(draftReadOut.text)
                        if (!r.ok) { mail.error = r.error; return }
                        mail.composeTo = r.draft.to; mail.composeSubject = r.draft.subject; mail.composeBody = r.draft.body
                        mail.draftSaved = mail.draftText; mail.draftReady = true
                        if (mail.composeTo || mail.composeSubject || mail.composeBody) mail.composing = true
                    } catch (e) { mail.error = "Mail couldn't restore your draft. It was left untouched." }
                }
            }
            Process {
                id: draftWriter
                command: ["python3", mail.helper, "draft-save"]
                stdinEnabled: true
                stdout: StdioCollector { id: draftWriteOut }
                onStarted: { write(mail.draftPending); stdinEnabled = false }
                onExited: (code) => {
                    stdinEnabled = true
                    let r = ({})
                    try { r = JSON.parse(draftWriteOut.text) } catch (e) {}
                    if (code !== 0 || !r.ok) {
                        mail.error = r.error || "Your draft couldn't be saved. Mail was kept open; try again."
                        mail.closing = false
                        return
                    }
                    mail.draftSaved = mail.draftPending
                    Qt.callLater(() => mail.saveDraft())
                }
            }

            // What the provider wants instead of the account password, said
            // before Connect rather than after the server turns it down.
            readonly property string setupDomain: setupEmail.includes("@") ? setupEmail.split("@").pop().toLowerCase() : ""
            readonly property string passwordHint: ["gmail.com", "googlemail.com"].includes(setupDomain)
                ? "Gmail needs an app password, not your Google password: turn on 2-Step Verification, then make one at myaccount.google.com/apppasswords."
                : ["icloud.com", "me.com", "mac.com"].includes(setupDomain)
                ? "iCloud Mail needs an app-specific password: make one at account.apple.com, under Sign-In and Security."
                : ["yahoo.com", "ymail.com", "aol.com"].includes(setupDomain)
                ? "This account needs an app password: make one under Account Security › Generate app password."
                : ["outlook.com", "hotmail.com", "live.com", "msn.com"].includes(setupDomain)
                ? "Microsoft accounts only sign in through Microsoft's own page, which Mail doesn't have yet."
                : ""
            // Servers filled in for a known provider as the address is typed
            // (they were only filled by the button), unless typed by hand.
            property bool serversTyped: false
            onSetupDomainChanged: if (!serversTyped) inferServers()
            function inferServers() {
                const domain = setupEmail.split("@").pop().toLowerCase()
                if (domain === "gmail.com" || domain === "googlemail.com") {
                    imapHost = "imap.gmail.com"; imapPort = "993"; imapSecurity = 0
                    smtpHost = "smtp.gmail.com"; smtpPort = "465"; smtpSecurity = 0
                } else if (["outlook.com", "hotmail.com", "live.com", "office365.com"].includes(domain)) {
                    imapHost = "outlook.office365.com"; imapPort = "993"; imapSecurity = 0
                    smtpHost = "smtp.office365.com"; smtpPort = "587"; smtpSecurity = 1
                } else if (["icloud.com", "me.com", "mac.com"].includes(domain)) {
                    imapHost = "imap.mail.me.com"; imapPort = "993"; imapSecurity = 0
                    smtpHost = "smtp.mail.me.com"; smtpPort = "587"; smtpSecurity = 1
                } else if (domain === "yahoo.com") {
                    imapHost = "imap.mail.yahoo.com"; imapPort = "993"; imapSecurity = 0
                    smtpHost = "smtp.mail.yahoo.com"; smtpPort = "465"; smtpSecurity = 0
                }
                if (!setupUsername)
                    setupUsername = setupEmail
            }

            function status() {
                statusProc.running = true
            }

            function refresh() {
                if (!configured || loading || listProc.running)
                    return
                loading = true
                error = ""
                listProc.running = true
            }

            function read(uid) {
                if (!uid) return
                selectedUid = uid
                if (selectedMessage.uid !== uid) selectedMessage = ({})
                if (readProc.running) {
                    queuedUid = uid
                    return
                }
                readProc.command = ["python3", helper, "read", uid]
                readProc.running = true
            }

            function setupAccount() {
                if (setupProc.running)
                    return
                error = ""
                setupProc.stdinEnabled = true
                setupProc.running = true
            }

            function send() {
                if (sending || !draftReady || closing || !composeTo.trim())
                    return
                error = ""
                sending = true
                sendProc.stdinEnabled = true
                sendProc.running = true
            }

            function clearCompose() {
                composeTo = ""
                composeSubject = ""
                composeBody = ""
                composing = false
                selectedFolder = "inbox"
            }

            Component.onCompleted: status()

            Process {
                id: statusProc
                command: ["python3", mail.helper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            mail.configured = !!r.configured
                            mail.account = r.account ?? ""
                            if (mail.configured)
                                mail.refresh()
                        } catch (e) {
                            mail.error = "Mail could not read the account state."
                        }
                    }
                }
            }

            Process {
                id: setupProc
                command: ["python3", mail.helper, "setup"]
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                mail.configured = true
                                mail.account = r.account ?? mail.setupEmail
                                mail.setupPassword = ""
                                mail.refresh()
                            } else {
                                mail.error = r.error ?? "The account could not be configured."
                            }
                        } catch (e) {
                            mail.error = "The account could not be configured."
                        }
                    }
                }
                onStarted: {
                    write(JSON.stringify({
                        email: mail.setupEmail.trim(),
                        username: mail.setupUsername.trim() || mail.setupEmail.trim(),
                        password: mail.setupPassword,
                        imap_host: mail.imapHost.trim(),
                        imap_port: parseInt(mail.imapPort, 10) || 993,
                        imap_security: mail.imapSecurity === 0 ? "ssl" : "starttls",
                        smtp_host: mail.smtpHost.trim(),
                        smtp_port: parseInt(mail.smtpPort, 10) || 465,
                        smtp_security: mail.smtpSecurity === 0 ? "ssl" : "starttls"
                    }))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: listProc
                command: ["python3", mail.helper, "list"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                mail.messages = r.messages ?? []
                                if (mail.selectedUid && !mail.messages.some((m) => m.uid === mail.selectedUid)) {
                                    mail.selectedUid = ""
                                    mail.selectedMessage = ({})
                                }
                                mail.account = r.account ?? mail.account
                                mail.error = ""
                            } else {
                                mail.error = r.error ?? "Inbox could not be refreshed."
                            }
                        } catch (e) {
                            mail.error = "Inbox could not be refreshed."
                        }
                    }
                }
                onExited: mail.loading = false
            }

            Process {
                id: readProc
                onExited: {
                    if (mail.queuedUid) {
                        const uid = mail.queuedUid
                        mail.queuedUid = ""
                        mail.read(uid)
                    }
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                const item = r.message ?? ({})
                                if (item.uid === mail.selectedUid) mail.selectedMessage = item
                                mail.messages = mail.messages.map((m) => {
                                    if (m.uid !== item.uid) return m
                                    const copy = Object.assign({}, m)
                                    copy.unread = false
                                    return copy
                                })
                            } else {
                                mail.error = r.error ?? "The message could not be opened."
                            }
                        } catch (e) {
                            mail.error = "The message could not be opened."
                        }
                    }
                }
            }

            Process {
                id: sendProc
                command: ["python3", mail.helper, "send"]
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                mail.clearCompose()
                                mail.refresh()
                            } else {
                                mail.error = r.error ?? "The message could not be sent."
                            }
                        } catch (e) {
                            mail.error = "The message could not be sent."
                        }
                    }
                }
                onStarted: {
                    write(JSON.stringify({
                        to: mail.composeTo.trim(),
                        subject: mail.composeSubject.trim(),
                        body: mail.composeBody
                    }))
                    stdinEnabled = false
                }
                onExited: {
                    stdinEnabled = true
                    mail.sending = false
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            Column {
                visible: !mail.configured
                anchors.centerIn: parent
                width: Math.min(520, parent.width - 80)
                spacing: 12

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "envelope"
                    size: 50
                    tone: "accent"
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Set Up Mail"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 25; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Connect an IMAP/SMTP account. Your password is stored in the system keyring, not in Mail's settings file."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }

                TextField {
                    width: parent.width
                    placeholder: "Email address"
                    text: mail.setupEmail
                    onTextChanged: mail.setupEmail = text
                    onAccepted: mail.inferServers()
                }
                TextField {
                    width: parent.width
                    placeholder: "Username (usually your email)"
                    text: mail.setupUsername
                    onTextChanged: mail.setupUsername = text
                }

                Row {
                    width: parent.width
                    spacing: 8
                    // The server takes what the port and the SSL/TLS control leave.
                    TextField {
                        width: parent.width - imapPort.width - imapSecurity.width - 2 * parent.spacing
                        placeholder: "IMAP server"
                        text: mail.imapHost
                        onTextChanged: { if (text !== mail.imapHost && activeFocus) mail.serversTyped = true; mail.imapHost = text }
                    }
                    TextField {
                        id: imapPort
                        width: 64
                        placeholder: "993"
                        text: mail.imapPort
                        onTextChanged: mail.imapPort = text.replace(/[^0-9]/g, "")
                    }
                    Segmented {
                        id: imapSecurity
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["SSL", "TLS"]
                        current: mail.imapSecurity
                        onPicked: (i) => mail.imapSecurity = i
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    // The server takes what the port and the SSL/TLS control leave.
                    TextField {
                        width: parent.width - smtpPort.width - smtpSecurity.width - 2 * parent.spacing
                        placeholder: "SMTP server"
                        text: mail.smtpHost
                        onTextChanged: { if (text !== mail.smtpHost && activeFocus) mail.serversTyped = true; mail.smtpHost = text }
                    }
                    TextField {
                        id: smtpPort
                        width: 64
                        placeholder: "465"
                        text: mail.smtpPort
                        onTextChanged: mail.smtpPort = text.replace(/[^0-9]/g, "")
                    }
                    Segmented {
                        id: smtpSecurity
                        anchors.verticalCenter: parent.verticalCenter
                        options: ["SSL", "TLS"]
                        current: mail.smtpSecurity
                        onPicked: (i) => mail.smtpSecurity = i
                    }
                }

                TextField {
                    width: parent.width
                    password: true
                    placeholder: mail.passwordHint && !mail.passwordHint.startsWith("Microsoft") ? "App password" : "Password or app-specific password"
                    text: mail.setupPassword
                    onTextChanged: mail.setupPassword = text
                    onAccepted: if (connectButton.enabled) mail.setupAccount()
                }
                Text {
                    visible: !!mail.passwordHint
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: mail.passwordHint
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
                // Why Connect didn't work (it was never shown, so a failed
                // Connect looked like nothing happening).
                Text {
                    objectName: "mailSetupError"
                    visible: !!mail.error && !setupProc.running
                    width: parent.width
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: mail.error
                    color: Theme.dark ? "#ff453a" : "#d70015"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Button {
                        text: "Fill Common Servers"
                        onClicked: mail.inferServers()
                    }
                    Button {
                        id: connectButton
                        text: setupProc.running ? "Connecting…" : "Connect"
                        prominent: true
                        enabled: !setupProc.running && mail.setupEmail.includes("@")
                            && !!mail.imapHost && !!mail.smtpHost && mail.setupPassword.length > 0
                        onClicked: mail.setupAccount()
                    }
                }
            }

            // The content begins BELOW the toolbar: three-column macOS Mail
            // layout on wide windows, single list/reader pane when compact.
            Row {
                id: mailWorkspace
                objectName: "mailWorkspace"
                visible: mail.configured && !mail.composing && mail.selectedFolder === "inbox"
                anchors.fill: parent
                spacing: 0

                Rectangle {
                    id: messageListPane
                    objectName: "mailMessageListPane"
                    visible: !mail.compactReading || !mail.selectedUid
                    width: mail.compactReading ? mail.width :
                        Math.max(304, Math.min(mail.preferredListWidth, mail.width - 350))
                    height: parent.height
                    color: Theme.dark ? "#232428" : "#f5f5f7"
                    clip: true

                    Item {
                        id: listHeader
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 94
                        Column {
                            x: 19
                            y: 13
                            spacing: 3
                            Text {
                                text: "Inbox"
                                color: Theme.label
                                font { family: Theme.fontDisplay; pixelSize: Theme.fs(23); weight: Font.Bold }
                            }
                            Text {
                                text: mail.loading ? "Checking for new mail…" :
                                      mail.filteredMessages.length + (mail.filteredMessages.length === 1 ? " message" : " messages")
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                        ToolbarPill {
                            anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 7 }
                            ToolbarButton {
                                text: "All"; checked: !mail.unreadOnly
                                onClicked: mail.unreadOnly = false
                            }
                            ToolbarButton {
                                text: "Unread"; checked: mail.unreadOnly
                                onClicked: mail.unreadOnly = true
                            }
                        }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1; color: Theme.separator
                        }
                    }

                    ListView {
                        id: mailMessageList
                        objectName: "mailMessageList"
                        anchors { top: listHeader.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                        clip: true
                        model: mail.filteredMessages
                        cacheBuffer: 250
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: messageEntry
                            required property var modelData
                            width: ListView.view.width
                            height: 91
                            readonly property bool chosen: String(mail.selectedUid) === String(modelData.uid)
                            color: chosen ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b,
                                                    Theme.dark ? 0.26 : 0.13)
                                : messageHover.hovered ? (Theme.dark ? "#19ffffff" : "#10000000") : "transparent"
                            Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : 110 } }

                            Rectangle {
                                anchors { bottom: parent.bottom; left: parent.left; leftMargin: 59; right: parent.right }
                                height: 1; color: Theme.separator
                                opacity: messageEntry.chosen ? 0.3 : 0.75
                            }
                            Rectangle {
                                x: 15; y: 14
                                width: 35; height: 35; radius: width / 2
                                color: Theme.dark ? "#494b56" : "#dfe4ec"
                                Text {
                                    anchors.centerIn: parent
                                    text: mail.initials(messageEntry.modelData.from)
                                    color: Theme.dark ? "#f4f7ff" : "#263445"
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                                }
                            }
                            Column {
                                x: 59; y: 12
                                width: Math.max(80, parent.width - x - 16)
                                spacing: 5
                                Row {
                                    width: parent.width
                                    spacing: 5
                                    Text {
                                        width: Math.max(60, parent.width - dateLabel.implicitWidth - 24)
                                        text: mail.senderName(messageEntry.modelData.from)
                                        color: Theme.label
                                        elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(13);
                                               weight: messageEntry.modelData.unread ? Font.Bold : Font.DemiBold }
                                    }
                                    Text {
                                        id: dateLabel
                                        text: mail.conciseDate(messageEntry.modelData.date)
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    text: messageEntry.modelData.subject || "(No Subject)"
                                    elide: Text.ElideRight
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12);
                                           weight: messageEntry.modelData.unread ? Font.DemiBold : Font.Normal }
                                }
                                Text {
                                    width: parent.width - 10
                                    text: mail.account
                                    elide: Text.ElideRight
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                }
                            }
                            Rectangle {
                                visible: !!messageEntry.modelData.unread
                                x: 5; y: 23; width: 7; height: 7; radius: 3.5
                                color: Theme.accent
                            }
                            HoverHandler { id: messageHover }
                            TapHandler { onTapped: mail.read(String(messageEntry.modelData.uid)) }
                        }
                    }

                    EmptyState {
                        visible: !mail.loading && mail.filteredMessages.length === 0
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 30, 310)
                        height: 190
                        symbol: mail.query || mail.unreadOnly ? "search" : "envelope"
                        title: mail.query ? "No Matching Messages" : mail.unreadOnly ? "All Caught Up" : "No Messages"
                        text: mail.query ? "Try a different search." :
                              mail.unreadOnly ? "You have no unread mail." : "Your inbox is empty."
                    }
                    ProgressBar {
                        visible: mail.loading
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
                        width: parent.width - 42; indeterminate: true
                    }
                }

                Rectangle {
                    id: readingPane
                    objectName: "mailReadingPane"
                    visible: !mail.compactReading || !!mail.selectedUid
                    width: mail.compactReading ? mail.width : mail.width - messageListPane.width
                    height: parent.height
                    color: Theme.contentBg

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 1; color: Theme.separator
                    }
                    EmptyState {
                        visible: !mail.selectedUid
                        anchors.centerIn: parent
                        width: Math.min(440, parent.width - 60); height: 260
                        symbol: "envelope"; title: "No Message Selected"
                        text: "Choose a message in your inbox to read it here."
                    }
                    ProgressBar {
                        visible: !!mail.selectedUid && mail.selectedMessage.uid !== mail.selectedUid
                        anchors.centerIn: parent
                        width: Math.min(230, parent.width - 50)
                        indeterminate: true
                    }
                    Flickable {
                        id: messageReader
                        objectName: "mailMessageReader"
                        visible: !!mail.selectedUid && mail.selectedMessage.uid === mail.selectedUid
                        anchors { fill: parent; leftMargin: 28; rightMargin: 28; topMargin: 23; bottomMargin: 16 }
                        clip: true
                        contentWidth: width
                        contentHeight: readerContents.implicitHeight + 30
                        boundsBehavior: Flickable.StopAtBounds
                        onVisibleChanged: if (visible) contentY = 0
                        Column {
                            id: readerContents
                            width: parent.width
                            spacing: 17
                            Text {
                                width: parent.width
                                text: mail.selectedMessage.subject || "(No Subject)"
                                color: Theme.label
                                wrapMode: Text.WordWrap
                                font { family: Theme.fontDisplay; pixelSize: Theme.fs(23); weight: Font.Bold }
                            }
                            Row {
                                width: parent.width; spacing: 12
                                Rectangle {
                                    width: 42; height: 42; radius: 21
                                    color: Theme.dark ? "#3c4b5d" : "#dae4ee"
                                    Text {
                                        anchors.centerIn: parent
                                        text: mail.initials(mail.selectedMessage.from)
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold }
                                    }
                                }
                                Column {
                                    width: Math.max(90, parent.width - 54)
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        text: mail.senderName(mail.selectedMessage.from)
                                        elide: Text.ElideRight
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
                                    }
                                    Text {
                                        width: parent.width
                                        text: "To: " + (mail.selectedMessage.to || mail.account)
                                        color: Theme.secondaryLabel
                                        elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                    }
                                    Text {
                                        width: parent.width
                                        text: mail.selectedMessage.date || ""
                                        color: Theme.secondaryLabel
                                        elide: Text.ElideRight
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                    }
                                }
                            }
                            Rectangle { width: parent.width; height: 1; color: Theme.separator }
                            Text {
                                width: parent.width
                                text: mail.selectedMessage.body || ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: Theme.label
                                lineHeight: 1.3
                                font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                            }
                            Row {
                                spacing: 8
                                Button {
                                    text: "Reply"
                                    enabled: !!mail.address(mail.selectedMessage.from)
                                    onClicked: mail.reply()
                                }
                                Button {
                                    text: "Forward"
                                    onClicked: mail.forward()
                                }
                            }
                        }
                    }
                }
            }

            // The saved draft is local; do not fabricate Sent/Trash mailboxes
            // until the IMAP backend actually supports those folders.
            Item {
                id: localDrafts
                objectName: "mailDraftsPane"
                visible: mail.configured && !mail.composing && mail.selectedFolder === "drafts"
                anchors.fill: parent
                EmptyState {
                    visible: !mail.hasDraft
                    anchors.centerIn: parent
                    width: Math.min(430, parent.width - 60); height: 250
                    symbol: "doc"; title: "No Drafts"
                    text: "Messages you begin writing are saved here automatically."
                }
                Column {
                    visible: mail.hasDraft
                    anchors { fill: parent; margins: 28 }
                    spacing: 12
                    Text {
                        text: "Drafts"
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: Theme.fs(24); weight: Font.Bold }
                    }
                    Rectangle {
                        width: Math.min(590, parent.width); height: 105
                        radius: 13
                        color: Theme.dark ? "#26282d" : "#f0f2f6"
                        border { width: 1; color: Theme.separator }
                        Column {
                            anchors { fill: parent; margins: 15 }
                            spacing: 6
                            Text { text: mail.composeTo || "No recipient"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
                            Text {
                                width: parent.width
                                text: mail.composeSubject || "(No Subject)"
                                elide: Text.ElideRight; color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: mail.composeBody.replace(/\\s+/g, " ").slice(0, 105)
                                elide: Text.ElideRight; color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                        TapHandler { onTapped: mail.composing = true }
                    }
                    Button { text: "Continue Writing"; onClicked: mail.composing = true }
                }
            }

            Item {
                id: composerPane
                objectName: "mailComposerPane"
                visible: mail.configured && mail.composing
                enabled: mail.draftReady && !mail.closing
                anchors.fill: parent
                Rectangle { anchors.fill: parent; color: Theme.contentBg }
                Column {
                    id: composeFields
                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 26; rightMargin: 26; topMargin: 18 }
                    spacing: 12
                    Text {
                        text: "New Message"
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: Theme.fs(22); weight: Font.DemiBold }
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.separator }
                    Row {
                        width: parent.width; height: 32; spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62
                            text: "To:"; color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                        TextField {
                            id: composeToField
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 72
                            bare: true
                            placeholder: "Name or email address"
                            text: mail.composeTo
                            onTextChanged: mail.composeTo = text
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.separator }
                    Row {
                        width: parent.width; height: 32; spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 62
                            text: "Subject:"; color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                        TextField {
                            id: composeSubjectField
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 72
                            bare: true; placeholder: "Subject"
                            text: mail.composeSubject
                            onTextChanged: mail.composeSubject = text
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.separator }
                }
                TextArea {
                    id: composeEditor
                    objectName: "mailComposeEditor"
                    anchors {
                        left: parent.left; right: parent.right
                        top: composeFields.bottom; bottom: composeActions.top
                        leftMargin: 26; rightMargin: 26; topMargin: 16; bottomMargin: 14
                    }
                    placeholder: "Write your message…"
                    text: mail.composeBody
                    onTextChanged: mail.composeBody = text
                    wrapMode: TextEdit.Wrap
                    clip: true
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                }
                Row {
                    id: composeActions
                    anchors { right: parent.right; rightMargin: 26; bottom: parent.bottom; bottomMargin: 19 }
                    spacing: 8
                    Button {
                        text: "Writing Tools…"
                        enabled: !mail.sending && composeEditor.length > 0
                        onClicked: composeEditor.openWritingTools()
                    }
                    Button {
                        text: "Save Draft"
                        enabled: !mail.sending && mail.draftReady
                        onClicked: { mail.saveDraft(); mail.selectedFolder = "drafts"; mail.composing = false }
                    }
                    Button {
                        text: mail.sending ? "Sending…" : "Send"
                        prominent: true
                        enabled: !mail.sending && mail.draftReady && mail.composeTo.trim().length > 0
                        onClicked: mail.send()
                    }
                }
            }

            // (While setting up, the error shows under Connect instead.)
            Glass {
                objectName: "mailInboxError"
                visible: !!mail.error && mail.configured
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                width: Math.min(560, parent.width - 40)
                height: Math.max(54, errorText.implicitHeight + 22)
                radius: 17
                tint: Theme.dark ? "#d02b1f24" : "#eefdf0f0"
                z: 50
                Text {
                    id: errorText
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: mail.error
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }
        }
    }
}
