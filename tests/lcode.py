#!/usr/bin/env python3
"""LCode: backend (projects, diagnostics, build/run sessions, Simulator) and the
shared CodeEditor. Runs without Quickshell or a Swift toolchain: a stand-in
`swift` script plays the compiler. The Simulator part runs when Xvfb is
installed (CI: apt-get install xvfb).

    QT_QPA_PLATFORM=offscreen python tests/lcode.py
"""
from __future__ import annotations

import json
import os
import pathlib
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/lcode"))
import lcode_project as proj  # noqa: E402

STAND_IN_SWIFT = r"""#!/bin/sh
# Plays `swift` for the tests: build prints SwiftPM-style progress and
# diagnostics, then "builds" a program that prints and reads stdin.
case "$1" in
  --version) echo "Swift version 6.1 (test stand-in)"; exit 0;;
  build)
    product=""; while [ $# -gt 0 ]; do [ "$1" = "--product" ] && product="$2"; shift; done
    echo "Building for debugging..."
    echo "[1/2] Compiling $product main.swift"
    echo "[2/2] Linking $product"
    if grep -q BROKEN Sources/*/*.swift; then
      f=$(grep -l BROKEN Sources/*/*.swift | head -1)
      echo "$PWD/$f:2:1: error: cannot find 'BROKEN' in scope"
      exit 1
    fi
    echo "Sources/$product/main.swift:1:5: warning: variable 'x' was never used"
    mkdir -p .build/debug
    printf '#!/bin/sh\necho "Hello from %s on ${LCODE_DEVICE_NAME:-host}"\nread name\necho "Hi, $name"\n' "$product" > .build/debug/$product
    chmod +x .build/debug/$product
    echo "Build complete!"; exit 0;;
  test) echo "Test Suite 'All tests' passed"; exit 0;;
  package) exit 0;;
esac
"""


