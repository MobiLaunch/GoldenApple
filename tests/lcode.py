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
import tarfile
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

    def test_swift_templates_create_valid_packages(self):
        for template in ("app", "tool", "library"):
            root = proj.create_project(self.tmp, template, f"My {template}", "Acme", "com.acme", True, False)
            p = proj.open_project(root)
            self.assertEqual((p["kind"], p["toolchain"]), (template, "swift"))
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

    def test_every_template_is_recognised_as_what_it_is(self):
        expect = {
            "gg-app": ("goldengate", "app", ["Clock Work"], "host"),
            "python-app": ("python", "app", ["Clock Work"], "lphone-16"),
            "python-tool": ("python", "tool", ["Clock Work"], "host"),
            "rust-app": ("cargo", "app", ["clock-work"], "lphone-16"),
            "rust-tool": ("cargo", "tool", ["clock-work"], "host"),
            "rust-library": ("cargo", "library", [], "host"),
            "c-app": ("meson", "app", ["clock-work"], "lphone-16"),
            "c-tool": ("meson", "tool", ["clock-work"], "host"),
        }
        self.assertEqual(set(expect) | {"app", "tool", "library"}, set(proj.TEMPLATES))
        for template, (toolchain, kind, products, destination) in expect.items():
            folder = pathlib.Path(self.tmp) / template
            folder.mkdir()
            root = proj.create_project(str(folder), template, "Clock Work", "", "org.example", True, False,
                                       options={"accent": "#30d158", "style": "window"})
            p = proj.open_project(root)
            self.assertEqual((p["toolchain"], p["kind"], p["products"], p["destination"]), (toolchain, kind, products, destination), template)
            self.assertEqual(p["meta"]["toolchain"], toolchain)
            # Without LCode's own data the build files alone say what it is.
            shutil.rmtree(pathlib.Path(root) / ".lcode")
            self.assertEqual(proj.open_project(root)["toolchain"], toolchain, template)
        app_id = (pathlib.Path(self.tmp) / "c-app/Clock Work/src/main.c").read_text()
        self.assertIn('adw_application_new ("org.example.Clock_Work"', app_id)
        self.assertIn("#30d158", (pathlib.Path(self.tmp) / "python-app/Clock Work/clock_work/style.css").read_text())

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
        self.assertTrue(proj.new_file_contents("tool.py", "App").startswith("#\n#  tool.py"))
        self.assertIn('#include "util.h"', proj.new_file_contents("util.c", "App"))
        self.assertEqual(proj.snake_name("2048 Game!"), "app_2048_game")
        self.assertEqual(proj.application_id("com.acme.My-App"), "com.acme.My_App")

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

    def test_rust_c_and_python_formats(self):
        d = proj.parse_diagnostic("src/main.rs:2:5: error[E0425]: cannot find value `x` in this scope", "/r")
        self.assertEqual((d["path"], d["line"], d["column"], d["severity"]), ("/r/src/main.rs", 2, 5, "error"))
        d = proj.parse_diagnostic("../src/main.c:9:3: fatal error: gtk.h: No such file or directory", "/c/build")
        self.assertEqual((d["path"], d["severity"]), ("/c/src/main.c", "error"))
        # Summaries that repeat what was reported aren't issues of their own.
        for line in ("error: could not compile `demo` (bin \"demo\") due to 1 previous error",
                     "warning: `demo` (bin \"demo\") generated 1 warning"):
            self.assertIsNone(proj.parse_diagnostic(line, "/r"), line)
        self.assertEqual(proj.parse_progress("   Compiling gtk4 v0.11.5"), {"done": 0, "total": 0, "message": "Compiling gtk4 v0.11.5"})

    def test_python_tracebacks_become_runtime_issues(self):
        import lcode_toolchains as tc
        with tempfile.TemporaryDirectory() as root:
            r = tc.RuntimeIssues(root)
            out = r.feed("Traceback (most recent call last):\n"
                         f'  File "{root}/main.py", line 7, in <module>\n    main()\n'
                         f'  File "{root}/app/window.py", line 31, in main\n    x = 1 / 0\n'
                         '  File "/usr/lib/python3/thing.py", line 3, in helper\n')
            self.assertEqual(out, [])
            out = r.feed("ZeroDivisionError: division by zero\n")
            self.assertEqual(out[0]["path"], os.path.realpath(f"{root}/app/window.py"))
            self.assertEqual((out[0]["line"], out[0]["message"]), (31, "ZeroDivisionError: division by zero"))

    def test_python_check_reports_syntax_errors_like_a_compiler(self):
        with tempfile.TemporaryDirectory() as root:
            pathlib.Path(root, "ok.py").write_text("x = 1\n")
            pathlib.Path(root, "bad.py").write_text("def f(:\n    pass\n")
            p = subprocess.run([sys.executable, str(ROOT / "apps/lcode/lcode_tool.py"), "check", root],
                               stdout=subprocess.PIPE, text=True)
            self.assertEqual(p.returncode, 1)
            issues = [d for d in (proj.parse_diagnostic(l, root) for l in p.stdout.splitlines()) if d]
            self.assertEqual([(pathlib.Path(i["path"]).name, i["line"]) for i in issues if i["path"]], [("bad.py", 1)])


