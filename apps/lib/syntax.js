// Syntax colouring for CodeEditor: a small line tokenizer per language family,
// with the colours of the classic Apple IDE themes (Default Light / Dark).
//
// A line is coloured from the state its predecessor left behind (inside a
// block comment or a multi-line string), so the editor can recolour any
// visible line without re-reading the file.
.pragma library

const NORMAL = 0, BLOCK_COMMENT = 1, MULTILINE_STRING = 2, MULTILINE_SINGLE = 3;

const SWIFT_KEYWORDS = new Set(("associatedtype class deinit enum extension fileprivate func import init inout internal let open " +
    "operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue " +
    "default defer do else fallthrough for guard if in repeat return throw throws switch where while as is try await async " +
    "actor nonisolated isolated some any self Self super true false nil mutating nonmutating override final required convenience " +
    "lazy weak unowned dynamic indirect optional get set willSet didSet macro consuming borrowing sending package").split(" "));
const C_KEYWORDS = new Set(("auto break case char const continue default do double else enum extern float for goto if inline int " +
    "long register return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false " +
    "class namespace template typename public private protected virtual override final new delete this nullptr using try catch " +
    "throw const_cast static_cast dynamic_cast reinterpret_cast constexpr noexcept NULL TRUE FALSE size_t gboolean gint gchar " +
    "interface package func go defer chan select map range fallthrough val fun object when is null").split(" "));
const RUST_KEYWORDS = new Set(("as async await break const continue crate dyn else enum extern false fn for if impl in let loop " +
    "match mod move mut pub ref return self Self static struct super trait true type union unsafe use where while " +
    "Some None Ok Err").split(" "));
const JS_KEYWORDS = new Set(("break case catch class const continue debugger default delete do else export extends false finally " +
    "for function if import in instanceof let new null return super switch this throw true try typeof undefined var void " +
    "while with yield async await of property readonly required signal alias component pragma on").split(" "));
const PY_KEYWORDS = new Set(("and as assert async await break class continue def del elif else except False finally for from " +
    "global if import in is lambda None nonlocal not or pass raise return True try while with yield match case self").split(" "));
const SHELL_KEYWORDS = new Set(("if then else elif fi for while until do done case esac function in local export return exit " +
    "true false echo set unset readonly shift source").split(" "));
const DECLARERS = ["func", "struct", "class", "enum", "protocol", "actor", "extension", "typealias", "def", "fn", "trait", "impl",
                   "interface", "function", "mod", "type", "component", "signal"];
const JS_TYPES = new Set("int real string bool var color url list double alias date point rect size font".split(" "));

var PALETTES = {
    light: { plain: "#262626", keyword: "#9b2393", string: "#c41a16", comment: "#5d6c79", number: "#1c00cf",
             type: "#3900a0", attribute: "#815f03", preprocessor: "#643820", declaration: "#0f68a0" },
    dark: { plain: "#dfdfe0", keyword: "#fc5fa3", string: "#fc6a5d", comment: "#7f8c98", number: "#d0bf69",
            type: "#d0a8ff", attribute: "#bf8555", preprocessor: "#fd8f3f", declaration: "#41a1c0" },
};

// Editor colour themes, after the classic Apple IDE set. Each has the token
// colours above plus the editor's own: background, current line, selection
// (blank: the accent colour), cursor and line numbers.
var THEME_KEYS = ["plain", "keyword", "string", "comment", "number", "type", "attribute", "preprocessor",
                  "declaration", "background", "currentLine", "selection", "cursor", "lineNumber"];
var THEME_TITLES = { plain: "Plain Text", keyword: "Keywords", string: "Strings", comment: "Comments",
                     number: "Numbers", type: "Types", attribute: "Attributes", preprocessor: "Preprocessor",
                     declaration: "Declarations", background: "Background", currentLine: "Current Line",
                     selection: "Selection", cursor: "Cursor", lineNumber: "Line Numbers" };