class Projects(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_templates_create_valid_packages(self):
        for template in proj.TEMPLATES:
            root = proj.create_project(self.tmp, template, f"My {template}", "Acme", "com.acme", True, False)
            p = proj.open_project(root)
            self.assertEqual(p["kind"], template)
            self.assertEqual(p["bundleId"], f"com.acme.My-{template}")
            self.assertTrue((pathlib.Path(root) / "Package.swift").read_text().startswith("// swift-tools-version:"))
            self.assertTrue((pathlib.Path(root) / ".gitignore").read_text().count(".lcode/userdata/"))
            if template == "library":
                self.assertEqual(p["products"], [])
            else:
                self.assertEqual(p["products"], [f"My_{template}"])
                self.assertEqual(p["destination"], "lphone-16" if template == "app" else "host")
            with self.assertRaises(FileExistsError):
                proj.create_project(self.tmp, template, f"My {template}")

    def test_git_repository_is_created_with_a_first_commit(self):
        if not shutil.which("git"):
            self.skipTest("git not installed")
        root = proj.create_project(self.tmp, "tool", "Tool", git=True)
        log = subprocess.run(["git", "log", "--oneline"], cwd=root, stdout=subprocess.PIPE, text=True)
        self.assertIn("Initial Commit", log.stdout)

    def test_module_names_and_new_files(self):
        self.assertEqual(proj.module_name("2048 Game"), "_2048_Game")
        self.assertIn("struct SettingsView: View", proj.new_file_contents("SettingsView.swift", "App"))
        self.assertIn("import Foundation", proj.new_file_contents("Model.swift", "App"))
        self.assertEqual(proj.new_file_contents("notes.txt", "App"), "")

    def test_existing_packages_are_recognised(self):
        root = pathlib.Path(self.tmp) / "Existing"
        root.mkdir()
        (root / "Package.swift").write_text('let package = Package(\n  name: "Existing",\n'
                                            '  dependencies: [.package(url: "https://github.com/moreSwift/swift-cross-ui", from: "0.9.0")],\n'
                                            '  products: [.executable(name: "cli", targets: ["A"])],\n'
                                            '  targets: [.executableTarget(name: "A")])\n')
        p = proj.open_project(str(root))
        self.assertEqual((p["name"], p["kind"], p["products"]), ("Existing", "app", ["cli", "A"]))

    def test_tree_and_find_skip_build_and_hidden_folders(self):
        root = pathlib.Path(proj.create_project(self.tmp, "tool", "Finder", git=False))
        (root / ".build/debug").mkdir(parents=True)
        (root / ".build/debug/main.swift").write_text('print("Hello")\n')
        names = [n["name"] for n in proj.tree(str(root))]
        self.assertEqual(names[:3], ["Sources", "Finder", "main.swift"])
        self.assertNotIn(".build", names)
        results = proj.find(str(root), "hello, world")
        self.assertEqual(len(results), 1)
        m = results[0]["matches"][0]
        self.assertEqual((m["text"][m["start"]:m["start"] + m["length"]]).lower(), "hello, world")


class Diagnostics(unittest.TestCase):
    def test_compiler_lines(self):
        d = proj.parse_diagnostic("/p/Sources/A/main.swift:12:5: error: cannot find 'x' in scope", "/p")
        self.assertEqual((d["severity"], d["line"], d["column"], d["message"]), ("error", 12, 5, "cannot find 'x' in scope"))
        d = proj.parse_diagnostic("Sources/A/b.swift:3: warning: unused", "/p")
        self.assertEqual((d["path"], d["line"], d["column"]), ("/p/Sources/A/b.swift", 3, 1))
        d = proj.parse_diagnostic("\x1b[1merror: \x1b[0mlink command failed", "/p")
        self.assertEqual((d["severity"], d["path"]), ("error", ""))
        self.assertIsNone(proj.parse_diagnostic("[3/7] Compiling A main.swift", "/p"))
        self.assertEqual(proj.parse_progress("[3/7] Compiling A main.swift"), {"done": 3, "total": 7, "message": "Compiling A main.swift"})


class Session:
    """helper.py serve, driven like the LCode window drives it."""

    def __init__(self, home: str, swift: str):
        env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=home + "/config", XDG_RUNTIME_DIR=home + "/run", LCODE_SWIFT=swift)
        os.makedirs(home + "/run", exist_ok=True)
        self.p = subprocess.Popen([sys.executable, str(ROOT / "apps/lcode/helper.py"), "serve"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, env=env, bufsize=1)
        self.q: queue.Queue = queue.Queue()
        threading.Thread(target=lambda: [self.q.put(json.loads(l)) for l in self.p.stdout], daemon=True).start()
        self.n = 0
        self.events: list[dict] = []

    def call(self, cmd: str, **args) -> dict:
        self.n += 1
        self.p.stdin.write(json.dumps({"id": self.n, "cmd": cmd, **args}) + "\n")
        self.p.stdin.flush()
        while True:
            m = self.q.get(timeout=30)
            if m.get("id") == self.n:
                return m
            self.events.append(m)

    def wait(self, pred, timeout: float = 30) -> dict:
        for m in self.events:
            if pred(m):
                self.events.remove(m)
                return m
        end = time.time() + timeout
        while time.time() < end:
            try:
                m = self.q.get(timeout=0.25)
            except queue.Empty:
                continue
            if pred(m):
                return m
            self.events.append(m)
        raise TimeoutError([e.get("event") for e in self.events][-12:])

    def close(self) -> None:
        self.p.stdin.close()
        self.p.wait(10)
        self.p.stdout.close()


class Backend(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        swift = os.path.join(self.home, "swift")
        pathlib.Path(swift).write_text(STAND_IN_SWIFT)
        os.chmod(swift, 0o755)
        self.s = Session(self.home, swift)
        r = self.s.call("create", parent=self.home, template="tool", name="Greeter", organization="", organizationId="com.example", git=False)
        self.assertTrue(r["ok"], r)
        self.root = r["root"]
        self.assertTrue(self.s.call("open", path=self.root)["ok"])

    def tearDown(self):
        self.s.close()
        shutil.rmtree(self.home, ignore_errors=True)

    def test_hello_settings_and_recents(self):
        r = self.s.call("hello")
        self.assertEqual(r["swiftVersion"], "Swift version 6.1 (test stand-in)")
        self.assertEqual(r["settings"]["recent"], [self.root])
        r = self.s.call("settings", values={"fontSize": 15, "recent": ["/nope"]})
        self.assertEqual((r["settings"]["fontSize"], r["settings"]["recent"]), (15, [self.root]))

    def test_files_read_write_rename_and_new(self):
        main = os.path.join(self.root, "Sources/Greeter/main.swift")
        text = self.s.call("read", path=main)["text"]
        self.assertTrue(self.s.call("write", path=main, text=text + "// edited\n")["ok"])
        self.assertTrue(pathlib.Path(main).read_text().endswith("// edited\n"))
        r = self.s.call("newFile", dir=os.path.dirname(main), name="WelcomeView.swift")
        self.assertIn("struct WelcomeView: View", pathlib.Path(r["path"]).read_text())
        self.assertFalse(self.s.call("newFile", dir=os.path.dirname(main), name="WelcomeView.swift")["ok"])
        r = self.s.call("rename", path=r["path"], name="HomeView.swift")
        self.assertTrue(r["ok"] and r["path"].endswith("HomeView.swift"))
        self.assertTrue(any(n["name"] == "HomeView.swift" for n in self.s.call("tree")["nodes"]))
        dirs = self.s.call("dirs", path=self.home)
        self.assertEqual([d["name"] for d in dirs["dirs"] if d["isProject"]], ["Greeter"])

    def test_build_reports_progress_issues_and_failure(self):
        self.s.call("build", product="Greeter")
        done = self.s.wait(lambda m: m.get("event") == "task.finished")
        self.assertEqual((done["code"], done["errors"], done["warnings"]), (0, 0, 1))
        self.assertTrue(any(e.get("event") == "task.progress" for e in self.s.events))
        main = os.path.join(self.root, "Sources/Greeter/main.swift")
        pathlib.Path(main).write_text('print("hi")\nBROKEN\n')
        self.s.events.clear()
        self.s.call("build", product="Greeter")
        issue = self.s.wait(lambda m: m.get("event") == "task.issue" and m["severity"] == "error")
        self.assertEqual((issue["path"], issue["line"]), (main, 2))
        done = self.s.wait(lambda m: m.get("event") == "task.finished")
        self.assertEqual((done["code"], done["errors"]), (1, 1))

    def test_run_on_host_with_console_input(self):
        r = self.s.call("run", product="Greeter", destination="host", device={})
        gen = r["gen"]
        self.s.wait(lambda m: m.get("event") == "run.started" and m["gen"] == gen)
        self.s.wait(lambda m: m.get("event") == "run.output" and "Hello from Greeter on host" in m["text"])
        self.s.call("stdin", text="Ada\n")
        self.s.wait(lambda m: m.get("event") == "run.output" and "Hi, Ada" in m["text"])
        exited = self.s.wait(lambda m: m.get("event") == "run.exited")
        self.assertEqual(exited["code"], 0)

    def test_stop_cancels_the_running_program(self):
        gen = self.s.call("run", product="Greeter", destination="host", device={})["gen"]
        self.s.wait(lambda m: m.get("event") == "run.started")
        self.s.call("stop")
        exited = self.s.wait(lambda m: m.get("event") == "run.exited" and m["gen"] == gen)
        self.assertIsNone(exited["code"])

    @unittest.skipUnless(shutil.which("Xvfb"), "Xvfb not installed")
    def test_simulator_boots_runs_and_rotates(self):
        device = {"id": "lphone-16", "name": "LPhone 16", "side": 764, "w": 393, "h": 764}
        r = self.s.call("run", product="Greeter", destination="lphone-16", device=device)
        self.assertTrue(r["ok"], r)
        self.s.wait(lambda m: m.get("event") == "sim.state" and m["power"] == "on", timeout=40)
        self.s.wait(lambda m: m.get("event") == "run.output" and "on LPhone 16" in m["text"], timeout=20)
        frame = self.s.wait(lambda m: m.get("event") == "sim.frame", timeout=20)
        self.assertEqual((frame["w"], frame["h"]), (393, 764))
        data = pathlib.Path(frame["frame"]).read_bytes()
        self.assertEqual(data[:2], b"BM")
        self.s.call("simInput", input={"t": "motion", "x": 10, "y": 10})
        self.s.call("simRegion", w=734, h=372)
        rotated = self.s.wait(lambda m: m.get("event") == "sim.frame" and m["w"] == 734, timeout=20)
        self.assertEqual(rotated["h"], 372)
        self.s.call("simShutdown")
        self.s.wait(lambda m: m.get("event") == "sim.state" and m["power"] == "off")
        self.assertFalse(os.path.exists(os.path.dirname(frame["frame"])))


class CodeEditor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        os.environ.setdefault("QT_QUICK_BACKEND", "software")
        try:
            from PySide6.QtGui import QGuiApplication
        except ImportError:
            raise unittest.SkipTest("PySide6 not installed")
        cls.app = QGuiApplication.instance() or QGuiApplication([])

    def setUp(self):
        from PySide6.QtCore import QUrl
        from PySide6.QtQml import QQmlComponent
        from PySide6.QtQuick import QQuickView
        self.view = QQuickView()
        self.component = c = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / "tests" / "Editor.qml"))
        c.setData(b'import QtQuick\nimport "../apps/lib"\n'
                  b'CodeEditor { width: 700; height: 400; language: "swift"; '
                  b'text: "struct A {\\n    func b() {\\n        let c = 1\\n    }\\n}\\n" }',
                  url)
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.ed = c.create()
        self.view.setContent(url, c, self.ed)
        self.view.show()
        self.app.processEvents()

    def tearDown(self):
        self.view.close()
        self.view.deleteLater()
        self.app.processEvents()

    def js(self, expr: str):
        from PySide6.QtQml import QQmlEngine, QQmlExpression
        e = QQmlExpression(QQmlEngine.contextForObject(self.ed), self.ed, expr)
        value, undefined = e.evaluate()
        self.assertFalse(e.hasError(), e.error().toString())
        self.app.processEvents()
        return value

    def text(self) -> str:
        return self.js("text")

    def test_lines_cursor_and_go_to(self):
        self.assertEqual(self.js("lineCount"), 6)
        self.js("goTo(3, 9)")
        self.assertEqual((self.js("cursorLine"), self.js("cursorColumn")), (3, 9))

    def test_comment_shift_and_find(self):
        self.js("goTo(3, 1)")
        self.js("toggleComment()")
        self.assertIn("        // let c = 1", self.text())
        self.js("toggleComment()")
        self.assertIn("\n        let c = 1\n", self.text())
        self.js("shiftLines(true)")
        self.assertIn("\n            let c = 1\n", self.text())
        self.assertEqual(self.js("countMatches('func', true)"), 1)
        self.js("goTo(1, 1)")
        self.assertTrue(self.js("findNext('func', true, true)"))
        self.assertEqual(self.js("editor.selectedText"), "func")
        self.assertEqual(self.js("replaceAll('let', 'var', true)"), 1)
        self.assertIn("var c = 1", self.text())

    def test_return_keeps_indentation(self):
        self.js("goTo(3, 18)")          # end of "        let c = 1"
        self.js("newline()")
        self.assertEqual(self.text().split("\n")[3], "        ")
        self.assertEqual(self.js("cursorLine"), 4)


if __name__ == "__main__":
    unittest.main(verbosity=1)
