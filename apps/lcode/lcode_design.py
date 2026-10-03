#!/usr/bin/env python3
"""Golden Gate apps made in LCode's App Designer: starter designs, checking a
design, and building it into a Quickshell app.

    lcode_design.py build ROOT [--release] [--check]   generate .build/app (QML) from Interface.lcdesign
    lcode_design.py show ROOT SCREEN                    print a screen's generated QML

A design (Interface.lcdesign, JSON) holds the app's settings, its variables,
named colours and screens of Golden Gate Kit components (apps/lib/kit). The
build writes ordinary QML that uses the same Kit components, so the app looks
exactly like the designer's canvas:

    .build/app/App.qml          the window, sidebar, state and saved variables
    .build/app/screens/*.qml    one file per screen
    .build/app/ui               Golden Gate's shared components (linked; copied for an archive)
    .build/app/Assets, Logic.js the project's images and code
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
UI = (HERE.parent / "lib").resolve()          # apps/lib, installed as /usr/share/golden-gate/ui
DESIGN_FILE = "Interface.lcdesign"


def load_catalog() -> dict:
    text = (UI / "kit" / "catalog.js").read_text(encoding="utf-8")
    body = text.split("/* CATALOG-JSON-BEGIN */", 1)[1].split("/* CATALOG-JSON-END */", 1)[0]
    return json.loads(body)


CATALOG = load_catalog()
COMPONENTS = CATALOG["components"]


def load(root) -> dict:
    try:
        doc = json.loads((pathlib.Path(root) / DESIGN_FILE).read_text(encoding="utf-8"))
        return doc if isinstance(doc, dict) else {}
    except (OSError, ValueError):
        return {}


# ------------------------------------------------------------- templates

class Ids:
    def __init__(self) -> None:
        self.n = 0

    def node(self, type_: str, children: list | None = None, actions: dict | None = None, **props) -> dict:
        self.n += 1
        node = {"id": f"n{self.n}", "type": type_, "props": {**COMPONENTS[type_].get("defaults", {}), **props}}
        if COMPONENTS[type_].get("container"):
            node["children"] = children or []
        if actions:
            node["actions"] = actions
        return node


def starter_design(name: str, style: str = "sidebar", accent: str = "#0a84ff") -> dict:
    """The design a new Golden Gate App starts from: a home screen with a
    counter, and (as a sidebar app) a to-do list and settings."""
    ids = Ids()
    n = ids.node
    hero = n("VStack", [
        n("Symbol", name="sparkles", size=40, foreground="white"),
        n("Text", text=f"Welcome to {name}", textStyle="largeTitle", foreground="white", textAlign="center"),
        n("Text", text="Designed in LCode. Select anything to change it in the inspector, or drag new pieces in from the Library (+).",
          foreground="white", textAlign="center", maxWidth=420),
    ], spacing=10, padding=28, cornerRadius=24, frameWidth="fill",
        background={"type": "gradient", "colors": ["accent", "purple"], "angle": 135}, shadowRadius=18, shadowOpacity=0.18)
    counter = n("VStack", [
        n("Text", text="You clicked {count} times", textStyle="title2"),
        n("HStack", [
            n("Button", title="Reset", buttonStyle="bordered", actions={"tap": [{"do": "clear", "var": "count"}]}),
            n("Button", title="Click Me", symbol="plus", buttonStyle="prominent", size="large",
              actions={"tap": [{"do": "increment", "var": "count", "by": 1}]}),
        ], spacing=10),
    ], spacing=14, padding=22, cornerRadius=18, frameWidth="fill",
        background={"type": "material", "material": "regular"}, shadowRadius=10, shadowOpacity=0.1)
    home = n("VStack", [hero, counter], spacing=18, padding=28, justify="center", alignment="center")
    state = [{"name": "count", "type": "number", "value": 0, "persist": False}]
    screens = [{"id": "home", "title": "Home", "symbol": "house", "toolbar": [], "root": home}]

    if style == "sidebar":
        add = [{"do": "append", "var": "todos", "value": "{newTask}"}, {"do": "clear", "var": "newTask"}]
        tasks = n("VStack", [
            n("Text", text="Tasks", textStyle="largeTitle"),
            n("Text", text="{todos} tasks, saved when you quit", foreground="secondaryLabel"),
            n("HStack", [
                n("TextField", placeholder="New task", binding="newTask", actions={"submit": add}),
                n("Button", title="Add", buttonStyle="prominent", actions={"tap": add}),
            ], spacing=8, frameWidth="fill"),
            n("List", binding="todos", checkable=True, deletable=True, emptyText="Nothing to do"),
        ], spacing=14, padding=28, alignment="leading", justify="start")
        settings = n("VStack", [
            n("Text", text="Settings", textStyle="largeTitle"),
            n("VStack", [
                n("Toggle", label="Show Tips", binding="showTips", frameWidth="fill"),
                n("Divider"),
                n("HStack", [n("Text", text="Text Size"), n("Spacer"),
                             n("Slider", binding="textSize", minimum=11, maximum=24, step=1, showValue=True)], frameWidth="fill"),
                n("Divider"),
                n("HStack", [n("Text", text="Theme"), n("Spacer"),
                             n("Segmented", options=["Auto", "Light", "Dark"], binding="theme")], frameWidth="fill"),
            ], spacing=12, padding=18, cornerRadius=14, frameWidth="fill", alignment="leading",
                background={"type": "color", "color": "secondaryBackground"}),
            n("Text", text="Tip: settings like these are variables. Bind controls to them in the Attributes inspector.",
              foreground="secondaryLabel", visibleWhen="showTips"),
        ], spacing=16, padding=28, alignment="leading", justify="start")
        screens += [{"id": "tasks", "title": "Tasks", "symbol": "checkmark-square", "toolbar": [], "root": tasks},
                    {"id": "settings", "title": "Settings", "symbol": "gear", "toolbar": [], "root": settings}]
        state += [
            {"name": "newTask", "type": "text", "value": "", "persist": False},
            {"name": "todos", "type": "list", "persist": True,
             "value": [{"title": "Try the App Designer", "done": True}, {"title": "Make something beautiful", "done": False}]},
            {"name": "showTips", "type": "bool", "value": True, "persist": True},
            {"name": "textSize", "type": "number", "value": 13, "persist": True},
            {"name": "theme", "type": "number", "value": 0, "persist": True},
        ]
    sizes = {"sidebar": (980, 660), "window": (760, 560), "utility": (420, 520)}
    w, h = sizes.get(style, sizes["window"])
    return {
        "format": 1,
        "app": {"name": name, "style": style, "accent": accent, "appearance": "auto", "width": w, "height": h,
                "resizable": style != "utility", "sidebarWidth": 220, "font": ""},
        "state": state,
        "colors": [{"name": "Brand", "light": accent, "dark": accent}],
        "screens": screens,
    }


LOGIC_JS = """// Logic.js: your own code for {name}.
//
// Buttons and other controls can call these functions with the "Call
// Logic.js" action. Each gets the app: read and change its variables with
// app.values.name and app.set("name", value), go to a screen with
// app.navigate("id"), or show an alert with app.alert("Title", "Message").