function theme(id, name, dark, colors) {
    return Object.assign({ id: id, name: name, dark: dark, builtIn: true }, colors);
}
var THEMES = [
    theme("default-light", "Default (Light)", false, Object.assign({}, PALETTES.light,
        { background: "#ffffff", currentLine: "#ecf5ff", selection: "", cursor: "#000000", lineNumber: "#a6a6a6" })),
    theme("default-dark", "Default (Dark)", true, Object.assign({}, PALETTES.dark,
        { background: "#1f1f24", currentLine: "#23252b", selection: "", cursor: "#ffffff", lineNumber: "#747478" })),
    theme("presentation-light", "Presentation (Light)", false, Object.assign({}, PALETTES.light,
        { plain: "#000000", background: "#ffffff", currentLine: "#e8f2ff", selection: "", cursor: "#000000", lineNumber: "#8e8e93" })),
    theme("presentation-dark", "Presentation (Dark)", true, Object.assign({}, PALETTES.dark,
        { plain: "#ffffff", background: "#1c1c1e", currentLine: "#2c2c30", selection: "", cursor: "#ffffff", lineNumber: "#98989d" })),
    theme("midnight", "Midnight", true, { plain: "#ffffff", keyword: "#d31895", string: "#ff2c38", comment: "#41cc45",
        number: "#786dff", type: "#00a0ff", attribute: "#ec7600", preprocessor: "#de6c4a", declaration: "#4eb0cc",
        background: "#000000", currentLine: "#16171c", selection: "#404a5f", cursor: "#ffffff", lineNumber: "#5c5c66" }),
    theme("dusk", "Dusk", true, { plain: "#ffffff", keyword: "#b21889", string: "#db2c38", comment: "#41b645",
        number: "#786dc4", type: "#00a0be", attribute: "#c77c48", preprocessor: "#c67c48", declaration: "#83c057",
        background: "#1e2028", currentLine: "#272a33", selection: "#4b5165", cursor: "#ffffff", lineNumber: "#6c6f7c" }),
    theme("sunset", "Sunset", false, { plain: "#000000", keyword: "#294277", string: "#df0700", comment: "#c3741c",
        number: "#294277", type: "#476a97", attribute: "#a5490a", preprocessor: "#a5490a", declaration: "#294277",
        background: "#fffce5", currentLine: "#f5efc7", selection: "#ffe2b8", cursor: "#000000", lineNumber: "#b5ac85" }),
    theme("low-key", "Low Key", false, { plain: "#000000", keyword: "#262c6a", string: "#702c51", comment: "#4c8273",
        number: "#262c6a", type: "#7059a4", attribute: "#763f57", preprocessor: "#763f57", declaration: "#4a5c9b",
        background: "#ffffff", currentLine: "#f0f2f7", selection: "#dee2ef", cursor: "#000000", lineNumber: "#a6a8b5" }),
    theme("civic", "Civic", true, { plain: "#e1e2e7", keyword: "#e12da0", string: "#d3232e", comment: "#45bb3e",
        number: "#149c92", type: "#25908d", attribute: "#d28f5a", preprocessor: "#d28f5a", declaration: "#8de9d8",
        background: "#1e2028", currentLine: "#2b2d36", selection: "#38506b", cursor: "#ffffff", lineNumber: "#6b6e7a" }),
    theme("classic", "Classic (Light)", false, { plain: "#000000", keyword: "#aa0d91", string: "#c41a16", comment: "#007400",
        number: "#1c00cf", type: "#5c2699", attribute: "#836c28", preprocessor: "#643820", declaration: "#3f6e74",
        background: "#ffffff", currentLine: "#edf4ff", selection: "#b4d8fd", cursor: "#000000", lineNumber: "#a6a6a6" }),
    theme("spartan", "Spartan", false, { plain: "#000000", keyword: "#000000", string: "#000000", comment: "#8e8e93",
        number: "#000000", type: "#000000", attribute: "#000000", preprocessor: "#000000", declaration: "#000000",
        background: "#ffffff", currentLine: "#f4f4f4", selection: "#d8d8d8", cursor: "#000000", lineNumber: "#b0b0b0" }),
    theme("solarized-light", "Solarized (Light)", false, { plain: "#586e75", keyword: "#859900", string: "#2aa198",
        comment: "#93a1a1", number: "#d33682", type: "#b58900", attribute: "#cb4b16", preprocessor: "#cb4b16",
        declaration: "#268bd2", background: "#fdf6e3", currentLine: "#eee8d5", selection: "#e3dcc5", cursor: "#586e75", lineNumber: "#93a1a1" }),
    theme("solarized-dark", "Solarized (Dark)", true, { plain: "#93a1a1", keyword: "#859900", string: "#2aa198",
        comment: "#586e75", number: "#d33682", type: "#b58900", attribute: "#cb4b16", preprocessor: "#cb4b16",
        declaration: "#268bd2", background: "#002b36", currentLine: "#073642", selection: "#0f4b5a", cursor: "#93a1a1", lineNumber: "#586e75" }),
    theme("golden-gate", "Golden Gate", true, { plain: "#f2ece4", keyword: "#ff7b54", string: "#ffc56b", comment: "#8a8f9c",
        number: "#c7a6ff", type: "#7fd1ff", attribute: "#ff9f7a", preprocessor: "#ffb08a", declaration: "#6fe3c1",
        background: "#1b1d26", currentLine: "#252834", selection: "#5a3a33", cursor: "#ff7b54", lineNumber: "#5e6272" }),
];
function themeById(id, custom) {
    const all = THEMES.concat(custom || []);
    for (const t of all) if (t.id === id) return t;
    return null;
}
// The theme to draw with: the chosen one for this appearance, else the default.
function resolveTheme(id, dark, custom) {
    const t = themeById(id, custom);
    if (t) return t;
    return dark ? THEMES[1] : THEMES[0];
}
// A copy to customize, with a fresh id.
function duplicateTheme(t, existing) {
    const names = (existing || []).map((e) => e.name);
    let name = t.name.replace(/ copy( \d+)?$/, "") + " copy", n = 2;
    while (names.includes(name)) name = t.name.replace(/ copy( \d+)?$/, "") + " copy " + n++;
    return Object.assign({}, t, { id: "custom-" + Date.now().toString(36) + Math.floor(Math.random() * 1e4), name: name, builtIn: false });
}

