#!/usr/bin/env python3
"""Golden Gate Web: Safari-inspired Qt Quick chrome over Chromium."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

from PySide6.QtCore import QCoreApplication, QLockFile, QStandardPaths, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWebEngineQuick import QtWebEngineQuick

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


def instance_name(profile):
    key = profile_key(profile)
    base = "goldengate-web-" + str(os.getuid())
    return base if key == "personal" else base + "-" + key


def handoff_to_existing(values, profile):
    socket = QLocalSocket()
    socket.connectToServer(instance_name(profile))
    if not socket.waitForConnected(1500):
        return False
    socket.write((json.dumps(values or ["about:blank"]) + "\n").encode())
    socket.waitForBytesWritten(1500)
    socket.disconnectFromServer()
    return True


def main():
    if os.geteuid() == 0:
        sys.exit("Run Web as your desktop user, not root. Chromium sandboxing remains enabled.")

    QCoreApplication.setOrganizationName("Golden Gate")
    QCoreApplication.setApplicationName("GoldenGateWeb")
    QCoreApplication.setApplicationVersion("0.2")
    QtWebEngineQuick.initialize()

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
            if handoff_to_existing(launch_values, profile_name):
                return 0
            sys.stderr.write("This Golden Gate Web profile is already running but could not receive this request.\n")
            return 1
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("BrowserBackend", backend)

    qml = Path(__file__).with_name("Browser.qml")
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        sys.stderr.write("Golden Gate Web could not load its QML interface.\n")
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

    server = None
    sockets = set()
    if not private:
        server = QLocalServer(app)
        name = instance_name(profile_name)
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

    code = app.exec()
    if lock is not None:
        lock.unlock()
    return code


if __name__ == "__main__":
    sys.exit(main())
