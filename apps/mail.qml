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

            Row {
                visible: mail.configured && !mail.composing
                anchors.fill: parent

                Rectangle {
                    width: Math.min(360, parent.width * 0.38)
                    height: parent.height
                    color: Theme.dark ? "#111113" : "#f7f7f9"
                    border { width: 0; color: "transparent" }

                    ListView {
                        anchors.fill: parent
                        clip: true
                        model: mail.messages
                        spacing: 1

                        delegate: Rectangle {
                            id: msgRow
                            required property var modelData
                            width: ListView.view.width
                            height: 78
                            color: mail.selectedUid === modelData.uid
                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                : msgHover.hovered
                                    ? (Theme.dark ? "#0dffffff" : "#07000000")
                                    : "transparent"

                            Column {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 12; topMargin: 10; bottomMargin: 8 }
                                spacing: 3

                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Rectangle {
                                        visible: msgRow.modelData.unread
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7; height: 7; radius: 3.5
                                        color: Theme.accent
                                    }
                                    Text {
                                        width: parent.width - (msgRow.modelData.unread ? 13 : 0)
                                        text: msgRow.modelData.from
                                        elide: Text.ElideRight
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: msgRow.modelData.unread ? Font.Bold : Font.DemiBold }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: msgRow.modelData.subject
                                    elide: Text.ElideRight
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: msgRow.modelData.unread ? Font.DemiBold : Font.Normal }
                                }
                                Text {
                                    width: parent.width
                                    text: msgRow.modelData.date
                                    elide: Text.ElideRight
                                    color: Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                                }
                            }

                            HoverHandler { id: msgHover }
                            TapHandler { onTapped: mail.read(msgRow.modelData.uid) }
                        }
                    }

                    EmptyState {
                        visible: !mail.loading && mail.messages.length === 0
                        anchors.centerIn: parent
                        width: parent.width - 30
                        height: 220
                        symbol: "checkmark"
                        title: "Inbox Empty"
                        text: "There are no messages to show."
                    }

                    ProgressBar {
                        visible: mail.loading
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
                        width: parent.width - 40
                        indeterminate: true
                    }
                }

                Item {
                    width: parent.width - Math.min(360, parent.width * 0.38)
                    height: parent.height

                    EmptyState {
                        visible: !mail.selectedUid
                        anchors.centerIn: parent
                        width: Math.min(420, parent.width - 60)
                        height: 260
                        symbol: "doc"
                        title: "Select a Message"
                        text: "Choose a message from the inbox to read it."
                    }

                    Flickable {
                        visible: !!mail.selectedUid
                        anchors { fill: parent; margins: 26 }
                        contentWidth: width
                        contentHeight: messageBody.implicitHeight + 40
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: messageBody
                            width: parent.width
                            spacing: 10

                            Text {
                                width: parent.width
                                text: mail.selectedMessage.subject ?? ""
                                wrapMode: Text.WordWrap
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(23); weight: Font.Bold }
                            }
                            Text {
                                width: parent.width
                                text: mail.selectedMessage.from ?? ""
                                elide: Text.ElideRight
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: mail.selectedMessage.date ?? ""
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
                            }
                            Rectangle { width: parent.width; height: 0.5; color: Theme.separator }
                            Text {
                                width: parent.width
                                text: mail.selectedMessage.body ?? ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                            }
                        }
                    }
                }
            }

            Column {
                visible: mail.configured && mail.composing
                enabled: mail.draftReady && !mail.closing
                anchors { fill: parent; margins: 24 }
                spacing: 10

                TextField {
                    width: parent.width
                    placeholder: "To"
                    text: mail.composeTo
                    onTextChanged: mail.composeTo = text
                }
                TextField {
                    width: parent.width
                    placeholder: "Subject"
                    text: mail.composeSubject
                    onTextChanged: mail.composeSubject = text
                }

                Rectangle {
                    width: parent.width
                    height: parent.height - 118
                    radius: 12
                    color: Theme.dark ? "#121214" : "#ffffff"
                    border { width: 0.5; color: Theme.separator }

                    TextArea {
                        id: composeEditor
                        anchors { fill: parent; margins: 14 }
                        text: mail.composeBody
                        onTextChanged: mail.composeBody = text
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        color: Theme.label
                        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Button { text: "Writing Tools…"; enabled: !mail.sending && composeEditor.length > 0; onClicked: composeEditor.openWritingTools() }
                    Button { text: "Save Draft"; enabled: !mail.sending && mail.draftReady; onClicked: { mail.saveDraft(); mail.composing = false } }
                    Button {
                        text: mail.sending ? "Sending…" : "Send"
                        prominent: true
                        enabled: !mail.sending && mail.composeTo.trim().length > 0
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
