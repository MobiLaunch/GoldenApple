//@ pragma AppId org.goldengate.LCode
// LCode, CitronOS's IDE, laid out like Xcode on macOS 27: navigators in a
// floating glass sidebar, the editor with tabs and a jump bar, the debug
// area underneath, inspectors in a trailing sidebar, and Run, the scheme and
// the activity view in the toolbar. Projects are CitronOS apps made in the
// App Designer, Swift packages, Rust crates, Meson (C) projects or Python
// programs; apps run on "My Linux PC" or in the Simulator.
//
// The window talks to lcode/helper.py (JSON lines); the Simulator's display
// lives in its own agent process (lcode/lcode_sim.py).
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "lcode"
import "lcode/devices.js" as Devices
import "lcode/commands.js" as Commands
import "lib/syntax.js" as Syntax

ShellRoot {
    id: shell

    Backend {
        id: helper
        onEvent: (e) => ide.handle(e)
    }

    Item {
        id: ide

        // ---------------------------------------------------------- state
        property var settings: ({ fontSize: 13, tabWidth: 4, showMinimap: true, showWelcome: true, defaultSimulator: "lphone-16", recent: [] })
        property var toolchains: ({})           // id → { path, version, hint, name }, from the helper
        readonly property var projectToolchain: project && toolchains[project.toolchain] ? toolchains[project.toolchain] : null
        property bool xvfbInstalled: true
        property bool helloDone: false

        property var project: null              // root, name, kind, products, bundleId, destination, isPackage
        property var nodes: []                  // the project tree, flat and parent-linked
        property string scheme: ""
        property string destination: "host"

        property var issues: []                 // { severity, message, path, line, column }
        readonly property int errorCount: issues.filter((i) => i.severity === "error").length
        readonly property int warningCount: issues.filter((i) => i.severity === "warning").length
        property var reports: []                // newest first: { gen, title, time, status }
        property var logs: ({})                 // gen → text (not bound; read on demand)

        property int taskGen: 0
        property string taskKind: ""
        property bool busy: false
        property bool appRunning: false
        property string status: "Ready"
        property real progress: -1              // -1 hidden, -2 indeterminate, else 0…1
        property string consoleText: ""
        property string pendingRunTitle: ""

        // Settings ▸ General: "light" or "dark" overrides the system appearance.
        readonly property string appearance: settings.appearance === "light" || settings.appearance === "dark" ? settings.appearance : ""
        property bool settingsOpen: false
        property int settingsPage: 0
        function revealSettingsFile() {
            const base = Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
            Quickshell.execDetached(["gg-files", "--select", base + "/golden-gate/lcode.json"])
        }
        function openSettings(page) {
            if (page !== undefined) settingsPage = page
            settingsOpen = true
            settingsRaised()
        }
        // The code editor's colours: the theme chosen for the current appearance.
        readonly property var editorColors: Syntax.resolveTheme(Theme.dark ? settings.editorThemeDark : settings.editorThemeLight,
                                                                Theme.dark, settings.customThemes || [])
        readonly property var keyBindings: settings.keyBindings || ({})
        function keysFor(id) { return Commands.keysFor(id, keyBindings) }
        function shortcutFor(id) { return Commands.displayFor(id, keyBindings) }

        property bool simulatorOpen: false
        property string simPower: "off"
        property string simError: ""
        property var simFrame: null
        property string simDeviceId: settings.defaultSimulator || "lphone-16"
        property int simOrientation: 0
        property var installedApps: []          // product names, for the home screen
        property bool simShowingHome: true

        signal revealLocation(string path, int line, int column, string message)
        signal alertRequested(string title, string message)
        signal organizerRequested()
        signal settingsRaised()
        // Settings ▸ Behaviors: the workspace shows or hides its areas.
        signal behaviorRequested(string event, var options)

        function behave(event, title, detail) {
            const b = Commands.behavior(event, settings.behaviors)
            if (b.notify)
                Quickshell.execDetached(["notify-send", "-a", "LCode", "-i", "org.goldengate.LCode", title, detail || ""])
            if (b.sound) {
                const name = event.endsWith("Failed") ? "dialog-warning" : "complete"
                Quickshell.execDetached(["sh", "-c", "canberra-gtk-play -i " + name + " 2>/dev/null || pw-play /usr/share/sounds/freedesktop/stereo/" + name + ".oga 2>/dev/null || paplay /usr/share/sounds/freedesktop/stereo/" + name + ".oga"])
            }
            behaviorRequested(event, b)
            if (b.reveal) {
                const first = issues.find((i) => i.severity === "error" && i.path)
                if (first) revealLocation(first.path, first.line, first.column, first.message)
            }
        }

        // The Simulator's devices, with your own from Settings ▸ Simulators.
        readonly property var devices: Devices.all(settings.customDevices || [])
        function deviceById(id) { return devices.find((d) => d.id === id) || null }
        readonly property var simDevice: deviceById(simDeviceId) || Devices.DEVICES[0]
        readonly property string destinationName: destination === "host" ? "My Linux PC" : (deviceById(destination)?.name ?? destination)
        readonly property string schemeName: scheme || (project ? project.name : "")

        Component.onCompleted: {
            helper.call("hello", {}, (r) => {
                // Without the helper's settings LCode still opens (on its
                // defaults) rather than showing no window at all.
                if (!r.ok) { ide.helloDone = true; return }
                ide.applySettings(r)
                ide.xvfbInstalled = r.xvfb
                ide.helloDone = true
                const path = Quickshell.env("LCODE_PROJECT") || ""
                if (path) ide.openProject(path)
            })
        }

        function applySettings(r) {
            settings = r.settings
            if (r.toolchains) toolchains = r.toolchains
            simDeviceId = settings.defaultSimulator || simDeviceId
        }

        function saveSettings(values) {
            helper.call("settings", { values: values }, (r) => { if (r.ok) ide.applySettings(r) })
        }

        // ------------------------------------------------------- projects
        function openProject(path) {
            if (project && project.root !== path) {
                // One project per window, as in Xcode: a new LCode for another one.
                Quickshell.execDetached(["sh", Qt.resolvedUrl("lcode/open.sh").toString().replace("file://", ""), path])
                return
            }
            helper.call("open", { path: path }, (r) => {
                if (!r.ok) { ide.alertRequested("Couldn't Open the Project", r.error); return }
                const p = r.project
                const st = p.state || {}
                ide.scheme = (st.scheme && p.products.includes(st.scheme)) ? st.scheme : (p.products[0] || "")
                ide.destination = st.destination || p.destination
                ide.project = p
                ide.refreshTree()
            })
        }

        function refreshProject() {
            helper.call("projectInfo", {}, (r) => {
                if (!r.ok) return
                const p = r.project
                if (!p.products.includes(ide.scheme)) ide.scheme = p.products[0] || ""
                ide.project = Object.assign({}, ide.project, { products: p.products, name: p.name, isPackage: p.isPackage, kind: p.kind,
                    meta: p.meta, displayName: p.displayName, version: p.version, bundleId: p.bundleId, toolchain: p.toolchain })
            })
        }

        function refreshTree() {
            helper.call("tree", {}, (r) => { if (r.ok) ide.nodes = r.nodes })
        }

        function saveState(openFiles, selected) {
            if (!project) return
            helper.call("saveState", { state: { open_files: openFiles, selected_file: selected, scheme: scheme, destination: destination } })
        }

        // ---------------------------------------------------------- tasks
        property var beforeTask: null           // the workspace saves open files first

        function prepare(then) {
            if (!project) return
            if (!project.toolchain) {
                alertRequested("Nothing to Build",
                    "LCode builds CitronOS apps, Swift packages, Rust crates, Meson projects and Python programs. Add a Package.swift, Cargo.toml, meson.build or main.py to this folder, or create a new project.")
                return
            }
            const tc = projectToolchain
            if (project.toolchain !== "goldengate" && (!tc || !tc.path)) {
                const name = tc ? tc.name : project.toolchain
                alertRequested(name + " Not Found",
                    "LCode needs " + name + " to build this project. Install it with:\n\n" + (tc ? tc.hint : "") +
                    "\n\nthen set its location in LCode Settings ▸ Locations if it isn't on your PATH.")
                return
            }
            if (beforeTask) beforeTask(then); else then()
        }

        function run() {
            if (!scheme) { build(); return }
            if (project && project.toolchain === "goldengate" && !(toolchains.goldengate && toolchains.goldengate.path)) {
                alertRequested("Quickshell Not Found", "CitronOS apps run with Quickshell (qs), which CitronOS includes. Install it with:\n\nsudo pacman -S quickshell")
                return
            }
            prepare(() => {
                const target = destination === "host" ? {} : Devices.runTarget(deviceById(destination) || simDevice, simOrientation)
                if (destination !== "host") {
                    simDeviceId = destination
                    simulatorOpen = true
                }
                pendingRunTitle = scheme
                helper.call("run", { product: scheme, destination: destination, device: target }, ide.taskReply)
            })
        }
        function build() { prepare(() => helper.call("build", { product: scheme }, ide.taskReply)) }
        function test() { prepare(() => helper.call("test", {}, ide.taskReply)) }
        function archive() { prepare(() => helper.call("archive", { product: scheme }, ide.taskReply)) }
        function clean() { prepare(() => helper.call("clean", {}, ide.taskReply)) }
        function stop() { helper.call("stop", {}) }
        function taskReply(r) { if (!r.ok) alertRequested("Couldn't Start", r.error) }

        function timestamp() { return Qt.formatTime(new Date(), "hh:mm") }
        function appendConsole(text) {
            let t = consoleText + text
            if (t.length > 200000) t = t.slice(t.length - 150000)
            consoleText = t
        }

        function handle(e) {
            switch (e.event) {
            case "tree.changed":
                refreshTree()
                break
            case "task.started":
                taskGen = e.gen
                taskKind = e.kind
                busy = true
                if (e.kind === "run") {             // relaunching a built app
                    status = "Launching " + pendingRunTitle + "…"
                    break
                }
                progress = -2
                issues = []
                logs[e.gen] = ""
                status = e.kind === "build" ? "Building " + schemeName + "…" : e.kind === "test" ? "Testing " + schemeName + "…"
                       : e.kind === "archive" ? "Archiving " + schemeName + "…" : "Cleaning…"
                reports = [{ gen: e.gen, title: e.title, time: Qt.formatTime(new Date(), "hh:mm:ss"), status: "running" }].concat(reports)
                if (e.kind === "test") consoleText = ""
                break
            case "task.log":
                logs[e.gen] = (logs[e.gen] || "") + e.text
                if (e.gen === taskGen && taskKind === "test") appendConsole(e.text)
                break
            case "task.progress":
                if (e.gen !== taskGen) break
                if (e.total > 0) progress = e.done / e.total
                status = (e.message || "Building") + (e.total > 0 ? "  (" + e.done + " of " + e.total + ")" : "…")
                break
            case "task.issue":
                if (e.gen === taskGen) issues = issues.concat([e])
                break
            case "task.finished": {
                const ok = e.code === 0 && e.errors === 0 && !e.cancelled
                reports = reports.map((r) => r.gen === e.gen ? Object.assign({}, r, { status: e.cancelled ? "cancelled" : ok ? "ok" : "failed" }) : r)
                if (e.gen !== taskGen) break
                progress = -1
                const noun = e.kind === "build" ? "Build" : e.kind === "test" ? "Test" : e.kind === "archive" ? "Archive" : "Clean"
                status = e.cancelled ? noun + " Canceled" : ok ? (e.kind === "clean" ? "Clean Finished" : noun + " Succeeded") : noun + " Failed"
                status += "  |  Today at " + timestamp()
                // A successful Run build goes straight on to run.run.started.
                if (!(ok && e.kind === "build" && pendingRunTitle)) busy = false
                if (!ok) pendingRunTitle = ""
                if (ok && e.kind === "archive") organizerRequested()
                if (!e.cancelled && (e.kind === "build" || e.kind === "test"))
                    behave(e.kind + (ok ? "Succeeded" : "Failed"), status.split("  |")[0], schemeName)
                break
            }
            case "run.started":
                if (e.gen !== taskGen) break
                busy = true
                appRunning = true
                consoleText = ""
                status = "Running " + e.product + " on " + destinationName
                behave("runStarted", "Running " + e.product, destinationName)
                if (e.destination !== "host") {
                    if (!installedApps.includes(e.product)) installedApps = installedApps.concat([e.product])
                    simShowingHome = false
                }
                break
            case "run.output":
                if (e.gen === taskGen) appendConsole(e.text)
                break
            case "run.exited":
                if (e.gen !== taskGen) break
                busy = false
                appRunning = false
                if (e.error) appendConsole(e.error + "\n")
                appendConsole(e.code === null || e.code === undefined ? "Program was terminated.\n" : "Program ended with exit code: " + e.code + "\n")
                status = "Finished running " + (pendingRunTitle || schemeName) + " on " + destinationName + "  |  Today at " + timestamp()
                behave("runExited", (pendingRunTitle || schemeName) + " Exited", e.code === null || e.code === undefined ? "Terminated" : "Exit code " + e.code)
                pendingRunTitle = ""
                simShowingHome = true
                break
            case "sim.state":
                simPower = e.power
                simError = e.error || ""
                if (e.power === "off") simFrame = null
                break
            case "sim.frame":
                simFrame = e
                break
            }
        }

        // ------------------------------------------------------ simulator
        function bootSimulator() {
            const t = Devices.runTarget(simDevice, simOrientation)
            helper.call("simBoot", { side: t.side, w: t.w, h: t.h })
        }
        function shutDownSimulator() {
            if (appRunning && destination !== "host") stop()
            helper.call("simShutdown", {})
        }
        function setSimDevice(id) {
            if (id === simDeviceId) return
            shutDownSimulator()
            simDeviceId = id
            simOrientation = 0
            saveSettings({ defaultSimulator: id })
            if (simulatorOpen) bootTimer.start()
        }
        // Tap an icon on the Simulator's home screen.
        function launchInstalled(name) {
            if (appRunning && pendingRunTitle === name) { simShowingHome = false; return }
            pendingRunTitle = name
            helper.call("launch", { product: name, destination: simDeviceId, device: Devices.runTarget(simDevice, simOrientation) }, ide.taskReply)
        }
        function rotateSimulator(left) {
            simOrientation = simOrientation === 0 ? (left ? -90 : 90) : 0
            const a = Devices.appSize(simDevice, simOrientation)
            helper.call("simRegion", { w: a.w, h: a.h })
        }
        Timer { id: bootTimer; interval: 300; onTriggered: ide.bootSimulator() }
        // ⌘Q from any LCode window: the workspace's quit, which asks about
        // unsaved files (set while a project is open).
        property var quitHandler: null
    }

    LazyLoader {
        active: ide.helloDone && !ide.project && !Quickshell.env("LCODE_PROJECT")
        Welcome { app: ide; backend: helper }
    }

    LazyLoader {
        active: !!ide.project
        Workspace { app: ide; backend: helper }
    }

    LazyLoader {
        active: ide.settingsOpen
        SettingsWindow { app: ide; backend: helper }
    }

    LazyLoader {
        active: ide.simulatorOpen
        SimulatorWindow { app: ide; backend: helper }
    }
}