function greet(app) {{
    app.alert("Hello!", "You clicked " + app.str(app.values.count) + " times.")
}}
"""


def template_files(root: pathlib.Path, name: str, org: str = "", options: dict | None = None, **_) -> dict:
    options = options or {}
    style = options.get("style") if options.get("style") in ("sidebar", "window", "utility") else "sidebar"
    doc = starter_design(name, style, options.get("accent") or "#0a84ff")
    return {
        root / DESIGN_FILE: json.dumps(doc, indent=2) + "\n",
        root / "Logic.js": LOGIC_JS.format(name=name),
        root / "Assets" / "README.md": "Put your app's images here (PNG, JPEG, SVG, WebP) and pick them in the Image inspector.\n",
        root / ".gitignore": "/.build\n.lcode/userdata/\n",
    }


# ------------------------------------------------------------ checking

def walk(node: dict, parent: dict | None = None):
    yield node, parent
    for child in node.get("children") or []:
        yield from walk(child, node)


TEMPLATE = re.compile(r"\{([A-Za-z_][\w.]*)\}")


def label(node: dict) -> str:
    p = node.get("props") or {}
    title = COMPONENTS.get(node.get("type"), {}).get("title", node.get("type", "?"))
    hint = p.get("nodeName") or p.get("text") or p.get("title") or p.get("label") or ""
    return f"{title} “{str(hint)[:30]}”" if hint else title


def check(doc: dict, root: pathlib.Path | None = None) -> list[dict]:
    """Problems in a design: [{severity, message, node, screen}]."""
    issues: list[dict] = []

    def add(sev: str, msg: str, node: dict | None = None, screen: str = "") -> None:
        issues.append({"severity": sev, "message": msg, "node": (node or {}).get("id", ""), "screen": screen})

    variables = {v.get("name"): v for v in doc.get("state") or [] if isinstance(v, dict)}
    screens = {s.get("id") for s in doc.get("screens") or []}
    if not doc.get("screens"):
        add("error", "The design has no screens.")
    names: set[str] = set()
    for v in doc.get("state") or []:
        n = v.get("name", "")
        if not re.fullmatch(r"[A-Za-z_]\w*", n or ""):
            add("error", f"“{n}” isn't a valid variable name: use letters, digits and _, starting with a letter.")
        if n in names:
            add("error", f"There are two variables called “{n}”.")
        names.add(n)
    seen_ids: set[str] = set()
    for screen in doc.get("screens") or []:
        sid = screen.get("id", "")
        if not re.fullmatch(r"[a-z][a-z0-9-]*", sid or ""):
            add("error", f"Screen “{screen.get('title', sid)}” needs an id of lowercase letters, digits and hyphens.", screen=sid)
        root_node = screen.get("root")
        if not isinstance(root_node, dict):
            add("error", f"Screen “{screen.get('title', sid)}” is empty.", screen=sid)
            continue
        for node, _parent in walk(root_node):
            t = node.get("type")
            info = COMPONENTS.get(t)
            if not info:
                add("error", f"Unknown component “{t}”.", node, sid)
                continue
            if not re.fullmatch(r"n\d+", node.get("id", "")) or node["id"] in seen_ids:
                add("error", f"{label(node)} has a missing or duplicate id.", node, sid)
            seen_ids.add(node.get("id", ""))
            props = node.get("props") or {}
            for key in info.get("templates", []):
                value = props.get(key)
                if isinstance(value, str):
                    for ref in TEMPLATE.findall(value):
                        base = ref.split(".")[0]
                        if base not in variables and base not in ("item", "index"):
                            add("warning", f"{label(node)} shows {{{ref}}}, but there's no variable called “{base}”.", node, sid)
            binding = props.get("binding")
            if binding:
                if binding not in variables:
                    add("error", f"{label(node)} is bound to “{binding}”, which isn't a variable.", node, sid)
                elif info.get("bind"):
                    want = info["bind"].get("type")
                    have = variables[binding].get("type")
                    if want and have and want != have:
                        add("warning", f"{label(node)} wants a {want} variable, but “{binding}” is a {have}.", node, sid)
            if props.get("visibleWhen") and props["visibleWhen"] not in variables:
                add("error", f"{label(node)} shows only when “{props['visibleWhen']}”, which isn't a variable.", node, sid)
            if t == "Image" and props.get("source") and root is not None and not re.match(r"^(/|https?:|file:)", str(props["source"])):
                if not (root / str(props["source"])).exists():
                    add("warning", f"{label(node)} uses {props['source']}, which isn't in the project.", node, sid)
            for event, actions in (node.get("actions") or {}).items():
                for a in actions or []:
                    what = a.get("do")
                    if what in ("set", "increment", "toggle", "append", "removeItem", "clear") and a.get("var") not in variables:
                        add("error", f"{label(node)} changes “{a.get('var') or '?'}”, which isn't a variable.", node, sid)
                    if what == "navigate" and a.get("screen") not in screens:
                        add("error", f"{label(node)} goes to a screen that doesn't exist (“{a.get('screen') or '?'}”).", node, sid)
                    if what == "removeItem" and event != "itemTap":
                        add("warning", f"{label(node)}: Remove This Row only works when a list row is clicked.", node, sid)
                    if what == "script" and not re.fullmatch(r"[A-Za-z_]\w*", a.get("call") or ""):
                        add("error", f"{label(node)} calls Logic.js without a function name.", node, sid)
    return issues


# ------------------------------------------------------------- QML code

def js(value) -> str:
    """A JSON value as a QML/JS expression (objects in parentheses)."""
    text = json.dumps(value, ensure_ascii=False)
    return f"({text})" if isinstance(value, dict) else text


def number(value) -> str:
    try:
        f = float(value)
    except (TypeError, ValueError):
        f = 1.0
    return str(int(f)) if f.is_integer() else repr(f)


def screen_type(screen: dict) -> str:
    return "Screen" + "".join(w[:1].upper() + w[1:] for w in re.split(r"[^A-Za-z0-9]+", screen["id"]) if w)


SIGNAL_PARAMS = {"tapped": [], "edited": ["value"], "submitted": [], "itemTapped": ["index", "item"]}


class Gen:
    def __init__(self, doc: dict) -> None:
        self.doc = doc
        self.variables = {v["name"]: v for v in doc.get("state") or []}
        self.uses_logic = False

    # A variable (or a list row's item/index) as an expression.
    def ref(self, path: str, scope: tuple[str, ...] = ()) -> str | None:
        parts = path.split(".")
        if parts[0] in scope:
            return ".".join(parts)
        if parts[0] in self.variables:
            return "app.values." + ".".join(parts)
        return None

    def text(self, template: str, scope: tuple[str, ...] = ()) -> str:
        """'Count: {count}' → "Count: " + app.str(app.values.count)."""
        pieces, last = [], 0
        for m in TEMPLATE.finditer(template):
            expr = self.ref(m.group(1), scope)
            if expr is None:
                continue
            if m.start() > last:
                pieces.append(json.dumps(template[last:m.start()], ensure_ascii=False))
            pieces.append(f"app.str({expr})")
            last = m.end()
        if last < len(template) or not pieces:
            pieces.append(json.dumps(template[last:], ensure_ascii=False))
        return " + ".join(pieces)

    def value(self, raw, var: str = "", scope: tuple[str, ...] = ()) -> str:
        """An action's value: a whole {var} keeps its type; numbers stay numbers."""
        if isinstance(raw, str):
            whole = re.fullmatch(r"\{([A-Za-z_][\w.]*)\}", raw)
            if whole and self.ref(whole.group(1), scope):
                return self.ref(whole.group(1), scope)
            kind = self.variables.get(var, {}).get("type")
            if kind == "number" and re.fullmatch(r"-?\d+(\.\d+)?", raw.strip()):
                return raw.strip()
            if kind == "bool" and raw in ("true", "false"):
                return raw
            return self.text(raw, scope)
        return js(raw)

    def statement(self, a: dict, scope: tuple[str, ...]) -> str:
        what = a.get("do")
        v = a.get("var", "")
        t = lambda key: self.text(str(a.get(key) or ""), scope)  # noqa: E731
        if what == "set":
            s = f'app.set({json.dumps(v)}, {self.value(a.get("value", ""), v, scope)})'
        elif what == "increment":
            s = f'app.increment({json.dumps(v)}, {number(a.get("by", 1))})'
        elif what == "toggle":
            s = f"app.toggle({json.dumps(v)})"
        elif what == "clear":
            s = f"app.clear({json.dumps(v)})"
        elif what == "append":
            s = f'app.append({json.dumps(v)}, {self.value(a.get("value", ""), "", scope)})'
        elif what == "removeItem":
            if "index" not in scope:
                return "// Remove This Row works only when a list row is clicked."
            s = f"app.removeAt({json.dumps(v)}, index)"
        elif what == "navigate":
            s = f'app.navigate({json.dumps(a.get("screen", ""))})'
        elif what == "back":
            s = "app.back()"
        elif what == "alert":
            s = f"app.alert({t('title')}, {t('message')})"
        elif what == "notify":
            s = f"app.notify({t('title')}, {t('message')})"
        elif what == "openUrl":
            s = f"app.openUrl({t('url')})"
        elif what == "copy":
            s = f"app.copy({t('text')})"
        elif what == "run":
            s = f'app.run({t("command")}, {json.dumps(a.get("var", ""))})'
        elif what == "quit":
            s = "app.quit()"
        elif what == "script":
            self.uses_logic = True
            row = ", { index: index, item: item }" if "index" in scope else ""
            s = f"Logic.{a.get('call') or 'missing'}(app{row})"
        else:
            return f"// Unknown action {what!r}"
        when = a.get("when")
        if when and self.ref(when, scope):
            s = f"if ({self.ref(when, scope)}) {s}"
        return s

    @staticmethod
    def handler(signal: str, params: list[str], statements: list[str], pad: str) -> list[str]:
        name = "on" + signal[0].upper() + signal[1:]
        head = f"({', '.join(params)}) => " if params else ""
        if len(statements) == 1:
            return [f"{pad}{name}: {head}{statements[0]}"]
        return [f"{pad}{name}: {head}{{"] + [f"{pad}    {s}" for s in statements] + [f"{pad}}}"]

    def node(self, node: dict, depth: int) -> list[str]:
        t = node["type"]
        info = COMPONENTS[t]
        pad, p = "    " * depth, "    " * (depth + 1)
        props = dict(node.get("props") or {})
        lines = [f"{pad}Kit.{t} {{", f"{p}id: {node['id']}"]
        templates = set(info.get("templates", []))
        binding = props.pop("binding", None)
        visible_when = props.pop("visibleWhen", None)
        visible_not = props.pop("visibleWhenNot", False)
        props.pop("nodeName", None)                # the designer's own label for it
        bind = info.get("bind") or {}
        bound = bool(binding and binding in self.variables and bind.get("prop"))
        if bound:
            props.pop(bind["prop"], None)
        for key in sorted(props):
            value = props[key]
            if key in templates and isinstance(value, str) and TEMPLATE.search(value):
                lines.append(f"{p}{key}: {self.text(value)}")
            else:
                lines.append(f"{p}{key}: {js(value)}")
        if visible_when and visible_when in self.variables:
            prop = "visible" if info.get("plain") else "shown"
            lines.append(f"{p}{prop}: {'!' if visible_not else ''}app.values.{visible_when}")

        handlers: dict[str, list[str]] = {}
        if bound:
            lines.append(f"{p}{bind['prop']}: app.values.{binding}")
            if bind.get("signal"):
                handlers.setdefault(bind["signal"], []).append(f"app.set({json.dumps(binding)}, value)")
            if t == "List":
                lines.append(f'{p}onItemToggled: (index, done) => app.setItem({json.dumps(binding)}, index, "done", done)')
                lines.append(f"{p}onItemDeleted: (index) => app.removeAt({json.dumps(binding)}, index)")
        events = dict(info.get("events") or {})
        if not info.get("plain"):
            events.setdefault("tap", "tapped")
        if t == "Link":
            handlers.setdefault("tapped", []).append(f"app.openUrl({self.text(str(props.get('url', '')))})")
        tappable = False
        for event, actions in (node.get("actions") or {}).items():
            signal = events.get(event)
            if not signal or not actions:
                continue
            scope = ("index", "item") if signal == "itemTapped" else ()
            handlers.setdefault(signal, []).extend(self.statement(a, scope) for a in actions)
            tappable = tappable or (signal == "tapped" and t not in ("Button", "Link"))
        if tappable:
            lines.append(f"{p}tappable: true")
        for signal, stmts in handlers.items():
            lines += self.handler(signal, SIGNAL_PARAMS[signal], stmts, p)
        for child in node.get("children") or []:
            lines += self.node(child, depth + 1)
        lines.append(f"{pad}}}")
        return lines

    def screen(self, screen: dict) -> str:
        self.uses_logic = False
        body = self.node(screen["root"], 1)
        head = [f"// {screen.get('title', screen['id'])}: generated by LCode from Interface.lcdesign.",
                "// Change the design, not this file.",
                "import QtQuick", 'import "../ui/kit" as Kit']
        if self.uses_logic:
            head.append('import "../Logic.js" as Logic')
        return "\n".join(head + ["", "Kit.Screen {", "    id: screen", "    required property var app"] + body + ["}", ""])

    def app(self, bundle_id: str, has_logic: bool) -> str:
        doc = self.doc
        a = doc["app"]
        style = a.get("style", "window")
        screens = doc["screens"]
        initial = {v["name"]: v.get("value") for v in doc.get("state") or []}
        persisted = [v["name"] for v in doc.get("state") or [] if v.get("persist")]
        colors = {c["name"]: {"light": c.get("light"), "dark": c.get("dark")} for c in doc.get("colors") or []}
        dark = {"dark": "true", "light": "false"}.get(a.get("appearance"), "Theme.dark")
        name = a.get("name") or "App"
        sidebar = style == "sidebar"
        out = [
            f"//@ pragma AppId {bundle_id}",
            f"// {name}: generated by LCode from Interface.lcdesign. Change the design, not this file.",
            "import Quickshell",
            "import Quickshell.Io",
            "import QtQuick",
            'import "ui"',
            'import "ui/theme"',
            'import "ui/kit" as Kit',
            'import "ui/kit/kit.js" as K',
            'import "screens"',
        ]
        if has_logic:
            out.append('import "Logic.js" as Logic')
        out += [
            "",
            "ShellRoot {",
            "    id: root",
            f"    readonly property var persisted: {json.dumps(persisted)}",
            f'    readonly property string stateFile: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + {json.dumps("/" + bundle_id + "/state.json")}',
            f"    readonly property bool dark: {dark}",
            f"    readonly property var env: ({{ dark: root.dark, accent: {json.dumps(a.get('accent') or '')}, colors: {json.dumps(colors)}, "
            f"font: {json.dumps(a.get('font') or '')}, assetBase: Qt.resolvedUrl(\"Assets\").toString() }})",
            "",
            "    Kit.AppRuntime {",
            "        id: appRuntime",
            f"        initial: {js(initial)}",
            f"        screens: {json.dumps([s['id'] for s in screens])}",
            "        onChanged: (name) => { if (root.persisted.includes(name)) saveTimer.restart() }",
            '        onCommandRequested: (command, outVar) => { runner.outVar = outVar; runner.command = ["sh", "-c", command]; runner.running = true }',
            "        onCopyRequested: (text) => Quickshell.clipboardText = text",
            f'        onNotifyRequested: (title, body) => Quickshell.execDetached(["notify-send", "-a", {json.dumps(name)}, title, body])',
            "        onQuitRequested: Qt.quit()",
        ]
        if has_logic:
            out.append('        onScriptRequested: (name, scope) => { if (typeof Logic[name] === "function") Logic[name](appRuntime, scope) }')
        out += [
            "    }",
            "",
            "    // Variables marked Saved outlive the app: they're kept in its data folder.",
            "    FileView {",
            "        id: store",
            '        path: root.persisted.length ? root.stateFile : ""',
            "        printErrors: false",
            "        blockWrites: true",
            "        onLoaded: {",
            "            try {",
            "                const saved = JSON.parse(text())",
            "                const next = Object.assign({}, appRuntime.values)",
            "                for (const k of root.persisted) if (k in saved) next[k] = saved[k]",
            "                appRuntime.values = next",
            "            } catch (e) {}",
            "        }",
            "    }",
            "    Timer {",
            "        id: saveTimer",
            "        interval: 400",
            "        onTriggered: {",
            "            const out = {}",
            "            for (const k of root.persisted) out[k] = appRuntime.values[k]",
            '            Quickshell.execDetached(["mkdir", "-p", root.stateFile.replace(/\\/[^/]+$/, "")])',
            "            store.setText(JSON.stringify(out, null, 2))",
            "        }",
            "    }",
            "    Process {",
            "        id: runner",
            '        property string outVar: ""',
            "        stdout: StdioCollector { onStreamFinished: if (runner.outVar) appRuntime.set(runner.outVar, text.trim()) }",
            "    }",
            "",
            "    AppWindow {",
            "        id: win",
            f"        title: {json.dumps(name)}",
            f"        implicitWidth: {int(a.get('width') or 900)}",
            f"        implicitHeight: {int(a.get('height') or 620)}",
            f"        minimumSize: Qt.size({int(a.get('minWidth') or 320)}, {int(a.get('minHeight') or 240)})",
            f"        resizable: {'true' if a.get('resizable', True) else 'false'}",
            f"        sidebarWidth: {int(a.get('sidebarWidth') or 220) if sidebar else 0}",
            f"        appearance: {json.dumps(a.get('appearance') if a.get('appearance') in ('light', 'dark') else '')}",
        ]
        if a.get("background"):
            out.append(f"        background: K.color({json.dumps(a['background'])}, root.env, Theme.windowBg)")
        if not sidebar and len(screens) > 1:
            out += [
                "        toolbarLeft: [",
                "            ToolbarButton {",
                "                round: true",
                '                symbol: "chevron-left"',
                "                visible: appRuntime.backStack.length > 0",
                "                onClicked: appRuntime.back()",
                "            }",
                "        ]",
            ]
        if sidebar:
            out += ["        sidebar: [",
                    "            Column {",
                    "                anchors { fill: parent; topMargin: 8; leftMargin: 8; rightMargin: 8 }",
                    "                spacing: 2"]
            for s in screens:
                out.append(f'                SidebarRow {{ width: parent.width; text: {json.dumps(s.get("title") or s["id"])}; '
                           f'symbol: {json.dumps(s.get("symbol") or "doc")}; selected: appRuntime.screen === {json.dumps(s["id"])}; '
                           f'onClicked: appRuntime.navigate({json.dumps(s["id"])}) }}')
            out += ["            }", "        ]"]
        out += ["", "        Kit.Scope {", "            anchors.fill: parent", "            env: root.env"]
        for s in screens:
            out.append(f"            Loader {{ anchors.fill: parent; active: appRuntime.screen === {json.dumps(s['id'])}; "
                       f"sourceComponent: Component {{ {screen_type(s)} {{ app: appRuntime }} }} }}")
        out += ["            Kit.AlertHost { app: appRuntime }", "        }", "    }", "}", ""]
        return "\n".join(out)


