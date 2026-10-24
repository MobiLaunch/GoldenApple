#!/usr/bin/env python3
"""CitronOS Web: Safari-inspired Qt Quick chrome over Chromium."""
from __future__ import annotations

import faulthandler
# Enable tracing before importing Qt's native modules: import-time segfaults
# happen before main(), where enabling it would be too late.
faulthandler.enable(all_threads=True)
import hashlib
import json
import os
from pathlib import Path
import signal
import sys

def cant_start(exc: BaseException) -> None:
    """Qt couldn't be loaded: say why and what fixes it (launch.sh shows the
    first line, exit 3). PySide only says "could not import module …"."""
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from diagnose import diagnose
    print(f"{exc.__class__.__name__}: {exc}", file=sys.stderr)
    summary, details = diagnose()
    print("WEB-CANT-START: " + summary, file=sys.stderr)
    for line in details:
        print("  " + line, file=sys.stderr)
    raise SystemExit(3)


try:
    from PySide6.QtCore import QCoreApplication, QLockFile, QTimer, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtNetwork import QLocalServer, QLocalSocket
    from PySide6.QtQml import QQmlApplicationEngine
except ImportError as exc:
    cant_start(exc)

import webengine

from backend import BrowserBackend, profile_key


def parse_arguments(values):
    private = False
    profile = "Personal"
    launch = []
    i = 0
    while i < len(values):
        value = values[i]
        if value == "--private":
            private = True
        elif value == "--profile" and i + 1 < len(values):
            i += 1
            profile = values[i].strip()[:60] or "Personal"
        else:
            launch.append(value)
        i += 1
    return private, profile, launch


def instance_name(profile, data_dir):
    # One instance per profile data directory, the same scope as the lock: a
    # Web on another data directory (another XDG_DATA_HOME) is a different
    # instance, and its exit must not remove this one's socket.
    key = profile_key(profile)
    place = hashlib.sha1(str(Path(data_dir).resolve()).encode()).hexdigest()[:10]
    return "goldengate-web-" + str(os.getuid()) + "-" + key + "-" + place


def handoff_to_existing(values, profile, data_dir):
    socket = QLocalSocket()
    socket.connectToServer(instance_name(profile, data_dir))
    if not socket.waitForConnected(1500):
        return False
    socket.write((json.dumps(values or ["about:blank"]) + "\n").encode())
    socket.waitForBytesWritten(1500)
    socket.disconnectFromServer()
    return True


def main():
    if os.geteuid() == 0:
        sys.exit("Run Web as your desktop user, not root. Chromium sandboxing remains enabled.")

    # Keeps its old name: Qt files the profile (history, logins) under it.
    QCoreApplication.setOrganizationName("Golden Gate")
    QCoreApplication.setApplicationName("GoldenGateWeb")
    QCoreApplication.setApplicationVersion("0.2")
    # PySide6's WebEngine binding when it loads; Qt's own start-up call when
    # Arch has Qt and PySide6 out of step (tracker blocking is off then).
    try:
        bindings = webengine.initialize()
    except webengine.Unavailable as exc:
        cant_start(exc)
    if not bindings:
        print("Qt WebEngine started without PySide6's WebEngine binding (it doesn't load with this Qt); "
              "tracker blocking is off until PySide6 is updated.", file=sys.stderr)

    app = QGuiApplication(sys.argv)
    app.setApplicationDisplayName("Web")
    app.setDesktopFileName("org.goldengate.Web")
    app.setQuitOnLastWindowClosed(True)

    private, profile_name, launch_args = parse_arguments(sys.argv[1:])

    # Load the selected profile before resolving command-line search text so its
    # search-engine preference applies to desktop/CLI launches as well.
    backend = BrowserBackend(
        private=private,
        launch_values=[],
        profile_name=profile_name,
    )
    launch_values = []
    for value in launch_args[:30]:
        resolved = backend.resolveAddress(value)
        if resolved:
            launch_values.append(resolved)
    backend.launch_values = launch_values

    lock = None
    if not private:
        profile_data = Path(backend.dataDir)
        profile_data.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock = QLockFile(str(profile_data / "browser.lock"))
        lock.setStaleLockTime(0)
        if not lock.tryLock(0):
            if handoff_to_existing(launch_values, profile_name, backend.dataDir):
                return 0
            sys.stderr.write("This CitronOS Web profile is already running but could not receive this request.\n")
            return 1
    # Listen as soon as this process owns the profile, before the slow QML and
    # Chromium start-up: a second launch in that window would otherwise find
    # the lock taken and nobody to hand its URLs to. Requests queue until the
    # event loop runs, by which time the window exists to receive them.
    server = None
    sockets = set()
    if not private:
        server = QLocalServer(app)
        name = instance_name(profile_name, backend.dataDir)
        QLocalServer.removeServer(name)
        server.setSocketOptions(QLocalServer.UserAccessOption)
        if server.listen(name):
            def connected():
                socket = server.nextPendingConnection()
                if socket is None:
                    return
                sockets.add(socket)

                def read():
                    while socket.canReadLine():
                        try:
                            values = json.loads(bytes(socket.readLine()).decode())
                        except (UnicodeDecodeError, ValueError, TypeError):
                            continue
                        if not isinstance(values, list):
                            continue
                        valid = []
                        for value in values[:30]:
                            if not isinstance(value, str):
                                continue
                            resolved = backend.resolveAddress(value)
                            if resolved:
                                valid.append(resolved)
                        backend.externalUrls.emit(json.dumps(valid or ["about:blank"]))

                def gone():
                    sockets.discard(socket)
                    socket.deleteLater()

                socket.readyRead.connect(read)
                socket.disconnected.connect(gone)
                read()

            server.newConnection.connect(connected)

    engine = QQmlApplicationEngine()
    qml_warnings = []

    def report_qml_warnings(warnings):
        for warning in warnings:
            detail = warning.toString()
            qml_warnings.append(detail)
            sys.stderr.write("Web QML: " + detail + "\n")

    engine.warnings.connect(report_qml_warnings)
    engine.rootContext().setContextProperty("BrowserBackend", backend)

    qml = Path(__file__).with_name("Browser.qml")
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        from diagnose import qml_failure
        sys.stderr.write("CitronOS Web could not load its QML interface.\n")
        sys.stderr.write("WEB-CANT-START: " + qml_failure(qml_warnings) + "\n")
        return 2

    # CI/test-only timed exit. Production never sets this environment variable.
    # Keeping the hook in the launcher lets tests exercise the exact QML +
    # Chromium startup path instead of a separate fake window.
    try:
        test_exit_ms = int(os.environ.get("GG_WEB_TEST_EXIT_MS", "0"))
    except ValueError:
        test_exit_ms = 0
    if test_exit_ms > 0:
        QTimer.singleShot(test_exit_ms, app.quit)


    # Log out, shutdown and `kill` end Web with a signal. Python would stop
    # on the spot, before the open tabs and the last cookies are written;
    # quit through Qt instead, as closing the window does. The timer lets
    # Python run its signal handlers while Qt's loop is waiting.
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, lambda *_: app.quit())
    heartbeat = QTimer()
    heartbeat.start(250)
    heartbeat.timeout.connect(lambda: None)

    code = app.exec()
    # Close the window and its pages, then the profile, while the application
    # still exists: Chromium writes the cookie store and site data to disk as
    # the profile goes. Left to Python's exit, the order is up to chance.
    heartbeat.stop()
    for window in engine.rootObjects():
        window.close()
    del engine
    app.processEvents()
    if lock is not None:
        lock.unlock()
    return code


if __name__ == "__main__":
    sys.exit(main())
