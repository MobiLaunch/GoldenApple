//@ pragma AppId org.goldengate.Passwords
// Passwords, as on the Mac: every website password, verification code and
// Wi-Fi password in one place, locked until you unlock it with your login
// password (or Touch ID). Website passwords are Web's own (the system
// keyring, apps/passwords/helper.py), so one saved in Web is here and one
// added here fills in Web. Sections: All, Codes, Wi-Fi, Security (weak and
// reused passwords) and Recently Deleted (kept 30 days).
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Passwords"
        implicitWidth: Math.min(1020, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(680, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(760, 480)
        sidebarWidth: app.locked ? 0 : 220
        background: Theme.contentBg

        toolbarItems: [
            Text {
                visible: !app.locked
                x: win.contentX + 16
                anchors.verticalCenter: parent.verticalCenter
                text: app.sectionTitle
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
            },
            Row {
                visible: !app.locked
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8
                TextField {
                    objectName: "passwordsSearch"
                    width: 200
                    search: true
                    placeholder: "Search"
                    text: app.query
                    onTextChanged: app.query = text
                }
                ToolbarButton { round: true; symbol: "plus"; onClicked: app.startNew(app.section === "codes" ? "code" : "website") }
                ToolbarButton { round: true; symbol: "lock"; onClicked: app.lock() }
            }
        ]

        sidebar: [
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: app.sections
                    delegate: SidebarRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.title
                        symbol: modelData.symbol
                        selected: app.section === modelData.id
                        badge: modelData.count > 0 ? String(modelData.count) : ""
                        onClicked: { app.section = modelData.id; app.select("") }
                    }
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent

            readonly property string helper: decodeURIComponent(Qt.resolvedUrl("passwords/helper.py").toString().replace("file://", ""))
            // Opens locked. (GG_PASSWORDS_PREVIEW=1 opens it unlocked, for
            // screenshots and tests; the lock keeps prying eyes off, the
            // keyring itself is what keeps the passwords.)
            property bool locked: Quickshell.env("GG_PASSWORDS_PREVIEW") !== "1"
            property string section: Quickshell.env("GG_PASSWORDS_PREVIEW_SECTION") || "all"
            property string query: ""
            property var items: []
            property var wifi: []
            property var deleted: []
            property var codes: ({})            // id → { code, remaining, period }
            property string selectedId: ""
            property var secret: ({})           // the selected item's password, notes, code key
            property bool reveal: false
            property bool editing: false
            property var draft: ({})
            property string error: ""
            property string toast: ""
            property bool loading: false

            readonly property var weakOrReused: items.filter((i) => i.weak || i.reused)
            readonly property var sections: [
                { id: "all", title: "All", symbol: "key", count: 0 },
                { id: "codes", title: "Codes", symbol: "timer", count: 0 },
                { id: "wifi", title: "Wi-Fi", symbol: "wifi", count: 0 },
                { id: "security", title: "Security", symbol: "shield", count: weakOrReused.length },
                { id: "deleted", title: "Recently Deleted", symbol: "trash", count: 0 }
            ]
            readonly property string sectionTitle: sections.find((s) => s.id === section)?.title ?? ""
            readonly property var shown: {
                const q = query.trim().toLowerCase()
                const base = section === "all" ? items.filter((i) => i.kind === "website")
                    : section === "codes" ? items.filter((i) => i.hasCode)
                    : section === "wifi" ? wifi
                    : section === "security" ? weakOrReused
                    : deleted
                return q ? base.filter((i) => (i.title + " " + i.username).toLowerCase().includes(q)) : base
            }
            readonly property var selected: selectedId === "new" ? draft
                : (items.concat(wifi, deleted).find((i) => i.id === selectedId) ?? null)

            // ---------------------------------------------------- the helper
            component Call: Process {
                id: call
                property var request: ({})
                property var done: null
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text.trim().split("\n").pop()) } catch (e) { r = { ok: false, error: "Passwords couldn't read the keyring's answer." } }
                        if (!r.ok && r.error) app.error = r.error
                        if (call.done) call.done(r)
                        call.destroy()
                    }
                }
                onStarted: { write(JSON.stringify(request)); stdinEnabled = false }
            }
            Component { id: callComp; Call {} }
            function call(cmd, request, done) {
                const args = ["python3", helper, cmd].concat(cmd !== "save" && request?.id ? [request.id] : [])
                const c = callComp.createObject(app, { command: args, request: request ?? {}, done: done ?? null })
                c.running = true
            }

            function refresh() {
                loading = true
                call("list", {}, (r) => {
                    loading = false
                    if (!r.ok) return
                    items = r.items ?? []; wifi = r.wifi ?? []; deleted = r.deleted ?? []
                    refreshCodes()
                    // Screenshots: a section, and an item in it.
                    const pick = Quickshell.env("GG_PASSWORDS_PREVIEW_SELECT")
                    if (pick && !selectedId) { const it = items.concat(wifi).find((i) => i.title === pick); if (it) select(it.id) }
                })
            }
            function refreshCodes() {
                call("codes", {}, (r) => {
                    if (!r.ok) return
                    const m = {}
                    for (const c of r.codes ?? []) m[c.id] = c
                    codes = m
                })
            }
            // The codes count down here and are asked for again as they roll over.
            Timer {
                interval: 1000; repeat: true; running: !app.locked && Object.keys(app.codes).length > 0
                onTriggered: {
                    const m = {}
                    let roll = false
                    for (const id in app.codes) {
                        const c = Object.assign({}, app.codes[id])
                        c.remaining -= 1
                        if (c.remaining <= 0) roll = true
                        m[id] = c
                    }
                    app.codes = m
                    if (roll) app.refreshCodes()
                }
            }

            function select(id) {
                selectedId = id
                secret = ({}); reveal = false; editing = false; error = ""
                const it = selected
                if (!it || id === "new") return
                if (it.kind === "website" || it.kind === "code")
                    call("secret", { id: id }, (r) => { if (r.ok && app.selectedId === id) app.secret = r })
            }
            function startNew(kind) {
                draft = { id: "new", kind: kind, title: "", website: "", username: "", password: "", notes: "", totp: "" }
                selectedId = "new"; editing = true; secret = ({}); error = ""
                if (kind === "website") call("generate", {}, (r) => { if (r.ok && app.selectedId === "new") app.draft = Object.assign({}, app.draft, { password: r.password }) })
            }
            function startEdit() {
                const it = selected
                draft = { id: it.id, kind: it.kind, title: it.title, website: it.origin ?? "", username: it.username,
                          password: secret.password ?? "", notes: secret.notes ?? "", totp: secret.totp ?? "" }
                editing = true
            }
            function save() {
                call("save", draft, (r) => {
                    if (!r.ok) return
                    editing = false
                    const id = r.id
                    refresh()
                    afterRefresh.target = id
                    afterRefresh.restart()
                })
            }
            Timer { id: afterRefresh; property string target; interval: 600; onTriggered: app.select(target) }
            function remove(it) {
                call(it.kind === "deleted" ? "purge" : "delete", { id: it.id }, (r) => { if (r.ok) { app.select(""); app.refresh() } })
            }
            function restore(it) {
                call("restore", { id: it.id }, (r) => { if (r.ok) { app.select(""); app.section = "all"; app.refresh() } })
            }
            function showWifi(it) {
                call("wifi-secret", { id: it.id }, (r) => { if (r.ok && app.selectedId === it.id) { app.secret = r; app.reveal = true } })
            }

            // Copied: and taken off the clipboard after a minute, if it's still there.
            property string copied: ""
            function copy(text, what) {
                if (!text) return
                Quickshell.clipboardText = text
                copied = text
                clearClipboard.restart()
                toast = what + " copied"
                toastTimer.restart()
            }
            Timer {
                id: clearClipboard; interval: 60000
                onTriggered: { if (Quickshell.clipboardText === app.copied) Quickshell.clipboardText = ""; app.copied = "" }
            }
            Timer { id: toastTimer; interval: 1800; onTriggered: app.toast = "" }

            // --------------------------------------------------------- locking
            function lock() {
                locked = true
                secret = ({}); reveal = false; editing = false; selectedId = ""; items = []; wifi = []; deleted = []; codes = ({})
                unlockField.text = ""
            }
            function unlocked() {
                locked = false
                unlockError = ""
                refresh()
                lockTimer.restart()
            }
            // Locked again after five minutes without a touch.
            Timer { id: lockTimer; interval: 5 * 60 * 1000; running: !app.locked; onTriggered: app.lock() }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.NoButton; hoverEnabled: true; z: 1000
                onPositionChanged: if (!app.locked) lockTimer.restart()
            }
            property string unlockError: ""
            property string pending: ""
            PamContext {
                id: pam
                config: "login"
                user: Quickshell.env("USER") ?? ""
                onResponseRequiredChanged: if (responseRequired) { respond(app.pending); app.pending = "" }
                onCompleted: (result) => {
                    if (result === PamResult.Success) app.unlocked()
                    else app.unlockError = "That password isn't right."
                }
            }
            // Touch ID, when a finger is enrolled: the reader listens while locked.
            property bool touchId: false
            Process {
                running: true
                command: ["sh", "-c", "command -v fprintd-list >/dev/null && fprintd-list \"$USER\" 2>/dev/null"]
                stdout: StdioCollector { onStreamFinished: app.touchId = /^\s*-\s*#\d+:/m.test(text) }
            }
            PamContext {
                id: finger
                config: "gg-touchid"
                user: Quickshell.env("USER") ?? ""
                onCompleted: (result) => { if (result === PamResult.Success) app.unlocked(); else if (app.locked) fingerAgain.restart() }
            }
            Timer { id: fingerAgain; interval: 800; onTriggered: if (app.locked && app.touchId && !finger.active) finger.start() }
            onLockedChanged: if (locked && touchId) fingerAgain.restart(); else if (!locked && finger.active) finger.abort()
            onTouchIdChanged: if (touchId && locked) fingerAgain.restart()
            Component.onCompleted: if (!locked) unlocked()
            function tryUnlock() {
                if (pam.active || !unlockField.text) return
                unlockError = ""
                pending = unlockField.text
                unlockField.text = ""
                pam.start()
            }

            Rectangle { anchors.fill: parent; color: Theme.contentBg }

            // ------------------------------------------------------ locked
            Column {
                objectName: "passwordsLocked"
                visible: app.locked
                anchors.centerIn: parent
                width: 320
                spacing: 12
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72; radius: 18
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#5ac8fa" }
                        GradientStop { position: 1; color: "#0a6cf0" }
                    }
                    Symbol { anchors.centerIn: parent; name: "key"; size: 36; tone: "white" }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Passwords Is Locked"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(20); weight: Font.Bold }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: app.touchId ? "Touch ID or enter your password to unlock." : "Enter your password to unlock."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                TextField {
                    id: unlockField
                    width: parent.width
                    password: true
                    placeholder: "Password"
                    enabled: !pam.active
                    onAccepted: app.tryUnlock()
                    Component.onCompleted: if (app.locked) input.forceActiveFocus()
                }
                Text {
                    visible: !!app.unlockError
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: app.unlockError
                    color: Theme.dark ? "#ff453a" : "#d70015"
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pam.active ? "Unlocking…" : "Unlock"
                    prominent: true
                    enabled: !pam.active && unlockField.text.length > 0
                    onClicked: app.tryUnlock()
                }
            }

            // ---------------------------------------------------- unlocked
            component Avatar: Rectangle {
                id: av
                property string title
                property string kind
                property real size: 32
                width: size; height: size; radius: size * 0.24
                readonly property var tints: ["#0a84ff", "#30b0c7", "#34c759", "#ff9f0a", "#ff375f", "#bf5af2", "#5e5ce6", "#ff6482"]
                color: kind === "wifi" ? "#0a84ff" : kind === "code" ? "#8e8e93"
                    : tints[Math.abs(Array.from(title || "?").reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7)) % tints.length]
                Text {
                    visible: av.kind !== "wifi" && av.kind !== "code"
                    anchors.centerIn: parent
                    text: (av.title || "?").charAt(0).toUpperCase()
                    color: "white"
                    font { family: Theme.fontUi; pixelSize: av.size * 0.46; weight: Font.DemiBold }
                }
                Symbol { visible: av.kind === "wifi" || av.kind === "code"; anchors.centerIn: parent; name: av.kind === "wifi" ? "wifi" : "timer"; size: av.size * 0.5; tone: "white" }
            }

            Row {
                visible: !app.locked
                anchors.fill: parent

                Rectangle {
                    id: listPane
                    width: Math.min(320, parent.width * 0.4)
                    height: parent.height
                    color: Theme.dark ? "#111113" : "#f7f7f9"
                    ListView {
                        id: list
                        objectName: "passwordsList"
                        anchors { fill: parent; topMargin: 6 }
                        clip: true
                        model: app.shown
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            width: ListView.view.width
                            height: 54
                            color: app.selectedId === modelData.id ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                : rowHover.hovered ? (Theme.dark ? "#0dffffff" : "#07000000") : "transparent"
                            Avatar { id: rowAvatar; x: 14; anchors.verticalCenter: parent.verticalCenter; title: row.modelData.title; kind: row.modelData.kind }
                            Column {
                                anchors { left: rowAvatar.right; leftMargin: 10; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: row.modelData.title
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                                }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    visible: !!text
                                    text: row.modelData.kind === "deleted" ? (row.modelData.daysLeft + " days left · " + row.modelData.username)
                                        : app.section === "security" ? (row.modelData.reused ? "Reused password" : "Weak password")
                                        : app.section === "codes" && app.codes[row.modelData.id] ? app.codes[row.modelData.id].code.replace(/(\d{3})(\d+)/, "$1 $2")
                                        : row.modelData.username
                                    color: app.section === "security" ? "#ff9f0a" : Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                }
                            }
                            HoverHandler { id: rowHover }
                            TapHandler { onTapped: app.select(row.modelData.id) }
                        }
                    }
                    Scroller { flickable: list }
                    EmptyState {
                        visible: !app.loading && app.shown.length === 0
                        anchors.centerIn: parent
                        width: parent.width - 30; height: 220
                        symbol: app.section === "security" ? "checkmark" : app.section === "deleted" ? "trash" : "key"
                        title: app.query ? "No Results"
                            : app.section === "security" ? "No Security Recommendations"
                            : app.section === "deleted" ? "No Recently Deleted Passwords"
                            : app.section === "codes" ? "No Verification Codes"
                            : app.section === "wifi" ? "No Wi-Fi Networks" : "No Passwords"
                        text: app.query ? "Nothing matches “" + app.query + "”."
                            : app.section === "security" ? "None of your passwords are weak or reused."
                            : app.section === "codes" ? "Set up a code from a website's two-factor settings."
                            : app.section === "all" ? "Passwords you save in Web, or add here, appear here." : ""
                    }
                }

                // The selected item, or a new one being made.
                Item {
                    width: parent.width - listPane.width
                    height: parent.height

                    EmptyState {
                        visible: !app.selected
                        anchors.centerIn: parent
                        width: Math.min(420, parent.width - 60); height: 240
                        symbol: "key"
                        title: "No Item Selected"
                        text: "Choose a password, code or network to see it."
                    }

                    Flickable {
                        id: detailFlick
                        visible: !!app.selected
                        anchors { fill: parent; margins: 28 }
                        contentHeight: detail.implicitHeight + 40
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: detail
                            objectName: "passwordsDetail"
                            width: detailFlick.width
                            spacing: 14
                            readonly property var it: app.selected ?? ({})

                            Row {
                                spacing: 14
                                Avatar { size: 56; title: detail.it.title || detail.it.website || "?"; kind: detail.it.kind ?? "" }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        text: app.selectedId === "new" ? (detail.it.kind === "code" ? "New Verification Code" : "New Password") : detail.it.title ?? ""
                                        color: Theme.label
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(20); weight: Font.Bold }
                                    }
                                    Text {
                                        visible: !!text
                                        text: detail.it.kind === "deleted" ? "Deleted · " + detail.it.daysLeft + " days until it's gone"
                                            : detail.it.modified ? "Last modified " + String(detail.it.modified).slice(0, 10) : ""
                                        color: Theme.secondaryLabel
                                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                    }
                                }
                            }

                            // Security: what's wrong, and the fix.
                            Rectangle {
                                visible: !app.editing && (detail.it.weak || detail.it.reused) === true
                                width: parent.width; height: warnText.implicitHeight + 20; radius: 10
                                color: Theme.dark ? "#3a2a10" : "#fff4e0"
                                Text {
                                    id: warnText
                                    anchors { fill: parent; margins: 10 }
                                    wrapMode: Text.WordWrap
                                    text: detail.it.reused ? "This password is used on more than one website. If one of them is breached, the others are at risk. Change it to a strong, unique password."
                                        : "This password is easy to guess. Change it to a strong password."
                                    color: Theme.label
                                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                }
                            }

                            // Viewing.
                            Rectangle {
                                visible: !app.editing
                                width: parent.width
                                height: fields.implicitHeight
                                radius: 12
                                color: Theme.dark ? "#1c1c1e" : "#ffffff"
                                border { width: 0.5; color: Theme.separator }
                                Column {
                                    id: fields
                                    width: parent.width
                                    component Field: Item {
                                        id: field
                                        property string label
                                        property string value
                                        property string shownValue: value
                                        property bool secretValue: false
                                        property string copyWhat: label
                                        width: parent.width; height: 46
                                        visible: !!value || secretValue
                                        Text {
                                            x: 14; width: 110; anchors.verticalCenter: parent.verticalCenter
                                            text: field.label; color: Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                                        }
                                        Text {
                                            x: 130; width: parent.width - 130 - 90; anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            text: field.shownValue
                                            color: Theme.label
                                            font { family: field.secretValue && app.reveal ? "SF Mono" : Theme.fontUi; pixelSize: Theme.fs(13) }
                                        }
                                        Row {
                                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                            spacing: 6
                                            ToolbarButton {
                                                visible: field.secretValue
                                                round: true; symbol: app.reveal ? "eye-slash" : "eye"
                                                onClicked: { if (detail.it.kind === "wifi" && !app.secret.password) app.showWifi(detail.it); else app.reveal = !app.reveal }
                                            }
                                            ToolbarButton {
                                                visible: !!field.value
                                                round: true; symbol: "copy"
                                                onClicked: app.copy(field.value, field.copyWhat)
                                            }
                                        }
                                        Rectangle { anchors.bottom: parent.bottom; x: 14; width: parent.width - 14; height: 0.5; color: Theme.separator }
                                    }
                                    Field { label: "User Name"; value: detail.it.username ?? "" }
                                    Field {
                                        label: "Password"
                                        visible: detail.it.kind === "website" || detail.it.kind === "wifi"
                                        secretValue: true
                                        value: app.secret.password ?? ""
                                        shownValue: app.reveal && value ? value : "••••••••••••"
                                    }
                                    Field {
                                        label: "Code"
                                        value: app.codes[detail.it.id]?.code ?? ""
                                        shownValue: value ? value.replace(/(\d{3})(\d+)/, "$1 $2") + "   · " + (app.codes[detail.it.id]?.remaining ?? 0) + "s" : ""
                                        copyWhat: "Code"
                                    }
                                    Field { label: "Website"; value: detail.it.origin ? String(detail.it.origin).replace(/^https?:\/\//, "") : "" }
                                    Field { label: "Notes"; value: app.secret.notes ?? "" }
                                }
                            }

                            // Editing (or new).
                            Column {
                                visible: app.editing
                                width: parent.width
                                spacing: 8
                                component Labeled: Column {
                                    property string label
                                    default property alias content: holder.data
                                    width: parent.width; spacing: 4
                                    Text { text: parent.label; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                                    Item { id: holder; width: parent.width; height: childrenRect.height }
                                }
                                Labeled {
                                    label: app.draft.kind === "code" ? "Name" : "Website"
                                    TextField {
                                        objectName: "draftWebsite"
                                        width: parent.width
                                        placeholder: app.draft.kind === "code" ? "e.g. AWS" : "example.com"
                                        text: app.draft.kind === "code" ? (app.draft.title ?? "") : (app.draft.website ?? "")
                                        onTextChanged: app.draft[app.draft.kind === "code" ? "title" : "website"] = text
                                    }
                                }
                                Labeled {
                                    label: app.draft.kind === "code" ? "Account" : "User Name"
                                    TextField { width: parent.width; placeholder: "Optional"; text: app.draft.username ?? ""; onTextChanged: app.draft.username = text }
                                }
                                Labeled {
                                    visible: app.draft.kind !== "code"
                                    label: "Password"
                                    Row {
                                        width: parent.width; spacing: 8
                                        TextField {
                                            id: draftPassword
                                            width: parent.width - suggest.width - 8
                                            text: app.draft.password ?? ""
                                            onTextChanged: app.draft.password = text
                                        }
                                        Button {
                                            id: suggest
                                            text: "Suggest Strong Password"
                                            onClicked: app.call("generate", {}, (r) => { if (r.ok) draftPassword.text = r.password })
                                        }
                                    }
                                }
                                Labeled {
                                    label: "Verification Code Setup Key"
                                    TextField {
                                        width: parent.width
                                        placeholder: "Setup key or otpauth:// link (optional)"
                                        text: app.draft.totp ?? ""
                                        onTextChanged: app.draft.totp = text
                                    }
                                }
                                Labeled {
                                    visible: app.draft.kind !== "code"
                                    label: "Notes"
                                    TextField { width: parent.width; placeholder: "Optional"; text: app.draft.notes ?? ""; onTextChanged: app.draft.notes = text }
                                }
                            }

                            Text {
                                visible: !!app.error
                                width: parent.width; wrapMode: Text.WordWrap
                                text: app.error
                                color: Theme.dark ? "#ff453a" : "#d70015"
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }

                            Row {
                                spacing: 8
                                // Viewing.
                                Button { visible: !app.editing && (detail.it.kind === "website" || detail.it.kind === "code"); text: "Edit"; onClicked: app.startEdit() }
                                Button { visible: !app.editing && (detail.it.kind === "website" || detail.it.kind === "code"); text: "Delete"; destructive: true; onClicked: app.remove(detail.it) }
                                Button { visible: !app.editing && detail.it.kind === "deleted"; text: "Recover"; prominent: true; onClicked: app.restore(detail.it) }
                                Button { visible: !app.editing && detail.it.kind === "deleted"; text: "Delete Now"; destructive: true; onClicked: app.remove(detail.it) }
                                Button { visible: !app.editing && detail.it.kind === "website" && !!detail.it.origin; text: "Open Website"; onClicked: Quickshell.execDetached(["gg-web", detail.it.origin]) }
                                // Editing.
                                Button { visible: app.editing; text: "Cancel"; onClicked: { if (app.selectedId === "new") app.select(""); else app.editing = false; app.error = "" } }
                                Button { visible: app.editing; objectName: "draftSave"; text: "Save"; prominent: true; onClicked: app.save() }
                            }
                        }
                    }
                }
            }

            // A short note: "Password copied".
            Glass {
                visible: !!app.toast
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                width: toastText.implicitWidth + 32; height: 34; radius: 17
                z: 50
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    text: app.toast
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                }
            }
        }
    }
}
