#!/usr/bin/env python3
"""Security lints for the whole tree (CS2-001, CS2-002, CS2-016).

1. Shell scripts are never built from data. In QML, JS and Python, an
   `sh -c` / `bash -c` script is made only of literal strings (joined with
   + at most); data goes in as "$1", "$2"… after it. Hyprland's
   dispatch("exec …") is never built from data either.
2. Python never asks for a shell: no shell=True, os.system or os.popen.
3. polkit: every action a rule grants without a password (or a policy
   marks "yes") runs a helper that is reviewed here, by name, with the
   subcommands it may have; it can't change where updates come from or
   install code that isn't signed.
4. No password, token or other secret is put in a command's argv (any
   account can read it in ps); secrets go on stdin.

Findings already in tests/security-lint.baseline are reported but allowed;
that list may only shrink, and a stale entry fails too.

    python3 tests/security-lint.py            # check
    python3 tests/security-lint.py --list     # print every finding
"""
from __future__ import annotations
import ast
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tests/security-lint.baseline"
SKIP = {".git", "node_modules", "build", "__pycache__", "prototype", "third_party", "vendor"}
SHELLS = {"sh", "bash", "/bin/sh", "/bin/bash", "/usr/bin/sh", "/usr/bin/bash"}
SECRET = re.compile(r"^(--?)?(password|token|secret|psk|api[-_]?key)(=.*)?$", re.I)
SECRET_NAME = re.compile(r"^(password|passphrase|token|secret|psk|apiKey|api_key)$", re.I)
# A reviewed exception says why, on the line or the one before:
#     // security-lint: allow the command comes from the session's own environment
ALLOW = re.compile(r"security-lint:\s*allow\s+\S")

# Helpers polkit may run without a password, and all they may do. A new
# subcommand, or a new passwordless helper, is a reviewed change here.
PASSWORDLESS = {
    "apps/settings/update-helper.py": {"check", "apply", "apply-user", "source"},
}
# Calls a passwordless helper must never make: they change where updates
# come from, or install code the release key didn't sign.
FORBIDDEN_CALLS = {"set_source", "verify_source", "install_local", "update_disk"}


def files(*suffixes):
    for path in sorted(ROOT.rglob("*")):
        if path.suffix in suffixes and path.is_file() and not SKIP & set(path.relative_to(ROOT).parts):
            yield path


def rel(path):
    return str(path.relative_to(ROOT))


# --- QML and JS: a small lexer, enough to see strings, names and brackets.

TOKEN = re.compile(r"""
    (?P<ws>\s+) | (?P<comment>//[^\n]*|/\*.*?\*/) |
    (?P<str>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*') |
    (?P<tpl>`) | (?P<name>[A-Za-z_$][\w$]*) | (?P<num>\d[\w.]*) |
    (?P<punct>=>|\.\.\.|[-+*/%=!<>&|^~?:;,.()\[\]{}])
""", re.S | re.X)


def lex(text):
    """[(kind, value, line)]: kinds str, tpl (with has_expr), name, num, punct."""
    out, i, n, line, counted = [], 0, len(text), 1, 0
    while i < n:
        m = TOKEN.match(text, i)
        if not m:
            i += 1
            continue
        kind = m.lastgroup
        line += text.count("\n", counted, i)
        counted = i
        if kind == "tpl":
            j, has_expr, depth, prefix = i + 1, False, 0, None
            while j < n:
                c = text[j]
                if c == "\\":
                    j += 2
                    continue
                if depth == 0 and c == "`":
                    break
                if text.startswith("${", j):
                    if prefix is None:
                        prefix = text[i + 1:j]
                    has_expr, depth, j = True, depth + 1, j + 2
                    continue
                if depth and c == "}":
                    depth -= 1
                j += 1
            out.append(("tpl", (has_expr, text[i + 1:j] if prefix is None else prefix), line))
            i = j + 1
            continue
        if kind not in ("ws", "comment"):
            value = m.group()
            out.append((kind, value[1:-1] if kind == "str" else value, line))
        i = m.end()
    return out


