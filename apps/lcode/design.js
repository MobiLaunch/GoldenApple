// The App Designer's document (Interface.lcdesign): pure functions that read
// and change it. Every change returns a new document, so undo is a stack of
// snapshots and nothing on screen holds a stale node.
//
//   { format: 1,
//     app:     { name, style: sidebar|window|utility, accent, appearance, width, height, … },
//     state:   [ { name, type: text|number|bool|list, value, persist } ],
//     colors:  [ { name, light, dark } ],
//     screens: [ { id, title, symbol, toolbar: [nodes], root: node } ] }
//   node:      { id, type, props: {…}, actions: { tap: [ {do, …} ] }, children: [nodes] }
.pragma library
.import "../lib/kit/catalog.js" as Catalog

function clone(x) { return JSON.parse(JSON.stringify(x)); }

function parse(text) {
    const doc = JSON.parse(text);
    if (!doc || typeof doc !== "object") throw new Error("Not a design.");
    doc.format = doc.format || 1;
    doc.app = Object.assign({ name: "App", style: "window", accent: "#0a84ff", appearance: "auto", width: 900, height: 620,
                              resizable: true, sidebarWidth: 220 }, doc.app || {});
    doc.state = Array.isArray(doc.state) ? doc.state : [];
    doc.colors = Array.isArray(doc.colors) ? doc.colors : [];
    doc.screens = Array.isArray(doc.screens) && doc.screens.length ? doc.screens
        : [{ id: "home", title: "Home", symbol: "house", root: { id: "n1", type: "VStack", props: {}, children: [] } }];
    for (const s of doc.screens) {
        if (!s.root) s.root = { id: newId(doc), type: "VStack", props: {}, children: [] };
        s.toolbar = Array.isArray(s.toolbar) ? s.toolbar : [];
    }
    return doc;
}

function serialize(doc) { return JSON.stringify(doc, null, 2) + "\n"; }

// ------------------------------------------------------------------ nodes

function walk(node, fn, parent, depth) {
    if (!node) return;
    fn(node, parent || null, depth || 0);
    for (const c of node.children || []) walk(c, fn, node, (depth || 0) + 1);
}

function allNodes(doc) {
    const out = [];
    for (const s of doc.screens) walk(s.root, (n) => out.push(n));
    return out;
}

function newId(doc) {
    let max = 0;
    for (const s of doc.screens || []) walk(s.root, (n) => {
        const m = /^n(\d+)$/.exec(n.id || "");
        if (m) max = Math.max(max, +m[1]);
    });
    return "n" + (max + 1);
}

// { node, parent, index, screen } for an id, or null.
function find(doc, id) {
    for (const s of doc.screens) {
        if (s.root && s.root.id === id) return { node: s.root, parent: null, index: 0, screen: s };
        let hit = null;
        walk(s.root, (n, parent) => {
            if (!hit && n.id === id) hit = { node: n, parent: parent, index: parent ? parent.children.indexOf(n) : 0, screen: s };
        });
        if (hit) return hit;
    }
    return null;
}

function screenById(doc, id) { return doc.screens.find((s) => s.id === id) || null; }

// The ids from the screen's root down to a node (for the outline and selection).
function pathTo(doc, id) {
    const hit = find(doc, id);
    if (!hit) return [];
    const out = [];
    const visit = (n, trail) => {
        if (n.id === id) { out.push(...trail, n.id); return true; }
        for (const c of n.children || []) if (visit(c, trail.concat([n.id]))) return true;
        return false;
    };
    visit(hit.screen.root, []);
    return out;
}

// A new node of a type (or a Library entry: { type, props, children }).
function createNode(doc, entry) {
    const spec = typeof entry === "string" ? { type: entry } : entry;
    const info = Catalog.component(spec.type);
    if (!info) throw new Error("Unknown component " + spec.type);
    let next = +newId(doc).slice(1);
    const build = (s) => {
        const node = { id: "n" + next++, type: s.type, props: Object.assign({}, clone((Catalog.component(s.type) || {}).defaults || {}), clone(s.props || {})) };
        if (Catalog.isContainer(s.type)) node.children = (s.children || []).map(build);
        return node;
    };
    return build(spec);
}

// Fresh ids for a copied subtree.
function reid(doc, node, extraTaken) {
    let next = +newId(doc).slice(1) + (extraTaken || 0);
    const copy = clone(node);
    walk(copy, (n) => { n.id = "n" + next++; });
    return copy;
}

function insert(doc, parentId, index, node) {
    const d = clone(doc);
    const hit = find(d, parentId);
    if (!hit || !Catalog.isContainer(hit.node.type)) throw new Error("That can't contain other items.");
    hit.node.children = hit.node.children || [];
    const i = index < 0 || index > hit.node.children.length ? hit.node.children.length : index;
    hit.node.children.splice(i, 0, clone(node));
    return d;
}

