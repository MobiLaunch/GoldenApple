// LCode's commands and their key bindings, rebindable in Settings ▸ Key
// Bindings. Bindings are Qt key sequences; CitronOS's keyd layer sends ⌘
// as Ctrl, so "Ctrl+R" is shown and typed as ⌘R.
.pragma library

var COMMANDS = [
    { id: "run", title: "Run", menu: "Product", keys: ["Ctrl+R"] },
    { id: "build", title: "Build", menu: "Product", keys: ["Ctrl+B"] },
    { id: "test", title: "Test", menu: "Product", keys: ["Ctrl+U"] },
    { id: "clean", title: "Clean Build Folder", menu: "Product", keys: ["Ctrl+Shift+K"] },
    { id: "stop", title: "Stop", menu: "Product", keys: ["Ctrl+."] },
    { id: "archive", title: "Archive", menu: "Product", keys: [] },
    { id: "editScheme", title: "Edit Scheme…", menu: "Product", keys: ["Ctrl+<", "Ctrl+Shift+,"] },
    { id: "save", title: "Save", menu: "File", keys: ["Ctrl+S"] },
    { id: "saveAll", title: "Save All", menu: "File", keys: ["Ctrl+Alt+S"] },
    { id: "newFile", title: "New File…", menu: "File", keys: ["Ctrl+N"] },
    { id: "newProject", title: "New Project…", menu: "File", keys: ["Ctrl+Shift+N"] },
    { id: "open", title: "Open…", menu: "File", keys: ["Ctrl+O"] },
    { id: "openQuickly", title: "Open Quickly…", menu: "File", keys: ["Ctrl+Shift+O"] },
    { id: "find", title: "Find", menu: "Find", keys: ["Ctrl+F"] },
    { id: "findReplace", title: "Find and Replace", menu: "Find", keys: ["Ctrl+Alt+F"] },
    { id: "findNext", title: "Find Next", menu: "Find", keys: ["Ctrl+G"] },
    { id: "findPrevious", title: "Find Previous", menu: "Find", keys: ["Ctrl+Shift+G"] },
    { id: "findInProject", title: "Find in Project…", menu: "Find", keys: ["Ctrl+Shift+F"] },
    { id: "toggleComment", title: "Comment Selection", menu: "Editor", keys: ["Ctrl+/"] },
    { id: "complete", title: "Show Completions", menu: "Editor", keys: ["Ctrl+Space"] },
    { id: "goToLine", title: "Go to Line…", menu: "Editor", keys: ["Ctrl+L"] },
    { id: "fontBigger", title: "Increase Font Size", menu: "Editor", keys: ["Ctrl+=", "Ctrl++"] },
    { id: "fontSmaller", title: "Decrease Font Size", menu: "Editor", keys: ["Ctrl+-"] },
    { id: "fontReset", title: "Actual Size", menu: "Editor", keys: [] },
    { id: "library", title: "Library", menu: "View", keys: ["Ctrl+Shift+L"] },
    { id: "toggleNavigator", title: "Show/Hide Navigator", menu: "View", keys: ["Ctrl+0"] },
    { id: "toggleDebug", title: "Show/Hide Debug Area", menu: "View", keys: ["Ctrl+Shift+Y"] },
    { id: "toggleInspector", title: "Show/Hide Inspectors", menu: "View", keys: ["Ctrl+Alt+0"] },
    { id: "projectNavigator", title: "Project Navigator", menu: "View", keys: ["Ctrl+1"] },
    { id: "findNavigator", title: "Find Navigator", menu: "View", keys: ["Ctrl+4"] },
    { id: "issueNavigator", title: "Issue Navigator", menu: "View", keys: ["Ctrl+5"] },
    { id: "reportNavigator", title: "Report Navigator", menu: "View", keys: ["Ctrl+9"] },
    { id: "clearConsole", title: "Clear Console", menu: "Debug", keys: ["Ctrl+K"] },
    { id: "simulator", title: "Open Simulator", menu: "Window", keys: ["Ctrl+Shift+2"] },
    { id: "settings", title: "Settings…", menu: "LCode", keys: ["Ctrl+,"] },
];

var MENUS = ["LCode", "File", "Editor", "Find", "View", "Product", "Debug", "Window"];

function byId(id) {
    for (var i = 0; i < COMMANDS.length; i++) if (COMMANDS[i].id === id) return COMMANDS[i];
    return null;
}

// The sequences for a command: the user's binding (an array, possibly empty)
// or the default.
function keysFor(id, overrides) {
    if (overrides && Object.prototype.hasOwnProperty.call(overrides, id)) return overrides[id] || [];
    var c = byId(id);
    return c ? c.keys : [];
}

// ⌘⌥⇧ symbols, as in Apple menus: "Ctrl+Shift+K" → "⇧⌘K".
var KEY_NAMES = { "Space": "Space", "Esc": "⎋", "Escape": "⎋", "Return": "↩", "Enter": "↩", "Tab": "⇥",
                  "Backspace": "⌫", "Delete": "⌦", "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
                  "Home": "↖", "End": "↘", "PgUp": "⇞", "PgDown": "⇟" };
