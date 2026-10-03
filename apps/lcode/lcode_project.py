"""LCode projects: Swift packages, templates, compiler diagnostics and search.

An LCode project is a folder with a Package.swift. LCode keeps its own data in
.lcode/: project.json (product type, bundle identifier, default run
destination; committed) and userdata/state.json (open tabs; git-ignored),
the counterparts of an .xcodeproj and its xcuserdata.
"""
from __future__ import annotations

import datetime
import getpass
import json
import os
import pathlib
import pwd
import re
import subprocess

HOST = "host"
IGNORED_DIRS = {"build", "DerivedData", "node_modules"}


def is_ignored(name: str) -> bool:
    return name.startswith(".") or name in IGNORED_DIRS


# --------------------------------------------------------------------- model

PACKAGE_NAME = re.compile(r'Package\s*\(\s*name:\s*"([^"]+)"')
EXECUTABLES = re.compile(r'\.(?:executableTarget|executable)\s*\(\s*name:\s*"([^"]+)"')
GUI_MARKERS = ("swift-cross-ui", "SwiftCrossUI", "adwaita-swift", "Adwaita")


def manifest(root: pathlib.Path) -> str:
    try:
        return (root / "Package.swift").read_text(encoding="utf-8")
    except OSError:
        return ""


def executable_products(text: str) -> list[str]:
    out: list[str] = []
    for m in EXECUTABLES.finditer(text):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def guess_kind(text: str) -> str:
    if any(marker in text for marker in GUI_MARKERS):
        return "app"
    if not text or EXECUTABLES.search(text):
        return "tool"
    return "library"