def expression(tokens, start):
    """The tokens of one argument/element from start, up to , or a closing bracket."""
    depth, j = 0, start
    while j < len(tokens):
        kind, value, _ = tokens[j]
        if kind == "punct" and value in "([{":
            depth += 1
        elif kind == "punct" and value in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif kind == "punct" and value == "," and depth == 0:
            break
        j += 1
    return tokens[start:j], j


def literal_only(expr, constants=frozenset()):
    """Literal strings joined with +, nothing else."""
    if not expr:
        return False
    for kind, value, _ in expr:
        if kind == "str" or (kind == "tpl" and not value[0]) or (kind == "name" and value in constants):
            continue
        if kind == "punct" and value in "+()":
            continue
        return False
    return True


def constants_of(t):
    """Names bound to literal-only readonly strings in this file."""
    out = set()
    for i in range(len(t) - 4):
        if [v for _, v, _ in t[i:i + 3]] == ["readonly", "property", "string"] and t[i + 4][1] == ":":
            expr, _ = expression(t, i + 5)
            # A property's value ends at the line's end; stop at the next line.
            expr = [x for x in expr if x[2] == t[i + 5][2]] if i + 5 < len(t) else []
            if literal_only(expr, out):
                out.add(t[i + 3][1])
    return out


def check_qml(path, text, findings):
    t = lex(text)
    constants = constants_of(t)
    lines = text.splitlines()

    def report(line, what):
        here = lines[line - 1] if line <= len(lines) else ""
        before = lines[line - 2] if line >= 2 else ""
        if not (ALLOW.search(here) or ALLOW.search(before)):
            findings.append((rel(path), line, what))

    for i, (kind, value, line) in enumerate(t):
        # [ "sh", "-c", <script>, ... ]
        if kind == "str" and value in SHELLS and i + 3 < len(t) and t[i + 1][1] == "," \
                and t[i + 2][0] == "str" and t[i + 2][1] == "-c" and t[i + 3][1] == ",":
            script, _ = expression(t, i + 4)
            if not literal_only(script, constants):
                report(line, "shell script built from data")
        # Settings' Sys.sh(script, done) and the like: the script is a shell script.
        if kind == "name" and value == "sh" and i + 2 < len(t) and t[i + 1][1] == "(" \
                and not (i and t[i - 1][1] == "function"):
            script, _ = expression(t, i + 2)
            if not literal_only(script, constants):
                report(line, "shell script built from data")
        # dispatch("exec " + …) / dispatch(`exec ${…}`)
        if kind == "name" and value == "dispatch" and i + 2 < len(t) and t[i + 1][1] == "(":
            arg, _ = expression(t, i + 2)
            first = arg[0] if arg else None
            text0 = first[1] if first and first[0] == "str" else first[1][1] if first and first[0] == "tpl" else ""
            if text0.lstrip().startswith("exec") and not literal_only(arg, constants):
                report(line, "Hyprland exec built from data")
        # An argv array: [ "command", ... ] whose elements include a secret.
        if kind == "punct" and value == "[" and i + 1 < len(t) and t[i + 1][0] == "str" \
                and re.fullmatch(r"[\w./+-]+", t[i + 1][1] or "-"):
            j = i + 1
            while j < len(t) and t[j][1] != "]":
                element, j = expression(t, j)
                names = [v for k, v, _ in element if k == "name"]
                strings = [v for k, v, _ in element if k == "str"]
                if any(SECRET.match(s) for s in strings) or (names and SECRET_NAME.match(names[-1])):
                    report(element[0][2], "secret in argv")
                    break
                if j < len(t) and t[j][1] == ",":
                    j += 1
                else:
                    break


# --- Python: the AST.

def is_shell_list(node):
    return isinstance(node, (ast.List, ast.Tuple)) and len(node.elts) >= 3 \
        and isinstance(node.elts[0], ast.Constant) and node.elts[0].value in SHELLS \
        and isinstance(node.elts[1], ast.Constant) and node.elts[1].value == "-c"