class Session:
    """helper.py serve, driven like the LCode window drives it."""

    def __init__(self, home: str, swift: str, **extra):
        env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=home + "/config", XDG_RUNTIME_DIR=home + "/run", LCODE_SWIFT=swift, **extra)
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
        self.assertEqual(r["toolchains"]["swift"]["version"], "Swift version 6.1 (test stand-in)")
        self.assertEqual(r["toolchains"]["python"]["name"], "Python")
        self.assertEqual(r["settings"]["recent"], [self.root])
        r = self.s.call("settings", values={"fontSize": 15, "recent": ["/nope"]})
        self.assertEqual((r["settings"]["fontSize"], r["settings"]["recent"]), (15, [self.root]))

    def test_settings_are_checked_and_git_identity(self):
        r = self.s.call("settings", values={"appearance": "dark", "showLineNumbers": "yes", "fontSize": True,
                                            "keyBindings": {"run": ["Ctrl+Shift+R"]}, "nope": 1,
                                            "customDevices": [{"id": "custom-a", "name": "A", "width": 400, "height": 800}]})
        st = r["settings"]
        self.assertEqual((st["appearance"], st["showLineNumbers"], st["fontSize"]), ("dark", True, 13))
        self.assertEqual(st["keyBindings"], {"run": ["Ctrl+Shift+R"]})
        self.assertEqual(st["customDevices"][0]["name"], "A")
        self.assertNotIn("nope", st)
        if not shutil.which("git"):
            self.skipTest("git not installed")
        r = self.s.call("gitIdentity", values={"name": "Ada Lovelace", "email": "ada@example.com", "bogus": "x"})
        self.assertEqual(r["identity"], {"name": "Ada Lovelace", "email": "ada@example.com", "defaultBranch": ""})
        self.assertIn("Ada Lovelace", pathlib.Path(self.home, ".gitconfig").read_text())
        # New files are created by you.
        main = os.path.join(self.root, "Sources/Greeter")
        made = self.s.call("newFile", dir=main, name="Extra.swift")
        self.assertIn("Created by Ada Lovelace", pathlib.Path(made["path"]).read_text())
        r = self.s.call("gitIdentity", values={"email": ""})
        self.assertEqual(r["identity"]["email"], "")
        self.assertIsInstance(self.s.call("fonts")["families"], list)

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


