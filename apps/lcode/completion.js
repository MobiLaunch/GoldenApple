// Code completion for LCode's editor: the language's keywords, the names in
// your code (functions, types, variables, then any word), and snippets —
// built in and your own — whose <#placeholders#> Tab steps through, as in
// Xcode.
.pragma library
.import "../lib/syntax.js" as Syntax

// ------------------------------------------------------------- snippets
// body: "\n" lines (indented with four spaces, re-indented to your settings
// and the line you're on), <#name#> placeholders.
var SNIPPETS = {
    swift: [
        { trigger: "if", title: "If Statement", body: "if <#condition#> {\n    <#statements#>\n}" },
        { trigger: "ifelse", title: "If-Else Statement", body: "if <#condition#> {\n    <#statements#>\n} else {\n    <#statements#>\n}" },
        { trigger: "iflet", title: "If-Let Statement", body: "if let <#value#> = <#optional#> {\n    <#statements#>\n}" },
        { trigger: "guard", title: "Guard Statement", body: "guard <#condition#> else {\n    <#statements#>\n}" },
        { trigger: "for", title: "For-In Loop", body: "for <#item#> in <#collection#> {\n    <#statements#>\n}" },
        { trigger: "while", title: "While Loop", body: "while <#condition#> {\n    <#statements#>\n}" },
        { trigger: "switch", title: "Switch Statement", body: "switch <#value#> {\ncase <#pattern#>:\n    <#statements#>\ndefault:\n    <#statements#>\n}" },
        { trigger: "func", title: "Function", body: "func <#name#>(<#parameters#>) -> <#ReturnType#> {\n    <#statements#>\n}" },
        { trigger: "struct", title: "Struct", body: "struct <#Name#> {\n    <#properties#>\n}" },
        { trigger: "class", title: "Class", body: "class <#Name#> {\n    <#properties#>\n\n    init(<#parameters#>) {\n        <#statements#>\n    }\n}" },
        { trigger: "enum", title: "Enumeration", body: "enum <#Name#> {\n    case <#first#>\n    case <#second#>\n}" },
        { trigger: "init", title: "Initializer", body: "init(<#parameters#>) {\n    <#statements#>\n}" },
        { trigger: "do", title: "Do-Catch Statement", body: "do {\n    try <#statements#>\n} catch {\n    <#handle error#>\n}" },
        { trigger: "view", title: "SwiftUI View", body: "struct <#Name#>: View {\n    var body: some View {\n        <#content#>\n    }\n}" },
        { trigger: "state", title: "State Property", body: "@State private var <#name#> = <#value#>" },
        { trigger: "main", title: "Main Entry Point", body: "@main\nstruct <#Name#> {\n    static func main() {\n        <#statements#>\n    }\n}" },
        { trigger: "test", title: "Test Function", body: "func test<#Name#>() throws {\n    XCTAssertEqual(<#actual#>, <#expected#>)\n}" },
        { trigger: "mark", title: "MARK Comment", body: "// MARK: - <#Section#>" },
    ],
    python: [
        { trigger: "def", title: "Function", body: "def <#name#>(<#parameters#>):\n    <#body#>" },
        { trigger: "class", title: "Class", body: "class <#Name#>:\n    def __init__(self, <#parameters#>):\n        <#body#>" },
        { trigger: "dataclass", title: "Data Class", body: "@dataclass\nclass <#Name#>:\n    <#field#>: <#type#>" },
        { trigger: "if", title: "If Statement", body: "if <#condition#>:\n    <#body#>" },
        { trigger: "ifmain", title: "Main Guard", body: "if __name__ == \"__main__\":\n    <#main()#>" },
        { trigger: "for", title: "For Loop", body: "for <#item#> in <#iterable#>:\n    <#body#>" },
        { trigger: "while", title: "While Loop", body: "while <#condition#>:\n    <#body#>" },
        { trigger: "try", title: "Try-Except", body: "try:\n    <#body#>\nexcept <#Exception#> as error:\n    <#handle#>" },
        { trigger: "with", title: "With Statement", body: "with open(<#path#>) as <#file#>:\n    <#body#>" },
        { trigger: "lambda", title: "Lambda", body: "lambda <#arguments#>: <#expression#>" },
        { trigger: "test", title: "Test Function", body: "def test_<#name#>():\n    assert <#condition#>" },
        { trigger: "gtkwindow", title: "GTK Window", body: "window = Gtk.ApplicationWindow(application=<#app#>, title=<#\"Title\"#>)\nwindow.set_default_size(<#800#>, <#600#>)\nwindow.present()" },
    ],
    rust: [
        { trigger: "fn", title: "Function", body: "fn <#name#>(<#parameters#>) -> <#ReturnType#> {\n    <#body#>\n}" },
        { trigger: "struct", title: "Struct", body: "#[derive(Debug, Clone)]\nstruct <#Name#> {\n    <#field#>: <#Type#>,\n}" },
        { trigger: "enum", title: "Enum", body: "#[derive(Debug, Clone, PartialEq)]\nenum <#Name#> {\n    <#First#>,\n    <#Second#>,\n}" },
        { trigger: "impl", title: "Impl Block", body: "impl <#Type#> {\n    <#methods#>\n}" },
        { trigger: "new", title: "Constructor", body: "pub fn new(<#parameters#>) -> Self {\n    Self { <#fields#> }\n}" },
        { trigger: "match", title: "Match Expression", body: "match <#value#> {\n    <#pattern#> => <#expression#>,\n    _ => <#expression#>,\n}" },
        { trigger: "iflet", title: "If Let", body: "if let Some(<#value#>) = <#option#> {\n    <#body#>\n}" },
        { trigger: "for", title: "For Loop", body: "for <#item#> in <#iterator#> {\n    <#body#>\n}" },
        { trigger: "test", title: "Test Module", body: "#[cfg(test)]\nmod tests {\n    use super::*;\n\n    #[test]\n    fn <#name#>() {\n        assert_eq!(<#left#>, <#right#>);\n    }\n}" },
        { trigger: "main", title: "Main Function", body: "fn main() {\n    <#body#>\n}" },
    ],
    c: [
        { trigger: "main", title: "Main Function", body: "int main(int argc, char *argv[])\n{\n    <#statements#>\n    return 0;\n}" },
        { trigger: "if", title: "If Statement", body: "if (<#condition#>) {\n    <#statements#>\n}" },
        { trigger: "for", title: "For Loop", body: "for (<#int i = 0#>; <#i < n#>; <#i++#>) {\n    <#statements#>\n}" },
        { trigger: "while", title: "While Loop", body: "while (<#condition#>) {\n    <#statements#>\n}" },
        { trigger: "switch", title: "Switch Statement", body: "switch (<#value#>) {\ncase <#constant#>:\n    <#statements#>\n    break;\ndefault:\n    break;\n}" },
        { trigger: "struct", title: "Struct Type", body: "typedef struct {\n    <#type#> <#member#>;\n} <#Name#>;" },
        { trigger: "func", title: "Function", body: "static <#void#>\n<#name#> (<#parameters#>)\n{\n    <#statements#>\n}" },
        { trigger: "include", title: "Include", body: "#include <<#header.h#>>" },
        { trigger: "signal", title: "GTK Signal Handler", body: "g_signal_connect (<#widget#>, \"<#clicked#>\", G_CALLBACK (<#on_clicked#>), <#data#>);" },
    ],
    js: [
        { trigger: "item", title: "Item", body: "Item {\n    id: <#name#>\n    <#content#>\n}" },
        { trigger: "rect", title: "Rectangle", body: "Rectangle {\n    width: <#100#>; height: <#100#>\n    radius: <#12#>\n    color: <#Theme.accent#>\n}" },
        { trigger: "text", title: "Text", body: "Text {\n    text: <#\"Hello\"#>\n    color: Theme.label\n    font { family: Theme.fontUi; pixelSize: <#13#> }\n}" },
        { trigger: "button", title: "Button", body: "Button {\n    text: <#\"Title\"#>\n    onClicked: <#action#>\n}" },
        { trigger: "column", title: "Column", body: "Column {\n    spacing: <#8#>\n    <#content#>\n}" },
        { trigger: "row", title: "Row", body: "Row {\n    spacing: <#8#>\n    <#content#>\n}" },
        { trigger: "repeater", title: "Repeater", body: "Repeater {\n    model: <#model#>\n    delegate: <#Item#> {\n        required property var modelData\n        <#content#>\n    }\n}" },
        { trigger: "property", title: "Property", body: "property <#var#> <#name#>: <#value#>" },
        { trigger: "function", title: "Function", body: "function <#name#>(<#parameters#>) {\n    <#body#>\n}" },
        { trigger: "connections", title: "Connections", body: "Connections {\n    target: <#object#>\n    function on<#Signal#>() { <#body#> }\n}" },
        { trigger: "timer", title: "Timer", body: "Timer {\n    interval: <#1000#>\n    running: true\n    repeat: <#true#>\n    onTriggered: <#action#>\n}" },
        { trigger: "appwindow", title: "CitronOS Window", body: "AppWindow {\n    title: <#\"My App\"#>\n    implicitWidth: <#900#>; implicitHeight: <#620#>\n    <#content#>\n}" },
        { trigger: "for", title: "For-Of Loop", body: "for (const <#item#> of <#items#>) {\n    <#body#>\n}" },
        { trigger: "if", title: "If Statement", body: "if (<#condition#>) {\n    <#body#>\n}" },
    ],
    css: [
        { trigger: "rule", title: "Rule", body: "<#selector#> {\n    <#property#>: <#value#>;\n}" },
        { trigger: "dark", title: "Dark Appearance", body: "@media (prefers-color-scheme: dark) {\n    <#rules#>\n}" },
    ],
    hash: [
        { trigger: "if", title: "If Statement", body: "if [ <#condition#> ]; then\n    <#commands#>\nfi" },
        { trigger: "for", title: "For Loop", body: "for <#item#> in <#list#>; do\n    <#commands#>\ndone" },
        { trigger: "function", title: "Function", body: "<#name#>() {\n    <#commands#>\n}" },
        { trigger: "case", title: "Case Statement", body: "case <#\"$1\"#> in\n    <#pattern#>) <#commands#> ;;\n    *) <#commands#> ;;\nesac" },
    ],
};