function display(seq) {
    if (!seq) return "";
    var parts = seq === "Ctrl++" ? ["Ctrl", "+"] : seq.split("+");
    var key = parts[parts.length - 1], mods = parts.slice(0, -1);
    if (key === "" && parts.length > 1) { key = "+"; mods = parts.slice(0, -2); }
    var out = "";
    if (mods.indexOf("Meta") >= 0) out += "⌃";
    if (mods.indexOf("Alt") >= 0) out += "⌥";
    if (mods.indexOf("Shift") >= 0) out += "⇧";
    if (mods.indexOf("Ctrl") >= 0) out += "⌘";
    return out + (KEY_NAMES[key] || key.toUpperCase());
}
function displayFor(id, overrides) {
    var k = keysFor(id, overrides);
    return k.length ? display(k[0]) : "";
}

// A key event → a sequence, while recording a binding. Returns "" for a
// lone modifier, which isn't a binding by itself.
function keyName(key, text) {
    // Qt.Key_* values for the keys that have no printable text.
    var names = { 0x01000000: "Esc", 0x01000001: "Tab", 0x01000003: "Backspace", 0x01000004: "Return",
                  0x01000005: "Enter", 0x01000007: "Delete", 0x01000010: "Home", 0x01000011: "End",
                  0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
                  0x01000016: "PgUp", 0x01000017: "PgDown", 0x20: "Space" };
    if (names[key]) return names[key];
    if (key >= 0x01000030 && key <= 0x01000052) return "F" + (key - 0x01000030 + 1);
    if (key >= 0x20 && key < 0x7f) return String.fromCharCode(key).toUpperCase();
    return text && text.trim() ? text.toUpperCase() : "";
}
function sequenceFor(key, modifiers, text) {
    // Lone modifiers (Shift, Ctrl, Meta, Alt).
    if (key >= 0x01000020 && key <= 0x01000023) return "";
    var name = keyName(key, text);
    if (!name) return "";
    var mods = [];
    if (modifiers & 0x04000000) mods.push("Ctrl");
    if (modifiers & 0x10000000) mods.push("Meta");
    if (modifiers & 0x08000000) mods.push("Alt");
    if (modifiers & 0x02000000) mods.push("Shift");
    return mods.concat([name]).join("+");
}

// Commands that already use a sequence (to warn before taking it).
function conflicts(seq, exceptId, overrides) {
    var out = [];
    for (var i = 0; i < COMMANDS.length; i++) {
        var c = COMMANDS[i];
        if (c.id !== exceptId && keysFor(c.id, overrides).indexOf(seq) >= 0) out.push(c);
    }
    return out;
}

// Bind `seq` to `id` alone, taking it from any other command.
function bind(id, seq, overrides) {
    var next = {};
    for (var k in overrides || {}) next[k] = overrides[k].slice();
    var others = conflicts(seq, id, overrides);
    for (var i = 0; i < others.length; i++) {
        next[others[i].id] = keysFor(others[i].id, next).filter(function (s) { return s !== seq; });
    }
    next[id] = seq ? [seq] : [];
    return next;
}
function reset(id, overrides) {
    var next = {};
    for (var k in overrides || {}) if (k !== id) next[k] = overrides[k];
    return next;
}
function isCustomized(id, overrides) {
    return !!overrides && Object.prototype.hasOwnProperty.call(overrides, id);
}

// Settings ▸ Behaviors: what LCode does when a build, test or run starts or
// ends. debug: "" (no change) | "show" | "hide"; navigator: "" | "project" |
// "issues" | "reports"; reveal: jump to the first error; notify: a system
// notification; sound: a sound.
var EVENTS = [
    { id: "buildSucceeded", group: "Building", title: "Succeeds", defaults: { debug: "", navigator: "", reveal: false, notify: false, sound: false } },
    { id: "buildFailed", group: "Building", title: "Fails", defaults: { debug: "", navigator: "issues", reveal: true, notify: false, sound: false } },
    { id: "testSucceeded", group: "Testing", title: "Succeeds", defaults: { debug: "show", navigator: "", reveal: false, notify: false, sound: false } },
    { id: "testFailed", group: "Testing", title: "Fails", defaults: { debug: "show", navigator: "issues", reveal: true, notify: false, sound: false } },
    { id: "runStarted", group: "Running", title: "Starts", defaults: { debug: "show", navigator: "", reveal: false, notify: false, sound: false } },
    { id: "runExited", group: "Running", title: "Exits", defaults: { debug: "", navigator: "", reveal: false, notify: false, sound: false } },
];

function behavior(id, settings) {
    var e = null;
    for (var i = 0; i < EVENTS.length; i++) if (EVENTS[i].id === id) e = EVENTS[i];
    if (!e) return {};
    var out = {}, own = (settings || {})[id] || {};
    for (var k in e.defaults) out[k] = Object.prototype.hasOwnProperty.call(own, k) ? own[k] : e.defaults[k];
    return out;
}
