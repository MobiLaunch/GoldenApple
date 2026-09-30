//@ pragma AppId org.goldengate.Setup
// Setup Assistant: the first thing after the first login, as on a new Mac.
//
// A hello written in Liquid Glass over drifting colour, then: Country or
// Region (keyboard and time zone), Wi-Fi, Data & Privacy, Location Services,
// Time Zone, Analytics (crash and diagnostics sharing), Choose Your Look, and
// Welcome. The panels are the compositor's Liquid Glass shader, which works
// here because the assistant draws the backdrop it bends.
//
// It runs once: finishing writes ~/.config/golden-gate/setup-done, and
// hyprland.conf only starts it while that file is missing (and not with
// gg.nosetup on the kernel command line). GG_SETUP_STEP=<n> opens a step
// directly (screenshots).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "lib"
import "lib/theme"
import "setup"
import "setup/regions.js" as Regions

ShellRoot {
    id: root
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config")
    readonly property string here: decodeURIComponent(Qt.resolvedUrl(".").toString().replace("file://", ""))

    FileView {
        path: root.configDir + "/golden-gate/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            let prefs = {}
            try { prefs = JSON.parse(text()) } catch (e) {}
            Theme.reduceMotion = prefs.reduceMotion ?? false
            Theme.reduceTransparency = prefs.reduceTransparency ?? false
        }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "gg-setup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "black"

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            // -------------------------------------------------------------- state
            property int step: Math.max(0, Math.min(9, parseInt(Quickshell.env("GG_SETUP_STEP") || "0", 10) || 0))   // 0 = hello
            readonly property var steps: ["hello", "account", "region", "wifi", "privacy", "location", "timezone", "analytics", "look", "welcome"]
            property var region: Regions.LIST[0]
            property string zone: region.zone
            property bool location: true
            property bool shareDiagnostics: true
            property bool shareWithDevelopers: false
            property string look: "light"
            property bool finishing: false
            property bool liveSession: false
            property bool switchAfterFinish: false
            property string createdUsername: ""
            property string finishError: ""
            property var preferences: ({})

            function go(n) {
                if (pageSwap.running || finishing || n < 0 || n >= steps.length || n === step) return
                if (Theme.reduceMotion) { step = n; return }
                pageSwap.forward = n > step
                pageSwap.target = n
                pageSwap.restart()
            }
            function next() { go(step + 1) }
            function back() { go(step - 1) }
            // Return is the default button: Continue.
            function defaultButton() {
                if (step === 0) next()
                else if (page.item && page.item.canContinue !== false) (steps[step] === "account" ? page.item.submit() : page.item.next())
            }
            Keys.onReturnPressed: defaultButton()
            Keys.onEnterPressed: defaultButton()
            Keys.onSpacePressed: if (step === 0) next()

            function run(cmd) { Quickshell.execDetached(cmd) }
            function setKeyboard(kb) {
                const l = Regions.layout(kb)
                run(["hyprctl", "--batch", "keyword input:kb_layout " + l.layout + " ; keyword input:kb_variant " + l.variant])
            }
            function setLook(v) {
                look = v
                const dark = v === "dark" || (v === "auto" && (new Date().getHours() < 7 || new Date().getHours() >= 19))
                Theme.dark = dark
                run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", dark ? "prefer-dark" : "default"])
            }
            // Everything chosen, saved; then the desktop.
            function finish(switchUser) {
                if (finishing) return
                finishing = true
                switchAfterFinish = switchUser === true
                finishError = ""
                const l = Regions.layout(region.keyboard)
                preferences = {layout: l.layout, variant: l.variant, look: look, location: location,
                    shareDiagnostics: shareDiagnostics, shareWithDevelopers: shareWithDevelopers}
                if (createdUsername) accountFinish.running = true
                else saveSettings.running = true
            }
            Process {
                id: accountFinish
                command: ["sh", root.here + "/setup/account-call.sh"]
                stdinEnabled: true
                onStarted: {
                    write(JSON.stringify({operation: "finish", username: stage.createdUsername, preferences: stage.preferences}))
                    stdinEnabled = false
                }
                onExited: (code) => {
                    stdinEnabled = true
                    if (code === 0) saveSettings.running = true
                    else { stage.finishing = false; stage.finishError = "Your account exists, but its settings could not be saved. Authorize the request and try again." }
                }
            }
            Process {
                id: saveSettings
                command: ["python3", root.here + "/setup/save-preferences.py"]
                stdinEnabled: true
                onStarted: { write(JSON.stringify(stage.preferences)); stdinEnabled = false }
                onExited: (code) => {
                    stdinEnabled = true
                    if (code !== 0) { stage.finishing = false; stage.finishError = "Settings could not be saved. Check free disk space and try again."; return }
                    stage.run(["timedatectl", "set-timezone", stage.zone])
                    stage.run(["gsettings", "set", "org.gnome.system.location", "enabled", String(stage.location)])
                    if (stage.shareDiagnostics) stage.run(["bash", root.here + "/setup/crash-watch.sh"])
                    if (stage.switchAfterFinish && stage.createdUsername && !stage.liveSession) {
                        const sid = Quickshell.env("XDG_SESSION_ID") || ""
                        if (!sid) {
                            stage.finishing = false
                            stage.finishError = "Golden Gate could not identify this login session. Use the system menu to sign out, then choose " + stage.createdUsername + " at the login screen."
                            return
                        }
                        switchSession.command = ["loginctl", "terminate-session", sid]
                        switchSession.running = true
                    } else {
                        outro.start()
                    }
                }
            }
            Process {
                id: switchSession
                onExited: (code) => {
                    // A successful terminate-session normally removes this process
                    // before the callback. If it returns while we are still alive,
                    // close Setup. A failure keeps the user in control.
                    if (code === 0) Qt.quit()
                    else {
                        stage.finishing = false
                        stage.finishError = "The account is ready, but Golden Gate could not sign out automatically. Use the system menu to sign out, then choose " + stage.createdUsername + "."
                    }
                }
            }
            Process {
                running: true
                command: ["sh", "-c", "test -d /run/archiso"]
                onExited: (code) => stage.liveSession = code === 0
            }

            // Guess the region from the time zone and language.
            Process {
                running: true
                command: ["readlink", "-f", "/etc/localtime"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const r = Regions.guess(text.trim().split("zoneinfo/")[1] ?? "", Quickshell.env("LANG") ?? "")
                        stage.region = r
                        stage.zone = r.zone
                    }
                }
            }

            // -------------------------------------------------------------- backdrop
            Backdrop {
                id: backdrop
                anchors.fill: parent
                moving: GraphicsInfo.api !== GraphicsInfo.Software && !Theme.reduceMotion
            }

            // -------------------------------------------------------------- hello
            Item {
                id: helloScene
                anchors.fill: parent
                visible: opacity > 0
                opacity: stage.step === 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

                GlassHello {
                    id: hello
                    width: 720; height: 340
                    scale: Math.min(1.25, stage.width / 1100)
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -40
                    progress: Theme.reduceMotion ? 1 : 0
                }
                // Written, held, rubbed out and written again, until you go on.
                SequentialAnimation {
                    running: stage.step === 0 && !Theme.reduceMotion
                    loops: Animation.Infinite
                    PauseAnimation { duration: 600 }
                    NumberAnimation { target: hello; property: "progress"; from: 0; to: 1; duration: 3400; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 5200 }
                    NumberAnimation { target: hello; property: "opacity"; to: 0; duration: 700 }
                    PropertyAction { target: hello; property: "progress"; value: 0 }
                    PropertyAction { target: hello; property: "opacity"; value: 1 }
                }
                // Get started: a glass button that appears once hello is written.
                Item {
                    id: startButton
                    anchors { horizontalCenter: parent.horizontalCenter; top: hello.bottom; topMargin: 70 * hello.scale }
                    width: 64; height: 64
                    opacity: hello.progress > 0.85 || startShown ? 1 : 0
                    property bool startShown: false
                    onOpacityChanged: if (opacity === 1) startShown = true
                    Behavior on opacity { NumberAnimation { duration: 600 } }
                    LiquidGlass {
                        anchors.fill: parent
                        radius: 32; bezel: 18; strength: 16
                        tint: "#40ffffff"
                    }
                    Symbol { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; name: "chevron-right"; tone: "white"; size: 26 }
                    TapHandler { onTapped: stage.next() }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; top: startButton.bottom; topMargin: 14 }
                    opacity: startButton.opacity * 0.85
                    text: "Get Started"
                    color: "#ffffff"
                    font { family: Theme.fontUi; pixelSize: 14; weight: Font.Medium }
                }
            }

            // -------------------------------------------------------------- steps
            Item {
                id: sheetHolder
                anchors.centerIn: parent
                width: Math.min(700, stage.width - 32); height: Math.min(660, stage.height - 32)
                visible: opacity > 0
                opacity: stage.step > 0 ? 1 : 0
                scale: stage.step > 0 ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 550; easing.type: Easing.OutCubic } }

                LiquidGlass {
                    anchors.fill: parent
                    radius: 34; bezel: 30; strength: 38
                    tint: Theme.dark ? "#c4202024" : "#d2f5f5f8"
                }
                Loader {
                    id: page
                    width: parent.width; height: parent.height
                    // Keys (Return = Continue) go to the assistant, not the old page.
                    onLoaded: stage.forceActiveFocus()
                    sourceComponent: [null, accountStep, regionStep, wifiStep, privacyStep, locationStep, zoneStep, analyticsStep, lookStep, welcomeStep][stage.step]
                }
            }
            // Page change: the old page slides out, the new one in.
            SequentialAnimation {
                id: pageSwap
                property int target: 0
                property bool forward: true
                ParallelAnimation {
                    NumberAnimation { target: page; property: "opacity"; to: 0; duration: 140 }
                    NumberAnimation { target: page; property: "x"; to: pageSwap.forward ? -40 : 40; duration: 140; easing.type: Easing.InCubic }
                }
                ScriptAction { script: { stage.step = pageSwap.target; page.x = pageSwap.forward ? 40 : -40 } }
                ParallelAnimation {
                    NumberAnimation { target: page; property: "opacity"; to: 1; duration: 260 }
                    NumberAnimation { target: page; property: "x"; to: 0; duration: 320; easing.type: Easing.OutCubic }
                }
            }
            // The desktop, revealed.
            SequentialAnimation {
                id: outro
                PauseAnimation { duration: Theme.reduceMotion ? 0 : 500 }
                NumberAnimation { target: stage; property: "opacity"; to: 0; duration: Theme.reduceMotion ? 0 : 700; easing.type: Easing.InOutQuad }
                ScriptAction { script: Qt.quit() }
            }

            // ---------------------------------------------------------- step pages
            Component {
                id: accountStep
                AccountStep {
                    createdUsername: stage.createdUsername
                    onAccountCreated: (username) => stage.createdUsername = username
                    onBack: stage.back()
                    onAdvance: stage.next()
                }
            }
            Component {
                id: regionStep
                StepFrame {
                    symbol: "globe"
                    title: "Select Your Country or Region"
                    canGoBack: true
                    onBack: stage.back()
                    onNext: { stage.setKeyboard(stage.region.keyboard); stage.next() }
                    Rectangle {
                        id: search
                        width: parent.width; height: 30; radius: 8
                        color: Theme.dark ? "#1affffff" : "#b3ffffff"
                        border { width: 0.5; color: Theme.separator }
                        Symbol { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "search"; tone: "gray"; size: 13 }
                        TextInput {
                            id: q
                            x: 30; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                            color: Theme.label; clip: true
                            font { family: Theme.fontUi; pixelSize: 13 }
                            Text { visible: !q.text; text: "Search"; color: Theme.tertiaryLabel; font: q.font }
                        }
                    }
                    ListView {
                        id: list
                        y: 40; width: parent.width; height: parent.height - 40
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Regions.LIST.filter((r) => r.name.toLowerCase().includes(q.text.toLowerCase()))
                        Component.onCompleted: Qt.callLater(() => positionViewAtIndex(Math.max(0, model.findIndex((r) => r.name === stage.region.name)), ListView.Contain))
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool chosen: modelData.name === stage.region.name
                            width: list.width; height: 34; radius: 8
                            color: chosen ? Theme.accent : "transparent"
                            Text {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.flag
                                font { family: "Noto Color Emoji"; pixelSize: 17 }
                            }
                            Text {
                                x: 44; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                color: parent.chosen ? "#ffffff" : Theme.label
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }
                            TapHandler {
                                onTapped: { stage.region = modelData; stage.zone = modelData.zone }
                                onDoubleTapped: { stage.region = modelData; stage.zone = modelData.zone; stage.setKeyboard(modelData.keyboard); stage.next() }
                            }
                        }
                    }
                }
            }

            Component {
                id: wifiStep
                WifiStep { onBack: stage.back(); onNext: stage.next() }
            }

            Component {
                id: privacyStep
                StepFrame {
                    symbol: "shield"
                    title: "Data & Privacy"
                    text: "This icon appears when Golden Gate asks to use your personal information."
                    onBack: stage.back(); onNext: stage.next()
                    Column {
                        width: parent.width
                        spacing: 14
                        Repeater {
                            model: [
                                "Golden Gate is designed to protect your information and let you choose what you share.",
                                "Nothing leaves this computer unless you decide it should. There is no online account to create, no advertising identifier and no background telemetry.",
                                "Your files, notes, photos and music stay in your home folder, in ordinary formats any app can open.",
                                "On the next screens you can choose whether apps may use your location, and whether to share crash reports with the people who make Golden Gate.",
                            ]
                            delegate: Text {
                                required property string modelData
                                width: parent.width; wrapMode: Text.WordWrap
                                text: modelData
                                color: Theme.label
                                lineHeight: 1.15
                                font { family: Theme.fontUi; pixelSize: 13 }
                            }
                        }
                    }
                }
            }

            Component {
                id: locationStep
                StepFrame {
                    symbol: "location"
                    title: "Enable Location Services"
                    text: "Location Services lets apps like Maps and Weather use this computer's approximate location, found from nearby Wi-Fi networks."
                    onBack: stage.back(); onNext: stage.next()
                    Column {
                        width: parent.width
                        spacing: 18
                        Checkbox {
                            text: "Enable Location Services on this computer"
                            detail: "You can change this later in Settings › Privacy."
                            checked: stage.location
                            onCheckedChanged: stage.location = checked
                        }
                    }
                }
            }

            Component {
                id: zoneStep
                TimeZoneStep {
                    zone: stage.zone
                    onZoneChosen: (z) => stage.zone = z
                    onBack: stage.back(); onNext: stage.next()
                }
            }

            Component {
                id: analyticsStep
                StepFrame {
                    symbol: "gauge"
                    title: "Analytics"
                    text: "Help make Golden Gate better by sharing what went wrong when something goes wrong."
                    onBack: stage.back(); onNext: stage.next()
                    Column {
                        width: parent.width
                        spacing: 20
                        Checkbox {
                            text: "Share crash and diagnostics logs with the Golden Gate developers"
                            detail: "When an app or the desktop quits unexpectedly, you'll be offered a report of what happened: the crash, recent errors and this computer's hardware and versions. Nothing is sent until you've seen it and chosen to send it."
                            checked: stage.shareDiagnostics
                            onCheckedChanged: stage.shareDiagnostics = checked
                        }
                        Checkbox {
                            text: "Share crash data with app developers"
                            detail: "Include apps that aren't part of Golden Gate, so their developers can be told about crashes too."
                            checked: stage.shareWithDevelopers
                            onCheckedChanged: stage.shareWithDevelopers = checked
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            text: "Reports never include the contents of your files. Reports are always saved in Documents › Diagnostics, and you can write one yourself any time with gg-diagnostics."
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 11 }
                        }
                    }
                }
            }

            Component {
                id: lookStep
                LookStep {
                    look: stage.look
                    onChosen: (v) => stage.setLook(v)
                    onBack: stage.back(); onNext: stage.next()
                }
            }

            Component {
                id: welcomeStep
                StepFrame {
                    symbol: "logo"
                    symbolColor: "#ff9f0a"
                    title: "Welcome to Golden Gate"
                    text: "Everything's set up. Your apps are in the Dock, Spotlight is ⌘ Space, and Control Center is at the top right of the menu bar."
                    continueText: stage.finishing ? "Saving…" : "Get Started"
                    canContinue: !stage.finishing
                    canGoBack: !stage.finishing
                    secondaryText: stage.createdUsername && !stage.liveSession && !stage.finishing ? "Sign Out & Switch User" : ""
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                        text: stage.finishError || (stage.createdUsername
                            ? (stage.liveSession
                                ? "Account created: " + stage.createdUsername + ". This is a live session, so the account is temporary; you can sign in to it from another console while the live system is running."
                                : "Account created: " + stage.createdUsername + ". Choose Get Started to stay signed in as " + Quickshell.env("USER") + ", or sign out now and continue in your new Golden Gate account.")
                            : "")
                        color: stage.finishError ? "#d8483e" : Theme.secondaryLabel
                        font.pixelSize: 13
                    }
                    onBack: stage.back()
                    onSecondary: stage.finish(true)
                    onNext: stage.finish(false)
                }
            }
        }
    }
}