var LANGUAGE_NAMES = { swift: "Swift", python: "Python", rust: "Rust", c: "C", js: "QML & JavaScript", css: "CSS", hash: "Shell", plain: "Any Language" };

// The snippets for a language, yours first.
function snippetsFor(lang, user) {
    var own = (user || []).filter(function (s) { return !s.language || s.language === lang || s.language === "plain"; })
        .map(function (s) { return Object.assign({ own: true }, s); });
    return own.concat(SNIPPETS[lang] || []);
}

// ------------------------------------------------------------ the names
var DECLARATIONS = /\b(func|struct|class|enum|protocol|actor|extension|typealias|def|fn|trait|impl|interface|function|mod|type|component|signal|let|var|const|static|property\s+[\w<>]+|readonly\s+property\s+[\w<>]+)\s+(?:mut\s+)?([A-Za-z_]\w*)/g;
var FUNCTION_KINDS = ["func", "def", "fn", "function", "signal"];
var TYPE_KINDS = ["struct", "class", "enum", "protocol", "actor", "extension", "typealias", "trait", "impl", "interface", "mod", "type", "component"];

function kindOf(declarer) {
    var d = declarer.split(/\s+/)[0];
    if (FUNCTION_KINDS.indexOf(d) >= 0) return "function";
    if (TYPE_KINDS.indexOf(d) >= 0) return "type";
    return "variable";
}

