// CitronOS Kit: the shared rules behind the components LCode's App Designer
// places and the QML it generates — colours, fonts, fills and text templates.
// The designer's canvas and the built app both use these, so they agree.
.pragma library

// ------------------------------------------------------------------ colours
// System colours, light and dark, after Apple's: they adapt to the appearance.
var SYSTEM = {
    accent:          ["#0a84ff", "#0a84ff"],
    blue:            ["#007aff", "#0a84ff"],
    indigo:          ["#5856d6", "#5e5ce6"],
    purple:          ["#af52de", "#bf5af2"],
    pink:            ["#ff2d55", "#ff375f"],
    red:             ["#ff3b30", "#ff453a"],
    orange:          ["#ff9500", "#ff9f0a"],
    yellow:          ["#ffcc00", "#ffd60a"],
    green:           ["#34c759", "#30d158"],
    mint:            ["#00c7be", "#63e6e2"],
    teal:            ["#30b0c7", "#40c8e0"],
    cyan:            ["#32ade6", "#64d2ff"],
    brown:           ["#a2845e", "#ac8e68"],
    gray:            ["#8e8e93", "#98989d"],
    white:           ["#ffffff", "#ffffff"],
    black:           ["#000000", "#000000"],
    clear:           ["#00000000", "#00000000"],
    label:           ["#e0000000", "#ebffffff"],
    secondaryLabel:  ["#8c000000", "#8cffffff"],
    tertiaryLabel:   ["#47000000", "#40ffffff"],
    background:      ["#ffffff", "#1e1e1e"],
    secondaryBackground: ["#f2f2f7", "#2c2c2e"],
    tertiaryBackground:  ["#ffffff", "#3a3a3c"],
    groupedBackground:   ["#f2f2f7", "#000000"],
    fill:            ["#14000000", "#1fffffff"],
    secondaryFill:   ["#0d000000", "#14ffffff"],
    separator:       ["#1f000000", "#26ffffff"],
};

// Names in the order the colour picker lists them.
var SYSTEM_NAMES = ["accent", "label", "secondaryLabel", "tertiaryLabel", "background", "secondaryBackground", "groupedBackground",
                    "fill", "separator", "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo",
                    "purple", "pink", "brown", "gray", "white", "black", "clear"];

function isHex(s) { return typeof s === "string" && /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(s); }

// A colour from a name (system or asset colour), a hex string or {light, dark}.
function color(spec, env, fallback) {
    const dark = !!(env && env.dark);
    if (spec === undefined || spec === null || spec === "") return fallback !== undefined ? fallback : "#00000000";
    if (typeof spec === "object") {
        if (spec.light !== undefined || spec.dark !== undefined) return color(dark ? (spec.dark || spec.light) : (spec.light || spec.dark), env, fallback);
        return fallback !== undefined ? fallback : "#00000000";
    }
    if (isHex(spec)) return spec;
    if (spec === "accent" && env && env.accent) return env.accent;
    const asset = env && env.colors ? env.colors[spec] : null;
    if (asset) return dark ? (asset.dark || asset.light) : (asset.light || asset.dark);
    const sys = SYSTEM[spec];
    if (sys) return sys[dark ? 1 : 0];
    return fallback !== undefined ? fallback : String(spec);
}

// "#rrggbb" with an opacity, for tints.
function alpha(c, a) {
    const s = String(c);
    let hex = s.replace("#", "");
    if (hex.length === 8) hex = hex.slice(2);
    if (hex.length === 3) hex = hex.split("").map((ch) => ch + ch).join("");
    const aa = Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16).padStart(2, "0");
    return "#" + aa + hex;
}

