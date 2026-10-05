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

            function selectedModel() {
                return disk && disk.model ? disk.model : "Storage Device"
            }

            function selectedPath() {
                return disk && disk.path ? disk.path : ""
            }

            function accountValid() {
                return /^[a-z_][a-z0-9_-]{0,30}$/.test(username)
                    && password.length >= 6
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
                if (step < 3) {
                    step++
                    return
                }
                if (step === 3)
                    beginInstall()
            }

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
                    } else if (event.event === "error") {
                        error = event.message ?? "Installation could not complete."
                        installing = false
                        step = 3
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
                error = ""
                progress = 0.01
                status = "Starting installation…"
                detail = ""
                step = 4
                // Live media normally grants the installer passwordless sudo.
                // If that policy is missing or changed, fall back to the desktop
                // Polkit agent instead of failing silently after the confirmation step.
                install.command = [
                    "sh", "-c",
                    "if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then exec sudo -n python3 \"$1\" install; "
                    + "elif command -v pkexec >/dev/null 2>&1; then exec pkexec python3 \"$1\" install; "
                    + "else printf '%s\\n' 'No administrator authorization method is available.' >&2; exit 127; fi",
                    "sh", helper
                ]
                install.running = true
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
                        stage.step = 3
                        if (!stage.error)
                            stage.error = "Installation stopped before it finished. The destination may need to be erased before retrying."
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
                        : "checkmark"
                    size: 58
                    tone: stage.step === 3 ? "red" : stage.step === 5 ? "accent" : "auto"
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
                        placeholder: "At least 6 characters"
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
                    visible: !!stage.error
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
                    visible: stage.step === 5
                    text: "Restart"
                    prominent: true
                    onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                }
            }
        }
    }
}
