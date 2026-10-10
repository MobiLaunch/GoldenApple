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
    property var windows: ({})       // windows.json (compositor window controls)
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
            stderr: StdioCollector { id: err }
            onExited: (code) => { if (p.done) p.done(out.text, code, err.text); p.destroy() }
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
            property var done: null
            stdinEnabled: true
            stderr: StdioCollector { id: werr }
            onStarted: { write(w.content); stdinEnabled = false }
            onExited: (code) => {
                if (code !== 0) sys.failed(w.what, werr.text.trim() || "the file couldn't be written")
                if (w.done) w.done(code === 0)
                w.destroy()
            }
        }
    }
    // Every preference file is replaced whole and atomically (write-file.py),
    // and a failure is reported, never assumed away.
    function writeFile(path, text, what, done) {
        const w = writeComp.createObject(sys, { command: ["python3", writer, path], content: text,
                                                what: what ?? path.split("/").pop(), done: done ?? null })
        w.running = true
    }
    function writeJson(file, obj) { writeFile(gg + "/" + file, JSON.stringify(obj, null, 1) + "\n", file) }
    function failed(what, why) {
        writeError = "Your change couldn't be saved (" + what + ": " + why + "). The previous setting was kept."
        for (const f of [desktopFile, privacyFile, inputFile, windowsFile]) f.reload()
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

    // desktop.json has one authoritative writer: gg-pref performs an atomic
    // nested-key update, so Settings, shell IPC and Control Center cannot stomp
    // one another by rewriting a stale copy of the whole file.
    function setPref(path, value) {
        prefs = setIn(prefs, path, value)
        const key = path.join(".")
        run(["gg-pref", key, JSON.stringify(value)], (out, code) => { if (code !== 0) sys.failed("desktop.json", key) })
        if (path[0] === "glass" || path[0] === "glassWindows" || path[0] === "glassSolidity" || path[0] === "reduceTransparency") {
            glassDirty = true
            glassSync.restart()
        }
    }
    // privacy.json, input.json (with hypr's input.conf) and accessibility.json
    // (with accessibility.conf) have one writer too, set-prefs.py: it changes
    // only the keys asked for in the latest saved record, under the record's
    // lock, so two Settings windows never undo each other's changes. A change
    // is shown at once, saved (changes made close together go in one call),
    // and only once it's saved applied to the running session; the record
    // shown afterwards is the one saved.
    readonly property string setter: decodeURIComponent(Qt.resolvedUrl("set-prefs.py").toString().replace("file://", ""))
    readonly property var recordFiles: ({ privacy: "privacy.json", input: "input.json", accessibility: "accessibility.json", windows: "windows.json" })
    property var pendingKeys: ({})          // record → { key: value } not yet saved
    property var afterSave: ({})            // record → [function(ok)]
    function setRecord(name, key, value, applied) {
        const p = Object.assign({}, pendingKeys)
        p[name] = Object.assign({}, p[name] ?? {})
        p[name][key] = value
        pendingKeys = p
        if (applied) {
            const a = Object.assign({}, afterSave)
            a[name] = (a[name] ?? []).concat([applied])
            afterSave = a
        }
        if (sys[name] !== undefined) sys[name] = setIn(sys[name], [key], value)
        recordSave.restart()
    }
    Timer {
        id: recordSave
        interval: 80
        onTriggered: {
            const pending = sys.pendingKeys, after = sys.afterSave
            sys.pendingKeys = ({})
            sys.afterSave = ({})
            for (const name in pending) {
                const keys = pending[name]
                sys.run(["python3", sys.setter, name].concat(Object.keys(keys).map((k) => k + "=" + JSON.stringify(keys[k]))), (out, code) => {
                    let r = null
                    try { r = JSON.parse(out) } catch (e) {}
                    const ok = code === 0 && !!r && r.ok === true
                    if (ok && sys[name] !== undefined) sys[name] = r.record
                    if (!ok) sys.failed(sys.recordFiles[name], r?.error ?? "the file couldn't be written")
                    for (const f of after[name] ?? []) f(ok, keys)
                })
            }
        }
    }
    // A change was saved but the running session refused it: it isn't lost,
    // and it applies the next time you sign in.
    function notApplied(what, why) {
        writeError = "Your change was saved, but it couldn't be applied now (" + what + ": " + why + "). It takes effect the next time you sign in."
    }
    function applyLive(args, what) {
        run(args, (out, code) => {
            if (code !== 0 || /error|invalid|no such/i.test(out)) notApplied(what, (out.trim() || "status " + code).split("\n")[0])
        })
    }

    function setPrivacy(key, value) { setRecord("privacy", key, value) }

    // Keyboard and pointer: input.json is the record; hypr's input.conf is
    // generated from it with it (sourced by hyprland.conf).
    readonly property var inputKeywords: ({ layout: "input:kb_layout", variant: "input:kb_variant", repeatRate: "input:repeat_rate", repeatDelay: "input:repeat_delay",
                                            sensitivity: "input:sensitivity", naturalScroll: "input:touchpad:natural_scroll", tapToClick: "input:touchpad:tap-to-click",
                                            twoFingerClick: "input:touchpad:clickfinger_behavior", disableWhileTyping: "input:touchpad:disable_while_typing",
                                            tapAndDrag: "input:touchpad:tap_and_drag", dragLock: "input:touchpad:drag_lock",
                                            scrollFactor: "input:touchpad:scroll_factor" })
    function setInput(key, value) {
        setRecord("input", key, value, (ok) => {
            const kw = inputKeywords[key]
            if (ok && kw) applyLive(["hyprctl", "keyword", kw, String(typeof value === "number" && key !== "sensitivity" ? Math.round(value) : value)], "input.conf")
        })
    }

    // Persist and apply the exact Hyprland controls from Desktop & Dock.
    // The record writer generates ~/.config/hypr/golden-gate/windows.conf
    // atomically, so the same values survive restart or Settings OTA updates.
    readonly property var windowKeywords: ({
        snapEnabled: "general:snap:enabled",
        windowGap: "general:snap:window_gap",
        monitorGap: "general:snap:monitor_gap",
        respectGaps: "general:snap:respect_gaps",
        resizeOnBorder: "general:resize_on_border",
        grabArea: "general:extend_border_grab_area"
    })
    function setWindow(key, value) {
        if (!windowKeywords[key]) return
        setRecord("windows", key, value, (ok) => {
            if (ok) {
                // machine.conf contains the optional windows.conf snapshot.
                // Refresh it after each saved change so a Hyprland reload
                // keeps the user's choices without ever sourcing a missing
                // windows.conf from the main configuration.
                const setup = sys.config + "/hypr/golden-gate/machine-conf.sh"
                const generated = sys.config + "/hypr/golden-gate/machine.conf"
                run(["sh", setup, generated], (out, code) => {
                    if (code !== 0) sys.notApplied("machine.conf", out || "Could not update session defaults.")
                })
                applyLive(["hyprctl", "keyword", windowKeywords[key],
                    typeof value === "boolean" ? String(value).toLowerCase() : String(value)], "windows.conf")
            }
        })
    }

    // Region, formats and what Setup Assistant put off (region.py): Language &
    // Region shows the saved formats, not the language's; Finish Setting Up
    // lists what's left, each with a way to finish it.
    readonly property string regionTool: decodeURIComponent(Qt.resolvedUrl("region.py").toString().replace("file://", ""))
    readonly property string systemCall: decodeURIComponent(Qt.resolvedUrl("../setup/account-call.sh").toString().replace("file://", ""))
    property var region: ({ region: "", zone: "", formats: "", deferred: [] })
    function refreshRegion() {
        run(["python3", regionTool, "status"], (out) => {
            try { const r = JSON.parse(out); if (r.ok) region = r } catch (e) {}
        })
    }
    function regionRun(args, done) {
        run(["python3", regionTool].concat(args), (out, code) => {
            let r = null
            try { r = JSON.parse(out) } catch (e) {}
            refreshRegion()
            if (done) done(code === 0 && !!r && r.ok === true, r?.error ?? "")
        })
    }
    // The system-wide part (time zone, generating a formats locale) needs an
    // administrator: the same root helper Setup Assistant uses.
    function systemSetup(request, done) {
        run(["sh", "-c", 'printf "%s" "$1" | sh "$2"', "sh", JSON.stringify(Object.assign({ operation: "system" }, request)), systemCall], (out, code) => {
            let r = null
            try { r = JSON.parse(out) } catch (e) {}
            done(code === 0 && !!r && r.ok === true, r ? (r.zone || r.formats || r.error || "") : (out.trim() || "Authorization was refused or isn't available."))
        })
    }
    function setZone(zone, done) {
        run(["timedatectl", "set-timezone", zone], (out, code) => {
            if (code !== 0) { if (done) done(false, out.trim() || "The time zone couldn't be set."); return }
            regionRun(["set-zone", zone], done)
        })
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
    JsonFile { id: windowsFile; path: sys.gg + "/windows.json"; key: "windows" }
    // First time: show the keyboard Setup Assistant wrote (set-prefs.py keeps
    // it in input.json the first time it saves, so a later change, such as the
    // repeat rate, keeps the same layout and variant).
    Component.onCompleted: { refreshRegion(); readSetupKeyboard() }
    function readSetupKeyboard() { sh('sed -n "s/^ *\\(kb_layout\\|kb_variant\\) *= *\\(.*\\)/\\1=\\2/p" "' + config + '/hypr/golden-gate/input.conf" 2>/dev/null', (out) => {
        if (input.layout) return
        let i = input
        for (const line of out.split("\n")) {
            const [k, v] = line.split("=")
            if (k === "kb_layout" && v && v.trim()) i = setIn(i, ["layout"], v.trim())
            if (k === "kb_variant" && v !== undefined) i = setIn(i, ["variant"], v.trim())
        }
        input = i
    }) }
}
