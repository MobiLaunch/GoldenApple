// Spotlight: glass search capsule over the desktop. Opens with ⌘Space
// (Hyprland binds SUPER+SPACE to `qs ipc call spotlight toggle`).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"
import "spotlight/answers.js" as Answers

PanelWindow {
    id: spot
    property bool open: false
    function toggle() { open = !open; if (open) { input.text = ""; Qt.callLater(() => input.input.forceActiveFocus()) } }

    visible: open || closeTimer.running
    onOpenChanged: if (!open) closeTimer.restart()
    Timer { id: closeTimer; interval: Prefs.reduceMotion ? 1 : 150 }
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "gg-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    IpcHandler {
        target: "spotlight"
        function toggle(): void { spot.toggle() }
        // Open with a search already typed (qs ipc call spotlight search "2+2").
        function search(text: string): void {
            if (!spot.open) spot.toggle()
            input.text = text
        }
    }

    // What the search finds, in the order the Mac shows it: a Top Hit, then
    // an answer (arithmetic, a conversion), apps, System Settings panes,
    // documents in the home folder, and searching the web. One list, so the
    // arrow keys walk through all of it; `section` labels each part.
    readonly property string query: input.text.trim()
    property var files: []              // { path, name, folder, dir } from fileSearch
    // Each kind can be turned off in Settings → Spotlight.
    readonly property var answer: Prefs.spotlightShows("answers") ? Answers.calculate(query) ?? Answers.convert(query) : null
    readonly property var apps: {
        const q = query.toLowerCase()
        if (!q || !Prefs.spotlightShows("apps")) return []
        return DesktopEntries.applications.values
            // GNOME Settings opens CitronOS's own (gnome-control-center wrapper): list it once.
            .filter((e) => !e.noDisplay && e.id !== "org.gnome.Settings" && (e.name.toLowerCase().includes(q) || (e.genericName ?? "").toLowerCase().includes(q) || (e.keywords ?? []).some((k) => k.toLowerCase().startsWith(q))))
            .sort((a, b) => { const at = (e) => { const i = e.name.toLowerCase().indexOf(q); return i < 0 ? 99 : i }; return at(a) - at(b) })
            .slice(0, 6)
    }
    readonly property var results: {
        const q = query
        if (!q) return []
        const lower = q.toLowerCase()
        const out = []
        const app = (e, section) => ({ section: section, kind: "app", entry: e, title: e.name, subtitle: "Application", icon: e.icon })
        let rest = apps
        // Top Hit: the answer, else an app whose name starts with the search.
        if (answer) out.push({ section: "Top Hit", kind: "answer", title: answer.display, subtitle: answer.expression + "  ·  Return copies it", symbol: "calculator" })
        else if (apps.length && apps[0].name.toLowerCase().startsWith(lower)) { out.push(app(apps[0], "Top Hit")); rest = apps.slice(1) }
        for (const e of rest) out.push(app(e, "Applications"))
        for (const p of Prefs.spotlightShows("settings") ? Answers.settings(q) : []) out.push({ section: "System Settings", kind: "settings", pane: p.pane, title: p.title, subtitle: "System Settings", symbol: "gear" })
        for (const f of files.slice(0, 6)) out.push({ section: "Documents", kind: "file", path: f.path, dir: f.dir, title: f.name, subtitle: f.folder, symbol: f.symbol })
        if (Prefs.spotlightShows("web")) out.push({ section: "Web", kind: "web", title: "Search the Web for \u201c" + q + "\u201d", subtitle: "Web", symbol: "globe" })
        return out
    }

    // Documents: names in the home folder (hidden folders skipped), shortly after typing stops.
    Timer {
        id: fileDelay
        interval: 160
        onTriggered: {
            if (spot.query.length < 2 || spot.answer || !Prefs.spotlightShows("files")) { spot.files = []; return }
            fileSearch.running = false
            fileSearch.command = ["sh", "-c", 'cd "$HOME" 2>/dev/null || exit 0; find . -maxdepth 5 \\( -path "*/.*" -prune \\) -o -iname "*$1*" -print 2>/dev/null | head -n 40', "sh", spot.query]
            fileSearch.running = true
        }
    }
    onQueryChanged: { selected = 0; fileDelay.restart() }
    Process {
        id: fileSearch
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Quickshell.env("HOME"), q = spot.query.toLowerCase()
                const kind = (name, isDir) => isDir ? "folder"
                    : /\.(png|jpe?g|gif|webp|heic|svg)$/i.test(name) ? "photo"
                    : /\.(mp3|m4a|flac|ogg|wav|aac)$/i.test(name) ? "music"
                    : /\.(mp4|mkv|mov|webm)$/i.test(name) ? "film" : "doc"
                spot.files = text.split("\n").filter((l) => l && l !== ".").map((l) => {
                    const rel = l.replace(/^\.\//, ""), name = rel.split("/").pop()
                    const isDir = !/\.[A-Za-z0-9]{1,5}$/.test(name)
                    const folder = rel.includes("/") ? "~/" + rel.slice(0, rel.lastIndexOf("/")) : "~"
                    return { path: home + "/" + rel, name: name, folder: folder, dir: isDir, symbol: kind(name, isDir) }
                }).sort((a, b) => (b.name.toLowerCase().startsWith(q) - a.name.toLowerCase().startsWith(q)) || a.name.length - b.name.length)
            }
        }
    }

    property int selected: 0
    property var launchers: []
    function launch(i) {
        const r = results[i]
        if (!r) return
        if (r.kind === "app") {
            const e = r.entry
            const l = launchers.find((x) => x.screen === spot.screen) ?? launchers[0]
            const row = list.itemAtIndex(i)
            if (l?.enabled && row) {
                // Spotlight covers its screen, so the row icon's position is already in screen space.
                const icon = row.appIcon, p = icon.mapToItem(null, 0, 0)
                l.launch(e, Qt.rect(p.x, p.y, icon.width, icon.height))
            } else e.execute()
        } else if (r.kind === "answer") {
            Quickshell.clipboardText = String(parseFloat(answer.value.toPrecision(12)))
        } else if (r.kind === "settings") {
            Quickshell.execDetached(["gg-settings", r.pane])
        } else if (r.kind === "file") {
            Quickshell.execDetached(r.dir ? ["gg-files", r.path] : ["gio", "open", r.path])
        } else if (r.kind === "web") {
            Quickshell.execDetached(["gg-web", query])
        }
        open = false
    }

    MouseArea { anchors.fill: parent; onClicked: spot.open = false }

    ColumnLayout {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.22 }
        width: Math.min(680, parent.width - 32)
        spacing: 10
        opacity: spot.open ? 1 : 0
        scale: spot.open ? 1 : 0.975
        Behavior on opacity { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 140; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; Spring { spring: Theme.popover } }

        Glass {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            role: "regular"
            radius: 28
            // One capsule, as in macOS 26: the glass is the field, with no
            // second ring inside it.
            TextField {
                id: input
                anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
                search: true
                bare: true
                glyphSize: 20
                placeholder: "Spotlight Search"
                input.font.pixelSize: Theme.fs(21)
                input.Keys.onEscapePressed: spot.open = false
                input.Keys.onDownPressed: spot.selected = Math.max(0, Math.min(spot.results.length - 1, spot.selected + 1))
                input.Keys.onUpPressed: spot.selected = Math.max(0, spot.selected - 1)
                input.Keys.onReturnPressed: spot.launch(spot.selected)
            }
        }

        Glass {
            id: resultsPanel
            visible: spot.results.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.contentHeight + 16, Math.max(60, spot.height * 0.78 - 90))
            // The results grow and shrink with what you type instead of jumping.
            Behavior on Layout.preferredHeight { enabled: resultsPanel.visible && !Prefs.reduceMotion; Spring { spring: Theme.snappy } }
            role: "regular"
            radius: 24
            ListView {
                id: list
                anchors { fill: parent; margins: 8 }
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: spot.selected
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                model: spot.results
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property Item appIcon: rowIcon
                    readonly property bool header: index === 0 || spot.results[index - 1].section !== modelData.section
                    readonly property bool current: index === spot.selected
                    width: list.width
                    height: 44 + (header ? 26 : 0)
                    Text {
                        visible: row.header
                        x: 12; y: 6
                        text: row.modelData.section
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 44; radius: 12
                        color: row.current ? Theme.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 1 : 80 } }
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 12
                            Item {
                                Layout.preferredWidth: 30; Layout.preferredHeight: 30
                                Image {
                                    id: rowIcon
                                    anchors.fill: parent
                                    visible: row.modelData.kind === "app"
                                    source: visible ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
                                    sourceSize: Qt.size(60, 60)
                                    scale: row.current && !Prefs.reduceMotion ? 1.055 : 1
                                    Behavior on scale { NumberAnimation { duration: Prefs.reduceMotion ? 1 : 85; easing.type: Easing.OutCubic } }
                                }
                                // Everything else: its glyph on a soft tile, white on the selection.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: row.modelData.kind !== "app"
                                    radius: 8
                                    color: row.current ? "#33ffffff" : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                    Symbol { anchors.centerIn: parent; name: row.modelData.symbol ?? "doc"; size: 17; tone: row.current ? "white" : "accent" }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                elide: Text.ElideRight
                                color: row.current ? "#ffffff" : Theme.label
                                font {
                                    family: Theme.fontUi
                                    pixelSize: row.modelData.kind === "answer" ? 20 : 14
                                    weight: row.modelData.kind === "answer" ? Font.DemiBold : Font.Normal
                                }
                            }
                            Text {
                                Layout.maximumWidth: 260
                                text: row.modelData.subtitle
                                elide: Text.ElideMiddle
                                color: row.current ? "#ccffffff" : Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            }
                        }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: spot.selected = row.index; onClicked: spot.launch(row.index) }
                    }
                }
            }
        }
    }
}

