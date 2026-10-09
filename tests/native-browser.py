#!/usr/bin/env python3
"""Exercise the production QML/Chromium browser path under Xvfb.

These tests intentionally launch apps/browser/browser.py itself. That catches
QML import/creation failures, Qt WebEngine initialization mistakes, profile
startup failures and single-instance handoff regressions that unit tests of the
state model cannot see.
"""
from __future__ import annotations

import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BROWSER = ROOT / "apps/browser/browser.py"


COOKIES_SEEN = []


REQUESTS = []
REPORTS = []

# Pages for the navigation and password tests.
PAGES = {
    # Signs in by itself, as a person typing and pressing Sign In would.
    "/signin": '<title>Sign In</title><form method="post" action="/session">'
               '<input name="email" type="email"><input name="pass" type="password"><button>Sign In</button></form>'
               '<script>setTimeout(() => { document.forms[0].email.value = "ada@example.com";'
               'document.forms[0].pass.value = "correct horse"; document.querySelector("button").click() }, 600)</script>',
    # Reports what Web filled in.
    "/signin-again": '<title>Sign In</title><form><input name="email" type="email"><input name="pass" type="password"></form>'
                     '<script>setTimeout(() => fetch("/report?u=" + encodeURIComponent(document.forms[0].email.value)'
                     '+ "&p=" + encodeURIComponent(document.forms[0].pass.value)), 1200)</script>',
    # A web app that changes its own address, as YouTube or Gmail do.
    "/app": '<title>App</title><script>setTimeout(() => history.pushState({}, "", "/app/inbox"), 300);'
            'setTimeout(() => history.pushState({}, "", "/app/settings"), 600)</script>',
}


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        REQUESTS.append(("POST", self.path))
        self.send_response(303)
        self.send_header("Location", "/welcome")
        self.end_headers()

    def do_GET(self):
        COOKIES_SEEN.append((self.path, self.headers.get("Cookie") or ""))
        REQUESTS.append(("GET", self.path))
        if self.path.startswith("/report?"):
            REPORTS.append(self.path)
        if self.path == "/moved":
            self.send_response(302)
            self.send_header("Location", "/app")
            self.end_headers()
            return
        if self.path in PAGES:
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(PAGES[self.path].encode())
            return
        page = (
            f"<title>Fixture {self.path}</title>"
            '<article><h1>Reader Test</h1><p>CitronOS browser fixture content.</p></article>'
            '<a href="/second">Second page</a>'
        )
        self.send_response(200)
        if self.path.startswith("/login"):  # /login-a, /login-term
            # A site's login: one cookie for the browser session only, one kept for a day.
            self.send_header("Set-Cookie", "session=signed-in; Path=/; HttpOnly")
            self.send_header("Set-Cookie", "remember=yes; Path=/; Max-Age=86400")
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        try:
            self.wfile.write(page.encode())
        except BrokenPipeError:
            pass

    def log_message(self, *_):
        pass


SERVER = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
threading.Thread(target=SERVER.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{SERVER.server_port}"


def browser_env(root: Path, exit_ms=1700):
    home = root / "home"
    data = root / "data"
    cache = root / "cache"
    downloads = root / "downloads"
    run = root / "run"
    for path in (home, data, cache, downloads, run):
        path.mkdir(parents=True, exist_ok=True)
    run.chmod(0o700)
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        # Its own runtime dir: on CI runners the real one can hold another
        # session's keyring, which `gnome-keyring-daemon --start` joins.
        "XDG_RUNTIME_DIR": str(run),
        "XDG_DATA_HOME": str(data),
        "XDG_CACHE_HOME": str(cache),
        "XDG_DOWNLOAD_DIR": str(downloads),
        "QT_QPA_PLATFORM": env.get("QT_QPA_PLATFORM", "xcb"),
        "QTWEBENGINE_CHROMIUM_FLAGS": (env.get("QTWEBENGINE_CHROMIUM_FLAGS", "") + " --disable-gpu").strip(),
        "GG_WEB_TEST_EXIT_MS": str(exit_ms),
    })
    return env