// Declared names in some code: { name, kind }.
function declarations(text) {
    var out = [], seen = {}, m;
    DECLARATIONS.lastIndex = 0;
    while ((m = DECLARATIONS.exec(text)) !== null) {
        if (seen[m[2]]) continue;
        seen[m[2]] = true;
        out.push({ name: m[2], kind: kindOf(m[1]) });
    }
    return out;
}

// Every identifier in some code, three letters or more.
function words(text) {
    var out = {}, re = /[A-Za-z_][A-Za-z0-9_]{2,}/g, m, n = 0;
    while ((m = re.exec(text)) !== null && n < 20000) { out[m[0]] = true; n++; }
    return Object.keys(out);
}

// The identifier being typed just before `pos`.
function prefixAt(text, pos) {
    var start = pos;
    while (start > 0 && /[A-Za-z0-9_]/.test(text.charAt(start - 1))) start--;
    // Not after a digit-only run (numbers aren't names).
    var prefix = text.slice(start, pos);
    if (/^[0-9]/.test(prefix)) return { start: pos, text: "" };
    return { start: start, text: prefix };
}

// How well `name` matches what was typed: a prefix beats a word-start
// match beats letters in order; null when it doesn't match at all.
function score(name, typed) {
    if (!typed) return 0;
    var n = name.toLowerCase(), t = typed.toLowerCase();
    if (name === typed) return 1000;
    if (name.indexOf(typed) === 0) return 900 - name.length;
    if (n.indexOf(t) === 0) return 800 - name.length;
    var i = 0, j = 0, gaps = 0;
    while (i < n.length && j < t.length) {
        if (n[i] === t[j]) j++; else gaps++;
        i++;
    }
    if (j < t.length) return null;
    return 400 - gaps;
}

