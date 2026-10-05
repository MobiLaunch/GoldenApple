// The Organizer, after Product ▸ Archive: the archived app, and the ways to
// share it — install it on this computer (it appears in Applications), a
// PKGBUILD for Arch and CitronOS, a Flatpak, or a portable archive.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

Sheet {
    id: sheet
    property var app
    property var backend
    property var info: null
    property string message: ""
    property string error: ""
    property string resultPath: ""
    property string working: ""
    panelWidth: 600

    function refresh() {
        backend.call("archiveInfo", {}, (r) => { if (r.ok) sheet.info = r })
    }
    onShownChanged: if (shown) { message = ""; error = ""; resultPath = ""; working = ""; refresh() }

    function distribute(method) {
        working = method
        message = ""
        error = ""
        backend.call("distribute", { method: method }, (r) => {
            sheet.working = ""
            if (!r.ok) { sheet.error = r.error; return }
            sheet.message = r.message
            sheet.resultPath = r.path || ""
            sheet.info = r.info
        })
    }

    readonly property var methods: [
        { id: "install", symbol: "download", title: "Install on This Computer",
          detail: "Adds the app to Applications for you, with its icon. Choose it again to update it." },
        { id: "pkgbuild", symbol: "shippingbox", title: "Arch Linux Package",
          detail: "A PKGBUILD for CitronOS and Arch. makepkg -si builds and installs it for everyone; share it on the AUR." },
        { id: "flatpak", symbol: "layers", title: "Flatpak",
          detail: "A manifest for flatpak-builder: your app in a sandbox with the capabilities you chose, for any Linux." },
        { id: "tarball", symbol: "archive", title: "Portable Archive",
          detail: "A .tar.gz with the app and an install script, for any Linux with the app's libraries." },
    ]

    Column {
        width: parent.width
        spacing: 14
        Row {
            spacing: 14
            Image {
                width: 64; height: 64
                sourceSize: Qt.size(128, 128)
                cache: false
                source: sheet.shown && sheet.app.project ? "file://" + sheet.app.project.root + "/.lcode/userdata/icon-preview.svg" : ""
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: sheet.info ? sheet.info.name + " " + sheet.info.version : "Archive"
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 17; weight: Font.Bold }
                }
                Text {
                    text: !sheet.info ? "" : sheet.info.archived
                        ? "Archived " + Qt.formatDateTime(new Date(sheet.info.archive.date), "d MMM yyyy, hh:mm") + "  ·  " + Math.max(1, Math.round(sheet.info.size / 1024)) + " KB"
                        : "Not archived yet: choose Product ▸ Archive."
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
                Text {
                    visible: !!sheet.info && sheet.info.installed
                    width: sheet.panelWidth - 140
                    elide: Text.ElideMiddle
                    text: "Installed in " + (sheet.info ? sheet.info.installedAt.replace(/^\/home\/[^/]+/, "~") : "")
                    color: "#30d158"
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
            }
        }

        Text {
            text: "Distribute App"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
        }
        Repeater {
            model: sheet.methods
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool unavailable: !sheet.info || !sheet.info.archived || (modelData.id === "flatpak" && !sheet.info.flatpak)
                width: parent.width
                height: 62
                radius: 12
                color: cardHover.hovered && !unavailable ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1) : (Theme.dark ? "#0fffffff" : "#08000000")
                border { width: 0.5; color: Theme.separator }
                opacity: unavailable ? 0.5 : 1
                Symbol { x: 16; anchors.verticalCenter: parent.verticalCenter; name: card.modelData.symbol; size: 24; tone: "accent" }
                Column {
                    x: 54
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54 - 110
                    spacing: 2
                    Text { text: card.modelData.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: card.modelData.id === "flatpak" && sheet.info && !sheet.info.flatpak
                            ? "CitronOS apps run on Quickshell, which isn't a Flatpak runtime." : card.modelData.detail
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
                Button {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    enabled: !card.unavailable && !sheet.working
                    prominent: card.modelData.id === "install"
                    text: sheet.working === card.modelData.id ? "Working…" : card.modelData.id === "install" ? (sheet.info && sheet.info.installed ? "Update" : "Install") : "Export"
                    onClicked: sheet.distribute(card.modelData.id)
                }
                HoverHandler { id: cardHover }
            }
        }

        Text {
            visible: !!sheet.message || !!sheet.error
            width: parent.width
            wrapMode: Text.Wrap
            text: sheet.error || sheet.message
            color: sheet.error ? "#ff453a" : Theme.label
            font { family: Theme.fontUi; pixelSize: 12 }
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            Button {
                visible: !!sheet.info && sheet.info.installed
                text: "Uninstall"
                destructive: true
                enabled: !sheet.working
                onClicked: sheet.distribute("uninstall")
            }
            Button {
                visible: !!sheet.resultPath
                text: "Show in Files"
                onClicked: Quickshell.execDetached(["gg-files", "--select", sheet.resultPath])
            }
            Button {
                text: "Archive Again"
                onClicked: { sheet.close(); sheet.app.archive() }
            }
            Button { text: "Done"; prominent: true; onClicked: sheet.close() }
        }
    }
}