class OtherToolchains(unittest.TestCase):
    """Python always; C and Rust when Meson and cargo are installed."""

    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.s = Session(self.home, "/nonexistent/swift", LCODE_PYTHON=sys.executable)

    def tearDown(self):
        self.s.close()
        shutil.rmtree(self.home, ignore_errors=True)

    def project(self, template: str, name: str) -> dict:
        r = self.s.call("create", parent=self.home, template=template, name=name, organization="", organizationId="org.example", git=False)
        self.assertTrue(r["ok"], r)
        return self.s.call("open", path=r["root"])["project"]

    def task(self, cmd: str, timeout: float = 120, **args) -> tuple[dict, list[dict]]:
        self.s.events.clear()
        self.assertTrue(self.s.call(cmd, **args)["ok"])
        done = self.s.wait(lambda m: m.get("event") == "task.finished", timeout)
        return done, [e for e in self.s.events if e.get("event") == "task.issue"]

    def build_test_run(self, template: str, timeout: float = 120) -> None:
        p = self.project(template, "Demo " + template)
        product = p["products"][0]
        done, issues = self.task("build", timeout, product=product)
        self.assertEqual((done["code"], done["errors"]), (0, 0), issues)
        done, _ = self.task("test", timeout)
        self.assertEqual(done["code"], 0)
        gen = self.s.call("run", product=product, destination="host", device={})["gen"]
        self.s.wait(lambda m: m.get("event") == "run.output" and "Hello, World!" in m["text"], timeout)
        self.s.call("stdin", text="Ada\n")
        self.s.wait(lambda m: m.get("event") == "run.output" and "Hello, Ada!" in m["text"])
        self.assertEqual(self.s.wait(lambda m: m.get("event") == "run.exited" and m["gen"] == gen)["code"], 0)
        done, _ = self.task("clean", timeout)
        self.assertEqual(done["code"], 0)

    def test_python_script(self):
        self.build_test_run("python-tool")

    def test_python_errors_at_build_and_run_time(self):
        p = self.project("python-tool", "Broken")
        main = pathlib.Path(p["root"]) / "main.py"
        main.write_text("def broken(:\n    pass\n")
        done, issues = self.task("build", product=p["products"][0])
        self.assertEqual(done["errors"], 1)
        self.assertEqual((issues[0]["path"], issues[0]["line"]), (str(main), 1))
        main.write_text("import sys\n\nprint('starting')\nvalue = {}['missing']\n")
        self.s.call("run", product=p["products"][0], destination="host", device={})
        issue = self.s.wait(lambda m: m.get("event") == "task.issue" and m.get("runtime"))
        self.assertEqual((issue["path"], issue["line"], issue["message"]), (str(main), 4, "KeyError: 'missing'"))

    @unittest.skipUnless(shutil.which("meson") and shutil.which("cc"), "Meson and a C compiler aren't installed")
    def test_c_tool(self):
        self.build_test_run("c-tool")

    # A bare rustup (as CI images have) has cargo but no toolchain to run it.
    @unittest.skipUnless(shutil.which("cargo") and subprocess.run(["cargo", "--version"], capture_output=True).returncode == 0,
                         "cargo isn't installed")
    def test_rust_tool(self):
        self.build_test_run("rust-tool", timeout=300)