// Where something new goes when nothing says otherwise: into the selected
// container, after the selected item, or at the end of the screen.
function insertionPoint(doc, screenId, selectedId) {
    const screen = screenById(doc, screenId) || doc.screens[0];
    const hit = selectedId ? find(doc, selectedId) : null;
    if (hit && hit.screen === screen) {
        if (Catalog.isContainer(hit.node.type)) return { parent: hit.node.id, index: (hit.node.children || []).length };
        if (hit.parent) return { parent: hit.parent.id, index: hit.index + 1 };
    }
    return { parent: screen.root.id, index: (screen.root.children || []).length };
}

function remove(doc, id) {
    const d = clone(doc);
    const hit = find(d, id);
    if (!hit || !hit.parent) return d;            // a screen's root stays
    hit.parent.children.splice(hit.index, 1);
    return d;
}

function isInside(doc, id, ancestorId) {
    const hit = find(doc, ancestorId);
    if (!hit) return false;
    let inside = false;
    walk(hit.node, (n) => { if (n.id === id) inside = true; });
    return inside;
}

function move(doc, id, parentId, index) {
    if (id === parentId || isInside(doc, parentId, id)) return doc;
    const hit = find(doc, id);
    if (!hit || !hit.parent) return doc;
    let i = index;
    if (hit.parent.id === parentId && hit.index < index) i--;
    const node = clone(hit.node);
    return insert(remove(doc, id), parentId, i, node);
}

// Patch a node's properties; a null value removes one (back to its default).
function update(doc, id, patch) {
    const d = clone(doc);
    const hit = find(d, id);
    if (!hit) return d;
    hit.node.props = hit.node.props || {};
    for (const k in patch) {
        if (patch[k] === null || patch[k] === undefined) delete hit.node.props[k];
        else hit.node.props[k] = clone(patch[k]);
    }
    return d;
}

function setActions(doc, id, event, actions) {
    const d = clone(doc);
    const hit = find(d, id);
    if (!hit) return d;
    hit.node.actions = hit.node.actions || {};
    if (actions && actions.length) hit.node.actions[event] = clone(actions);
    else delete hit.node.actions[event];
    if (!Object.keys(hit.node.actions).length) delete hit.node.actions;
    return d;
}

function duplicate(doc, id) {
    const hit = find(doc, id);
    if (!hit || !hit.parent) return { doc: doc, id: id };
    const copy = reid(doc, hit.node);
    return { doc: insert(doc, hit.parent.id, hit.index + 1, copy), id: copy.id };
}

// Wrap a node in a new container (Embed In ▸ Vertical Stack, Card, …).
function embed(doc, id, entry) {
    const hit = find(doc, id);
    if (!hit) return { doc: doc, id: id };
    const wrapper = createNode(doc, Object.assign({}, typeof entry === "string" ? { type: entry } : entry, { children: [] }));
    const d = clone(doc);
    const h = find(d, id);
    wrapper.children = [clone(h.node)];
    if (h.parent) h.parent.children[h.index] = wrapper;
    else h.screen.root = wrapper;
    return { doc: d, id: wrapper.id };
}

// Replace a container with its contents.
function unembed(doc, id) {
    const hit = find(doc, id);
    if (!hit || !Catalog.isContainer(hit.node.type)) return doc;
    const d = clone(doc);
    const h = find(d, id);
    const kids = h.node.children || [];
    if (!h.parent) {
        if (kids.length === 1 && Catalog.isContainer(kids[0].type)) h.screen.root = kids[0];
        return d;
    }
    h.parent.children.splice(h.index, 1, ...kids);
    return d;
}

// What the outline calls a node: its name, or its type and a hint of its content.
function label(node) {
    if (!node) return "";
    const p = node.props || {};
    if (p.nodeName) return p.nodeName;
    const t = Catalog.title(node.type);
    const hint = p.text || p.title || p.label || p.placeholder || (node.type === "Symbol" ? p.name : "") || "";
    return hint ? t + " “" + String(hint).split("\n")[0].slice(0, 24) + "”" : t;
}

// ---------------------------------------------------------------- screens

function screenId(doc, title) {
    const base = String(title || "screen").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "screen";
    let id = base, n = 2;
    while (doc.screens.some((s) => s.id === id)) id = base + "-" + n++;
    return id;
}

function addScreen(doc, title) {
    const d = clone(doc);
    const id = screenId(d, title);
    const root = createNode(d, { type: "VStack", props: { spacing: 16, padding: 24, alignment: "leading", justify: "start" },
                                 children: [{ type: "Text", props: { text: title, textStyle: "largeTitle" } }] });
    d.screens.push({ id: id, title: title, symbol: "doc", toolbar: [], root: root });
    return { doc: d, id: id };
}

function removeScreen(doc, id) {
    if (doc.screens.length <= 1) return doc;
    const d = clone(doc);
    d.screens = d.screens.filter((s) => s.id !== id);
    return d;
}

function updateScreen(doc, id, patch) {
    const d = clone(doc);
    const s = screenById(d, id);
    if (s) for (const k in patch) s[k] = clone(patch[k]);
    return d;
}