def read_json(path: pathlib.Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_json(path: pathlib.Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def open_project(raw: str, default_simulator: str = "lphone-16") -> dict:
    root = pathlib.Path(raw).expanduser().resolve()
    if not root.is_dir():
        raise FileNotFoundError(f"“{raw}” is not a folder.")
    text = manifest(root)
    m = PACKAGE_NAME.search(text)
    meta = read_json(root / ".lcode/project.json")
    kind = meta.get("kind") or guess_kind(text)
    destination = meta.get("default_destination") or (default_simulator if kind == "app" else HOST)
    return {
        "root": str(root),
        "name": m.group(1) if m else root.name,
        "isPackage": bool(text),
        "kind": kind,
        "products": executable_products(text),
        "bundleId": meta.get("bundle_identifier", ""),
        "organization": meta.get("organization", ""),
        "destination": destination,
        "state": read_json(root / ".lcode/userdata/state.json"),
    }


def save_meta(root: str, kind: str, bundle_id: str) -> None:
    path = pathlib.Path(root) / ".lcode/project.json"
    meta = read_json(path)
    meta["kind"] = kind
    meta["bundle_identifier"] = bundle_id
    write_json(path, meta)


def save_state(root: str, state: dict) -> None:
    write_json(pathlib.Path(root) / ".lcode/userdata/state.json", state)


def tree(raw: str, limit: int = 20000) -> list[dict]:
    """Every file and folder under root (hidden and build folders skipped),
    folders first, then names case-insensitively, as a flat parent-linked list."""
    root = pathlib.Path(raw)
    out: list[dict] = []

    def walk(folder: pathlib.Path, depth: int) -> None:
        try:
            entries = [e for e in os.scandir(folder) if not is_ignored(e.name)]
        except OSError:
            return
        entries.sort(key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower()))
        for e in entries:
            if len(out) >= limit:
                return
            is_dir = e.is_dir(follow_symlinks=False)
            out.append({"path": e.path, "name": e.name, "dir": is_dir, "depth": depth, "parent": str(folder)})
            if is_dir:
                walk(pathlib.Path(e.path), depth + 1)

    walk(root, 0)
    return out


def tree_signature(raw: str) -> tuple:
    """Cheap change detector for the project tree: folder mtimes and names."""
    sig = []
    for dirpath, dirnames, filenames in os.walk(raw):
        dirnames[:] = sorted(d for d in dirnames if not is_ignored(d))
        try:
            sig.append((dirpath, os.stat(dirpath).st_mtime_ns))
        except OSError:
            pass
    return tuple(sig)


def files(raw: str, limit: int = 20000) -> list[str]:
    return [n["path"] for n in tree(raw, limit) if not n["dir"]]


# ------------------------------------------------------------- diagnostics

LOCATED = re.compile(r"^(?P<path>[^:\s][^:]*):(?P<line>\d+):(?:(?P<col>\d+):)? (?P<sev>error|warning|note): (?P<msg>.+)$")
GLOBAL = re.compile(r"^(?:\S+: )?(?P<sev>error|warning): (?P<msg>.+)$")
PROGRESS = re.compile(r"^\[(?P<done>\d+)/(?P<total>\d+)\]\s*(?P<what>.*)$")
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


def strip_ansi(text: str) -> str:
    return ANSI.sub("", text)


def parse_diagnostic(line: str, root: str) -> dict | None:
    line = strip_ansi(line).rstrip()
    m = LOCATED.match(line)
    if m:
        path = m.group("path")
        if not os.path.isabs(path):
            path = os.path.join(root, path)
        return {
            "severity": m.group("sev"),
            "message": m.group("msg"),
            "path": os.path.normpath(path),
            "line": int(m.group("line")),
            "column": int(m.group("col") or 1),
        }
    m = GLOBAL.match(line)
    if m:
        return {"severity": m.group("sev"), "message": m.group("msg"), "path": "", "line": 0, "column": 0}
    return None


def parse_progress(line: str) -> dict | None:
    m = PROGRESS.match(strip_ansi(line))
    if not m:
        return None
    return {"done": int(m.group("done")), "total": int(m.group("total")), "message": m.group("what").strip()}


# ------------------------------------------------------------------ search

def find(raw: str, query: str, case_sensitive: bool = False, max_results: int = 2000) -> list[dict]:
    """Plain-text search across project files: [{path, matches: [{line, column, text, start, length}]}]."""
    needle = query if case_sensitive else query.lower()
    out: list[dict] = []
    total = 0
    if not needle:
        return out
    for path in files(raw):
        try:
            if os.path.getsize(path) > 2 * 1024 * 1024:
                continue
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        matches = []
        for i, line in enumerate(text.splitlines()):
            hay = line if case_sensitive else line.lower()
            idx = hay.find(needle)
            if idx < 0:
                continue
            lead = len(line) - len(line.lstrip())
            matches.append({"line": i + 1, "column": idx + 1, "text": line.strip()[:240],
                            "start": max(0, idx - lead), "length": len(needle)})
            total += 1
            if total >= max_results:
                break
        if matches:
            out.append({"path": path, "matches": matches})
        if total >= max_results:
            break
    return out


# --------------------------------------------------------------- templates

TEMPLATES = ("app", "tool", "library")


def module_name(product: str) -> str:
    s = "".join(c if c.isalnum() or c == "_" else "_" for c in product) or "App"
    return "_" + s if s[0].isdigit() else s


def bundle_identifier(org_id: str, product: str) -> str:
    slug = "".join(c if c.isascii() and (c.isalnum() or c == "-") else "-" for c in product)
    return f"{org_id}.{slug}" if org_id else slug


def author_name() -> str:
    try:
        gecos = pwd.getpwuid(os.getuid()).pw_gecos.split(",")[0].strip()
        if gecos:
            return gecos
    except KeyError:
        pass
    return getpass.getuser()


def file_header(file_name: str, project: str, organization: str = "") -> str:
    today = datetime.date.today().strftime("%x")
    header = f"//\n//  {file_name}\n//  {project}\n//\n//  Created by {author_name()} on {today}.\n"
    if organization:
        header += f"//  Copyright © {datetime.date.today().year} {organization}. All rights reserved.\n"
    return header + "//\n\n"


def _test_target(module: str, include: bool, deps: str = "") -> str:
    if not include:
        return ""
    return f'        .testTarget(\n            name: "{module}Tests",\n            dependencies: [{deps}]\n        ),\n'


def _manifests(template: str, name: str, module: str, tests: bool) -> str:
    if template == "app":
        return f'''// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "{name}",
    dependencies: [
        .package(url: "https://github.com/moreSwift/swift-cross-ui", .upToNextMinor(from: "0.9.0")),
    ],
    targets: [
        .executableTarget(
            name: "{module}",
            dependencies: [
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
            ]
        ),
{_test_target(module, tests)}    ]
)
'''
    if template == "tool":
        return f'''// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{name}",
    targets: [
        .executableTarget(
            name: "{module}"
        ),
{_test_target(module, tests)}    ]
)
'''
    return f'''// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "{name}",
    products: [
        .library(
            name: "{module}",
            targets: ["{module}"]
        ),
    ],
    targets: [
        .target(
            name: "{module}"
        ),
{_test_target(module, tests, f'"{module}"')}    ]
)
'''


def create_project(parent: str, template: str, name: str, organization: str = "", org_id: str = "",
                   tests: bool = True, git: bool = True, default_simulator: str = "lphone-16") -> str:
    if template not in TEMPLATES:
        raise ValueError(f"Unknown template “{template}”.")
    name = name.strip()
    if not name or "/" in name:
        raise ValueError("Enter a product name.")
    root = pathlib.Path(parent).expanduser() / name
    if root.exists() and any(root.iterdir()):
        raise FileExistsError(f"“{root}” already exists and is not empty.")
    module = module_name(name)
    sources = root / "Sources" / module
    files: dict[pathlib.Path, str] = {root / "Package.swift": _manifests(template, name, module, tests)}
    if template == "app":
        app_file = f"{module}App.swift"
        files[sources / app_file] = file_header(app_file, name, organization) + (
            "import SwiftCrossUI\nimport DefaultBackend\n\n@main\n"
            f"struct {module}App: App {{\n    var body: some Scene {{\n        WindowGroup(\"{name}\") {{\n"
            "            ContentView()\n        }\n    }\n}\n")
        files[sources / "ContentView.swift"] = file_header("ContentView.swift", name, organization) + (
            "import SwiftCrossUI\n\nstruct ContentView: View {\n    @State var count = 0\n\n"
            "    var body: some View {\n        VStack {\n            Text(\"Hello, world!\")\n"
            "                .font(.title)\n            HStack {\n                Button(\"-\") { count -= 1 }\n"
            "                Text(\"Count: \\(count)\")\n                Button(\"+\") { count += 1 }\n"
            "            }\n        }\n        .padding()\n    }\n}\n")
    elif template == "tool":
        files[sources / "main.swift"] = file_header("main.swift", name, organization) + 'print("Hello, World!")\n'
    else:
        lib_file = f"{module}.swift"
        files[sources / lib_file] = file_header(lib_file, name, organization) + (
            f"/// A greeting from {module}.\npublic func greeting(for name: String) -> String {{\n"
            "    \"Hello, \\(name)!\"\n}\n")
    if tests:
        tests_name = f"{module}Tests"
        body = (f"import XCTest\n@testable import {module}\n\nfinal class {tests_name}: XCTestCase {{\n"
                "    func testGreeting() throws {\n        XCTAssertEqual(greeting(for: \"LCode\"), \"Hello, LCode!\")\n    }\n}\n"
                if template == "library" else
                f"import XCTest\n\nfinal class {tests_name}: XCTestCase {{\n    func testExample() throws {{\n"
                "        XCTAssertTrue(true)\n    }\n}\n")
        files[root / "Tests" / tests_name / f"{tests_name}.swift"] = file_header(f"{tests_name}.swift", name, organization) + body
    files[root / ".gitignore"] = ".DS_Store\n/.build\n/Packages\n.lcode/userdata/\n*.swp\n"

    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    write_json(root / ".lcode/project.json", {
        "kind": template,
        "bundle_identifier": bundle_identifier(org_id, name),
        "organization": organization,
        "default_destination": default_simulator if template == "app" else HOST,
    })
    if git:
        _git_init(root)
    return str(root)


def _git_init(root: pathlib.Path) -> None:
    def git(*args: str, check: bool = False) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=check)
    try:
        if git("init", "--quiet").returncode:
            return
    except OSError:
        return
    git("add", "-A")
    identity = []
    if not git("config", "user.email").stdout.strip():
        identity = ["-c", f"user.name={author_name()}", "-c", f"user.email={getpass.getuser()}@localhost"]
    git(*identity, "commit", "--quiet", "-m", "Initial Commit")


def new_file_contents(name: str, project: str, organization: str = "") -> str:
    """File ▸ New ▸ File…: a Swift file, a SwiftCrossUI view for *View.swift, otherwise empty."""
    if name.endswith("View.swift"):
        view = module_name(name[: -len(".swift")])
        return file_header(name, project, organization) + (
            f"import SwiftCrossUI\n\nstruct {view}: View {{\n    var body: some View {{\n"
            "        Text(\"Hello, world!\")\n    }\n}\n")
    if name.endswith(".swift"):
        return file_header(name, project, organization) + "import Foundation\n\n"
    return ""
