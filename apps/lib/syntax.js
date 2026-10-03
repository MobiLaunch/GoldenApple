// Syntax colouring for CodeEditor: a small line tokenizer per language family,
// with the colours of the classic Apple IDE themes (Default Light / Dark).
//
// A line is coloured from the state its predecessor left behind (inside a
// block comment or a multi-line string), so the editor can recolour any
// visible line without re-reading the file.
.pragma library

const NORMAL = 0, BLOCK_COMMENT = 1, MULTILINE_STRING = 2;

const SWIFT_KEYWORDS = new Set(("associatedtype class deinit enum extension fileprivate func import init inout internal let open " +
    "operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue " +
    "default defer do else fallthrough for guard if in repeat return throw throws switch where while as is try await async " +
    "actor nonisolated isolated some any self Self super true false nil mutating nonmutating override final required convenience " +
    "lazy weak unowned dynamic indirect optional get set willSet didSet macro consuming borrowing sending package").split(" "));
const C_KEYWORDS = new Set(("auto break case char const continue default do double else enum extern float for goto if inline int " +
    "long register return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false " +
    "class namespace template typename public private protected virtual override final new delete this nullptr using try catch " +
    "throw const_cast static_cast dynamic_cast reinterpret_cast constexpr noexcept fn let mut pub impl trait mod use crate self " +
    "Self match loop where async await move ref type dyn unsafe extern as in function var import export from of interface " +
    "package func go defer chan select map range fallthrough val fun object when is null").split(" "));
const PY_KEYWORDS = new Set(("and as assert async await break class continue def del elif else except False finally for from " +
    "global if import in is lambda None nonlocal not or pass raise return True try while with yield match case self " +
    "then fi done esac function local export echo exit").split(" "));

var PALETTES = {
    light: { plain: "#262626", keyword: "#9b2393", string: "#c41a16", comment: "#5d6c79", number: "#1c00cf",
             type: "#3900a0", attribute: "#815f03", preprocessor: "#643820", declaration: "#0f68a0" },
    dark: { plain: "#dfdfe0", keyword: "#fc5fa3", string: "#fc6a5d", comment: "#7f8c98", number: "#d0bf69",
            type: "#d0a8ff", attribute: "#bf8555", preprocessor: "#fd8f3f", declaration: "#41a1c0" },
};

function languageFor(path) {
    const name = String(path || "").split("/").pop().toLowerCase();
    const ext = name.includes(".") ? name.split(".").pop() : "";
    if (ext === "swift") return "swift";
    if (["c", "h", "cc", "cpp", "hpp", "m", "mm", "rs", "js", "mjs", "ts", "java", "kt", "go", "cs", "qml"].includes(ext)) return "c";
    if (["py", "sh", "bash", "zsh", "toml", "yml", "yaml", "cmake"].includes(ext) || name === "makefile" || name === "pkgbuild") return "hash";
    if (ext === "json") return "json";
    return "plain";
}

function keywordsFor(lang) {
    return lang === "swift" ? SWIFT_KEYWORDS : lang === "c" ? C_KEYWORDS : lang === "hash" ? PY_KEYWORDS : null;
}

// Split one line into [kind, text] runs; returns { runs, state }.
function tokenize(line, state, lang) {
    const runs = [];
    const push = (kind, text) => { if (text) runs.push([kind, text]); };
    if (lang === "plain")
        return { runs: [["plain", line]], state: NORMAL };
    const keywords = keywordsFor(lang);
    const hashComments = lang === "hash";
    let i = 0, n = line.length;
    let prevWord = "";

    if (state === BLOCK_COMMENT) {
        const end = line.indexOf("*/");
        if (end < 0) return { runs: [["comment", line]], state };
        push("comment", line.slice(0, end + 2)); i = end + 2; state = NORMAL;
    } else if (state === MULTILINE_STRING) {
        const end = line.indexOf('"""');
        if (end < 0) return { runs: [["string", line]], state };
        push("string", line.slice(0, end + 3)); i = end + 3; state = NORMAL;
    }

    while (i < n) {
        const c = line[i], next = line[i + 1];
        // Comments.
        if ((!hashComments && c === "/" && next === "/") || (hashComments && c === "#" && !(lang === "hash" && line[i - 1] === "$"))) {
            push("comment", line.slice(i)); break;
        }
        if (!hashComments && c === "/" && next === "*") {
            const end = line.indexOf("*/", i + 2);
            if (end < 0) { push("comment", line.slice(i)); state = BLOCK_COMMENT; break; }
            push("comment", line.slice(i, end + 2)); i = end + 2; continue;
        }
        // Strings.
        if (c === '"' && line.startsWith('"""', i) && (lang === "swift" || lang === "hash")) {
            const end = line.indexOf('"""', i + 3);
            if (end < 0) { push("string", line.slice(i)); state = MULTILINE_STRING; break; }
            push("string", line.slice(i, end + 3)); i = end + 3; continue;
        }
        if (c === '"' || (c === "'" && lang !== "swift") || (c === "`" && lang === "c")) {
            let j = i + 1;
            while (j < n && line[j] !== c) j += line[j] === "\\" ? 2 : 1;
            push("string", line.slice(i, Math.min(n, j + 1))); i = j + 1; continue;
        }
        // Attributes (@State) and compiler directives (#if, #include).
        if (c === "@" && /[A-Za-z_]/.test(next || "")) {
            let j = i + 1; while (j < n && /[\w]/.test(line[j])) j++;
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
            let j = i + 1; while (j < n && /[\w$]/.test(line[j])) j++;
            const word = line.slice(i, j);
            let kind = "plain";
            if (lang === "json") kind = (word === "true" || word === "false" || word === "null") ? "keyword" : "plain";
            else if (keywords && keywords.has(word)) kind = "keyword";
            else if (["func", "struct", "class", "enum", "protocol", "actor", "extension", "typealias", "def", "fn", "trait", "impl", "interface", "function"].includes(prevWord)) kind = "declaration";
            else if (/^[A-Z]/.test(word) && lang !== "hash") kind = "type";
            push(kind, word);
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
function lineStates(lines, lang) {
    const states = new Array(lines.length);
    let state = NORMAL;
    for (let k = 0; k < lines.length; k++) {
        states[k] = state;
        const line = lines[k];
        if (lang === "plain" || lang === "json") continue;
        // Fast path: lines with no comment or string openers can't change the state.
        if (state === NORMAL && !line.includes("/*") && !line.includes('"""')) continue;
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
function html(line, state, lang, dark, tabWidth) {
    const palette = dark ? PALETTES.dark : PALETTES.light;
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

// Comment or uncomment lines with `// ` at their common indentation.
function toggleComment(lines, lang) {
    const marker = lang === "hash" ? "#" : "//";
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
