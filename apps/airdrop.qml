//@ pragma AppId org.goldengate.AirDrop
// CitronOS AirDrop: share files with people nearby, as AirDrop on the Mac.
// Devices on the same network appear as round pictures; drop files on one, or
// click it and choose files, and it shows how the transfer goes. When someone
// shares with you, you Accept or Decline and the files land in Downloads.
//
// AirDrop speaks the open LocalSend protocol (apps/airdrop/airdropd.py), so
// the other side can be another CitronOS computer or the LocalSend app on
// an iPhone, iPad, Android phone, Windows PC or Mac. Apple's own AirDrop isn't
// open to other systems, so an iPhone needs LocalSend installed.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes
import "lib"
import "lib/theme"
import "airdrop"
import "messages" as Messages

ShellRoot {
    AppWindow {
        id: win
        title: "AirDrop"
        implicitWidth: 780
        implicitHeight: 560
        minimumSize: Qt.size(560, 440)
        background: Theme.contentBg

        toolbarCenter: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "AirDrop"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
        }

        Item {
            id: app
            anchors.fill: parent

            property var peers: []
            property var transfers: ({})        // fingerprint → { state, sent, total, message }
            property string discoverable: "everyone"
            property string alias: ""
            property string downloads: ""
            property var request: null          // the incoming request on screen
            property var receiving: null         // { from, received, total, count }
            property var received: null          // { from, paths }
            property var message: null           // { from, text }
            property var pending: []             // files shared from Files, waiting for a device
            property var chooseFor: null         // the device the chooser is open for
            readonly property var devices: peers.map((p) => Object.assign({}, p, { transfer: transfers[p.fingerprint] || p.transfer || null }))

            function sendTo(device, paths) {
                if (!paths.length) return
                service.send({ cmd: "send", to: device.fingerprint, paths: paths })
                pending = []
            }
            function answer(accept) {
                if (!request) return
                service.send({ cmd: "answer", id: request.id, accept: accept })
                request = null
            }
            function size(n) {
                return n > 1e9 ? (n / 1e9).toFixed(1) + " GB" : n > 1e6 ? (n / 1e6).toFixed(1) + " MB"
                     : n > 1e3 ? Math.round(n / 1e3) + " KB" : n + " bytes"
            }

            Service {
                id: service
                Component.onCompleted: { send({ cmd: "hello" }); send({ cmd: "scan" }) }
                onEvent: (name, data) => {
                    if (name === "state") {
                        app.peers = data.peers || []
                        app.discoverable = data.discoverable
                        app.alias = data.alias
                        app.downloads = data.downloads
                        if ((data.requests || []).length && !app.request) app.request = data.requests[0]
                    } else if (name === "peers") {
                        app.peers = data.peers || []
                    } else if (name === "transfer") {
                        const t = Object.assign({}, app.transfers)
                        if (data.state === "sent" || data.state === "declined" || data.state === "failed" || data.state === "cancelled")
                            clearTransfer.schedule(data.to)
                        t[data.to] = { state: data.state, sent: data.sent, total: data.total, message: data.message }
                        app.transfers = t
                    } else if (name === "request") {
                        app.request = data
                    } else if (name === "request-done") {
                        if (app.request && app.request.id === data.id) app.request = null
                    } else if (name === "receiving") {
                        app.receiving = data
                    } else if (name === "received") {
                        app.receiving = null
                        if (!data.cancelled && (data.paths || []).length) app.received = data
                    } else if (name === "message") {
                        app.message = data
                    }
                }
            }
            // A finished transfer's line ("Sent", "Declined") stays a moment.
            Timer {
                id: clearTransfer
                property var keys: []
                function schedule(key) { keys.push(key); restart() }
                interval: 4000
                onTriggered: {
                    const t = Object.assign({}, app.transfers)
                    for (const k of keys) delete t[k]
                    keys = []
                    app.transfers = t
                }
            }
            // Look again now and then while the window is open.
            Timer { running: true; repeat: true; interval: 45000; onTriggered: service.send({ cmd: "scan" }) }

            // Files shared from Files (gg-airdrop FILE…) wait here for a device.
            Process {
                id: pendingProbe
                command: ["sh", "-c", 'f="${XDG_RUNTIME_DIR:-/tmp}/gg-airdrop-pending"; [ -s "$f" ] && cat "$f" && rm -f "$f"']
                stdout: StdioCollector {
                    onStreamFinished: {
                        const paths = text.split("\n").filter((l) => l.trim())
                        if (paths.length) app.pending = paths
                    }
                }
            }
            // Files shared while the window is open (gg-airdrop FILE… writes
            // them, then finds this window open): `gio monitor` says when the
            // file lands, so nothing polls. Without gio, look every 5 seconds.
            Component.onCompleted: pendingProbe.running = true
            Process {
                id: pendingWatch
                running: true
                command: ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}"; command -v gio >/dev/null || exit 3; '
                    + 'stdbuf -oL gio monitor -d "$d" | grep --line-buffered -F gg-airdrop-pending']
                stdout: SplitParser { onRead: pendingSettle.restart() }
                onExited: pendingPoll.running = true
            }
            Timer { id: pendingSettle; interval: 200; onTriggered: pendingProbe.running = true }
            Timer { id: pendingPoll; repeat: true; interval: 5000; onTriggered: pendingProbe.running = true }

            // ------------------------------------------------------- radar
            // Faint rings spread from the AirDrop icon at the bottom, as the
            // Mac's AirDrop window draws them.
            Item {
                id: radar
                anchors.fill: parent
                clip: true
                readonly property real cx: width / 2
                readonly property real cy: height - 118
                Repeater {
                    model: 6
                    delegate: Rectangle {
                        required property int index
                        readonly property real r: 120 + index * 110
                        x: radar.cx - r; y: radar.cy - r
                        width: r * 2; height: r * 2; radius: r
                        color: "transparent"
                        border { width: 1; color: Theme.dark ? "#1affffff" : "#12000000" }
                    }
                }
                // A soft wave moving outward while looking.
                Rectangle {
                    id: wave
                    property real r: 100
                    x: radar.cx - r; y: radar.cy - r
                    width: r * 2; height: r * 2; radius: r
                    color: "transparent"
                    border { width: 2; color: Theme.accent }
                    opacity: 0
                    SequentialAnimation {
                        running: !Theme.reduceMotion && app.discoverable !== "off"
                        loops: Animation.Infinite
                        ParallelAnimation {
                            NumberAnimation { target: wave; property: "r"; from: 90; to: Math.max(radar.width, radar.height); duration: 3200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: wave; property: "opacity"; from: 0.35; to: 0; duration: 3200; easing.type: Easing.OutCubic }
                        }
                        PauseAnimation { duration: 900 }
                    }
                }
            }

            // ----------------------------------------------------- banner
            Rectangle {
                visible: app.pending.length > 0
                anchors { top: parent.top; topMargin: win.toolbarHeight + 6; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width - 40, bannerRow.implicitWidth + 28)
                height: 34; radius: 17
                color: Theme.dark ? "#2a2a2e" : "#ffffff"
                border { width: 0.5; color: Theme.separator }
                Row {
                    id: bannerRow
                    anchors.centerIn: parent
                    spacing: 8
                    Symbol { name: "share"; size: 13; tone: "accent"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Choose who to send " + (app.pending.length === 1 ? "“" + app.pending[0].split("/").pop() + "”" : app.pending.length + " items") + " to."
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Cancel"
                        color: Theme.accent
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                        TapHandler { onTapped: app.pending = [] }
                    }
                }
            }

            // ---------------------------------------------------- devices
            Flow {
                id: devices
                anchors { top: parent.top; topMargin: win.toolbarHeight + 52; horizontalCenter: parent.horizontalCenter }
                width: Math.min(parent.width - 60, Math.max(1, app.devices.length) * 140)
                spacing: 8
                Repeater {
                    model: app.devices
                    delegate: DeviceTile {
                        required property var modelData
                        device: modelData
                        opacity: 0
                        scale: 0.6
                        Component.onCompleted: { opacity = 1; scale = 1 }
                        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 260 } }
                        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 360; easing.type: Easing.OutBack } }
                        onChosen: app.pending.length ? app.sendTo(modelData, app.pending) : (app.chooseFor = modelData, chooser.open(chooser.homePath))
                        onDropped: (paths) => app.sendTo(modelData, paths)
                        onCancelRequested: service.send({ cmd: "cancel", to: modelData.fingerprint })
                    }
                }
            }
            Column {
                visible: app.devices.length === 0
                anchors { top: parent.top; topMargin: win.toolbarHeight + 96; horizontalCenter: parent.horizontalCenter }
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: app.discoverable === "off" ? "AirDrop is off" : "Looking for people nearby…"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Medium }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(420, app.width - 60)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Devices on the same Wi-Fi appear here: CitronOS computers, and iPhones, iPads, Android phones and PCs with the free LocalSend app open."
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
            }

            // ------------------------------------------------------ footer
            Column {
                anchors { bottom: parent.bottom; bottomMargin: 26; horizontalCenter: parent.horizontalCenter }
                spacing: 8
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72
                    source: Quickshell.iconPath("org.goldengate.AirDrop", "network-wireless")
                    sourceSize: Qt.size(144, 144)
                    opacity: app.discoverable === "off" ? 0.45 : 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "AirDrop lets you share instantly with people nearby."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Allow me to be discovered by:"
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                    }
                    PopUpButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120; height: 22
                        menuParent: win.overlay
                        options: ["No One", "Everyone"]
                        current: app.discoverable === "off" ? 0 : 1
                        onPicked: (i) => service.send({ cmd: "set", discoverable: i === 0 ? "off" : "everyone" })
                    }
                }
                Text {
                    visible: app.alias !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Others see this computer as “" + app.alias + "”."
                    color: Theme.tertiaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }

            // ------------------------------------------------------ sheets
            Chooser {
                id: chooser
                visible: !!app.chooseFor
                homePath: Quickshell.env("HOME") || ""
                to: app.chooseFor ? app.chooseFor.alias : ""
                onAccepted: (paths) => { app.sendTo(app.chooseFor, paths); app.chooseFor = null }
                onCancelled: app.chooseFor = null
            }

            // Someone is sharing with you.
            Item {
                anchors.fill: parent
                visible: !!app.request
                z: 70
                Rectangle { anchors.fill: parent; color: "#33000000" }
                Glass {
                    role: "menu"
                    anchors.centerIn: parent
                    width: 320
                    height: ask.implicitHeight + 40
                    radius: 22
                    Column {
                        id: ask
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                        spacing: 10
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 56; height: 56
                            source: Quickshell.iconPath("org.goldengate.AirDrop", "network-wireless")
                            sourceSize: Qt.size(112, 112)
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: app.request ? app.request.from + " would like to share " + (app.request.count === 1 ? "“" + app.request.files[0] + "”" : app.request.count + " items") + "." : ""
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: !!app.request && app.request.count > 1
                            text: app.request ? app.request.files.join(", ") + (app.request.count > app.request.files.length ? ", …" : "") : ""
                            color: Theme.secondaryLabel
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: app.request ? app.size(app.request.size) + " · saved to Downloads" : ""
                            color: Theme.tertiaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                        Row {
                            topPadding: 6
                            spacing: 8
                            Button { width: (ask.width - 8) / 2; text: "Decline"; onClicked: app.answer(false) }
                            Button { width: (ask.width - 8) / 2; text: "Accept"; prominent: true; onClicked: app.answer(true) }
                        }
                    }
                }
            }

            // Receiving, then received.
            Glass {
                role: "menu"
                visible: !!app.receiving || !!app.received
                z: 65
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: win.toolbarHeight + 8 }
                width: 360
                height: 64
                radius: 18
                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36
                        source: Quickshell.iconPath("org.goldengate.AirDrop", "network-wireless")
                        sourceSize: Qt.size(72, 72)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Text {
                            width: 200
                            elide: Text.ElideRight
                            text: app.receiving ? "Receiving from " + app.receiving.from + "…"
                                : app.received ? (app.received.paths.length === 1 ? app.received.paths[0].split("/").pop() : app.received.paths.length + " items") + " from " + app.received.from
                                : ""
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                        }
                        ProgressBar {
                            visible: !!app.receiving
                            width: 200; height: 6
                            value: app.receiving && app.receiving.total > 0 ? app.receiving.received / app.receiving.total : 0
                        }
                        Text {
                            visible: !!app.received
                            text: "Saved to Downloads"
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                        }
                    }
                }
                Row {
                    visible: !!app.received
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Button {
                        text: "Show"
                        onClicked: {
                            const dir = app.received.paths[0].split("/").slice(0, -1).join("/")
                            Quickshell.execDetached(["sh", "-c", 'gg-files "$1" || xdg-open "$1"', "sh", dir])
                            app.received = null
                        }
                    }
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: closeHover.hovered ? Theme.fill : "transparent"
                        Symbol { anchors.centerIn: parent; name: "xmark"; size: 9; tone: "gray" }
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: app.received = null }
                    }
                }
            }

            // A message (text shared from LocalSend).
            Messages.Sheet {
                visible: !!app.message
                title: app.message ? app.message.from + " sent a message" : ""
                text: app.message ? app.message.text : ""
                confirmText: "Copy"
                onConfirmed: { Quickshell.execDetached(["wl-copy", app.message.text]); app.message = null }
                onCancelled: app.message = null
            }
        }
    }
}