// The language family for a file: swift, c, rust, js (JavaScript and QML),
// python, css, hash (shell, TOML, YAML, Meson: # comments), json or plain.
function languageFor(path) {
    const name = String(path || "").split("/").pop().toLowerCase();
    const ext = name.includes(".") ? name.split(".").pop() : "";
    if (ext === "swift") return "swift";
    if (ext === "rs") return "rust";
    if (ext === "py" || ext === "pyw") return "python";
    if (["js", "mjs", "cjs", "ts", "qml", "lcdesign"].includes(ext)) return ext === "lcdesign" ? "json" : "js";
    if (ext === "css") return "css";
    if (["c", "h", "cc", "cpp", "hpp", "m", "mm", "java", "kt", "go", "cs", "vala"].includes(ext)) return "c";
    if (["sh", "bash", "zsh", "toml", "yml", "yaml", "cmake", "ini", "desktop", "conf"].includes(ext) ||
        ["makefile", "pkgbuild", "meson.build", "meson_options.txt", "dockerfile"].includes(name)) return "hash";
    if (ext === "json") return "json";
    return "plain";
}

function keywordsFor(lang) {
    return { swift: SWIFT_KEYWORDS, c: C_KEYWORDS, rust: RUST_KEYWORDS, js: JS_KEYWORDS, python: PY_KEYWORDS, hash: SHELL_KEYWORDS }[lang] || null;
}