function moveScreen(doc, id, delta) {
    const d = clone(doc);
    const i = d.screens.findIndex((s) => s.id === id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= d.screens.length) return d;
    const [s] = d.screens.splice(i, 1);
    d.screens.splice(j, 0, s);
    return d;
}

function updateApp(doc, patch) {
    const d = clone(doc);
    for (const k in patch) {
        if (patch[k] === null || patch[k] === undefined) delete d.app[k];
        else d.app[k] = clone(patch[k]);
    }
    return d;
}

// -------------------------------------------------------------- variables

var VAR_DEFAULTS = { text: "", number: 0, bool: false, list: [] };

function variableName(doc, base) {
    let name = String(base || "value").replace(/[^A-Za-z0-9_]/g, "") || "value";
    if (/^[0-9]/.test(name)) name = "v" + name;
    let n = 2, out = name;
    while (doc.state.some((v) => v.name === out)) out = name + n++;
    return out;
}

function addVariable(doc, type, base) {
    const d = clone(doc);
    const name = variableName(d, base || (type === "list" ? "items" : type === "bool" ? "isOn" : type === "number" ? "count" : "text"));
    d.state.push({ name: name, type: type, value: clone(VAR_DEFAULTS[type]), persist: false });
    return { doc: d, name: name };
}

function variable(doc, name) { return doc.state.find((v) => v.name === name) || null; }

function updateVariable(doc, name, patch) {
    let d = clone(doc);
    const v = variable(d, name);
    if (!v) return d;
    if (patch.type && patch.type !== v.type) v.value = clone(VAR_DEFAULTS[patch.type]);
    for (const k in patch) if (k !== "name") v[k] = clone(patch[k]);
    if (patch.name && patch.name !== name) d = renameVariable(d, name, patch.name);
    return d;
}

function removeVariable(doc, name) {
    const d = clone(doc);
    d.state = d.state.filter((v) => v.name !== name);
    return d;
}

// Rename a variable everywhere it's used: {templates}, bindings, actions.
function renameVariable(doc, from, to) {
    const name = String(to).replace(/[^A-Za-z0-9_]/g, "");
    if (!name || doc.state.some((v) => v.name === name)) return doc;
    const d = clone(doc);
    const v = variable(d, from);
    if (v) v.name = name;
    const re = new RegExp("\\{" + from + "(\\.[\\w.]+)?\\}", "g");
    const fix = (s) => typeof s === "string" ? s.replace(re, (m, rest) => "{" + name + (rest || "") + "}") : s;
    for (const s of d.screens) walk(s.root, (n) => {
        for (const k in n.props || {}) n.props[k] = fix(n.props[k]);
        if (n.props && n.props.binding === from) n.props.binding = name;
        if (n.props && n.props.visibleWhen === from) n.props.visibleWhen = name;
        for (const ev in n.actions || {}) for (const a of n.actions[ev]) {
            if (a.var === from) a.var = name;
            if (a.when === from) a.when = name;
            for (const k of ["value", "title", "message", "url", "text", "command"]) a[k] = fix(a[k]);
        }
    });
    return d;
}

// Where a variable is used, for the inspector and warnings.
function usesOf(doc, name) {
    const out = [];
    for (const s of doc.screens) walk(s.root, (n) => {
        const p = n.props || {};
        let used = p.binding === name || p.visibleWhen === name;
        for (const k in p) if (typeof p[k] === "string" && p[k].indexOf("{" + name) >= 0) used = true;
        for (const ev in n.actions || {}) for (const a of n.actions[ev]) if (a.var === name || a.when === name) used = true;
        if (used) out.push({ screen: s.id, id: n.id });
    });
    return out;
}

// ------------------------------------------------------------------ colours

function addColor(doc) {
    const d = clone(doc);
    let n = d.colors.length + 1, name = "Color" + n;
    while (d.colors.some((c) => c.name === name)) name = "Color" + ++n;
    d.colors.push({ name: name, light: "#0a84ff", dark: "#409cff" });
    return { doc: d, name: name };
}

function updateColor(doc, name, patch) {
    const d = clone(doc);
    const c = d.colors.find((x) => x.name === name);
    if (c) for (const k in patch) c[k] = patch[k];
    return d;
}

function removeColor(doc, name) {
    const d = clone(doc);
    d.colors = d.colors.filter((c) => c.name !== name);
    return d;
}

// The env a Kit Scope needs for a document: accent, named colours, font.
function environment(doc, dark, assetBase) {
    const colors = {};
    for (const c of doc.colors || []) colors[c.name] = { light: c.light, dark: c.dark };
    return { dark: !!dark, accent: doc.app.accent || "", colors: colors, font: doc.app.font || "", assetBase: assetBase || "" };
}

function initialValues(doc) {
    const out = {};
    for (const v of doc.state || []) out[v.name] = clone(v.value);
    return out;
}