def literal_str(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return True
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return literal_str(node.left) and literal_str(node.right)
    return False


def check_python(path, text, findings):
    try:
        tree = ast.parse(text, filename=str(path))
    except SyntaxError:
        return
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for kw in node.keywords:
                if kw.arg == "shell" and not (isinstance(kw.value, ast.Constant) and kw.value.value is False):
                    findings.append((rel(path), node.lineno, "shell=True"))
            f = node.func
            if isinstance(f, ast.Attribute) and isinstance(f.value, ast.Name) and f.value.id == "os" \
                    and f.attr in ("system", "popen"):
                findings.append((rel(path), node.lineno, f"os.{f.attr}"))
        if is_shell_list(node) and not literal_str(node.elts[2]):
            findings.append((rel(path), node.lineno, "shell script built from data"))


# --- polkit.

def repo_path(installed):
    for prefix in ("/usr/share/golden-gate/", "/usr/lib/golden-gate/"):
        if installed.startswith(prefix):
            return installed[len(prefix):]
    return installed


def subcommands(tree):
    """The keys of the helper's `commands = {…}` table."""
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "commands" for t in node.targets) \
                and isinstance(node.value, ast.Dict):
            return {k.value for k in node.value.keys if isinstance(k, ast.Constant)}
    return None


def check_polkit(findings):
    actions = {}
    for policy in files(".policy"):
        for action in ET.parse(policy).getroot().iter("action"):
            exec_path = next((a.text for a in action.iter("annotate")
                              if a.get("key") == "org.freedesktop.policykit.exec.path"), None)
            defaults = action.find("defaults")
            free = defaults is not None and any((d.text or "").strip() == "yes" for d in defaults)
            actions[action.get("id")] = (exec_path, free, rel(policy))
    granted = set()
    for rules in files(".rules"):
        text = rules.read_text()
        if "polkit.Result.YES" in text:
            granted |= set(re.findall(r"""action\.id\s*===?\s*["']([\w.-]+)["']""", text))
            if re.search(r"""action\.id\.(indexOf|startsWith)\s*\(""", text):
                findings.append((rel(rules), 1, "polkit rule grants actions by prefix"))
    granted |= {a for a, (_, free, _) in actions.items() if free}
    for action in sorted(granted):
        exec_path, _, where = actions.get(action, (None, False, "?"))
        if not exec_path:
            findings.append((where, 1, f"passwordless polkit action {action} has no exec.path"))
            continue
        helper = repo_path(exec_path)
        if helper not in PASSWORDLESS:
            findings.append((where, 1, f"passwordless polkit action {action} runs unreviewed {helper}"))
            continue
        tree = ast.parse((ROOT / helper).read_text())
        have = subcommands(tree)
        if have != PASSWORDLESS[helper]:
            findings.append((helper, 1, f"passwordless helper's subcommands {sorted(have or [])} "
                                        f"aren't the reviewed {sorted(PASSWORDLESS[helper])}"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Call):
                name = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id", "")
                if name in FORBIDDEN_CALLS:
                    findings.append((helper, node.lineno, f"passwordless helper calls {name}"))
                if any(kw.arg == "unsigned" for kw in node.keywords):
                    findings.append((helper, node.lineno, "passwordless helper installs unsigned code"))


def scan():
    findings = []
    for path in files(".qml", ".js", ".mjs"):
        check_qml(path, path.read_text(errors="replace"), findings)
    for path in files(".py"):
        check_python(path, path.read_text(errors="replace"), findings)
    for path in ROOT.rglob("*"):
        # Python scripts without the extension (gg-* helpers).
        if path.is_file() and not path.suffix and not SKIP & set(path.relative_to(ROOT).parts):
            try:
                head = path.open("rb").readline()
            except OSError:
                continue
            if head.startswith(b"#!") and b"python" in head:
                check_python(path, path.read_text(errors="replace"), findings)
    check_polkit(findings)
    return sorted(set(findings))


def key(finding):
    # Line numbers move; a finding is its file and what it is.
    return f"{finding[0]}: {finding[2]}"


def self_test():
    """The lint itself: what it must catch, and what it must leave alone."""
    bad_qml = {
        'run(["sh", "-c", "nmcli connect " + ssid])': "shell script built from data",
        'run(["bash", "-c",\n  `ping ${host}`])': "shell script built from data",
        'sys.sh("bluetoothctl pair " + mac)': "shell script built from data",
        'Hyprland.dispatch("exec " + cmd)': "Hyprland exec built from data",
        'Hyprland.dispatch(`exec ${cmd}`)': "Hyprland exec built from data",
        'run(["nmcli", "dev", "wifi", "connect", ssid, "password", pw])': "secret in argv",
        'run(["gg-update", "--token", t])': "secret in argv",
        'command: ["curl", "-u", root.token]': "secret in argv",
    }
    good_qml = [
        'run(["sh", "-c", \'nmcli connection up id "$1"\', "sh", ssid])',
        'run(["sh", "-c", "a; " +\n  "b", "sh", x])',
        'readonly property string test: "-iname \'*.png\'"\nrun(["sh", "-c", "find . " + test])',
        'Hyprland.dispatch(`focusmonitor ${monitor.name}`)',
        'Hyprland.dispatch("exec gg-settings")',
        'command: ["getent", "passwd", user]',
        'runWithInput(["nmcli", "--ask", "device", "wifi", "connect", ssid], password + "\\n")',
        '// security-lint: allow a test hook\ncommand: ["sh", "-c", Quickshell.env("HOOK")]',
    ]
    bad_py = {
        'subprocess.run(cmd, shell=True)': "shell=True",
        'os.system("rm " + p)': "os.system",
        'subprocess.run(["sh", "-c", f"ls {d}"])': "shell script built from data",
    }
    good_py = ['subprocess.run(["sh", "-c", "ls \\"$1\\"", "sh", d])', 'subprocess.run(cmd, shell=False)']
    problems = []
    fake = ROOT / "sample"
    for src, want in bad_qml.items():
        out = []
        check_qml(fake, src, out)
        if [w for _, _, w in out] != [want]:
            problems.append(f"QML {src!r}: expected {want!r}, found {out}")
    for src in good_qml:
        out = []
        check_qml(fake, src, out)
        if out:
            problems.append(f"QML {src!r}: expected nothing, found {out}")
    for src, want in bad_py.items():
        out = []
        check_python(fake, src, out)
        if [w for _, _, w in out] != [want]:
            problems.append(f"Python {src!r}: expected {want!r}, found {out}")
    for src in good_py:
        out = []
        check_python(fake, src, out)
        if out:
            problems.append(f"Python {src!r}: expected nothing, found {out}")
    return problems


def main():
    problems = self_test()
    for p in problems:
        print("FAIL self-test:", p, file=sys.stderr)
    if problems:
        return 1
    findings = scan()
    if "--list" in sys.argv:
        for f, line, what in findings:
            print(f"{f}:{line}: {what}")
        return 0
    allowed = [l.strip() for l in BASELINE.read_text().splitlines()
               if l.strip() and not l.startswith("#")] if BASELINE.exists() else []
    seen = [key(f) for f in findings]
    new = [f for f in findings if key(f) not in allowed]
    stale = [a for a in allowed if a not in seen]
    for f, line, what in new:
        print(f"FAIL {f}:{line}: {what}", file=sys.stderr)
    for a in stale:
        print(f"FAIL {a}: fixed, so remove it from tests/security-lint.baseline", file=sys.stderr)
    if new or stale:
        return 1
    print(f"Security lint: no shell built from data, no shell=True, passwordless polkit reviewed, "
          f"no secrets in argv ({len(findings)} baselined)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