def children(pid: int) -> list[int]:
    found = []
    for task in Path(f"/proc/{pid}/task").glob("*"):
        try:
            kids = [int(k) for k in (task / "children").read_text().split()]
        except OSError:
            continue
        for kid in kids:
            found += [kid, *children(kid)]
    return found


def state_files(root: Path):
    return list(root.rglob("state.json"))


class NativeQmlBrowser(unittest.TestCase):
    def run_browser(self, tmp: Path, *args, exit_ms=1700, timeout=12):
        env = browser_env(tmp, exit_ms)
        return subprocess.run(
            [sys.executable, str(BROWSER), *args],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )

    def run_until(self, cmd, env, done, wait=40):
        """Run Web until `done()` holds, then quit it as logging out does.

        A fixed exit timer raced Chromium's cold start: on a slow machine Web
        quit before the page had signed in, and the test failed at random.
        """
        web = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + wait
            while time.monotonic() < deadline and not done():
                time.sleep(0.2)
            reached = done()
            time.sleep(0.8)  # let the page settle, as a person would before quitting
            # SIGTERM reaches Web itself, also under dbus-run-session.
            for pid in [web.pid, *children(web.pid)]:
                try:
                    argv = Path(f"/proc/{pid}/cmdline").read_text(errors="replace").split("\0")
                except OSError:
                    continue
                if len(argv) > 1 and argv[1] == str(BROWSER):
                    os.kill(pid, signal.SIGTERM)
            out, err = web.communicate(timeout=30)
        finally:
            if web.poll() is None:
                web.kill()
        self.assertTrue(reached, "Web never got there:\n" + "\n".join(err.splitlines()[-25:]))
        return subprocess.CompletedProcess(cmd, web.returncode, out, err)

    def test_qml_chromium_starts_and_persists_session(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_browser(root, BASE + "/first")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("could not load its QML interface", result.stderr)
            self.assertNotIn("QQmlApplicationEngine failed", result.stderr)

            files = state_files(root)
            self.assertEqual(len(files), 1, [str(p) for p in files])
            state = json.loads(files[0].read_text())
            self.assertIn(BASE + "/first", state["tabs"])

    def test_starts_when_pyside_webengine_binding_wont_load(self):
        # Arch shipped PySide6 built against a newer Qt WebEngine than its
        # qt6-webengine ("could not import module 'PySide6.QtWebEngineCore'",
        # an undefined symbol) and Web didn't start at all. Its pages are
        # Qt's own QML module, so Web starts Qt WebEngine itself and loads
        # pages, only without tracker blocking.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            broken = root / "broken"
            broken.mkdir()
            (broken / "sitecustomize.py").write_text(
                "import sys\n"
                "class Broken:\n"
                "    def find_spec(self, name, path=None, target=None):\n"
                "        if name.startswith('PySide6.QtWebEngine'):\n"
                "            raise ImportError(\"libshiboken: could not import module '%s'\" % name)\n"
                "sys.meta_path.insert(0, Broken())\n")
            env = browser_env(root, 0)
            env["PYTHONPATH"] = str(broken) + os.pathsep + env.get("PYTHONPATH", "")
            result = self.run_until([sys.executable, str(BROWSER), BASE + "/no-binding"], env,
                                    lambda: any(p == "/no-binding" for p, _ in COOKIES_SEEN))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("without PySide6's WebEngine binding", result.stderr)
            self.assertNotIn("WEB-CANT-START", result.stderr)

    def test_logins_survive_closing_web(self):
        # Closing Web used to sign you out of every site: from Qt 6.9 the QML
        # profile stayed in memory and no cookie ever reached the disk.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # Long enough for a cold Chromium start to reach the page.
            first = self.run_until([sys.executable, str(BROWSER), BASE + "/login-a"], browser_env(root, 0),
                                   lambda: any(p == "/login-a" for p, _ in COOKIES_SEEN))
            self.assertEqual(first.returncode, 0, first.stderr)
            again = self.run_until([sys.executable, str(BROWSER), BASE + "/check-a"], browser_env(root, 0),
                                   lambda: any(p == "/check-a" for p, _ in COOKIES_SEEN))
            self.assertEqual(again.returncode, 0, again.stderr)
            sent = [cookie for path, cookie in COOKIES_SEEN if path == "/check-a"]
            self.assertTrue(sent, COOKIES_SEEN)
            self.assertIn("session=signed-in", sent[0])
            self.assertIn("remember=yes", sent[0])
            self.assertTrue(list(root.rglob("Cookies")), "no cookie store on disk")

    def test_pages_load_once(self):
        # Each tab's view was bound to the address it reported: a redirect,
        # a signed-in form's result or a web app changing its own address
        # loaded the page again, and web apps reloaded themselves forever.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            REQUESTS.clear()
            for start in ("/moved", "/signin"):
                result = self.run_browser(root, BASE + start, exit_ms=3500, timeout=40)
                self.assertEqual(result.returncode, 0, result.stderr)
            pages = [r for r in REQUESTS if r[1] != "/favicon.ico"]
            self.assertEqual(pages.count(("GET", "/app")), 1, pages)
            self.assertNotIn(("GET", "/app/inbox"), pages)
            self.assertNotIn(("GET", "/app/settings"), pages)
            self.assertEqual(pages.count(("POST", "/session")), 1, pages)
            self.assertEqual(pages.count(("GET", "/welcome")), 1, pages)

    @unittest.skipUnless(shutil.which("secret-tool") and shutil.which("gnome-keyring-daemon") and shutil.which("dbus-run-session"),
                         "needs libsecret, gnome-keyring and dbus")
    def test_passwords_are_saved_and_filled(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # An open login keyring, as the live ISO and a signed-in session have.
            rings = root / "data/keyrings"
            rings.mkdir(parents=True)
            (rings / "login.keyring").write_text("[keyring]\ndisplay-name=Login\nctime=0\nmtime=0\nlock-on-idle=false\nlock-after=false\n")
            (rings / "default").write_text("login")

            def saved():
                return "org.goldengate.Web" in "".join(p.read_text(errors="replace") for p in rings.glob("*.keyring"))

            def run(url, done):
                env = browser_env(root, 0)
                env["GG_WEB_TEST_ACCEPT_PASSWORDS"] = "1"
                return self.run_until(
                    ["dbus-run-session", "--", "sh", "-c",
                     'gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1; exec "$0" "$@"',
                     sys.executable, str(BROWSER), url], env, done)

            REPORTS.clear()
            first = run(BASE + "/signin", saved)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertTrue(saved(), "the password never reached the keyring")
            again = run(BASE + "/signin-again", lambda: bool(REPORTS))
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(REPORTS, ["/report?u=ada%40example.com&p=correct%20horse"], REPORTS)

    def test_quitting_by_signal_keeps_tabs_and_logins(self):
        # Logging out or shutting down ends Web with SIGTERM.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = browser_env(root, 0)
            web = subprocess.Popen([sys.executable, str(BROWSER), BASE + "/login-term"], cwd=ROOT, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline and not any(p == "/login-term" for p, _ in COOKIES_SEEN):
                    time.sleep(0.2)
                time.sleep(1.0)
                web.send_signal(signal.SIGTERM)
                _, err = web.communicate(timeout=20)
            finally:
                if web.poll() is None:
                    web.kill()
            self.assertEqual(web.returncode, 0, err)
            tabs = json.loads(state_files(root)[0].read_text())["tabs"]
            self.assertIn(BASE + "/login-term", tabs)
            again = self.run_browser(root, BASE + "/check-term", exit_ms=2500, timeout=30)
            self.assertEqual(again.returncode, 0, again.stderr)
            sent = [cookie for path, cookie in COOKIES_SEEN if path == "/check-term"]
            self.assertTrue(sent and "session=signed-in" in sent[0], COOKIES_SEEN[-4:])

    def test_private_window_is_off_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_browser(root, "--private", BASE + "/login-private")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state_files(root), [])
            self.assertEqual(list(root.rglob("Cookies")), [])

    def test_named_profile_uses_isolated_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            personal = self.run_browser(root, BASE + "/personal")
            self.assertEqual(personal.returncode, 0, personal.stderr)
            work = self.run_browser(root, "--profile", "Work", BASE + "/work")
            self.assertEqual(work.returncode, 0, work.stderr)

            files = sorted(state_files(root))
            self.assertEqual(len(files), 2, [str(p) for p in files])
            states = [json.loads(path.read_text()) for path in files]
            tab_sets = [set(state["tabs"]) for state in states]
            self.assertTrue(any(BASE + "/personal" in tabs for tabs in tab_sets))
            self.assertTrue(any(BASE + "/work" in tabs for tabs in tab_sets))
            self.assertFalse(any(
                BASE + "/personal" in tabs and BASE + "/work" in tabs
                for tabs in tab_sets
            ))

    def test_second_launch_hands_url_to_existing_window(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = browser_env(root, 0)
            seconds = []

            def handed_over():
                # Once the first window shows its page it is listening for
                # other launches (it listens before loading). A second launch
                # before then would become a browser of its own.
                if not any(p == "/handoff-first" for p, _ in COOKIES_SEEN):
                    return False
                if not seconds:
                    seconds.append(subprocess.run([sys.executable, str(BROWSER), BASE + "/handoff-second"], cwd=ROOT, env=env,
                                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30))
                return any(p == "/handoff-second" for p, _ in COOKIES_SEEN)

            first = self.run_until([sys.executable, str(BROWSER), BASE + "/handoff-first"], env, handed_over)
            self.assertEqual(seconds[0].returncode, 0, seconds[0].stderr)
            self.assertEqual(first.returncode, 0, first.stderr)

            files = state_files(root)
            self.assertEqual(len(files), 1, [str(p) for p in files])
            tabs = json.loads(files[0].read_text())["tabs"]
            self.assertIn(BASE + "/handoff-first", tabs)
            self.assertIn(BASE + "/handoff-second", tabs)

    def test_no_crash_prone_patterns(self):
        """Two ways Web used to be able to crash mid-use."""
        import re
        qml = (ROOT / "apps/browser/Browser.qml").read_text()
        # A new-window request is deleted once its handler returns: it's
        # opened at once, not later.
        body = qml.split("function requestNewWindow(request) {", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("request.openIn(", body)
        code = "\n".join(l for l in body.splitlines() if not l.strip().startswith("//"))
        self.assertNotIn("callLater", code)
        # Signals from the keyring's threads reach QML on the main thread.
        backend = (ROOT / "apps/browser/backend.py").read_text()
        section = backend.split("def _keyring(self):", 1)[1].split("def createProfile(self", 1)[0]
        direct = [m for m in re.findall(r"self\.(\w+)\.emit\(", section) if m not in ("_copyRequested", "_mainCall")]
        self.assertEqual(direct, [], "keyring code emits only through _post")

    def test_production_path_is_qml_not_qtwidgets(self):
        launcher = (ROOT / "apps/browser/browser.py").read_text()
        qml = (ROOT / "apps/browser/Browser.qml").read_text()
        shell = (ROOT / "apps/browser/launch.sh").read_text()
        self.assertIn("webengine.initialize()", launcher)
        self.assertIn("QtWebEngineQuick.initialize", (ROOT / "apps/browser/webengine.py").read_text())
        self.assertIn("QQmlApplicationEngine", launcher)
        self.assertNotIn("QtWidgets", launcher)
        self.assertIn("WebEngineView", qml)
        self.assertIn("Search or enter website name", qml)
        self.assertIn("Reading List", qml)
        self.assertIn("TAB GROUPS", qml)
        self.assertIn("Save Tabs as Group", qml)
        self.assertIn("Profiles", qml)
        self.assertIn("Search Engine", qml)
        self.assertIn("Separate", qml)
        self.assertIn("Compact", qml)
        self.assertIn("Tab Overview", qml)
        self.assertIn("Website Settings", qml)
        self.assertIn("listAllPermissions", qml)
        self.assertIn("DragHandler", qml)
        self.assertIn("tabGroupsManager", qml)
        self.assertIn("Privacy Report", qml)
        self.assertIn("DragHandler", qml)
        self.assertIn("tabGroupsManager", qml)
        self.assertIn("Privacy Report", qml)
        self.assertIn("DuckDuckGo", qml)
        self.assertIn("Brave", qml)
        self.assertIn("browser.py", shell)
        self.assertFalse((ROOT / "apps/browser/ui.py").exists())


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        SERVER.shutdown()