// Perceived lightness 0…1, to pick legible text on a fill.
function luminance(c) {
    let hex = String(c).replace("#", "");
    if (hex.length === 8) hex = hex.slice(2);
    if (hex.length === 3) hex = hex.split("").map((ch) => ch + ch).join("");
    const r = parseInt(hex.slice(0, 2), 16) / 255, g = parseInt(hex.slice(2, 4), 16) / 255, b = parseInt(hex.slice(4, 6), 16) / 255;
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function onColor(c) { return luminance(c) > 0.62 ? "#e0000000" : "#ffffff"; }

// -------------------------------------------------------------------- fills
// A fill: none, or { type: "color" | "gradient" | "material" | "image", … }.
//   color:    { type: "color", color }
//   gradient: { type: "gradient", colors: [c1, c2, …], angle: 0…360, radial: bool }
//   material: { type: "material", material: "regular" | "thin" | "thick" | "clear" }
//   image:    { type: "image", source, fit: "fill" | "fit" }
function fillType(fill) { return fill && typeof fill === "object" && fill.type ? fill.type : "none"; }

// Materials: a translucent tint and a rim, like Liquid Glass.
function material(name, env) {
    const dark = !!(env && env.dark);
    switch (name) {
    case "thin": return { tint: dark ? "#5a1c1c1e" : "#66ffffff", rim: dark ? "#33ffffff" : "#b3ffffff" };
    case "thick": return { tint: dark ? "#d62c2c2e" : "#e6f6f6f8", rim: dark ? "#26ffffff" : "#ccffffff" };
    case "clear": return { tint: dark ? "#2e1c1c20" : "#38ffffff", rim: dark ? "#4dffffff" : "#d9ffffff" };
    default: return { tint: dark ? "#ad2a2a2e" : "#b8fafafc", rim: dark ? "#33ffffff" : "#b3ffffff" };
    }
}

// --------------------------------------------------------------------- type
// Text styles: size and weight, on the desktop scale CitronOS uses.
var TEXT_STYLES = {
    largeTitle: { size: 26, weight: 700 },
    title:      { size: 22, weight: 700 },
    title2:     { size: 17, weight: 700 },
    title3:     { size: 15, weight: 600 },
    headline:   { size: 13, weight: 700 },
    body:       { size: 13, weight: 400 },
    callout:    { size: 12, weight: 400 },
    subheadline:{ size: 11, weight: 400 },
    footnote:   { size: 10, weight: 400 },
    caption:    { size: 10, weight: 400 },
    caption2:   { size: 9,  weight: 400 },
};
var TEXT_STYLE_NAMES = ["largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption", "caption2"];
var TEXT_STYLE_TITLES = { largeTitle: "Large Title", title: "Title", title2: "Title 2", title3: "Title 3", headline: "Headline",
                          body: "Body", callout: "Callout", subheadline: "Subheadline", footnote: "Footnote", caption: "Caption", caption2: "Caption 2" };

// Font families: "" is the system font; the designs map to installed families.
var FONT_DESIGNS = { "": "", system: "", display: "SF Pro Display", rounded: "SF Pro Rounded", serif: "serif", mono: "monospace" };

function fontFamily(family, env, uiFont) {
    const f = family !== undefined && family !== null ? String(family) : "";
    if (f in FONT_DESIGNS && f !== "") return FONT_DESIGNS[f] || uiFont;
    if (f) return f;
    if (env && env.font) return fontFamily(env.font, null, uiFont);
    return uiFont;
}

function fontSize(style, size) { return size > 0 ? size : (TEXT_STYLES[style] || TEXT_STYLES.body).size; }
function fontWeight(style, weight) { return weight > 0 ? weight : (TEXT_STYLES[style] || TEXT_STYLES.body).weight; }

// QML's font weight (Qt 6 uses CSS weights, 100…900).
function qtWeight(w) { return Math.max(100, Math.min(900, Math.round((w || 400) / 100) * 100)); }

// ----------------------------------------------------------------- templates
// "Count: {count}" → the value of count; {item.title} inside list rows.
function str(v) {
    if (v === undefined || v === null) return "";
    if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(Math.round(v * 100) / 100);
    if (typeof v === "boolean") return v ? "On" : "Off";
    if (Array.isArray(v)) return String(v.length);
    if (typeof v === "object") return v.title !== undefined ? String(v.title) : JSON.stringify(v);
    return String(v);
}

function lookup(path, values, scope) {
    const parts = String(path).trim().split(".");
    let v = scope && parts[0] in scope ? scope : values;
    for (const p of parts) {
        if (v === undefined || v === null) return undefined;
        v = v[p];
    }
    return v;
}

function interpolate(template, values, scope) {
    if (typeof template !== "string" || template.indexOf("{") < 0) return template;
    return template.replace(/\{([A-Za-z_][\w.]*)\}/g, (m, name) => {
        const v = lookup(name, values || {}, scope);
        return v === undefined ? m : str(v);
    });
}

// The variable names a template uses.
function references(template) {
    const out = [];
    if (typeof template !== "string") return out;
    template.replace(/\{([A-Za-z_][\w.]*)\}/g, (m, name) => { out.push(name.split(".")[0]); return m; });
    return out;
}

// The nearest environment ({ dark, accent, colors, … }) up an item's parents.
function findEnv(item) {
    for (let p = item; p; p = p.parent) {
        const e = p.kenv;
        if (e) return e;
    }
    return null;
}

// ---------------------------------------------------------------- geometry
// Padding: a number, or [top, right, bottom, left].
function edges(p) {
    if (Array.isArray(p)) return { top: +p[0] || 0, right: +p[1] || 0, bottom: +p[2] || 0, left: +p[3] || 0 };
    const n = +p || 0;
    return { top: n, right: n, bottom: n, left: n };
}

// Where a box sits in its cell along one axis: start, center or end.
function place(align, cell, size) {
    if (align === "leading" || align === "top" || align === "start") return 0;
    if (align === "trailing" || align === "bottom" || align === "end") return Math.max(0, cell - size);
    return Math.max(0, (cell - size) / 2);
}
