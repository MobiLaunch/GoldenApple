//@ pragma AppId org.goldengate.Messages
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Messages"
        implicitWidth: Math.min(1040, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(700, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(760, 500)
        sidebarWidth: messages.configured ? 260 : 0
        fullSizeContent: true
        background: Theme.contentBg

        toolbarItems: [
            Row {
                visible: messages.configured
                x: win.contentX + 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: messages.currentRoomName || "Messages"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
                }
            },
            Row {
                visible: messages.configured
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8

                ToolbarButton {
                    round: true
                    symbol: "arrow-clockwise"
                    enabled: !messages.syncing
                    onClicked: messages.syncRooms()
                }
            }
        ]

        sidebar: [
            TextField {
                id: roomSearch
                width: parent.width
                height: 30
                search: true
                placeholder: "Search"
                onTextChanged: messages.query = text
                input.Keys.onEscapePressed: text = ""
            },
            Flickable {
                y: 42
                width: parent.width
                height: parent.height - 86
                contentHeight: roomColumn.height + 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: roomColumn
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: messages.filteredRooms
                        delegate: SidebarRow {
                            required property var modelData
                            width: parent.width
                            text: modelData.name
                            symbol: "bubble"
                            selected: messages.roomId === modelData.id
                            badge: modelData.unread > 0 ? String(modelData.unread) : ""
                            onClicked: messages.openRoom(modelData)
                        }
                    }

                    EmptyState {
                        visible: !messages.syncing && messages.filteredRooms.length === 0
                        width: parent.width
                        height: 180
                        symbol: "bubble"
                        title: messages.query.trim() ? "No Results" : "No Conversations"
                        text: messages.query.trim()
                            ? "No rooms match your search."
                            : "Joined Matrix rooms will appear here."
                    }
                }
            },
            Button {
                y: parent.height - 36
                width: parent.width
                text: "Sign Out"
                onClicked: messages.logout()
            }
        ]

        Item {
            id: messages
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("messages/helper.py").toString().replace("file://", "")
            property bool configured: false
            property string userId: ""
            property string homeserver: ""
            property var rooms: []
            property string query: ""
            property string roomId: ""
            property string currentRoomName: ""
            property var timeline: []
            property bool syncing: false
            property bool loadingRoom: false
            property bool sending: false
            property string error: ""
            property string draft: ""

            property string setupServer: "matrix.org"
            property string setupUser: ""
            property string setupPassword: ""

            readonly property var filteredRooms: {
                const q = query.trim().toLowerCase()
                if (!q)
                    return rooms
                return rooms.filter((room) =>
                    String(room.name ?? "").toLowerCase().includes(q)
                    || String(room.preview ?? "").toLowerCase().includes(q))
            }

            function status() {
                statusProc.running = true
            }

            function syncRooms() {
                if (!configured || syncProc.running)
                    return
                syncing = true
                syncProc.running = true
            }

            function openRoom(room) {
                if (!room || !room.id)
                    return
                roomId = room.id
                currentRoomName = room.name ?? "Conversation"
                refreshTimeline()
            }

            function refreshTimeline() {
                if (!roomId || roomProc.running)
                    return
                loadingRoom = true
                roomProc.command = ["python3", helper, "messages", roomId]
                roomProc.running = true
            }

            function login() {
                if (loginProc.running)
                    return
                error = ""
                loginProc.stdinEnabled = true
                loginProc.running = true
            }

            function send() {
                if (!roomId || sending || !draft.trim())
                    return
                error = ""
                sending = true
                sendProc.command = ["python3", helper, "send", roomId]
                sendProc.stdinEnabled = true
                sendProc.running = true
            }

            function logout() {
                if (!logoutProc.running)
                    logoutProc.running = true
            }

            Component.onCompleted: status()

            Timer {
                interval: 6500
                repeat: true
                running: messages.configured
                onTriggered: {
                    messages.syncRooms()
                    if (messages.roomId)
                        messages.refreshTimeline()
                }
            }

            Process {
                id: statusProc
                command: ["python3", messages.helper, "status"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            messages.configured = !!r.configured
                            messages.userId = r.user_id ?? ""
                            messages.homeserver = r.homeserver ?? ""
                            if (messages.configured)
                                messages.syncRooms()
                        } catch (e) {
                            messages.error = "Messages could not read the account state."
                        }
                    }
                }
            }

            Process {
                id: loginProc
                command: ["python3", messages.helper, "login"]
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                messages.configured = true
                                messages.userId = r.user_id ?? ""
                                messages.homeserver = r.homeserver ?? ""
                                messages.setupPassword = ""
                                messages.syncRooms()
                            } else {
                                messages.error = r.error ?? "Could not sign in to Matrix."
                            }
                        } catch (e) {
                            messages.error = "Could not sign in to Matrix."
                        }
                    }
                }
                onStarted: {
                    write(JSON.stringify({
                        homeserver: messages.setupServer.trim(),
                        username: messages.setupUser.trim(),
                        password: messages.setupPassword
                    }))
                    stdinEnabled = false
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: syncProc
                command: ["python3", messages.helper, "sync"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                messages.rooms = r.rooms ?? []
                                messages.userId = r.user_id ?? messages.userId
                                messages.error = ""
                                if (!messages.roomId && messages.rooms.length)
                                    messages.openRoom(messages.rooms[0])
                                else if (messages.roomId) {
                                    const room = messages.rooms.find((x) => x.id === messages.roomId)
                                    if (room)
                                        messages.currentRoomName = room.name
                                }
                            } else {
                                messages.error = r.error ?? "Messages could not sync."
                            }
                        } catch (e) {
                            messages.error = "Messages could not sync."
                        }
                    }
                }
                onExited: messages.syncing = false
            }

            Process {
                id: roomProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                messages.timeline = r.messages ?? []
                                messages.error = ""
                                Qt.callLater(() => chat.positionViewAtEnd())
                            } else {
                                messages.error = r.error ?? "Conversation history could not be loaded."
                            }
                        } catch (e) {
                            messages.error = "Conversation history could not be loaded."
                        }
                    }
                }
                onExited: messages.loadingRoom = false
            }

            Process {
                id: sendProc
                stdinEnabled: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                messages.draft = ""
                                composer.text = ""
                                messages.refreshTimeline()
                                messages.syncRooms()
                            } else {
                                messages.error = r.error ?? "The message could not be sent."
                            }
                        } catch (e) {
                            messages.error = "The message could not be sent."
                        }
                    }
                }
                onStarted: {
                    write(JSON.stringify({ body: messages.draft.trim() }))
                    stdinEnabled = false
                }
                onExited: {
                    stdinEnabled = true
                    messages.sending = false
                }
            }

            Process {
                id: logoutProc
                command: ["python3", messages.helper, "logout"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        messages.configured = false
                        messages.rooms = []
                        messages.timeline = []
                        messages.roomId = ""
                        messages.currentRoomName = ""
                        messages.userId = ""
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            Column {
                visible: !messages.configured
                anchors.centerIn: parent
                width: Math.min(470, parent.width - 80)
                spacing: 12

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "bubble"
                    size: 54
                    tone: "accent"
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Sign In to Messages"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 25; weight: Font.Bold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Connect to any Matrix homeserver. Your access token is stored in the system keyring."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }

                TextField {
                    width: parent.width
                    placeholder: "Homeserver, e.g. matrix.org"
                    text: messages.setupServer
                    onTextChanged: messages.setupServer = text
                }
                TextField {
                    width: parent.width
                    placeholder: "Username or Matrix ID"
                    text: messages.setupUser
                    onTextChanged: messages.setupUser = text
                }
                TextField {
                    width: parent.width
                    password: true
                    placeholder: "Password"
                    text: messages.setupPassword
                    onTextChanged: messages.setupPassword = text
                }

                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Sign In"
                    prominent: true
                    enabled: !!messages.setupServer && !!messages.setupUser && messages.setupPassword.length > 0
                    onClicked: messages.login()
                }
            }

            EmptyState {
                visible: messages.configured && !messages.roomId && !messages.syncing
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 60)
                height: 260
                symbol: "bubble"
                title: "No Conversation Selected"
                text: "Choose a room from the sidebar."
            }

            ListView {
                id: chat
                visible: messages.configured && !!messages.roomId
                anchors {
                    left: parent.left; right: parent.right; top: parent.top; bottom: composerBar.top
                    leftMargin: 20; rightMargin: 20; topMargin: 12; bottomMargin: 10
                }
                clip: true
                spacing: 8
                model: messages.timeline

                delegate: Item {
                    id: bubbleRow
                    required property var modelData
                    width: ListView.view.width
                    height: bubble.implicitHeight + 4

                    Rectangle {
                        id: bubble
                        anchors {
                            right: modelData.self ? parent.right : undefined
                            left: modelData.self ? undefined : parent.left
                        }
                        width: Math.min(parent.width * 0.70, Math.max(90, bubbleText.implicitWidth + 26))
                        implicitHeight: bubbleColumn.implicitHeight + 18
                        radius: 18
                        color: modelData.self
                            ? Theme.accent
                            : (Theme.dark ? "#28ffffff" : "#12000000")

                        Column {
                            id: bubbleColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
                            spacing: 3

                            Text {
                                visible: !bubbleRow.modelData.self
                                width: parent.width
                                text: bubbleRow.modelData.sender
                                elide: Text.ElideRight
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 9; weight: Font.DemiBold }
                            }

                            Text {
                                id: bubbleText
                                width: Math.min(500, implicitWidth)
                                text: bubbleRow.modelData.body
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                color: bubbleRow.modelData.self ? "#ffffff" : Theme.label
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }

                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignRight
                                text: new Date(bubbleRow.modelData.timestamp).toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                                color: bubbleRow.modelData.self ? "#ccffffff" : Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 9 }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: composerBar
                visible: messages.configured && !!messages.roomId
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 58
                color: Theme.dark ? "#161618" : "#f7f7f9"
                border { width: 0; color: "transparent" }

                TextField {
                    id: composer
                    anchors {
                        left: parent.left; right: sendButton.left; leftMargin: 14; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    height: 34
                    placeholder: "Message"
                    text: messages.draft
                    onTextChanged: messages.draft = text
                    onAccepted: messages.send()
                }

                Button {
                    id: sendButton
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    width: 74
                    text: messages.sending ? "…" : "Send"
                    prominent: true
                    enabled: !messages.sending && messages.draft.trim().length > 0
                    onClicked: messages.send()
                }
            }

            ProgressBar {
                visible: messages.syncing || messages.loadingRoom
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                width: 180
                indeterminate: true
                z: 30
            }

            Glass {
                visible: !!messages.error
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 68 }
                width: Math.min(560, parent.width - 40)
                height: 54
                radius: 17
                tint: Theme.dark ? "#d02b1f24" : "#eefdf0f0"
                z: 50

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: messages.error
                    color: "#ff453a"
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
        }
    }
}
