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

    function writeJson(file, obj) {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/$3"', "sh", gg, JSON.stringify(obj, null, 1), file])
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
        Quickshell.execDetached(["gg-pref", path.join("."), JSON.stringify(value)])
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
            Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "%s" "$2" > "$1/input.conf"', "sh",
                                     sys.config + "/hypr/golden-gate", sys.inputConfig()])
        }
    }

    component JsonFile: FileView {
        property string key
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { sys[key] = JSON.parse(text()) } catch (e) {} }
    }
    JsonFile { path: sys.gg + "/desktop.json"; key: "prefs" }
    JsonFile { path: sys.gg + "/privacy.json"; key: "privacy" }
    JsonFile { path: sys.gg + "/input.json"; key: "input" }
    // First time: pick up the keyboard layout Setup Assistant wrote.
    Component.onCompleted: sh('sed -n "s/^ *kb_layout *= *//p" "$HOME/.config/hypr/golden-gate/input.conf" 2>/dev/null | head -n1', (out) => {
        if (out.trim() && !input.layout) input = setIn(input, ["layout"], out.trim())
    })
}
