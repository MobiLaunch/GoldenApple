// What the Settings panes use to reach the system: run a command and get its
// output, and read and update the CitronOS preference files.
//   sys.run(["nmcli", "-t", ...], (out, code) => …)
//   sys.prefs.dock.size            (desktop.json, watched by the shell)
//   sys.setPref(["dock", "size"], 60)
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: sys
    readonly property string config: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string gg: config + "/golden-gate"
    property var prefs: ({})         // desktop.json
    property var privacy: ({})       // privacy.json
    property var input: ({})         // input.json (keyboard, trackpad)
    // A change that couldn't be saved: Settings shows it, and the file (which
    // was left as it was) is read again so the controls show what's saved.
    property string writeError: ""
    readonly property string writer: decodeURIComponent(Qt.resolvedUrl("write-file.py").toString().replace("file://", ""))

    Component {
        id: procComp
        Process {
            id: p
            property var done: null
            stdout: StdioCollector { id: out }
            onExited: (code) => { if (p.done) p.done(out.text, code); p.destroy() }
        }
    }
    function run(args, done) {
        const p = procComp.createObject(sys, { command: args, done: done ?? null })
        p.running = true
    }
    function sh(script, done) { run(["sh", "-c", script], done) }

    Component {
        id: writeComp
        Process {
            id: w
            property string content
            property string what
            stdinEnabled: true
            stderr: StdioCollector { id: werr }
            onStarted: { write(w.content); stdinEnabled = false }
            onExited: (code) => {
                if (code !== 0) sys.failed(w.what, werr.text.trim() || "the file couldn't be written")
                w.destroy()
            }
        }
    }
    // Every preference file is replaced whole and atomically (write-file.py),
    // and a failure is reported, never assumed away.
    function writeFile(path, text, what) {
        const w = writeComp.createObject(sys, { command: ["python3", writer, path], content: text, what: what ?? path.split("/").pop() })
        w.running = true
    }
    function writeJson(file, obj) { writeFile(gg + "/" + file, JSON.stringify(obj, null, 1) + "\n", file) }
    function failed(what, why) {
        writeError = "Your change couldn't be saved (" + what + ": " + why + "). The previous setting was kept."
        for (const f of [desktopFile, privacyFile, inputFile]) f.reload()
    }
    function setIn(obj, path, value) {
        const copy = JSON.parse(JSON.stringify(obj ?? {}))
        let o = copy
        for (let i = 0; i < path.length - 1; i++) o = o[path[i]] = (o[path[i]] && typeof o[path[i]] === "object") ? o[path[i]] : {}
        o[path[path.length - 1]] = value
        return copy
    }
    property bool glassDirty: false
    Timer {
        id: glassSync
        interval: 90
        onTriggered: {
            if (!sys.glassDirty) return
            sys.glassDirty = false
            Quickshell.execDetached(["gg-hyprglass-sync"])
        }
    }
    Timer { id: privacySave; interval: 70; onTriggered: sys.writeJson("privacy.json", sys.privacy) }

    // desktop.json has one authoritative writer: gg-pref performs an atomic
    // nested-key update, so Settings, shell IPC and Control Center cannot stomp
    // one another by rewriting a stale copy of the whole file.
    function setPref(path, value) {
        prefs = setIn(prefs, path, value)
        const key = path.join(".")
        run(["gg-pref", key, JSON.stringify(value)], (out, code) => { if (code !== 0) sys.failed("desktop.json", key) })
        if (path[0] === "glass" || path[0] === "reduceTransparency") {
            glassDirty = true
            glassSync.restart()
        }
    }
    function setPrivacy(key, value) {
        privacy = setIn(privacy, [key], value)
        privacySave.restart()
    }

    // Keyboard and pointer: input.json is the record; hypr's input.conf is written
    // from it (sourced by hyprland.conf), and each change applies at once.
    function setInput(key, value) {
        input = setIn(input, [key], value)
        inputSave.restart()
        const kw = { layout: "input:kb_layout", variant: "input:kb_variant", repeatRate: "input:repeat_rate", repeatDelay: "input:repeat_delay",
                     sensitivity: "input:sensitivity", naturalScroll: "input:touchpad:natural_scroll", tapToClick: "input:touchpad:tap-to-click" }[key]
        if (kw) Quickshell.execDetached(["hyprctl", "keyword", kw, String(typeof value === "number" && key !== "sensitivity" ? Math.round(value) : value)])
    }

    function inputConfig() {
        const i = input
        return "input {\n"
            + "    kb_layout = " + (i.layout ?? "us") + "\n"
            + "    kb_variant = " + (i.variant ?? "") + "\n"
            + "    repeat_rate = " + Math.round(i.repeatRate ?? 25) + "\n"
            + "    repeat_delay = " + Math.round(i.repeatDelay ?? 600) + "\n"
            + "    sensitivity = " + (i.sensitivity ?? 0).toFixed(2) + "\n"
            + "    touchpad {\n"
            + "        natural_scroll = " + (i.naturalScroll ?? true) + "\n"
            + "        tap-to-click = " + (i.tapToClick ?? true) + "\n"
            + "    }\n}\n"
    }
    Timer {
        id: inputSave
        interval: 80
        onTriggered: {
            sys.writeJson("input.json", sys.input)
            sys.writeFile(sys.config + "/hypr/golden-gate/input.conf", sys.inputConfig(), "input.conf")
        }
    }

    component JsonFile: FileView {
        property string key
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { sys[key] = JSON.parse(text()) } catch (e) {} }
    }
    JsonFile { id: desktopFile; path: sys.gg + "/desktop.json"; key: "prefs" }
    JsonFile { id: privacyFile; path: sys.gg + "/privacy.json"; key: "privacy" }
    JsonFile { id: inputFile; path: sys.gg + "/input.json"; key: "input" }
    // First time: pick up the keyboard Setup Assistant wrote (layout and
    // variant both: a later change, such as the repeat rate, rewrites the
    // file from input.json and must keep the same keys).
    Component.onCompleted: sh('sed -n "s/^ *\\(kb_layout\\|kb_variant\\) *= *\\(.*\\)/\\1=\\2/p" "' + config + '/hypr/golden-gate/input.conf" 2>/dev/null', (out) => {
        if (input.layout) return
        let i = input
        for (const line of out.split("\n")) {
            const [k, v] = line.split("=")
            if (k === "kb_layout" && v && v.trim()) i = setIn(i, ["layout"], v.trim())
            if (k === "kb_variant" && v !== undefined) i = setIn(i, ["variant"], v.trim())
        }
        input = i
    })
}