class Designer(unittest.TestCase):
    """CitronOS apps from the App Designer: checking, generating, loading."""

    def setUp(self):
        import lcode_design
        self.d = lcode_design
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def make(self, style: str) -> pathlib.Path:
        folder = pathlib.Path(self.tmp) / style
        folder.mkdir()
        return pathlib.Path(proj.create_project(str(folder), "gg-app", "Notes App", "", "org.example", True, False,
                                                options={"style": style, "accent": "#5e5ce6"}))

    def test_starters_check_out_and_build(self):
        for style, screens in (("sidebar", 3), ("window", 1), ("utility", 1)):
            root = self.make(style)
            doc = json.loads((root / "Interface.lcdesign").read_text())
            self.assertEqual(doc["app"]["accent"], "#5e5ce6")
            self.assertEqual(self.d.check(doc, root), [])
            lines: list[str] = []
            self.assertEqual(self.d.build(str(root), out=lines.append), 0, lines)
            app = root / ".build/app"
            self.assertEqual(len(list((app / "screens").glob("*.qml"))), screens)
            text = (app / "App.qml").read_text()
            self.assertTrue(text.startswith("//@ pragma AppId org.example.Notes-App"))
            self.assertEqual(os.path.realpath(app / "ui"), str(ROOT / "apps/lib"))
            self.assertEqual("sidebar: [" in text, style == "sidebar")

    def test_problems_are_reported_with_the_node(self):
        root = self.make("sidebar")
        doc = json.loads((root / "Interface.lcdesign").read_text())
        home = doc["screens"][0]["root"]
        button = home["children"][1]["children"][1]["children"][1]
        button["actions"]["tap"] = [{"do": "increment", "var": "clicks"}, {"do": "navigate", "screen": "nowhere"}]
        home["children"][0]["children"][1]["props"]["text"] = "Hi {nobody}"
        doc["state"].append({"name": "2bad", "type": "text", "value": ""})
        issues = self.d.check(doc, root)
        messages = [(i["severity"], i["node"]) for i in issues]
        self.assertIn(("error", button["id"]), messages)
        self.assertEqual(sum(1 for i in issues if i["severity"] == "error"), 3)
        self.assertTrue(any(i["severity"] == "warning" and "{nobody}" in i["message"] for i in issues))
        (root / "Interface.lcdesign").write_text(json.dumps(doc))
        lines: list[str] = []
        self.assertEqual(self.d.build(str(root), out=lines.append), 1)
        located = [proj.parse_diagnostic(l, str(root)) for l in lines]
        self.assertTrue(any(x and x["severity"] == "error" and x["message"].endswith(f"[home#{button['id']}]") for x in located))

    def test_generated_code_reads_like_qml(self):
        root = self.make("sidebar")
        doc = json.loads((root / "Interface.lcdesign").read_text())
        tasks = self.d.Gen(doc).screen(doc["screens"][1])
        self.assertIn('text: app.str(app.values.todos) + " tasks, saved when you quit"', tasks)
        self.assertIn('onItemDeleted: (index) => app.removeAt("todos", index)', tasks)
        self.assertIn('app.append("todos", app.values.newTask)', tasks)
        settings = self.d.Gen(doc).screen(doc["screens"][2])
        self.assertIn("shown: app.values.showTips", settings)
        formatter = shutil.which("pyside6-qmlformat") or shutil.which("qmlformat")
        if formatter:
            self.d.build(str(root), out=lambda _: None)
            for f in [root / ".build/app/App.qml", *(root / ".build/app/screens").glob("*.qml")]:
                p = subprocess.run([formatter, str(f)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
                self.assertEqual(p.returncode, 0, f"{f.name}: {p.stderr}")

    def test_generated_screens_run_with_the_kit(self):
        try:
            from PySide6.QtCore import QUrl
            from PySide6.QtGui import QGuiApplication
            from PySide6.QtQml import QQmlComponent, QQmlEngine, QQmlExpression
            from PySide6.QtQuick import QQuickView
        except ImportError:
            self.skipTest("PySide6 not installed")
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        app = QGuiApplication.instance() or QGuiApplication([])
        root = self.make("sidebar")
        self.d.build(str(root), out=lambda _: None)
        doc = json.loads((root / "Interface.lcdesign").read_text())
        initial = json.dumps({v["name"]: v["value"] for v in doc["state"]})
        view = QQuickView()
        component = QQmlComponent(view.engine())
        url = QUrl.fromLocalFile(str(root / ".build/app/Harness.qml"))
        component.setData(("import QtQuick\nimport \"ui/kit\" as Kit\nimport \"screens\"\n"
                           "Item { width: 900; height: 640\n"
                           f"  property alias rt: rt\n  Kit.AppRuntime {{ id: rt; initial: {initial}; screens: [\"home\", \"tasks\", \"settings\"] }}\n"
                           "  Kit.Scope { anchors.fill: parent; env: ({ dark: true, accent: \"#5e5ce6\" })\n"
                           "    ScreenTasks { id: tasks; anchors.fill: parent; app: rt }\n"
                           "    ScreenSettings { anchors.fill: parent; app: rt; visible: false } } }").encode(), url)
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        item = component.create()
        view.setContent(url, component, item)
        view.show()
        app.processEvents()

        def js(expr):
            e = QQmlExpression(QQmlEngine.contextForObject(item), item, expr)
            value, _ = e.evaluate()
            self.assertFalse(e.hasError(), e.error().toString())
            app.processEvents()
            return value

        self.assertEqual(js("rt.values.todos.length"), 2)
        js('rt.set("newTask", "Write tests"); rt.append("todos", rt.values.newTask); rt.clear("newTask")')
        self.assertEqual(js("rt.values.todos[2].title"), "Write tests")
        self.assertEqual(js("rt.values.newTask"), "")
        js('rt.perform([{ do: "increment", var: "count", by: 2 }, { do: "toggle", var: "showTips" }, { do: "navigate", screen: "settings" }])')
        self.assertEqual((js("rt.values.count"), js("rt.values.showTips"), js("rt.screen")), (2, False, "settings"))
        js("rt.back()")
        self.assertEqual(js("rt.screen"), "home")
        view.close()


class Distribution(unittest.TestCase):
    """Archive, install, and export packages."""

    def setUp(self):
        import lcode_archive
        self.a = lcode_archive
        self.tmp = tempfile.mkdtemp()
        self.saved = os.environ.get("XDG_DATA_HOME")
        os.environ["XDG_DATA_HOME"] = os.path.join(self.tmp, "home/.local/share")

    def tearDown(self):
        if self.saved is None:
            os.environ.pop("XDG_DATA_HOME", None)
        else:
            os.environ["XDG_DATA_HOME"] = self.saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_python_app_archives_installs_and_uninstalls(self):
        root = proj.create_project(self.tmp, "python-app", "Weather Now", "Acme", "com.acme", True, False)
        proj.save_meta(root, {"category": "Utility", "comment": "Rain or shine", "capabilities": ["network", "pictures"]})
        info = self.a.stage(root, out=lambda _: None)
        self.assertEqual(info.app_id, "com.acme.Weather_Now")
        launcher = info.stage / "bin/weather-now"
        self.assertIn('python3 "$here/../share/weather-now/main.py"', launcher.read_text())
        self.assertTrue(os.access(launcher, os.X_OK))
        self.assertFalse((info.stage / "share/weather-now/tests").exists())
        self.assertIn("<svg", (info.stage / "share/icons/hicolor/scalable/apps/com.acme.Weather_Now.svg").read_text())
        self.assertIn("<summary>Rain or shine</summary>", (info.stage / "share/metainfo/com.acme.Weather_Now.metainfo.xml").read_text())

        self.a.install(root, out=lambda _: None)
        local = pathlib.Path(self.tmp) / "home/.local"
        entry = (local / "share/applications/com.acme.Weather_Now.desktop").read_text()
        self.assertIn(f"Exec={local}/bin/weather-now", entry)
        self.assertIn("Comment=Rain or shine", entry)
        self.assertTrue(self.a.archive_summary(root)["installed"])
        self.a.uninstall(info.app_id, out=lambda _: None)
        self.assertFalse((local / "bin/weather-now").exists())
        self.assertFalse((local / "share/weather-now").exists())
        self.assertFalse(self.a.archive_summary(root)["installed"])

        manifest = json.loads(pathlib.Path(self.a.flatpak(root, out=lambda _: None)["path"], "com.acme.Weather_Now.json").read_text())
        self.assertEqual(manifest["id"], "com.acme.Weather_Now")
        self.assertIn("--share=network", manifest["finish-args"])
        self.assertIn("--filesystem=xdg-pictures", manifest["finish-args"])
        self.assertNotIn("--filesystem=home", manifest["finish-args"])
        pkg = (pathlib.Path(self.a.pkgbuild(root, out=lambda _: None)["path"]) / "PKGBUILD").read_text()
        self.assertIn("depends=('python' 'python-gobject' 'gtk4' 'libadwaita')", pkg)
        self.assertIn("pkgdesc='Rain or shine'", pkg)
        with tarfile.open(self.a.tarball(root, out=lambda _: None)["path"]) as tar:
            names = tar.getnames()
        self.assertIn("weather-now-1.0/install.sh", names)
        self.assertIn("weather-now-1.0/bin/weather-now", names)

    def test_golden_gate_apps_bring_their_ui_and_skip_flatpak(self):
        import lcode_design
        root = proj.create_project(self.tmp, "gg-app", "Tally", "", "org.example", True, False, options={"style": "window"})
        lcode_design.build(root, release=True, out=lambda _: None)
        info = self.a.stage(root, out=lambda _: None)
        ui = info.stage / "share/tally/ui"
        self.assertTrue(ui.is_dir() and not ui.is_symlink())
        self.assertTrue((ui / "kit/Box.qml").is_file())
        self.assertIn('qs -n -p "$here/../share/tally/App.qml"', (info.stage / "bin/tally").read_text())
        with self.assertRaises(RuntimeError):
            self.a.flatpak(root, out=lambda _: None)
        self.assertIn("depends=('quickshell' 'qt6-svg')", (pathlib.Path(self.a.pkgbuild(root, out=lambda _: None)["path"]) / "PKGBUILD").read_text())

    def test_icons_follow_the_golden_gate_style(self):
        import lcode_icon
        icon = lcode_icon.default_icon("python", "#ff9f0a")
        light, dark = lcode_icon.render(icon), lcode_icon.render(icon, dark=True)
        self.assertIn('stop-color="#ff9f0a"', light)
        self.assertIn('stop-color="#161618"', dark)            # graphite body…
        self.assertIn('stroke="#ff9f0a"', dark)                # …and the glyph in the icon's colour
        self.assertNotIn("<script", lcode_icon.render({"glyph": {"kind": "text", "value": "<script>"}}))


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

    def test_pairs_close_and_step_over(self):
        self.js("text = 'x\\n'; editor.cursorPosition = 1")
        self.assertTrue(self.js("typePair('(')"))
        self.assertEqual(self.text(), "x()\n")
        self.assertEqual(self.js("editor.cursorPosition"), 2)
        self.assertTrue(self.js("typePair(')')"))
        self.assertEqual((self.text(), self.js("editor.cursorPosition")), ("x()\n", 3))
        self.js("editor.cursorPosition = 2")
        self.assertTrue(self.js("deletePair()"))
        self.assertEqual(self.text(), "x\n")
        # Quotes don't pair after a letter; a selection gets wrapped.
        self.assertFalse(self.js("typePair('\"')"))
        self.js("editor.select(0, 1)")
        self.assertTrue(self.js("typePair('[')"))
        self.assertEqual(self.text(), "[x]\n")

    def test_tidy_whitespace_on_save(self):
        self.js("text = 'a  \\nb\\t\\n  c  '; editor.cursorPosition = 0")
        self.js("trimTrailingWhitespace()")
        self.js("ensureFinalNewline()")
        self.assertEqual(self.text(), "a  \nb\n  c\n")       # the cursor's line is left alone

    def test_placeholders_and_theme(self):
        self.js("text = 'for <#item#> in <#items#> {}'; editor.cursorPosition = 0")
        self.assertTrue(self.js("hasPlaceholders"))
        self.assertTrue(self.js("selectPlaceholder(false)"))
        self.assertEqual(self.js("editor.selectedText"), "<#item#>")
        self.js("selectPlaceholder(false)")
        self.assertEqual(self.js("editor.selectedText"), "<#items#>")
        self.js("selectPlaceholder(false)")
        self.assertEqual(self.js("editor.selectedText"), "<#item#>")
        self.js("colors = { background: '#102030', plain: '#ffffff', dark: true }")
        self.assertEqual(self.js("String(background)"), "#102030")
        self.assertTrue(self.js("darkColors"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