# ---------------------------------------------------------------- build

def build(root: str, release: bool = False, check_only: bool = False, out=print) -> int:
    root_path = pathlib.Path(root).resolve()
    design_path = root_path / DESIGN_FILE
    try:
        doc = json.loads(design_path.read_text(encoding="utf-8"))
    except OSError as exc:
        out(f"{design_path}:1:1: error: Couldn't read the design: {exc.strerror}")
        return 1
    except ValueError as exc:
        out(f"{design_path}:{getattr(exc, 'lineno', 1)}:{getattr(exc, 'colno', 1)}: error: The design isn't valid JSON: {exc}")
        return 1
    if not isinstance(doc, dict):
        out(f"{design_path}:1:1: error: The design isn't a design.")
        return 1
    meta: dict = {}
    try:
        meta = json.loads((root_path / ".lcode/project.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    doc.setdefault("app", {})
    doc.setdefault("state", [])
    doc.setdefault("colors", [])
    app_name = doc["app"].get("name") or root_path.name
    bundle_id = meta.get("bundle_identifier") or "org.example." + re.sub(r"[^A-Za-z0-9-]", "-", app_name)

    issues = check(doc, root_path)
    screens = doc.get("screens") or []
    steps = len(screens) + 3
    out(f"[1/{steps}] Checking {DESIGN_FILE}")
    errors = 0
    for i in issues:
        errors += i["severity"] == "error"
        where = f" [{i['screen']}#{i['node']}]" if i["node"] else ""
        out(f"{design_path}:1:1: {i['severity']}: {i['message']}{where}")
    if errors:
        out(f"{errors} error{'s' if errors != 1 else ''} in the design")
        return 1
    if check_only:
        out("The design checks out.")
        return 0

    app_dir = root_path / ".build" / "app"
    screens_dir = app_dir / "screens"
    if screens_dir.exists():
        shutil.rmtree(screens_dir)
    screens_dir.mkdir(parents=True, exist_ok=True)
    gen = Gen(doc)
    has_logic = (root_path / "Logic.js").is_file()
    qmldir = []
    for n, screen in enumerate(screens, 2):
        name = screen_type(screen)
        out(f"[{n}/{steps}] Generating {name}.qml")
        (screens_dir / f"{name}.qml").write_text(gen.screen(screen), encoding="utf-8")
        qmldir.append(f"{name} 1.0 {name}.qml")
    (screens_dir / "qmldir").write_text("\n".join(qmldir) + "\n", encoding="utf-8")
    out(f"[{steps - 1}/{steps}] Generating App.qml")
    (app_dir / "App.qml").write_text(gen.app(bundle_id, has_logic), encoding="utf-8")

    out(f"[{steps}/{steps}] Linking resources")
    link(UI, app_dir / "ui", copy=release)
    for extra in ("Assets", "Logic.js"):
        src, dst = root_path / extra, app_dir / extra
        if src.exists():
            link(src, dst, copy=release)
        elif dst.is_symlink() or dst.exists():
            remove(dst)
    out("Build complete!")
    return 0


def remove(path: pathlib.Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def link(src: pathlib.Path, dst: pathlib.Path, copy: bool = False) -> None:
    """A symlink while developing; a real copy for an archive."""
    if dst.is_symlink() or dst.exists():
        if not copy and dst.is_symlink() and os.readlink(dst) == str(src):
            return
        remove(dst)
    if copy:
        if src.is_dir():
            shutil.copytree(src, dst, symlinks=False, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(src, dst)
    else:
        dst.symlink_to(src)


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[1] == "build":
        return build(argv[2], release="--release" in argv, check_only="--check" in argv,
                     out=lambda s: print(s, flush=True))
    if len(argv) == 4 and argv[1] == "show":
        doc = load(argv[2])
        screen = next((s for s in doc.get("screens", []) if s.get("id") == argv[3]), None)
        if not screen:
            print(f"No screen {argv[3]!r}", file=sys.stderr)
            return 1
        print(Gen(doc).screen(screen))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
