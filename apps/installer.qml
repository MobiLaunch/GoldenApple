//@ pragma AppId org.goldengate.Installer
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: "Install CitronOS"
        implicitWidth: 780
        implicitHeight: 590
        minimumSize: Qt.size(720, 540)
        resizable: false
        // Nothing closes the installer while it's erasing and copying: the
        // install would carry on without a window to say how it ended.
        closeAction: () => {
            if (stage.installing) {
                stage.closeRefused = true
                closeNotice.restart()
            } else {
                Qt.quit()
            }
        }

        Item {
            id: stage
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("installer/helper.py").toString().replace("file://", "")
            property int step: 0
            property var disks: []
            property var disk: null
            property bool liveSession: false
            property bool preflightReady: false

            property string username: ""
            property string password: ""
            property string passwordConfirm: ""
            property bool eraseConfirmed: false

            property string error: ""
            property string status: ""
            property string detail: ""
            property real progress: 0
            property bool installing: false
            property bool complete: false
            property bool closeRefused: false
            // Set once the helper has started erasing: after that a failure is a
            // partial install, not a problem to fix on the confirmation page.
            property bool erased: false
            property string failedStage: ""
            property string log: ""

            function selectedModel() {
                return disk && disk.model ? disk.model : "Storage Device"
            }

            function selectedPath() {
                return disk && disk.path ? disk.path : ""
            }

            function accountValid() {
                // The quick check; installer/helper.py check-account has the
                // final say (setup/account_rules.py) before the erase step.
                return /^[a-z_][a-z0-9_-]{0,30}$/.test(username)
                    && password.length >= 8 && password.length <= 256
                    && !/[\x00-\x1f\x7f]/.test(password)
                    && password === passwordConfirm
            }

            function canContinue() {
                if (!liveSession || !preflightReady || installing)
                    return false
                if (step === 1)
                    return !!disk
                if (step === 2)
                    return accountValid()
                if (step === 3)
                    return !!disk && accountValid() && eraseConfirmed
                return true
            }

            function next() {
                error = ""
                if (step === 2) {
                    if (!checkAccount.running)
                        checkAccount.running = true
                    return
                }
                if (step < 3) {
                    step++
                    return
                }
                if (step === 3)
                    beginInstall()
            }

            // After a partial install: choose and confirm the disk again, from
            // a fresh list (it may have changed).
            function startOver() {
                error = ""
                erased = false
                failedStage = ""
                eraseConfirmed = false
                disk = null
                disks = []
                scan.running = true
                progress = 0
                step = 1
            }

            Timer { id: closeNotice; interval: 4000; onTriggered: stage.closeRefused = false }

            function back() {
                if (step > 0 && step < 4 && !installing) {
                    error = ""
                    step--
                }
            }

            function consume(line) {
                if (!line || !line.trim())
                    return
                try {
                    const event = JSON.parse(line)
                    if (event.event === "progress") {
                        progress = event.progress ?? progress
                        status = event.message ?? status
                        detail = event.detail ?? ""
                    } else if (event.event === "done") {
                        progress = 1
                        status = event.message ?? "CitronOS is installed."
                        detail = "You can restart into your new system."
                        installing = false
                        complete = true
                        step = 5
                    } else if (event.event === "erasing") {
                        erased = true
                    } else if (event.event === "error") {
                        error = event.message ?? "Installation could not complete."
                        erased = erased || !!event.erased
                        failedStage = event.stage ?? ""
                        log = event.log ?? ""
                        installing = false
                        eraseConfirmed = false
                        step = erased ? 6 : 3
                    }
                } catch (e) {
                    // Only structured helper events drive the UI.
                }
            }

            function beginInstall() {
                if (!canContinue())
                    return
                installing = true
                complete = false
                erased = false
                failedStage = ""
                error = ""
                progress = 0.01
                status = "Starting installation…"
                detail = ""
                step = 4
                // Live media normally grants the installer passwordless sudo.
                // If that policy is missing or changed, fall back to the desktop
                // Polkit agent instead of failing silently after the confirmation step.
                // systemd-inhibit holds off shutdown, restart and sleep until it ends.
                install.command = [
                    "sh", "-c",
                    "inh=''; if command -v systemd-inhibit >/dev/null 2>&1; then "
                    + "inh='systemd-inhibit --what=shutdown:sleep:idle:handle-power-key:handle-suspend-key:handle-lid-switch --who=CitronOS-Installer --why=Installing --mode=block'; fi; "
                    + "if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then exec sudo -n $inh python3 \"$1\" install; "
                    + "elif command -v pkexec >/dev/null 2>&1; then exec pkexec $inh python3 \"$1\" install; "
                    + "else printf '%s\\n' 'No administrator authorization method is available.' >&2; exit 127; fi",
                    "sh", helper
                ]
                install.running = true
            }

            Process {
                id: checkAccount
                command: ["python3", stage.helper, "check-account"]
                stdinEnabled: true
                onStarted: {
                    write(JSON.stringify({ username: stage.username, password: stage.password }))
                    stdinEnabled = false
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r && r.ok && stage.step === 2) stage.step = 3
                        else stage.error = r?.error || "The account couldn't be checked."
                    }
                }
                onExited: stdinEnabled = true
            }

            Process {
                id: preflight
                running: true
                command: ["python3", stage.helper, "preflight"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            stage.liveSession = !!r.live
                            stage.preflightReady = !!r.ok
                            if (!r.live)
                                stage.error = "Installation is only available when booted from CitronOS live media."
                            else if (!r.uefi)
                                stage.error = "CitronOS currently requires the computer to be booted in UEFI mode before installation."
                            else if ((r.missing ?? []).length)
                                stage.error = "The live image is missing installer tools: " + r.missing.join(", ")
                            else
                                stage.error = ""
                        } catch (e) {
                            stage.error = "The installer preflight check could not be read."
                        }
                    }
                }
            }

            Process {
                id: scan
                running: true
                command: ["python3", stage.helper, "disks"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            stage.disks = JSON.parse(text)
                            if (!stage.disks.length)
                                stage.error = "No internal disk larger than 32 GB was found."
                        } catch (e) {
                            stage.error = "Storage devices could not be read."
                        }
                    }
                }
                onExited: (code) => {
                    if (code !== 0)
                        stage.error = "Storage devices could not be read."
                }
            }

            Process {
                id: install
                stdinEnabled: true
                stdout: SplitParser { onRead: (line) => stage.consume(line) }

                onStarted: {
                    const payload = {
                        device: stage.selectedPath(),
                        username: stage.username,
                        password: stage.password,
                        identity: stage.disk ? stage.disk.identity ?? "" : "",
                        hostname: "golden-gate",
                        confirm: "ERASE:" + stage.selectedPath()
                    }
                    write(JSON.stringify(payload))
                    stdinEnabled = false
                }

                onExited: (code) => {
                    stdinEnabled = true
                    if (code !== 0 && stage.installing) {
                        stage.installing = false
                        stage.eraseConfirmed = false
                        stage.step = stage.erased ? 6 : 3
                        if (!stage.error)
                            stage.error = stage.erased
                                ? "The installer stopped before it finished."
                                : "Installation couldn't start: administrator authorization was refused or isn't available."
                    }
                }
            }

            Column {
                id: body
                anchors {
                    fill: parent
                    leftMargin: 42
                    rightMargin: 42
                    topMargin: 34
                    bottomMargin: 70
                }
                spacing: 16

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: stage.step === 0 ? "logo"
                        : stage.step === 1 ? "drive"
                        : stage.step === 2 ? "person"
                        : stage.step === 3 ? "info"
                        : stage.step === 4 ? "arrow-clockwise"
                        : stage.step === 6 ? "warning"
                        : "checkmark"
                    size: 58
                    tone: stage.step === 3 || stage.step === 6 ? "red" : stage.step === 5 ? "accent" : "auto"
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.label
                    font.family: Theme.fontUi
                    font.pixelSize: 25
                    font.weight: Font.DemiBold
                    text: stage.step === 0 ? "Install CitronOS"
                        : stage.step === 1 ? "Choose a Destination"
                        : stage.step === 2 ? "Create Your Account"
                        : stage.step === 3 ? "Ready to Install"
                        : stage.step === 4 ? "Installing CitronOS"
                        : stage.step === 6 ? "Installation Didn't Finish"
                        : "Installation Complete"
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: Theme.secondaryLabel
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    text: stage.step === 0
                        ? "Install the same CitronOS system you are using now onto this computer."
                        : stage.step === 1
                            ? "Choose the internal disk CitronOS should use. The live USB is hidden automatically."
                            : stage.step === 2
                                ? "This administrator account will be ready the first time the installed system starts."
                                : stage.step === 3
                                    ? "CitronOS will erase " + stage.selectedPath() + " and install a fresh system. This cannot be undone."
                                    : stage.step === 4
                                        ? stage.status
                                        : stage.step === 6
                                            ? stage.selectedPath() + " was erased, but CitronOS wasn't fully installed on it, so it won't start this computer. Its old contents can't be recovered from here."
                                            : "CitronOS was installed successfully."
                }

                Item { width: 1; height: 4 }

                ListView {
                    visible: stage.step === 1
                    width: parent.width
                    height: 250
                    clip: true
                    model: stage.disks
                    spacing: 8

                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width
                        height: 64
                        radius: 14
                        color: stage.disk && stage.disk.path === modelData.path
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            : (Theme.dark ? "#18ffffff" : "#0b000000")
                        border.width: stage.disk && stage.disk.path === modelData.path ? 2 : 0.5
                        border.color: stage.disk && stage.disk.path === modelData.path ? Theme.accent : Theme.separator

                        Column {
                            x: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: modelData.model
                                color: Theme.label
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: modelData.path + "  •  " + (modelData.size / 1000000000).toFixed(1) + " GB"
                                color: Theme.secondaryLabel
                                font.family: Theme.fontUi
                                font.pixelSize: 12
                            }
                        }

                        TapHandler {
                            onTapped: {
                                stage.disk = modelData
                                stage.eraseConfirmed = false
                                stage.error = ""
                            }
                        }
                    }
                }

                Column {
                    visible: stage.step === 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 360
                    spacing: 12

                    Text {
                        text: "Account name"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                    }
                    TextField {
                        width: parent.width
                        placeholder: "username"
                        text: stage.username
                        onTextChanged: stage.username = text.toLowerCase().replace(/[^a-z0-9_-]/g, "")
                    }

                    Text {
                        text: "Password"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                    }
                    TextField {
                        width: parent.width
                        password: true
                        placeholder: "At least 8 characters"
                        text: stage.password
                        onTextChanged: stage.password = text
                    }

                    Text {
                        text: "Verify password"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                    }
                    TextField {
                        width: parent.width
                        password: true
                        placeholder: "Type it again"
                        text: stage.passwordConfirm
                        onTextChanged: stage.passwordConfirm = text
                    }

                    Text {
                        width: parent.width
                        visible: stage.passwordConfirm.length > 0 && stage.password !== stage.passwordConfirm
                        text: "Passwords do not match."
                        color: "#ff453a"
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }

                Column {
                    visible: stage.step === 3
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(540, parent.width)
                    spacing: 14

                    Rectangle {
                        width: parent.width
                        height: 104
                        radius: 14
                        color: Theme.dark ? "#14ffffff" : "#09000000"
                        border { width: 0.5; color: Theme.separator }

                        Column {
                            anchors { fill: parent; margins: 16 }
                            spacing: 5
                            Text {
                                text: stage.selectedModel()
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: 14; weight: Font.DemiBold }
                            }
                            Text {
                                text: stage.selectedPath()
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 12 }
                            }
                            Text {
                                text: "Administrator: " + stage.username
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: 12 }
                            }
                        }
                    }

                    Checkbox {
                        width: parent.width
                        checked: stage.eraseConfirmed
                        text: "Erase this disk and install CitronOS"
                        detail: "All partitions and files currently on " + stage.selectedPath() + " will be removed."
                        onToggled: (on) => stage.eraseConfirmed = on
                    }
                }

                Column {
                    visible: stage.step === 4
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(520, parent.width)
                    spacing: 14

                    ProgressBar {
                        width: parent.width
                        value: stage.progress
                        indeterminate: false
                    }

                    Text {
                        width: parent.width
                        text: Math.round(stage.progress * 100) + "%"
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                    }

                    Text {
                        width: parent.width
                        visible: !!stage.detail
                        text: stage.detail
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }

                    Text {
                        width: parent.width
                        text: "Keep this computer connected to power. Do not remove the destination drive."
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                }

                Column {
                    objectName: "installerFailure"
                    visible: stage.step === 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(540, parent.width)
                    spacing: 8

                    Rectangle {
                        width: parent.width
                        height: failureFacts.implicitHeight + 28
                        radius: 14
                        color: Theme.dark ? "#14ffffff" : "#09000000"
                        border { width: 0.5; color: Theme.separator }
                        Column {
                            id: failureFacts
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                            spacing: 5
                            Text {
                                width: parent.width
                                visible: !!stage.failedStage
                                text: "Stopped while: " + stage.failedStage
                                color: Theme.label
                                wrapMode: Text.WordWrap
                                font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                            }
                            Text {
                                width: parent.width
                                text: stage.error
                                color: Theme.secondaryLabel
                                wrapMode: Text.WordWrap
                                font { family: Theme.fontUi; pixelSize: 12 }
                            }
                            Text {
                                width: parent.width
                                visible: !!stage.log
                                text: "The full log is in " + stage.log + " until you restart."
                                color: Theme.tertiaryLabel
                                wrapMode: Text.WordWrap
                                font { family: Theme.fontUi; pixelSize: 11 }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: "To try again, choose the destination and confirm erasing it again."
                        color: Theme.secondaryLabel
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                }

                Column {
                    visible: stage.step === 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(520, parent.width)
                    spacing: 12

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Restart the computer and remove the live USB when the firmware screen appears."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                }

                Text {
                    objectName: "installerCloseRefused"
                    visible: stage.closeRefused
                    width: parent.width
                    text: "The installer can't be closed while CitronOS is installing."
                    color: Theme.secondaryLabel
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                }

                Text {
                    visible: !!stage.error && stage.step !== 6
                    width: parent.width
                    text: stage.error
                    color: "#ff453a"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    font { family: Theme.fontUi; pixelSize: 12 }
                }
            }

            Row {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 24
                }
                spacing: 10

                Button {
                    visible: stage.step > 0 && stage.step < 4
                    text: "Back"
                    enabled: !stage.installing
                    onClicked: stage.back()
                }

                Button {
                    visible: stage.step < 4
                    text: stage.step === 3 ? "Erase Disk and Install" : "Continue"
                    prominent: true
                    destructive: stage.step === 3
                    enabled: stage.canContinue()
                    onClicked: stage.next()
                }

                Button {
                    visible: stage.step === 6 && !!stage.log
                    text: "Show Log"
                    onClicked: Quickshell.execDetached(["xdg-open", stage.log])
                }

                Button {
                    objectName: "installerStartOver"
                    visible: stage.step === 6
                    text: "Start Over"
                    prominent: true
                    onClicked: stage.startOver()
                }

                Button {
                    visible: stage.step === 5
                    text: "Restart"
                    prominent: true
                    onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                }
            }
        }
    }
}
