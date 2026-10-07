//@ pragma AppId org.goldengate.Settings
// Settings, laid out like System Settings on macOS 27: a glass sidebar with
// search (suggestions as you type), your account and the panes in groups,
// each with its coloured icon; back and forward in a glass pill beside the
// pane's title; panes of grouped rows with Liquid Glass controls.
//
// Every control changes the real system: NetworkManager, BlueZ, UPower,
// PipeWire, Hyprland (hyprctl, and its golden-gate/*.conf files), gsettings,
// timedatectl, and the desktop preferences the shell watches
// (~/.config/golden-gate/desktop.json).
//
// GG_SETTINGS_PANE=<id> opens a pane first; `qs -p …/settings.qml ipc call
// settings open <id>` switches a running Settings to it.
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "settings"

ShellRoot {
    AppWindow {
        id: win
        title: "Settings"
        implicitWidth: 780; implicitHeight: Math.min(700, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(680, 440)
        sidebarWidth: 240
        background: Theme.dark ? "#1e1e1e" : "#fbfbfd"

        // Back and forward, and the pane's title.
        toolbarItems: [
            Row {
                x: win.contentX + 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                ToolbarPill {
                    ToolbarButton { symbol: "chevron-left"; enabled: app.back.length > 0; onClicked: app.goBack() }
                    ToolbarButton { symbol: "chevron-right"; enabled: app.forward.length > 0; onClicked: app.goForward() }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: app.page?.title ?? ""
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Bold }
                }
            }
        ]

        sidebar: [
            TextField {
                id: search
                width: parent.width; height: 30
                search: true
                placeholder: "Search"
                onAccepted: if (app.matches.length) { app.open(app.matches[0].id); text = "" }
                input.Keys.onEscapePressed: text = ""
                input.Keys.onDownPressed: suggestions.forceActiveFocus()
            },
            Flickable {
                id: navFlick
                y: 40; width: parent.width; height: parent.height - 40
                // Keep the chosen pane's row in view (Keyboard, Trackpad sit below the fold).
                function ensure(row) {
                    const top = row.mapToItem(nav, 0, 0).y
                    if (top < contentY) contentY = Math.max(0, top - 8)
                    else if (top + row.height > contentY + height) contentY = Math.min(contentHeight - height, top + row.height - height + 8)
                }
                Behavior on contentY { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                contentHeight: nav.height + 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: nav
                    width: parent.width
                    AccountRow {
                        width: parent.width
                        name: app.userName
                        subtitle: "Local Account"
                        clickable: true
                        onClicked: app.open("users")
                    }
                    Repeater {
                        model: app.groups
                        delegate: Column {
                            required property var modelData
                            width: nav.width
                            Item { width: 1; height: 12 }
                            Repeater {
                                model: modelData
                                delegate: SidebarRow {
                                    id: navRow
                                    required property var modelData
                                    readonly property bool currentPane: app.paneOf(app.current) === modelData.id
                                    width: nav.width
                                    height: 30
                                    text: modelData.title
                                    selected: currentPane
                                    selectedFill: win.active ? Theme.accent : (Theme.dark ? "#26ffffff" : "#14000000")
                                    selectedTextColor: win.active ? "#ffffff" : Theme.label
                                    leadingSize: 22
                                    leading: Component {
                                        PaneIcon {
                                            symbol: navRow.modelData.symbol
                                            tint: navRow.modelData.tint
                                            size: 22
                                        }
                                    }
                                    onCurrentPaneChanged: if (currentPane) navFlick.ensure(navRow)
                                    Component.onCompleted: if (currentPane) Qt.callLater(() => navFlick.ensure(navRow))
                                    onClicked: app.open(modelData.id)
                                }
                            }
                        }
                    }
                }
            },
            Scroller { flickable: navFlick }
        ]

        Item {
            id: app
            anchors.fill: parent
            focus: true

            readonly property var panes: [
                // group, id, title, symbol, colour, file, words to search by
                [1, "wifi", "Wi-Fi", "wifi", "#0a84ff", "WifiPane", "wireless network internet join"],
                [1, "bluetooth", "Bluetooth", "bluetooth", "#0a84ff", "BluetoothPane", "devices headphones keyboard mouse pair"],
                [1, "network", "Network", "globe", "#0a84ff", "NetworkPane", "ethernet ip address vpn"],
                [1, "battery", "Battery", "power", "#34c759", "BatteryPane", "energy power charge low power mode"],
                [2, "general", "General", "gear", "#8e8e93", "GeneralPane", "about software update storage date time language region"],
                [2, "intelligence", "Citron Intelligence", "wand", "#9564e8", "IntelligencePane", "ai assistant gemini api key writing tools images photos"],
                [2, "accessibility", "Accessibility", "person", "#0a84ff", "AccessibilityPane", "reduce motion transparency text size"],
                [2, "appearance", "Appearance", "contrast", "#1d1d1f", "AppearancePane", "dark mode light auto accent colour color liquid glass scroll bars"],
                [2, "controlcenter", "Control Center", "control-center", "#8e8e93", "ControlCenterPane", "menu bar items battery percentage bluetooth sound focus now playing"],
                [2, "dock", "Desktop & Dock", "apps", "#1d1d1f", "DockPane", "dock size magnification indicators"],
                [2, "menubar", "Menu Bar", "panel-bottom", "#1d1d1f", "MenuBarPane", "menu bar background clock date seconds 24 hour"],
                [2, "displays", "Displays", "sun-max", "#0a84ff", "DisplaysPane", "resolution scale brightness night shift monitor"],
                [2, "spotlight", "Spotlight", "search", "#8e8e93", "SpotlightPane", "search results categories files web calculator"],
                [2, "wallpaper", "Wallpaper", "wallpaper", "#30b0c7", "WallpaperPane", "background desktop picture"],
                [3, "notifications", "Notifications", "bell", "#ff3b30", "NotificationsPane", "alerts banners badges sounds previews apps"],
                [3, "focus", "Focus", "moon", "#5e5ce6", "FocusPane", "do not disturb notifications"],
                [3, "sound", "Sound", "speaker-wave", "#ff2d55", "SoundPane", "volume output input speakers microphone mute"],
                [4, "lockscreen", "Lock Screen", "lock", "#1d1d1f", "LockScreenPane", "screen saver display off sleep require password lock message idle"],
                [4, "privacy", "Privacy & Security", "shield", "#0a84ff", "PrivacyPane", "location analytics crash diagnostics"],
                [4, "users", "Users & Groups", "people", "#0a84ff", "UsersPane", "account password admin"],
                [5, "keyboard", "Keyboard", "keyboard", "#8e8e93", "KeyboardPane", "key repeat layout input source"],
                [5, "trackpad", "Trackpad & Mouse", "rectangle-fill", "#8e8e93", "TrackpadPane", "tracking speed natural scrolling tap to click pointer"],
            ].map((p) => ({ group: p[0], id: p[1], title: p[2], symbol: p[3], tint: p[4], file: p[5], words: p[6] }))
            // Sub-pages of General: [id, title, file]
            readonly property var subpages: ({
                about: { title: "About", file: "AboutPane", parent: "general", symbol: "info", tint: "#8e8e93", words: "system version hardware memory graphics kernel computer" },
                update: { title: "Software Update", file: "UpdatePane", parent: "general", symbol: "arrow-clockwise", tint: "#8e8e93", words: "update upgrade packages arch software current" },
                storage: { title: "Storage", file: "StoragePane", parent: "general", symbol: "drive", tint: "#8e8e93", words: "disk drive space capacity available used" },
                datetime: { title: "Date & Time", file: "DateTimePane", parent: "general", symbol: "clock", tint: "#0a84ff", words: "date time timezone clock automatic ntp 24 hour" },
                language: { title: "Language & Region", file: "LanguagePane", parent: "general", symbol: "globe", tint: "#0a84ff", words: "language locale region measurement format" },
            })
            readonly property var groups: [1, 2, 3, 4, 5].map((g) => panes.filter((p) => p.group === g))
            function paneOf(id) { return subpages[id]?.parent ?? id }
            readonly property var page: panes.find((p) => p.id === current) ?? subpages[current] ?? null

            property string current: Quickshell.env("GG_SETTINGS_PANE") || "appearance"
            property var back: []
            property var forward: []
            property string userName: Quickshell.env("USER") ?? ""
            readonly property Item overlay: win.overlay

            function open(id) {
                if (id === current || !(panes.some((p) => p.id === id) || subpages[id])) return
                back = back.concat([current]); forward = []
                current = id
            }
            function push(id) { open(id) }
            function goBack() { if (!back.length) return; forward = [current].concat(forward); current = back[back.length - 1]; back = back.slice(0, -1) }
            function goForward() { if (!forward.length) return; back = back.concat([current]); current = forward[0]; forward = forward.slice(1) }

            readonly property var matches: {
                const q = search.text.trim().toLowerCase()
                if (!q) return []
                const nested = Object.keys(subpages).map((id) => Object.assign({ id: id }, subpages[id]))
                return nested.concat(panes)
                    .filter((p) => p.title.toLowerCase().includes(q) || (p.words ?? "").includes(q))
                    .slice(0, 6)
            }

            Keys.onPressed: (e) => {
                if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_BracketLeft) { goBack(); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_BracketRight) { goForward(); e.accepted = true }
                else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_F) { search.input.forceActiveFocus(); e.accepted = true }
            }

            Sys { id: sys }

            Process {
                running: true
                command: ["sh", "-c", "u=$(id -un); n=$(getent passwd \"$u\" | cut -d: -f5 | cut -d, -f1); echo \"${n:-$u}\""]
                stdout: StdioCollector { onStreamFinished: if (text.trim()) app.userName = text.trim() }
            }
            IpcHandler {
                target: "settings"
                function open(pane: string): void { app.open(pane) }
            }

            // The pane, sliding in from the side you went.
            Loader {
                id: loader
                width: parent.width; height: parent.height
                property string shown: ""
                function load() {
                    const f = app.page?.file
                    if (!f) return
                    setSource(Qt.resolvedUrl("settings/panes/" + f + ".qml"), { sys: sys, nav: app })
                    shown = app.current
                }
                Component.onCompleted: load()
                onStatusChanged: {
                    if (status === Loader.Error)
                        console.warn("CitronOS Settings: failed to load pane", app.current, source)
                }
            }
            Text {
                // A QML import or component failure must not produce a silent
                // empty Settings window (particularly after an update).
                anchors.centerIn: loader
                width: parent.width - 48
                visible: loader.status === Loader.Error
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: Theme.secondaryLabel
                text: "The " + (app.page?.title ?? "selected") + " settings pane couldn't load. Close and reopen Settings, or check the Quickshell log."
            }
            Connections {
                target: app
                function onCurrentChanged() { swap.forward = app.forward.length === 0; swap.restart() }
            }
            SequentialAnimation {
                id: swap
                property bool forward: true
                ParallelAnimation {
                    NumberAnimation { target: loader; property: "opacity"; to: 0; duration: 90 }
                    NumberAnimation { target: loader; property: "x"; to: swap.forward ? -24 : 24; duration: 90; easing.type: Easing.InQuad }
                }
                ScriptAction { script: { loader.load(); loader.x = swap.forward ? 24 : -24 } }
                ParallelAnimation {
                    NumberAnimation { target: loader; property: "opacity"; to: 1; duration: 180 }
                    NumberAnimation { target: loader; property: "x"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                }
            }
            // Scroll edge under the toolbar.
            Rectangle {
                width: parent.width; height: 14
                readonly property var flick: loader.item
                opacity: flick && flick.contentY > flick.originY - flick.topMargin + 2 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: win.background }
                    GradientStop { position: 0.6; color: Qt.rgba(win.background.r, win.background.g, win.background.b, 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(win.background.r, win.background.g, win.background.b, 0) }
                }
            }
        }

        // A preference that couldn't be saved: said, not assumed.
        Glass {
            objectName: "settingsWriteError"
            parent: win.overlay
            visible: !!sys.writeError
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            width: Math.min(560, parent.width - 40)
            height: writeErrorText.implicitHeight + 24
            radius: 16
            z: 50
            Text {
                id: writeErrorText
                anchors { left: parent.left; right: dismissWriteError.left; margins: 14; verticalCenter: parent.verticalCenter }
                text: sys.writeError
                wrapMode: Text.WordWrap
                color: "#ff453a"
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            Button { id: dismissWriteError; text: "OK"; anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } onClicked: sys.writeError = "" }
        }

        // Search suggestions, under the field.
        Rectangle {
            id: suggestions
            parent: win.overlay
            visible: app.matches.length > 0 && search.input.activeFocus
            x: 8 + 6; y: win.toolbarHeight + 32
            width: 228; height: sugCol.height + 34
            radius: 12
            color: Theme.dark ? "#f5323236" : "#faf6f6f8"
            border { width: 0.5; color: Theme.dark ? "#33ffffff" : "#26000000" }
            Rectangle { z: -1; anchors { fill: parent; topMargin: 4; bottomMargin: -8 } radius: parent.radius + 2; color: "#1f000000" }
            Text {
                x: 12; y: 8
                text: "Suggestions"
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
            }
            Column {
                id: sugCol
                x: 5; y: 26; width: parent.width - 10
                Repeater {
                    model: app.matches
                    delegate: Item {
                        required property var modelData
                        width: sugCol.width; height: 30
                        Rectangle { anchors.fill: parent; radius: 7; color: Theme.accent; visible: sh.hovered }
                        PaneIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; symbol: modelData.symbol; tint: modelData.tint }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: sh.hovered ? "#ffffff" : Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                        HoverHandler { id: sh }
                        TapHandler { onTapped: { app.open(modelData.id); search.text = ""; app.forceActiveFocus() } }
                    }
                }
            }
        }
    }
}
