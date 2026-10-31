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
import "settings/theme"

ShellRoot {
    AppWindow {
        id: win
        title: app.page?.title ? app.page.title + " — System Settings" : "System Settings"
        implicitWidth: 860; implicitHeight: Math.min(740, (Quickshell.screens[0]?.height ?? 900) - 120)
        minimumSize: Qt.size(700, 470)
        sidebarWidth: win.tabletCompact ? (app.showMobileCategories ? win.width : 0) : app.sidebarShown ? 244 : 0
        background: Theme.contentBg

        // Back and forward, and the pane's title.
        toolbarItems: [
            Row {
                x: win.tabletCompact ? win.toolbarSafeX : Math.max(win.contentX + 14, win.toolbarSafeX)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                ToolbarButton {
                    objectName: "settingsSidebarToggle"
                    symbol: "sidebar"
                    round: true
                    onClicked: {
                        if (win.tabletCompact) app.showMobileCategories = !app.showMobileCategories
                        else sys.setPref(["settings", "sidebarShown"], !app.sidebarShown)
                    }
                    Accessible.name: win.tabletCompact ? (app.showMobileCategories ? "Close Categories" : "All Settings") :
                        app.sidebarShown ? "Hide Settings Sidebar" : "Show Settings Sidebar"
                }
                ToolbarPill {
                    visible: !win.tabletCompact
                    ToolbarButton { symbol: "chevron-left"; enabled: app.back.length > 0; onClicked: app.goBack() }
                    ToolbarButton { symbol: "chevron-right"; enabled: app.forward.length > 0; onClicked: app.goForward() }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.tabletCompact && app.showMobileCategories ? "Settings" : (app.page?.title ?? "")
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.font.title3.pixelSize; weight: Font.Bold }
                }
            }
        ]

        sidebar: [
            TextField {
                id: search
                objectName: "settingsSearch"
                width: parent.width; height: 30
                search: true
                placeholder: "Search"
                onAccepted: app.acceptMatch()
                onTextChanged: app.selectedMatch = -1
                input.Keys.onEscapePressed: text = ""
                input.Keys.onDownPressed: app.selectedMatch = Math.min(app.matches.length - 1, app.selectedMatch + 1)
                input.Keys.onUpPressed: app.selectedMatch = Math.max(0, app.selectedMatch - 1)
            },
            Flickable {
                id: navFlick
                y: 40; width: parent.width; height: parent.height - 40
                // Keep the chosen pane's row in view (Keyboard, Trackpad sit below the fold).
                // Opened straight into a pane, the rows aren't laid out when the
                // chosen one asks: it's kept, and asked again as the list settles.
                property Item chosenRow: null
                onContentHeightChanged: if (chosenRow) ensure(chosenRow)
                onHeightChanged: if (chosenRow) ensure(chosenRow)
                function ensure(row) {
                    chosenRow = row
                    if (height <= 0 || contentHeight <= height) return
                    const top = row.mapToItem(nav, 0, 0).y
                    if (top < contentY) contentY = Math.max(0, top - 8)
                    else if (top + row.height > contentY + height) contentY = Math.min(contentHeight - height, top + row.height - height + 8)
                }
                Behavior on contentY { enabled: !Theme.reduceMotion; NumberAnimation { duration: Theme.motion.tap.duration; easing.type: Easing.OutCubic } }
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
                    // What Setup Assistant put off, until it's finished (as
                    // "Finish setting up your Mac" on macOS).
                    SidebarRow {
                        objectName: "finishSetupRow"
                        visible: (sys.region.deferred ?? []).length > 0
                        width: parent.width
                        height: visible ? 30 : 0
                        text: "Finish Setting Up"
                        badge: String((sys.region.deferred ?? []).length)
                        selected: app.current === "finishsetup"
                        selectedFill: win.active ? Theme.accent : Theme.unemphasizedSelection
                        selectedTextColor: win.active ? Theme.selectedText : Theme.label
                        leadingSize: 22
                        leading: Component { PaneIcon { symbol: "gear"; tint: PaneTints.orange; size: 22 } }
                        onClicked: app.open("finishsetup")
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
                                    selectedFill: win.active ? Theme.accent : Theme.unemphasizedSelection
                                    selectedTextColor: win.active ? Theme.selectedText : Theme.label
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
            objectName: "settingsApp"
            anchors.fill: parent
            focus: true

            readonly property var panes: [
                // group, id, title, symbol, colour, file, words to search by
                [1, "wifi", "Wi-Fi", "wifi", PaneTints.blue, "WifiPane", "wireless network internet join"],
                [1, "bluetooth", "Bluetooth", "bluetooth", PaneTints.blue, "BluetoothPane", "devices headphones keyboard mouse pair"],
                [1, "airpods", "AirPods", "headphones", PaneTints.blue, "CitronPodsPane", "CitronPods AirPods battery case noise cancellation anc transparency adaptive conversation awareness ear detection"],
                [1, "network", "Network", "globe", PaneTints.blue, "NetworkPane", "ethernet ip address vpn"],
                [1, "battery", "Battery", "power", PaneTints.green, "BatteryPane", "energy power charge low power mode"],
                [2, "general", "General", "gear", PaneTints.gray, "GeneralPane", "about software update storage date time language region"],
                [2, "intelligence", "Citron Intelligence", "wand", PaneTints.purple, "IntelligencePane", "ai assistant aion labs api key writing tools voice speech conversation"],
                [2, "accessibility", "Accessibility", "person", PaneTints.blue, "AccessibilityPane", "reduce motion transparency text size"],
                [2, "appearance", "Appearance", "contrast", PaneTints.graphite, "AppearancePane", "dark mode light auto accent colour color liquid glass scroll bars"],
                [2, "controlcenter", "Control Center", "control-center", PaneTints.gray, "ControlCenterPane", "menu bar items battery percentage bluetooth sound focus now playing"],
                [2, "dock", "Desktop & Dock", "apps", PaneTints.slate, "DockPane", "dock size pin reorder recents show dock snapping windows edges resize attraction"],
                [2, "menubar", "Menu Bar", "panel-bottom", PaneTints.graphite, "MenuBarPane", "menu bar background clock date seconds 24 hour"],
                [2, "displays", "Displays", "sun-max", PaneTints.blue, "DisplaysPane", "resolution scale brightness night shift monitor"],
                [2, "spotlight", "Spotlight", "search", PaneTints.gray, "SpotlightPane", "search results categories files web calculator"],
                [2, "wallpaper", "Wallpaper", "wallpaper", PaneTints.teal, "WallpaperPane", "background desktop picture"],
                [3, "notifications", "Notifications", "bell", PaneTints.red, "NotificationsPane", "alerts banners badges sounds previews apps"],
                [3, "focus", "Focus", "moon", PaneTints.indigo, "FocusPane", "do not disturb notifications duration schedule allowed apps alarms"],
                [3, "sound", "Sound", "speaker-wave", PaneTints.pink, "SoundPane", "volume output input speakers microphone mute"],
                [4, "lockscreen", "Lock Screen", "lock", PaneTints.graphite, "LockScreenPane", "screen saver display off sleep require password lock message idle"],
                [4, "touchid", "Touch ID & Password", "touchid", PaneTints.rose, "TouchIdPane", "fingerprint finger reader biometric unlock sudo fprintd"],
                [4, "privacy", "Privacy & Security", "shield", PaneTints.blue, "PrivacyPane", "location analytics crash diagnostics"],
                [4, "users", "Users & Groups", "people", PaneTints.blue, "UsersPane", "account password admin"],
                [5, "keyboard", "Keyboard", "keyboard", PaneTints.gray, "KeyboardPane", "key repeat layout input source"],
                [5, "trackpad", "Trackpad & Mouse", "rectangle-fill", PaneTints.gray, "TrackpadPane", "tracking speed natural scrolling tap to click two finger click scroll drag typing sensitivity"],
            ].map((p) => ({ group: p[0], id: p[1], title: p[2], symbol: p[3], tint: p[4], file: p[5], words: p[6] }))
            // Sub-pages of General: [id, title, file]
            readonly property var subpages: ({
                about: { title: "About", file: "AboutPane", parent: "general", symbol: "info", tint: PaneTints.gray, words: "system version hardware memory graphics kernel computer" },
                update: { title: "Software Update", file: "UpdatePane", parent: "general", symbol: "arrow-clockwise", tint: PaneTints.gray, words: "update upgrade packages arch software current" },
                storage: { title: "Storage", file: "StoragePane", parent: "general", symbol: "drive", tint: PaneTints.gray, words: "disk drive space capacity available used" },
                datetime: { title: "Date & Time", file: "DateTimePane", parent: "general", symbol: "clock", tint: PaneTints.blue, words: "date time timezone clock automatic ntp 24 hour" },
                finishsetup: { title: "Finish Setting Up", file: "FinishSetupPane", symbol: "gear", tint: PaneTints.orange, words: "setup deferred time zone formats location finish later" },
                dockapps: { title: "Add to Dock", file: "DockAppsPane", parent: "dock", symbol: "apps", tint: PaneTints.slate, words: "applications install launcher add dock pin reorder" },
                defaultapps: { title: "Default Applications", file: "DefaultAppsPane", parent: "general", symbol: "apps", tint: PaneTints.slate, words: "default browser email pictures text documents zip archive handlers xdg mime" },
                loginitems: { title: "Login Items", file: "LoginItemsPane", parent: "general", symbol: "apps", tint: PaneTints.steel, words: "startup automatic login launch applications start sign in" },
                airplay: { title: "AirPlay Receiver", file: "AirPlayPane", parent: "general", symbol: "airplay", tint: PaneTints.blue, words: "airplay receiver screen mirroring iphone ipad mac mirror code pin uxplay" },
                language: { title: "Language & Region", file: "LanguagePane", parent: "general", symbol: "globe", tint: PaneTints.blue, words: "language locale region measurement format" },
            })
            readonly property var groups: [1, 2, 3, 4, 5].map((g) => panes.filter((p) => p.group === g))
            function paneOf(id) { return subpages[id]?.parent ?? id }
            readonly property var page: panes.find((p) => p.id === current) ?? subpages[current] ?? null

            property string current: Quickshell.env("GG_SETTINGS_PANE") || "general"
            property bool showMobileCategories: true
            readonly property bool sidebarShown: sys.prefs.settings?.sidebarShown ?? true
            property var back: []
            property var forward: []
            property string userName: Quickshell.env("USER") ?? ""
            readonly property Item overlay: win.overlay

            function open(id) {
                if (!(panes.some((p) => p.id === id) || subpages[id])) return
                if (win.tabletCompact) showMobileCategories = false
                if (id === current) return
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
            property int selectedMatch: -1
            function acceptMatch() {
                if (!matches.length) return
                open(matches[Math.max(0, Math.min(matches.length - 1, selectedMatch))].id)
                search.text = ""
                forceActiveFocus()
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
                objectName: "settingsPaneLoader"
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
                function onCurrentChanged() {
                    swap.stop()
                    if (Theme.reduceMotion) { loader.load(); loader.x = 0; loader.opacity = 1 }
                    else { swap.forward = app.forward.length === 0; swap.restart() }
                }
            }
            Connections {
                target: Theme
                function onReduceMotionChanged() {
                    if (Theme.reduceMotion) { swap.stop(); if (loader.shown !== app.current) loader.load(); loader.x = 0; loader.opacity = 1 }
                }
            }
            SequentialAnimation {
                id: swap
                property bool forward: true
                ParallelAnimation {
                    NumberAnimation { target: loader; property: "opacity"; to: 0; duration: Theme.motion.hover }
                    NumberAnimation { target: loader; property: "x"; to: swap.forward ? -24 : 24; duration: Theme.motion.hover; easing.type: Easing.InQuad }
                }
                ScriptAction { script: { loader.load(); loader.x = swap.forward ? 24 : -24 } }
                ParallelAnimation {
                    NumberAnimation { target: loader; property: "opacity"; to: 1; duration: Theme.motion.fade }
                    NumberAnimation { target: loader; property: "x"; to: 0; duration: Theme.motion.tap.duration; easing.type: Easing.OutCubic }
                }
            }
            // Scroll edge under the toolbar.
            Rectangle {
                width: parent.width; height: 14
                readonly property var flick: loader.item
                opacity: flick && flick.contentY > flick.originY - flick.topMargin + 2 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.motion.menu } }
                gradient: Gradient {
                    GradientStop { position: 0; color: win.background }
                    GradientStop { position: 0.6; color: Qt.rgba(win.background.r, win.background.g, win.background.b, 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(win.background.r, win.background.g, win.background.b, 0) }
                }
            }
        }

        // A preference that couldn't be saved: said, not assumed.
        InlineBanner {
            objectName: "settingsWriteError"
            parent: win.overlay
            floating: true
            kind: "error"
            text: sys.writeError
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
            width: Math.min(560, parent.width - 40)
            z: 50
            onDismissed: sys.writeError = ""
        }

        // Search suggestions, under the field.
        Glass {
            id: suggestions
            role: "menu"
            objectName: "settingsSuggestions"
            parent: win.overlay
            readonly property bool expanded: app.matches.length > 0 && search.input.activeFocus
            visible: opacity > 0.001
            enabled: expanded
            opacity: expanded ? 1 : 0
            scale: expanded || Theme.reduceMotion ? 1 : 0.984
            transformOrigin: Item.TopLeft
            Behavior on opacity {
                NumberAnimation { duration: Theme.reduceMotion ? 0 : (suggestions.expanded ? Theme.motion.fade : Theme.motion.hover); easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Theme.reduceMotion
                NumberAnimation { duration: Theme.motion.menu; easing.type: Easing.OutCubic }
            }
            x: 8 + 6; y: win.toolbarHeight + 32
            width: 228; height: sugCol.height + 34
            radius: Theme.radius.menu
            Text {
                x: 12; y: 8
                text: "Suggestions"
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.font.subheadline.pixelSize; weight: Font.DemiBold }
            }
            Column {
                id: sugCol
                x: 5; y: 26; width: parent.width - 10
                Repeater {
                    model: app.matches
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === app.selectedMatch
                        width: sugCol.width; height: 30
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radius.field
                            color: Theme.accent
                            opacity: sh.hovered || parent.selected ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: Theme.reduceMotion ? 0 : Theme.motion.hover; easing.type: Easing.OutCubic }
                            }
                        }
                        PaneIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; symbol: modelData.symbol; tint: modelData.tint }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            text: modelData.title
                            color: sh.hovered || parent.selected ? Theme.selectedText : Theme.label
                            Behavior on color {
                                ColorAnimation { duration: Theme.reduceMotion ? 0 : Theme.motion.hover }
                            }
                            font { family: Theme.fontUi; pixelSize: Theme.font.body.pixelSize }
                        }
                        HoverHandler { id: sh }
                        Accessible.role: Accessible.MenuItem
                        Accessible.name: modelData.title
                        Accessible.onPressAction: { app.selectedMatch = index; app.acceptMatch() }
                        TapHandler { onTapped: { app.selectedMatch = index; app.acceptMatch() } }
                    }
                }
            }
        }
    }
}