function commentMarker(lang) { return lang === "hash" || lang === "python" ? "#" : "//"; }

// Split one line into [kind, text] runs; returns { runs, state }.
function tokenizeRaw(line, state, lang) {
    const runs = [];
    const push = (kind, text) => { if (text) runs.push([kind, text]); };
    if (lang === "plain")
        return { runs: [["plain", line]], state: NORMAL };
    const keywords = keywordsFor(lang);
    const hashComments = lang === "hash" || lang === "python";
    let i = 0, n = line.length;
    let prevWord = "";

    if (state === BLOCK_COMMENT) {
        const end = line.indexOf("*/");
        if (end < 0) return { runs: [["comment", line]], state };
        push("comment", line.slice(0, end + 2)); i = end + 2; state = NORMAL;
    } else if (state === MULTILINE_STRING || state === MULTILINE_SINGLE) {
        const end = line.indexOf(state === MULTILINE_STRING ? '"""' : "\'\'\'");
        if (end < 0) return { runs: [["string", line]], state };
        push("string", line.slice(0, end + 3)); i = end + 3; state = NORMAL;
    }

    while (i < n) {
        const c = line[i], next = line[i + 1];
        // Comments.
        if ((!hashComments && c === "/" && next === "/") || (hashComments && c === "#" && !(lang === "hash" && line[i - 1] === "$"))) {
            if (lang === "css") { push("plain", c); i++; continue; }
            push("comment", line.slice(i)); break;
        }
        if (!hashComments && c === "/" && next === "*") {
            const end = line.indexOf("*/", i + 2);
            if (end < 0) { push("comment", line.slice(i)); state = BLOCK_COMMENT; break; }
            push("comment", line.slice(i, end + 2)); i = end + 2; continue;
        }
        // Strings.
        if ((c === '"' && line.startsWith('"""', i) && (lang === "swift" || lang === "hash" || lang === "python")) ||
            (c === "'" && line.startsWith("\'\'\'", i) && lang === "python")) {
            const quote = line.slice(i, i + 3);
            const end = line.indexOf(quote, i + 3);
            if (end < 0) { push("string", line.slice(i)); state = c === '"' ? MULTILINE_STRING : MULTILINE_SINGLE; break; }
            push("string", line.slice(i, end + 3)); i = end + 3; continue;
        }
        // Rust lifetimes ('a) aren't strings; its char literals ('a') are.
        if (c === "'" && lang === "rust" && line[i + 2] !== "'" && !(next === "\\")) {
            let j = i + 1; while (j < n && /[\w]/.test(line[j])) j++;
            push("attribute", line.slice(i, j)); i = j; continue;
        }
        // CSS: #hex colours are numbers, .class and #id selectors declarations.
        if (lang === "css" && c === "#" ) {
            let j = i + 1; while (j < n && /[\w-]/.test(line[j])) j++;
            push(/^#[0-9a-fA-F]{3,8}$/.test(line.slice(i, j)) ? "number" : "declaration", line.slice(i, j)); i = j; continue;
        }
        if (lang === "css" && c === "." && /[A-Za-z_-]/.test(next || "") && !/[\w]/.test(line[i - 1] || "")) {
            let j = i + 1; while (j < n && /[\w-]/.test(line[j])) j++;
            push("declaration", line.slice(i, j)); i = j; continue;
        }
        if (c === '"' || (c === "'" && lang !== "swift") || (c === "`" && (lang === "c" || lang === "js"))) {
            let j = i + 1;
            while (j < n && line[j] !== c) j += line[j] === "\\" ? 2 : 1;
            push("string", line.slice(i, Math.min(n, j + 1))); i = j + 1; continue;
        }
        // Attributes (@State) and compiler directives (#if, #include).
        if (c === "@" && /[A-Za-z_]/.test(next || "")) {
            let j = i + 1; while (j < n && (/[\w]/.test(line[j]) || (lang === "css" && line[j] === "-"))) j++;
            push("attribute", line.slice(i, j)); i = j; continue;
        }
        if (c === "#" && lang === "rust" && (next === "[" || next === "!")) {
            let depth = 0, j = i + 1;
            while (j < n) { if (line[j] === "[") depth++; else if (line[j] === "]" && --depth === 0) { j++; break } j++ }
            push("attribute", line.slice(i, j)); i = j; continue;
        }
        if (c === "#" && !hashComments && /[A-Za-z]/.test(next || "")) {
            let j = i + 1; while (j < n && /[\w]/.test(line[j])) j++;
            push("preprocessor", line.slice(i, j)); i = j; continue;
        }
        // Numbers.
        if (/[0-9]/.test(c) && !/[\w]/.test(line[i - 1] || "")) {
            let j = i + 1; while (j < n && /[\w.]/.test(line[j]) && !(line[j] === "." && line[j + 1] === ".")) j++;
            push("number", line.slice(i, j)); i = j; continue;
        }
        // Words.
        if (/[A-Za-z_$]/.test(c)) {
            let j = i + 1; while (j < n && /[\w$]/.test(line[j]) || (lang === "css" && line[j] === "-")) j++;
            const word = line.slice(i, j);
            let kind = "plain";
            if (lang === "json") kind = (word === "true" || word === "false" || word === "null") ? "keyword" : "plain";
            else if (lang === "css") kind = line[j] === ":" || /^\s*:/.test(line.slice(j)) ? "keyword" : line[i - 1] === "@" ? "attribute" : "plain";
            else if (lang === "rust" && line[j] === "!") { kind = "preprocessor"; j++; }
            else if (keywords && keywords.has(word)) kind = "keyword";
            else if (lang === "js" && JS_TYPES.has(word) && (prevWord === "property" || prevWord === "readonly" || prevWord === "required")) kind = "type";
            else if (DECLARERS.includes(prevWord) || (lang === "js" && JS_TYPES.has(prevWord))) kind = "declaration";
            else if (/^[A-Z]/.test(word) && lang !== "hash") kind = "type";
            push(kind, line.slice(i, j));
            if (kind !== "plain" || word) prevWord = word;
            i = j; continue;
        }
        // Everything else, one run at a time.
        let j = i + 1;
        while (j < n && !/[A-Za-z0-9_$"'`@#\/]/.test(line[j])) j++;
        push("plain", line.slice(i, j));
        if (line.slice(i, j).trim()) prevWord = "";
        i = j;
    }
    return { runs, state };
}

// The state at the start of every line, for a whole document.
// Placeholder tokens (<#name#>) read as plain names, whatever is inside.
function tokenize(line, state, lang) {
    if (line.indexOf("<#") < 0) return tokenizeRaw(line, state, lang);
    const masked = line.replace(/<#[^#\n]*#>/g, (m) => "_".repeat(m.length));
    if (masked === line) return tokenizeRaw(line, state, lang);
    const result = tokenizeRaw(masked, state, lang);
    let at = 0;
    const runs = result.runs.map(([kind, text]) => { const r = [kind, line.slice(at, at + text.length)]; at += text.length; return r; });
    return { runs: runs, state: result.state };
}

function lineStates(lines, lang) {
    const states = new Array(lines.length);
    let state = NORMAL;
    for (let k = 0; k < lines.length; k++) {
        states[k] = state;
        const line = lines[k];
        if (lang === "plain" || lang === "json") continue;
        // Fast path: lines with no comment or string openers can't change the state.
        if (state === NORMAL && !line.includes("/*") && !line.includes('"""') && !line.includes("\'\'\'")) continue;
        state = tokenize(line, state, lang).state;
    }
    return states;
}

function ltrim(text) { return String(text).replace(/^\s+/, ""); }

function expandTabs(text, width) {
    if (!text.includes("\t")) return text;
    let out = "";
    for (const ch of text) {
        if (ch === "\t") out += " ".repeat(width - (out.length % width));
        else out += ch;
    }
    return out;
}

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
}

// StyledText for one line.
// `colors` is a theme (or palette) object, or true/false for the default dark or light.
function html(line, state, lang, colors, tabWidth) {
    const palette = typeof colors === "object" && colors ? colors : colors ? PALETTES.dark : PALETTES.light;
    const { runs } = tokenize(line, state, lang);
    let col = 0, out = "";
    for (const [kind, raw] of runs) {
        // Tabs expand against the whole line's column, not the run's.
        let text = "";
        for (const ch of raw) {
            if (ch === "\t") { const pad = tabWidth - (col % tabWidth); text += " ".repeat(pad); col += pad; }
            else { text += ch; col++; }
        }
        const body = escape(text);
        out += kind === "keyword"
            ? `<b><font color="${palette.keyword}">${body}</font></b>`
            : `<font color="${palette[kind] || palette.plain}">${body}</font>`;
    }
    // Placeholder tokens show just their name (the editor draws the pill).
    if (line.indexOf("<#") >= 0 && /<#[^#\n]*#>/.test(line))
        out = out.replace(/&lt;#/g, '<font color="#00000000">&lt;#</font>').replace(/#&gt;/g, '<font color="#00000000">#&gt;</font>');
    return out;
}

// A rough outline for the jump bar: declarations and `// MARK:` comments.
const DECLARATION = /^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|static|final|override|mutating|nonisolated|indirect|class|convenience|required)\s+)*(func|struct|class|enum|protocol|extension|actor|init|typealias)\b\s*([A-Za-z_][\w.]*)?/;

function symbols(text) {
    const out = [];
    let inComment = false;
    const lines = String(text).split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i], trimmed = line.trim();
        if (inComment) { if (trimmed.includes("*/")) inComment = false; continue; }
        if (trimmed.startsWith("/*")) { inComment = !trimmed.includes("*/"); continue; }
        if (trimmed.startsWith("//")) {
            const m = /^\/\/\s*MARK:\s*-?\s*(.*)$/.exec(trimmed);
            if (m) out.push({ line: i + 1, kind: "mark", name: m[1] || "—" });
            continue;
        }
        const m = DECLARATION.exec(line);
        if (m) out.push({ line: i + 1, kind: m[1], name: m[2] || m[1] });
    }
    return out;
}

// CSS has only block comments: wrap or unwrap each line in /* */.
function toggleBlockComment(lines) {
    const used = lines.filter((l) => l.trim().length > 0);
    if (used.length && used.every((l) => /^\s*\/\*.*\*\/\s*$/.test(l)))
        return lines.map((l) => l.replace(/^(\s*)\/\* ?(.*?) ?\*\/\s*$/, "$1$2"));
    return lines.map((l) => l.trim().length ? l.replace(/^(\s*)(.*)$/, "$1/* $2 */") : l);
}

// Comment or uncomment lines with `// ` (or `# `) at their common indentation.
function toggleComment(lines, lang) {
    const marker = lang === "css" ? null : commentMarker(lang);
    if (!marker) return toggleBlockComment(lines);
    const used = lines.filter((l) => l.trim().length > 0);
    if (!used.length) return lines;
    if (used.every((l) => ltrim(l).startsWith(marker))) {
        return lines.map((l) => {
            const indent = l.length - ltrim(l).length;
            const rest = l.slice(indent);
            if (rest.startsWith(marker + " ")) return l.slice(0, indent) + rest.slice(marker.length + 1);
            if (rest.startsWith(marker)) return l.slice(0, indent) + rest.slice(marker.length);
            return l;
        });
    }
    const indent = Math.min(...used.map((l) => l.length - ltrim(l).length));
    return lines.map((l) => l.trim().length ? l.slice(0, indent) + marker + " " + l.slice(indent) : l);
}
