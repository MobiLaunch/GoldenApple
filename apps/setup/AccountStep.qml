// The local account is part of Hello, before connectivity or analytics choices.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib"
import "../lib/theme"

StepFrame {
    id: step
    property string createdUsername: ""
    property bool liveSession: false
    property bool liveChecked: false
    property string error: ""
    property bool busy: createAccount.running
    property string currentUser: Quickshell.env("USER") || ""
    signal accountCreated(string username)
    signal advance()
    symbol: "person"
    title: createdUsername ? "Your Account Is Ready" : "Create Your Local Account"
    text: createdUsername ? "Sign in as " + createdUsername + " from the login screen. Your choices on the next screens will be saved for this account."
                         : "Your name, your files, your own password. No online account is needed."
    continueText: busy ? "Creating…" : createdUsername ? "Continue" : "Create Account"
    canGoBack: !busy
    canContinue: !busy && (!!createdUsername || (fullName.text.trim().length > 0 && /^[a-z_][a-z0-9_-]{0,30}$/.test(username.text)
                       && password.text.length >= 8 && password.text === confirm.text))
    secondaryText: liveChecked && !liveSession && !busy && !createdUsername ? "Use Existing Account" : ""
    onSecondary: advance()
    onNext: submit()

    function submit() {
        if (createdUsername) { advance(); return }
        if (!canContinue) return
        error = ""
        createAccount.running = true
    }
    Process {
        id: detectLive
        running: true
        command: ["sh", "-c", "test -d /run/archiso && test \"$(id -un)\" = golden"]
        onExited: (code) => { step.liveSession = code === 0; step.liveChecked = true }
    }
    Process {
        id: createAccount
        command: ["sh", decodeURIComponent(Qt.resolvedUrl("account-call.sh").toString().replace("file://", ""))]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify({username: username.text, fullName: fullName.text.trim(), password: password.text}))
            stdinEnabled = false
            password.text = ""; confirm.text = ""
        }
        onRunningChanged: if (!running) stdinEnabled = true
        stdout: StdioCollector { id: reply }
        stderr: StdioCollector { id: failure }
        onExited: (code) => {
            let result = {}
            try { result = JSON.parse(reply.text) } catch (e) {}
            if (code === 0 && result.ok) {
                step.createdUsername = result.username
                step.accountCreated(result.username)
            } else step.error = failure.text.includes("system setup helper") ? failure.text.trim()
                    : (result.error || "Account creation was canceled or failed. Check authorization and try again.")
        }
    }
    Flickable {
        anchors.fill: parent
        contentHeight: fields.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: fields
            width: parent.width
            spacing: 10
            Text { visible: !step.createdUsername; text: "Full Name"; color: Theme.label; font.pixelSize: 12 }
            TextField { id: fullName; visible: !step.createdUsername; width: parent.width; height: 32; placeholder: "Your full name"; enabled: !step.busy; input.maximumLength: 80 }
            TextField { id: username; visible: !step.createdUsername; width: parent.width; height: 32; placeholder: "Account name (lowercase, no spaces)"; enabled: !step.busy; input.maximumLength: 31 }
            TextField { id: password; visible: !step.createdUsername; width: parent.width; height: 32; placeholder: "Password (at least 8 characters)"; password: true; enabled: !step.busy; input.maximumLength: 256 }
            TextField { id: confirm; visible: !step.createdUsername; width: parent.width; height: 32; placeholder: "Confirm password"; password: true; enabled: !step.busy; input.maximumLength: 256; onAccepted: step.submit() }
            Text {
                width: parent.width; wrapMode: Text.WordWrap; color: Theme.secondaryLabel; font.pixelSize: 12
                text: step.liveSession ? "You are trying a live image. This account and its files last only for this live session unless your system has persistent storage."
                                      : "An administrator must authorize creation. You can also continue with the account you are already signed into."
            }
            Text { width: parent.width; visible: !!step.error; text: step.error; textFormat: Text.PlainText; wrapMode: Text.WordWrap; color: "#d8483e"; font.pixelSize: 12 }
        }
    }
}
