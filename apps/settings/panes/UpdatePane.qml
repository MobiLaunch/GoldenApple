// Native CitronOS Software Update. One button does it all: Update Now
// checks for updates and installs them, the system's packages first (as root,
// through the org.goldengate.update polkit action, which an administrator at
// the computer runs without a password) and then the user's Flatpak apps.
// Progress stays inside Settings; nothing opens a terminal.
//
// CitronOS itself updates from its GitHub repository (golden_update.py):
// the check lists what changed since the installed commit, and Update Now
// installs it with the system packages. Update Source sets the repository,
// branch and, for a private repository, a read-only access token.
import Quickshell
import Quickshell.Io
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "arrow-clockwise"
    headerTint: "#8e8e93"
    headerTitle: "Software Update"
    headerText: "CitronOS keeps the system and installed packages current in the background."

    readonly property string helper: Qt.resolvedUrl("../update-helper.py").toString().replace("file://", "")
    property string last: ""
    property string state: "idle"
    property string message: "Checking for updates…"
    property int updateCount: 0
    property int remaining: -1
    property int currentPackage: 0
    property int totalPackages: 0
    property double updateStartedAt: 0
    property int elapsedSeconds: 0
    property real progress: 0
    readonly property int etaSeconds: currentPackage > 0 && remaining > 0
        ? Math.max(1, Math.round((elapsedSeconds / currentPackage) * remaining))
        : -1
    property var packages: []
    property string error: ""
    property int systemCount: 0         // pacman packages and system Flatpaks
    property int userAppCount: 0        // the user's own Flatpak apps
    property bool installAfterCheck: false
    property var golden: ({})           // CitronOS's check: available, notes, needsToken…
    property var source: ({})           // repo, branch, hasToken, commit, date, subject
    property bool editingSource: false
    property bool relogin: false        // CitronOS was updated: log out to finish
    property string notice: ""

    function consume(line) {
        if (!line || !line.trim())
            return
        try {
            const event = JSON.parse(line)
            if (event.event === "checking") {
                state = "checking"
                message = event.message ?? "Checking for updates…"
                progress = event.progress ?? 0
            } else if (event.event === "result") {
                updateCount = event.count ?? 0
                systemCount = (event.system ?? 0) + ((event.apps ?? 0) - (event.userApps ?? 0))
                userAppCount = event.userApps ?? 0
                packages = event.packages ?? []
                golden = event.golden ?? ({})
                state = updateCount > 0 ? "available" : "current"
                message = updateCount > 0
                    ? updateCount + (updateCount === 1 ? " update is available." : " updates are available.")
                    : "CitronOS is up to date."
                progress = updateCount > 0 ? 0 : 1
                error = event.stale ? (event.message ?? "") : ""
            } else if (event.event === "progress") {
                state = "updating"
                message = event.message ?? "Installing updates…"
                progress = event.progress ?? progress
                remaining = event.remaining ?? -1
                currentPackage = event.current ?? currentPackage
                totalPackages = event.total ?? totalPackages
            } else if (event.event === "done") {
                if (event.restart) { relogin = true; readSource() }
                if (pane.phase === "system" && pane.userAppCount > 0) return   // the apps are next
                state = "current"
                progress = 1
                remaining = 0
                updateCount = 0
                message = event.message ?? "CitronOS is up to date."
                last = "Just now"
                error = ""
            } else if (event.event === "notice") {
                notice = event.message ?? ""
            } else if (event.event === "source") {
                source = event
            } else if (event.event === "error") {
                state = "error"
                error = event.message ?? "Software Update could not complete."
                message = "Update interrupted"
            }
        } catch (e) {
            // Ignore non-JSON helper noise; the helper's final event is authoritative.
        }
    }

    function checkNow() {
        if (checkProcess.running || updateProcess.running)
            return
        error = ""
        state = "checking"
        progress = 0
        remaining = -1
        message = "Checking for updates…"
        checkProcess.running = true
    }

    // Update Now: check first unless a check just found updates, then install.
    function updateNow() {
        if (updateProcess.running || checkProcess.running)
            return
        if (state !== "available" || updateCount <= 0) {
            installAfterCheck = true
            checkNow()
            return
        }
        install()
    }

    property string phase: ""           // "system" | "apps" while installing
    function install() {
        installAfterCheck = false
        error = ""
        state = "updating"
        progress = 0.02
        remaining = updateCount
        currentPackage = 0
        totalPackages = updateCount
        updateStartedAt = Date.now()
        elapsedSeconds = 0
        if (systemCount > 0) {
            phase = "system"
            message = "Preparing update…"
            // The live session's user has passwordless sudo; an installed
            // system uses the polkit action for this exact helper path.
            updateProcess.command = [
                "sh", "-c",
                "if sudo -n true >/dev/null 2>&1; then exec sudo -n \"$1\" apply; else exec pkexec \"$1\" apply; fi",
                "sh", pane.helper
            ]
        } else {
            phase = "apps"
            message = "Updating apps…"
            updateProcess.command = [pane.helper, "apply-user"]
        }
        updateProcess.running = true
    }

    function readSource() { sourceProcess.running = true }
    function saveSource(repo, branch, token) {
        sourceSave.payload = JSON.stringify({ repo: repo.trim(), branch: branch.trim(), token: token ? token.trim() : null }) + "\n"
        sourceSave.running = true
    }
    Process {
        id: sourceProcess
        command: ["python3", pane.helper, "source"]
        stdout: SplitParser { onRead: (line) => pane.consume(line) }
    }
    // Saving needs an administrator, like installing: the same polkit action.
    Process {
        id: sourceSave
        property string payload: ""
        command: ["sh", "-c", "if sudo -n true >/dev/null 2>&1; then exec sudo -n \"$1\" set-source; else exec pkexec \"$1\" set-source; fi",
                  "sh", pane.helper]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const e = JSON.parse(line)
                    if (e.event === "error") pane.sourceError = e.message
                    else if (e.event === "done" && e.message && e.message !== "Saved.") pane.notice = e.message
                } catch (err) {}
            }
        }
        // pkexec and sudo say on stderr why they didn't run the helper.
        stderr: SplitParser { onRead: (line) => { if (line.trim()) sourceSave.stderrLine = line.trim() } }
        property string stderrLine: ""
        onStarted: { stderrLine = ""; pane.sourceError = ""; write(payload) }
        onExited: (code) => {
            if (code === 0) { pane.editingSource = false; pane.sourceError = ""; tokenField.text = ""; pane.readSource(); pane.checkNow() }
            else if (!pane.sourceError)
                pane.sourceError = (code === 126 ? "Authorization was canceled." : "Couldn't save the update source.")
                    + (stderrLine ? " (" + stderrLine + ")" : "")
        }
    }
    property string sourceError: ""

    Component.onCompleted: {
        readSource()
        sys.sh("tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' | cut -c2-17",
               (o) => last = o.trim())
        checkTimer.start()
    }

    Timer {
        id: checkTimer
        interval: 350
        repeat: false
        onTriggered: pane.checkNow()
    }

    Timer {
        interval: 1000
        repeat: true
        running: pane.state === "updating"
        onTriggered: pane.elapsedSeconds = pane.updateStartedAt > 0
            ? Math.max(0, Math.floor((Date.now() - pane.updateStartedAt) / 1000))
            : 0
    }

    function etaText() {
        if (etaSeconds < 0)
            return remaining >= 0
                ? remaining + " package" + (remaining === 1 ? "" : "s") + " remaining"
                : "Calculating time remaining…"
        const min = Math.floor(etaSeconds / 60)
        const sec = etaSeconds % 60
        const time = min > 0
            ? "About " + min + " min " + String(sec).padStart(2, "0") + " sec remaining"
            : "About " + sec + " sec remaining"
        return remaining > 0
            ? time + "  •  " + remaining + " package" + (remaining === 1 ? "" : "s")
            : "Finishing…"
    }

    Process {
        id: checkProcess
        command: ["python3", pane.helper, "check"]
        stdout: SplitParser { onRead: (line) => pane.consume(line) }
        onExited: (code) => {
            if (code !== 0 && pane.state === "checking") {
                pane.state = "error"
                pane.error = "Could not check for updates. Verify your internet connection and try again."
            } else if (pane.installAfterCheck) {
                if (pane.state === "available") pane.install()
                else pane.installAfterCheck = false
            }
        }
    }

    Process {
        id: updateProcess
        stdout: SplitParser { onRead: (line) => pane.consume(line) }
        onExited: (code) => {
            if (code !== 0 && pane.state === "updating") {
                pane.phase = ""
                pane.state = "error"
                pane.error = code === 126 || code === 127
                    ? "Administrator authorization was canceled."
                    : "Software Update stopped before it finished."
            } else if (code === 0 && pane.phase === "system" && pane.userAppCount > 0) {
                // System done; now the user's apps, still without a terminal.
                pane.phase = "apps"
                pane.message = "Updating apps…"
                updateProcess.command = [pane.helper, "apply-user"]
                Qt.callLater(() => updateProcess.running = true)
            } else if (code === 0) {
                pane.phase = ""
                Qt.callLater(() => pane.checkNow())
            }
        }
    }

    Group {
        SetRow {
            title: pane.state === "current"
                ? "CitronOS is up to date"
                : pane.state === "available"
                    ? "Updates Available"
                    : pane.state === "updating"
                        ? "Installing Updates"
                        : pane.state === "error"
                            ? "Software Update"
                            : "Checking for Updates"
            subtitle: pane.last
                ? "Last successful system update: " + pane.last.replace("T", " at ")
                : "Updates include CitronOS, Arch Linux and installed applications."

            // One click: checks for updates and installs whatever it finds.
            Button {
                visible: pane.state !== "checking" && pane.state !== "updating"
                text: "Update Now"
                prominent: pane.state === "available"
                onClicked: pane.updateNow()
            }
        }

        SetRow {
            title: pane.message
            subtitle: pane.state === "updating"
                ? pane.etaText()
                : pane.state === "checking"
                    ? "This happens in the background."
                    : ""
            ProgressBar {
                width: 220
                value: pane.progress
                indeterminate: pane.state === "checking" || (pane.state === "updating" && pane.remaining < 0)
            }
        }

        SetRow {
            visible: pane.state === "available" && pane.packages.length > 0
            title: pane.updateCount + (pane.updateCount === 1 ? " update" : " updates")
            subtitle: pane.packages.slice(0, 4).join("  •  ") + (pane.packages.length > 4 ? "  •  …" : "")
        }
    }

    // CitronOS: the installed version, what an update brings, and where
    // updates come from.
    Group {
        title: "CitronOS"
        SetRow {
            title: pane.source.commit ? "CitronOS " + pane.source.commit.slice(0, 7) : "CitronOS"
            subtitle: pane.source.commit
                ? (pane.source.subject || "") + (pane.source.date ? "  •  " + String(pane.source.date).slice(0, 10) : "")
                : "Installed from an image without a version record; the next update adds one."
            Button {
                text: pane.editingSource ? "Cancel" : "Update Source…"
                onClicked: { pane.editingSource = !pane.editingSource; pane.sourceError = "" }
            }
        }
        SetRow {
            visible: !!pane.golden.available
            title: "What's New"
            subtitle: (pane.golden.ahead || (pane.golden.notes || []).length) + " change"
                + ((pane.golden.ahead || (pane.golden.notes || []).length) === 1 ? "" : "s")
                + " since this version, from " + (pane.golden.repo || "GitHub")
        }
        Repeater {
            model: pane.golden.available ? (pane.golden.notes || []).slice(0, 8) : []
            delegate: SetRow {
                required property var modelData
                title: "•  " + modelData
            }
        }
        SetRow {
            visible: pane.relogin
            title: "CitronOS was updated"
            subtitle: "Log out and back in to start using the new version everywhere."
            Button {
                text: "Log Out…"
                onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "session", "ask", "logout"])
            }
        }
        SetRow {
            visible: !!pane.notice
            title: "Note"
            subtitle: pane.notice
        }
        SetRow {
            visible: pane.editingSource
            title: "Repository"
            subtitle: "owner/name on GitHub"
            TextField { id: repoField; onAccepted: saveButton.clicked(); width: 230; text: pane.source.repo || ""; placeholder: "MobiLaunch/GoldenApple" }
        }
        SetRow {
            visible: pane.editingSource
            title: "Branch"
            TextField { id: branchField; onAccepted: saveButton.clicked(); width: 230; text: pane.source.branch || ""; placeholder: "main" }
        }
        SetRow {
            visible: pane.editingSource
            title: "Access Token"
            subtitle: pane.source.hasToken ? "A token is saved. Leave this empty to keep it."
                : "Only for a private repository: a fine-grained token with read-only Contents access."
            TextField { id: tokenField; onAccepted: saveButton.clicked(); width: 230; password: true; placeholder: pane.source.hasToken ? "••••••••" : "github_pat_…" }
        }
        SetRow {
            visible: pane.editingSource
            title: pane.sourceError ? "Couldn't save" : ""
            subtitle: pane.sourceError
            Button {
                id: saveButton
                text: "Save"
                prominent: true
                enabled: !sourceSave.running && repoField.text.trim() !== "" && branchField.text.trim() !== ""
                onClicked: pane.saveSource(repoField.text, branchField.text, tokenField.text)
            }
        }
    }

    // Why the CitronOS check failed, whatever the reason: no token, a token
    // GitHub refused or that can't see the repository, a missing branch, no network.
    Group {
        visible: (!!pane.golden.needsToken || !!pane.golden.error) && !pane.editingSource
        title: "CitronOS Updates"
        SetRow {
            title: !pane.golden.needsToken ? "Couldn't check for CitronOS updates"
                : pane.source.hasToken ? "The access token didn't work" : "CitronOS's repository needs access"
            subtitle: pane.golden.error || "Add a read-only access token to get CitronOS updates."
            Button {
                text: pane.golden.needsToken ? (pane.source.hasToken ? "Change Token…" : "Add Token…") : "Update Source…"
                onClicked: pane.editingSource = true
            }
        }
    }

    Group {
        visible: !!pane.error
        title: "Attention"
        SetRow {
            title: "Software Update couldn't finish"
            subtitle: pane.error
            Button { text: "Try Again"; onClicked: pane.updateNow() }
        }
    }
}
