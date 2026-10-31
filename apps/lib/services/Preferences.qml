// One domain of CitronOS preferences (desktop.json, …) for the shell and the
// apps: what's saved, kept current, and the way to change a key.
//   Preferences { id: desktop; domain: "desktop" }
//   desktop.data.dock?.size
//   desktop.write("dock.size", 64, (ok, why) => …)   shown at once, put back if it can't be saved
//   desktop.save("focus.session", s, (ok, why) => …)  shown once it's saved
// Through citronos-settingsd (org.citronos.Settings1) when it's there: its
// Changed signals keep `data` current, key by key, and a value that doesn't
// fit the schema is refused with the reason. Without it (before it starts,
// or if it can't), the file is read and watched and gg-pref writes, with the
// same schema and lock, so nothing is lost either way. GG_PREFS_READONLY=1 (the
// lock screen's process) reads the file only, and starts no bridge.
import Quickshell
import Quickshell.Io
import QtQuick
import ".."

QtObject {
    id: store
    property string domain: "desktop"
    property var data: ({})
    readonly property bool viaService: store.settingsd.ready
    readonly property bool useService: Quickshell.env("GG_PREFS_READONLY") !== "1"
    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/" + domain + ".json"
    signal restored(string message)          // a damaged file was put back from its last good copy

    property DBusObject settingsd: DBusObject {
        service: "org.citronos.Settings1"
        path: "/org/citronos/Settings1"
        signalNames: ["Changed", "Restored"]
        active: store.useService
        onReadyChanged: {
            if (ready) call("GetAll", [store.domain], (ok, result) => { if (ok) store.data = store.withShown(JSON.parse(result[0])) })
            else store.desktopFile.reload()
        }
        onSignalled: (name, args) => {
            if (args[0] !== store.domain) return
            if (name === "Restored") { store.restored(args[1]); return }
            // A change of ours not yet answered is the latest word on its key:
            // an earlier one's signal mustn't flick it back meanwhile.
            if (name === "Changed" && !store.busy(args[1]))
                store.data = store.setIn(store.data, args[1].split("."), JSON.parse(args[2]))
        }
    }

    // Keys with a change of ours in flight → how many.
    property var inFlight: ({})
    function busy(key) {
        for (const k in inFlight)
            if (k === key || key.startsWith(k + ".") || k.startsWith(key + ".")) return true
        return false
    }
    function track(key, step) {
        const f = Object.assign({}, inFlight)
        f[key] = (f[key] ?? 0) + step
        if (f[key] <= 0) delete f[key]
        inFlight = f
    }

    // Changes shown but not yet answered, key → value: whatever is read
    // meanwhile (GetAll's answer, the file) is shown with them on top, or a
    // change would vanish from the screen and come back.
    property var shown: ({})
    function withShown(read) {
        let out = read
        for (const k in shown) out = setIn(out, k.split("."), shown[k])
        return out
    }
    function write(key, value, done) {
        const before = valueAt(data, key)
        const wrote = JSON.stringify(value)
        data = setIn(data, key.split("."), value)
        shown = Object.assign({}, shown, { [key]: value })
        send(key, value, (ok, why) => {
            const latest = JSON.stringify(store.shown[key]) === wrote
            if (latest) {
                const s = Object.assign({}, store.shown)
                delete s[key]
                store.shown = s
            }
            // Put back only if nothing changed it again meanwhile.
            if (!ok && latest && JSON.stringify(valueAt(store.data, key)) === wrote)
                store.data = store.setIn(store.data, key.split("."), before)
            if (done) done(ok, why)
        })
    }
    function save(key, value, done) {
        send(key, value, (ok, why) => {
            if (ok) store.data = store.setIn(store.data, key.split("."), value)
            if (done) done(ok, why)
        })
    }
    function send(key, value, done) {
        const text = JSON.stringify(value)
        track(key, 1)
        const finish = (ok, why) => { store.track(key, -1); done(ok, why) }
        // Without the service (or if it stopped mid-change) gg-pref makes the
        // change: the same value, so it's harmless if it had been saved.
        store.settingsd.call("Set", [domain, key, text], (ok, result, why) => {
            if (!ok && why === "unavailable") store.ggPref(key, text, finish)
            else finish(ok, why)
        })
    }

    property Component prefWriter: Component {
        Process {
            id: w
            property var done
            stderr: StdioCollector { id: writeErr }
            onExited: (code) => {
                w.done(code === 0, code === 0 ? "" : (writeErr.text.trim() || "it couldn't be saved"))
                w.destroy()
            }
        }
    }
    function ggPref(key, text, done) {
        const p = store.prefWriter.createObject(store, { command: ["gg-pref", key, text], done: done })
        p.running = true
    }

    function setIn(obj, path, value) {
        const out = Object.assign({}, obj ?? {})
        out[path[0]] = path.length === 1 ? value : setIn(typeof out[path[0]] === "object" && out[path[0]] !== null ? out[path[0]] : {}, path.slice(1), value)
        return out
    }
    function valueAt(obj, key) {
        let node = obj
        for (const part of key.split(".")) node = (node && typeof node === "object") ? node[part] : undefined
        return node
    }

    // The file itself: read at once (so nothing waits for the service to
    // start), and watched while the service isn't there to say what changed.
    property FileView desktopFile: FileView {
        path: store.file
        printErrors: false
        watchChanges: !store.settingsd.ready
        onFileChanged: if (!store.settingsd.ready) reload()
        onLoaded: { if (!store.settingsd.ready) { try { store.data = store.withShown(JSON.parse(text())) } catch (e) { store.data = ({}) } } }
        onLoadFailed: if (!store.settingsd.ready) store.data = ({})
    }
}
