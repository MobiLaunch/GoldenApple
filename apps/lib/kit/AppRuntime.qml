// An app's state and what its actions do. The App Designer's canvas runs a
// design with one of these (in a sandbox: nothing leaves the canvas), and the
// QML LCode builds calls the same functions, so both behave alike.
//
//   values      the app's variables, by name
//   screen      the screen showing; navigate() and back() move between screens
//   perform()   runs a list of design actions ({ do: "increment", var: "count", by: 1 }, …)
import QtQuick
import "kit.js" as K

QtObject {
    id: app
    property var initial: ({})
    property var values: JSON.parse(JSON.stringify(initial))
    property var screens: []
    property string screen: screens.length ? screens[0] : ""
    property var backStack: []
    property bool sandbox: false
    property string alertTitle: ""
    property string alertMessage: ""
    property bool alertShown: false
    signal changed(string name)
    signal notice(string text)                // the sandbox says what would have happened
    signal commandRequested(string command, string outVar)
    signal copyRequested(string text)
    signal notifyRequested(string title, string body)
    signal quitRequested()
    signal scriptRequested(string name, var scope)

    function reset() {
        values = JSON.parse(JSON.stringify(initial))
        backStack = []
        screen = screens.length ? screens[0] : ""
    }

    // ------------------------------------------------------------ values
    function get(name) { return values[name] }
    function set(name, value) {
        const next = Object.assign({}, values)
        const old = next[name]
        if (typeof old === "number" && typeof value !== "number") {
            const n = parseFloat(value)
            value = isNaN(n) ? old : n
        } else if (typeof old === "boolean" && typeof value !== "boolean") {
            value = value === "true" || value === true || value === 1 || value === "1"
        }
        next[name] = value
        values = next
        changed(name)
    }
    function toggle(name) { set(name, !values[name]) }
    function increment(name, by) { set(name, (+values[name] || 0) + (by === undefined ? 1 : +by)) }
    function clear(name) {
        const v = values[name]
        set(name, Array.isArray(v) ? [] : typeof v === "number" ? 0 : typeof v === "boolean" ? false : "")
    }
    function append(name, item) {
        if (item === "" || item === undefined || item === null) return
        const list = Array.isArray(values[name]) ? values[name].slice() : []
        // A list of rows keeps rows: text becomes a row titled with it.
        if (typeof item === "string" && list.length && typeof list[0] === "object") item = { title: item, done: false }
        list.push(item)
        set(name, list)
    }
    function removeAt(name, index) {
        const list = Array.isArray(values[name]) ? values[name].slice() : []
        if (index >= 0 && index < list.length) list.splice(index, 1)
        set(name, list)
    }
    function setItem(name, index, key, value) {
        const list = Array.isArray(values[name]) ? values[name].slice() : []
        if (index < 0 || index >= list.length) return
        const row = typeof list[index] === "object" && list[index] !== null ? Object.assign({}, list[index]) : { title: K.str(list[index]) }
        row[key] = value
        list[index] = row
        set(name, list)
    }

    // ----------------------------------------------------------- screens
    function navigate(id) {
        if (!id || id === screen) return
        backStack = backStack.concat([screen])
        screen = id
    }
    function back() {
        if (!backStack.length) return
        screen = backStack[backStack.length - 1]
        backStack = backStack.slice(0, -1)
    }

    // ------------------------------------------------- the outside world
    function alert(title, message) { alertTitle = str(title); alertMessage = str(message); alertShown = true }
    function openUrl(url) { if (sandbox) notice("Opens " + url); else Qt.openUrlExternally(url) }
    function run(command, outVar) { if (sandbox) notice("Runs: " + command); else commandRequested(command, outVar || "") }
    function copy(text) { if (sandbox) notice("Copies “" + text + "”"); else copyRequested(str(text)) }
    function notify(title, body) { if (sandbox) notice("Notification: " + title); else notifyRequested(str(title), str(body)) }
    function quit() { if (sandbox) notice("Quits the app"); else quitRequested() }

    // ------------------------------------------------------------- text
    function str(v) { return K.str(v) }
    function text(template, scope) { return K.interpolate(template, values, scope) }

    // A value from a design: text templates filled in; numbers stay numbers.
    function resolve(value, scope) {
        if (typeof value !== "string") return value
        const whole = /^\{([A-Za-z_][\w.]*)\}$/.exec(value)
        if (whole) {
            const v = K.lookup(whole[1], values, scope)
            return v === undefined ? value : v
        }
        return text(value, scope)
    }

    // ---------------------------------------------------------- actions
    function perform(actions, scope) {
        for (const a of actions || []) {
            if (!a || !a.do) continue
            if (a.when && !K.lookup(a.when, values, scope)) continue
            switch (a.do) {
            case "set": set(a.var, resolve(a.value, scope)); break
            case "toggle": toggle(a.var); break
            case "increment": increment(a.var, a.by === undefined ? 1 : +a.by); break
            case "clear": clear(a.var); break
            case "append": append(a.var, resolve(a.value, scope)); break
            case "removeItem": if (scope && scope.index !== undefined) removeAt(a.var, scope.index); break
            case "navigate": navigate(a.screen); break
            case "back": back(); break
            case "alert": alert(text(a.title || "", scope), text(a.message || "", scope)); break
            case "openUrl": openUrl(text(a.url || "", scope)); break
            case "run": run(text(a.command || "", scope), a.var || ""); break
            case "copy": copy(text(a.text || "", scope)); break
            case "notify": notify(text(a.title || "", scope), text(a.message || "", scope)); break
            case "quit": quit(); break
            case "script":
                if (sandbox) notice("Calls Logic." + a.call + "()")
                else scriptRequested(a.call || "", scope || null)
                break
            }
        }
    }
}