// The completions at `pos`: [{ title, insert, kind, detail, snippet }].
// kind: keyword | snippet | function | type | variable | word.
function complete(text, pos, lang, opts) {
    opts = opts || {};
    var p = prefixAt(text, pos);
    if (!p.text && !opts.explicit) return { start: p.start, prefix: "", items: [] };
    var items = [], seen = {};
    function add(item, bonus) {
        var s = score(item.title, p.text);
        if (s === null) return;
        var key = item.kind === "snippet" ? "s:" + item.title : item.title;
        if (seen[key]) return;
        if (item.kind !== "snippet" && item.title === p.text) return;   // already typed
        seen[key] = true;
        item.score = s + (bonus || 0);
        items.push(item);
    }
    var snippets = snippetsFor(lang, opts.userSnippets);
    for (var i = 0; i < snippets.length; i++) {
        var s = snippets[i];
        var sc = score(s.trigger, p.text);
        if (sc === null) continue;
        var key = "s:" + s.title;
        if (seen[key]) continue;
        seen[key] = true;
        items.push({ title: s.trigger, label: s.title, insert: s.body, kind: "snippet", detail: s.title, snippet: true,
                     own: !!s.own, score: sc + 30 });
    }
    var decls = declarations(text).concat(opts.extraDeclarations || []);
    for (var d = 0; d < decls.length; d++) add({ title: decls[d].name, insert: decls[d].name, kind: decls[d].kind, detail: "" }, 20);
    var kw = Syntax.keywordsFor(lang);
    if (kw) kw.forEach(function (k) { add({ title: k, insert: k, kind: "keyword", detail: "" }, 10); });
    var ws = words(text);
    for (var w = 0; w < ws.length; w++) {
        // Not the word being typed itself.
        if (ws[w] === p.text) continue;
        add({ title: ws[w], insert: ws[w], kind: "word", detail: "" }, 0);
    }
    var extra = opts.extraWords || [];
    for (var e = 0; e < extra.length; e++) add({ title: extra[e], insert: extra[e], kind: "word", detail: "" }, -5);
    items.sort(function (a, b) { return b.score - a.score || a.title.length - b.title.length || (a.title < b.title ? -1 : 1); });
    return { start: p.start, prefix: p.text, items: items.slice(0, opts.limit || 60) };
}

// ------------------------------------------------------- placeholders
var PLACEHOLDER = /<#([^#\n]*)#>/g;

// A snippet body ready to insert at a line indented with `indent`, using
// `unit` for each level of indentation.
function expand(body, indent, unit) {
    return body.split("\n").map(function (line, i) {
        var lead = /^ */.exec(line)[0].length;
        var levels = Math.floor(lead / 4);
        var rest = line.slice(levels * 4);
        return (i === 0 ? "" : indent) + new Array(levels + 1).join(unit) + rest;
    }).join("\n");
}

// Placeholder ranges in some text: [{ start, end, name }].
function placeholders(text) {
    var out = [], m;
    PLACEHOLDER.lastIndex = 0;
    while ((m = PLACEHOLDER.exec(text)) !== null) out.push({ start: m.index, end: m.index + m[0].length, name: m[1] });
    return out;
}

// The placeholder to go to from `pos`: the next one, wrapping around.
function nextPlaceholder(text, pos, backwards) {
    var all = placeholders(text);
    if (!all.length) return null;
    if (backwards) {
        for (var i = all.length - 1; i >= 0; i--) if (all[i].end < pos) return all[i];
        return all[all.length - 1];
    }
    for (var j = 0; j < all.length; j++) if (all[j].start >= pos) return all[j];
    return all[0];
}
