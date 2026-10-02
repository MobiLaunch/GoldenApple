#!/usr/bin/env python3
"""Golden Gate Web: Safari-inspired Qt Quick chrome over Chromium."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys

from PySide6.QtCore import QCoreApplication, QLockFile, QStandardPaths, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWebEngineQuick import QtWebEngineQuick

from backend import BrowserBackend
from model import address_url


def normalized_launch_values(values):
    result = []
    for value in values:
        if value == "--private":
            continue
        try:
            result.append(address_url(value))
        except ValueError:
            pass
    return result


def handoff_to_existing(values):
    socket = QLocalSocket()
    socket.connectToServer("goldengate-web-" + str(os.getuid()))
    if not socket.waitForConnected(1500):
        return False
    socket.write((json.dumps(values or ["about:blank"]) + "\n").encode())
    socket.waitForBytesWritten(1500)
    socket.disconnectFromServer()
    return True


def main():
    if os.geteuid() == 0:
        sys.exit("Run Web as your desktop user, not root. Chromium sandboxing remains enabled.")

    QCoreApplication.setApplicationName("GoldenGateWeb")
    QCoreApplication.setApplicationVersion("0.2")
    QtWebEngineQuick.initialize()

    app = QGuiApplication(sys.argv)
    app.setApplicationDisplayName("Web")
    app.setDesktopFileName("org.goldengate.Web")
    app.setQuitOnLastWindowClosed(True)

    private = "--private" in sys.argv
    launch_values = normalized_launch_values(sys.argv[1:])

    data_dir = Path(QStandardPaths.writableLocation(QStandardPaths.AppDataLocation))
    data_dir.mkdir(parents=True, exist_ok=True, mode=0o700)

    lock = None
    if not private:
        lock = QLockFile(str(data_dir / "browser.lock"))
        lock.setStaleLockTime(0)
        if not lock.tryLock(0):
            if handoff_to_existing(launch_values):
                return 0
            sys.stderr.write("Golden Gate Web is already running but could not receive this request.\n")
            return 1

    backend = BrowserBackend(private=private, launch_values=launch_values)
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("BrowserBackend", backend)

    qml = Path(__file__).with_name("Browser.qml")
    engine.load(QUrl.fromLocalFile(str(qml)))
    if not engine.rootObjects():
        sys.stderr.write("Golden Gate Web could not load its QML interface.\n")
        return 2

    server = None
    sockets = set()
    if not private:
        server = QLocalServer(app)
        name = "goldengate-web-" + str(os.getuid())
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
                            try:
                                valid.append(address_url(value))
                            except ValueError:
                                pass
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
