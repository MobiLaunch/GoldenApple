#!/usr/bin/env python3
"""Design lint (T-2.8; CS2-018, CS2-043, CS2-013).

Counts, per QML file in shell/, apps/ and themes/:

  radius      a literal corner radius (`radius: 10`; 0 is no rounding and fine)
  duration    a literal animation duration (`duration: 180`; 0 is fine)
  colour      a literal colour ("#RRGGBB", "#RRGGBBAA", "#RGB")
  fs          a Theme.fs(n) type size, instead of a semantic text style
  accessible  a pointer handler that acts (a MouseArea or TapHandler with
              onClicked, onPressed, onTapped and the like) where neither it nor
              the item it sits in has Accessible.role and Accessible.name

The first four don't count in a theme/ folder, where the tokens are defined
(apps/lib/theme, or an app's own, such as apps/calculator/theme for a palette
the Mac's app keeps apart from the system's), and radius, duration and colour don't count in apps/lib/ either: the shared
components there are where the look is made (02-UI-UX-AUDIT §3, rule 1).
tests/design-lint.baseline.json holds each file's counts. A file may not go
over its count, and a count that has gone down must be lowered there too, so
the baseline only shrinks:

    python3 tests/design-lint.py              # check against the baseline
    python3 tests/design-lint.py --update     # write the new, lower counts
    python3 tests/design-lint.py --list RULE  # every finding of one rule

A reviewed exception says why, on the line or the one before:
    // design-lint: allow the map's own palette, not the system's
"""
from __future__ import annotations
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tests/design-lint.baseline.json"
SCOPE = ("shell", "apps", "themes")
RULES = ("radius", "duration", "colour", "fs", "accessible")
# M2's exit criteria (06-CLUB-SODA-ROADMAP.md), shown beside the totals.
TARGETS = {"radius": 40, "duration": 30, "colour": 600, "fs": 0, "accessible": None}
ALLOW = re.compile(r"design-lint:\s*allow\s+\S")
HEX = re.compile(r"^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
POINTERS = {"MouseArea", "TapHandler"}
ACTIONS = {"onClicked", "onPressed", "onReleased", "onTapped", "onSingleTapped", "onDoubleTapped",
           "onDoubleClicked", "onPressAndHold", "onLongPressed"}

TOKEN = re.compile(r"""
    (?P<ws>\s+) | (?P<comment>//[^\n]*|/\*.*?\*/) |
    (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`) |
    (?P<name>[A-Za-z_$][\w$]*) | (?P<num>\d[\w.]*) |
    (?P<punct>=>|\.\.\.|[-+*/%=!<>&|^~?:;,.()\[\]{}])
""", re.S | re.X)


def lex(text):
    """[(kind, value, line)] without spaces and comments; str values keep no quotes."""
    out, i, n, line, counted = [], 0, len(text), 1, 0
    while i < n:
        m = TOKEN.match(text, i)
        if not m:
            i += 1
            continue
        line += text.count("\n", counted, i)
        counted = i
        if m.lastgroup not in ("ws", "comment"):
            value = m.group()
            out.append((m.lastgroup, value[1:-1] if m.lastgroup == "str" else value, line))
        i = m.end()
    return out


class Obj:
    """A QML object: its type, the line it starts on, and its own tokens."""
    def __init__(self, kind, line, parent):
        self.kind, self.line, self.parent, self.own, self.children = kind, line, parent, [], []

    def has(self, prop):
        """Whether it sets Accessible.<prop> (also as Accessible { prop: … })."""
        t = self.own
        for i in range(len(t) - 3):
            if t[i][1] == "Accessible" and t[i + 1][1] == "." and t[i + 2][1] == prop and t[i + 3][1] == ":":
                return True
        return any(c.kind == "Accessible" and any(
            c.own[i][1] == prop and c.own[i + 1][1] == ":" for i in range(len(c.own) - 1)) for c in self.children)

    def sets(self, names):
        t = self.own
        return any(t[i][1] in names and t[i + 1][1] == ":" for i in range(len(t) - 1))

    def ignored(self):
        t = self.own
        return any(t[i][1] == "Accessible" and t[i + 2][1] == "ignored" and t[i + 4][1] == "true"
                   for i in range(len(t) - 4))


def tree(tokens):
    """The objects in a QML file. A `{` opens an object after a capitalised type
    name (Rectangle, QQC.Button); any other `{` is a JavaScript block or an
    object literal, kept in the object it's in."""
    root = Obj("(file)", 0, None)
    stack, objects = [(root, True)], []
    for i, tok in enumerate(tokens):
        kind, value, line = tok
        if value == "{":
            prev = tokens[i - 1] if i else None
            before = tokens[i - 2][1] if i > 1 else ""
            if prev and prev[0] == "name" and prev[1][:1].isupper() and before != "new":
                obj = Obj(prev[1], prev[2], stack[-1][0])
                stack[-1][0].children.append(obj)
                objects.append(obj)
                stack.append((obj, True))
                continue
            stack.append((stack[-1][0], False))
            stack[-1][0].own.append(tok)
            continue
        if value == "}" and len(stack) > 1:
            obj, is_object = stack.pop()
            if not is_object:
                obj.own.append(tok)
            continue
        stack[-1][0].own.append(tok)
    return objects


def check(rel, text):
    """[(rule, line)] for one file."""
    allowed = set()
    for n, l in enumerate(text.splitlines(), 1):
        if ALLOW.search(l):
            allowed.update((n, n + 1))
    tokens = lex(text)
    themed = "theme" in Path(rel).parts
    shared = rel.startswith("apps/lib/")
    found = []
    for i, (kind, value, line) in enumerate(tokens):
        if themed:
            break
        nxt = tokens[i + 1] if i + 1 < len(tokens) else ("", "", 0)
        if shared and not (kind == "name" and value == "fs"):
            continue
        if value in ("radius", "duration") and kind == "name" and nxt[1] == ":" and i + 2 < len(tokens):
            num = tokens[i + 2]
            after = tokens[i + 3] if i + 3 < len(tokens) else ("punct", "}", num[2] + 1)
            prev = tokens[i - 1][1] if i else ""
            if num[0] == "num" and prev != "." and (after[1] in (";", "}") or after[2] > num[2]):
                try:
                    literal = float(num[1]) != 0
                except ValueError:
                    literal = False
                if literal:
                    found.append((value, line))
        elif kind == "str" and HEX.match(value):
            found.append(("colour", line))
        elif kind == "name" and value == "fs" and nxt[1] == "(" and (i == 0 or tokens[i - 1][1] != "function"):
            found.append(("fs", line))
    for obj in tree(tokens):
        if obj.kind in POINTERS and obj.sets(ACTIONS):
            holders = [obj] + ([obj.parent] if obj.parent and obj.parent.kind != "(file)" else [])
            if any(h.ignored() for h in holders):
                continue
            if not any(h.has("role") and h.has("name") for h in holders):
                found.append(("accessible", obj.line))
    return [(rule, line) for rule, line in found if line not in allowed]


def scan():
    """{rule: {file: [lines]}}"""
    out = {rule: defaultdict(list) for rule in RULES}
    for top in SCOPE:
        for path in sorted((ROOT / top).rglob("*.qml")):
            rel = str(path.relative_to(ROOT))
            for rule, line in check(rel, path.read_text(errors="replace")):
                out[rule][rel].append(line)
    return out


def self_test():
    """What the lint must catch, and what it must leave alone."""
    cases = {
        "Rectangle { radius: 10 }": ["radius"],
        "Rectangle {\n    radius: 3.5\n    color: \"#ff8800\"\n}": ["radius", "colour"],
        "NumberAnimation { duration: 180; easing.type: Easing.OutCubic }": ["duration"],
        "Text { font.pixelSize: Theme.fs(13) }": ["fs"],
        "Item { MouseArea { anchors.fill: parent; onClicked: go() } }": ["accessible"],
        "Item { TapHandler { onTapped: go() } }": ["accessible"],
        "Rectangle { radius: 0; color: \"transparent\" }": [],
        "Rectangle { radius: Theme.radiusControl; NumberAnimation on x { duration: Theme.snappy.duration } }": [],
        "Rectangle { radius: height / 2 }": [],
        "Text { font.pixelSize: Theme.textBody.size }": [],
        "Item { Accessible.role: Accessible.Button; Accessible.name: \"Go\"\n"
        "  MouseArea { anchors.fill: parent; onClicked: go() } }": [],
        "Item { MouseArea { Accessible.role: Accessible.Button; Accessible.name: \"Go\"; onClicked: go() } }": [],
        "Item { Accessible { role: Accessible.Button; name: \"Go\" }\n  MouseArea { onClicked: go() } }": [],
        "Item { MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: show() } }": [],
        "Item { MouseArea { Accessible.ignored: true; onClicked: close() } }": [],
        "Item { MouseArea { onClicked: { if (x) { y() } } } }": ["accessible"],
        "// design-lint: allow the map's own palette\nRectangle { color: \"#123456\" }": [],
        "Item { property var m: ({ a: 1 }); function fs(n) { return n } }": [],
    }
    problems = []
    for src, want in cases.items():
        got = sorted(rule for rule, _ in check("apps/sample.qml", src))
        if got != sorted(want):
            problems.append(f"{src!r}: expected {sorted(want)}, found {got}")
    if check("apps/lib/theme/Theme.qml", 'QtObject { readonly property int r: 10; property color c: "#fff" }'):
        problems.append("theme/ files define the tokens: no literal rules there")
    if sorted(r for r, _ in check("apps/lib/Button.qml", 'Rectangle { radius: 6; color: "#fff"; Text { font.pixelSize: Theme.fs(13) } }')) != ["fs"]:
        problems.append("apps/lib/ makes the look (radius, duration, colour), but fs() still counts there")
    return problems


def counts(found):
    return {rule: {f: len(lines) for f, lines in sorted(found[rule].items())} for rule in RULES}


def main():
    problems = self_test()
    for p in problems:
        print("FAIL self-test:", p, file=sys.stderr)
    if problems:
        return 1
    found = scan()
    now = counts(found)
    if "--list" in sys.argv:
        rule = sys.argv[sys.argv.index("--list") + 1] if len(sys.argv) > sys.argv.index("--list") + 1 else None
        for r in [rule] if rule else RULES:
            for f, lines in sorted(found[r].items()):
                for line in lines:
                    print(f"{f}:{line}: {r}")
        return 0
    base = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    if "--update" in sys.argv:
        grew = [r for r in RULES if sum(now[r].values()) > sum(base.get(r, {}).values())] if base else []
        if grew and "--allow-increase" not in sys.argv:
            print(f"FAIL the totals went up ({', '.join(grew)}): fix those first "
                  "(or --allow-increase, for a file moved or split)", file=sys.stderr)
            return 1
        BASELINE.write_text(json.dumps({"about": "Per-file design-lint counts; see tests/design-lint.py. "
                                        "They may only go down.", **now}, indent=1, sort_keys=False) + "\n")
        print(f"wrote {BASELINE.relative_to(ROOT)}")
        return 0
    failed = False
    for rule in RULES:
        allowed = base.get(rule, {})
        for f in sorted(set(now[rule]) | set(allowed)):
            have, may = now[rule].get(f, 0), allowed.get(f, 0)
            if have > may:
                failed = True
                lines = ", ".join(map(str, found[rule][f]))
                print(f"FAIL {f}: {have} {rule} findings, the baseline allows {may} (lines {lines})", file=sys.stderr)
            elif have < may:
                failed = True
                print(f"FAIL {f}: {rule} is down to {have} from {may}: lower the baseline "
                      "(python3 tests/design-lint.py --update)", file=sys.stderr)
    totals = ", ".join(f"{r} {sum(now[r].values())}" + (f" (target ≤ {TARGETS[r]})" if TARGETS[r] is not None else "")
                       for r in RULES)
    if failed:
        print(f"Design lint: {totals}", file=sys.stderr)
        return 1
    print(f"Design lint: no new literals or unannotated pointer handlers; {totals}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
