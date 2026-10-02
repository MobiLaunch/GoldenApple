#!/usr/bin/env python3
"""Golden Gate Web QML launcher.

Chromium/Qt WebEngine stays in its own process, while all visible browser chrome
is Qt Quick so it can share Golden Gate's motion, typography, symbols and glass.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

from PySide6.QtCore import QLockFile, QObject, QTimer, QUrl, Signal
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWebEngineQuick import QtWebEngineQuick

from backend import BrowserBackend
from model import address_url


def send_to_existing(values: list[str]) -> bool:
    socket = QLocalSocket()
    socket.connectToServer(f"goldengate-web-{os.getuid()}")
    if not socket.waitForConnected(1200):
        return False
    socket.write((json.dumps(values or ["about:blank"]) + "\n").encode())
    socket.waitForBytesWritten(1200)
    socket.disconnectFromServer()
    return True


def main() -> int:
    if os.geteuid() == 0:
        print("Run Web as your desktop user, not root. Chromium sandboxing remains enabled.", file=sys.stderr)
        return 1

    private = "--private" in sys.argv
    values = [v for v in sys.argv[1:] if v != "--private"]

    # Qt WebEngine Quick must initialize before QGuiApplication creates any
    # platform/OpenGL context.
    QtWebEngineQuick.initialize()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("GoldenGateWeb")
    app.setOrganizationName("Golden Gate")
    app.setDesktopFileName("org.goldengate.Web")

    data_dir = Path.home() / ".local/share/GoldenGateWeb"
    data_dir.mkdir(parents=True, exist_ok=True, mode=0o700)

    lock = None
    server = None
    backend = BrowserBackend(private=private, launch_values=values)

    if not private:
        lock = QLockFile(str(data_dir / "browser.lock"))
        if not lock.tryLock(0):
            if send_to_existing(values):
                return 0
            print("Web is already starting or closing. Try again in a moment.", file=sys.stderr)
            return 1

        server = QLocalServer(app)
        name = f"goldengate-web-{os.getuid()}"
        QLocalServer.removeServer(name)
        server.setSocketOptions(QLocalServer.UserAccessOption)
        if server.listen(name):
            def connected():
                socket = server.nextPendingConnection()

                def read():
                    while socket.canReadLine():
                        try:
                            incoming = json.loads(bytes(socket.readLine()).decode())
                        except (UnicodeDecodeError, json.JSONDecodeError):
                            continue
                        if not isinstance(incoming, list):
                            continue
                        for value in incoming[:30]:
                            if not isinstance(value, str):
                                continue
                            try:
                                backend.externalUrlRequested.emit(address_url(value))
                            except ValueError:
                                pass
                    socket.disconnectFromServer()

                socket.readyRead.connect(read)
                socket.disconnected.connect(socket.deleteLater)
                read()

            server.newConnection.connect(connected)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    qml = Path(__file__).with_name("WebWindow.qml")
    engine.load(QUrl.fromLocalFile(str(qml)))

    if not engine.rootObjects():
        return 2

    # Keep Python-owned objects referenced for the full event loop.
    app._gg_backend = backend
    app._gg_lock = lock
    app._gg_server = server
    app._gg_engine = engine
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
