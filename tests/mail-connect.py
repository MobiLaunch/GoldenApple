#!/usr/bin/env python3
"""Mail's account setup against local IMAP and SMTP servers over TLS.

A wrong Gmail password says an app password is needed (not the server's raw
"[AUTHENTICATIONFAILED]"); an unknown server, a refused port and a server
that never answers each say so in words; a port and SSL/TLS choice that
disagree (993 with STARTTLS) still connects; both servers are checked before
the account is kept; the inbox lists what the server has; and the setup
screen shows the error under Connect, and that it's connecting."""
from __future__ import annotations

import base64
import json
import os
import pathlib
import socket
import ssl
import subprocess
import sys
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/mail/helper.py"
GOOD = "abcdefghijklmnop"
failures: list[str] = []


def check(ok: bool, what: str) -> None:
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


def serve(port_holder: list[int], handler, context: ssl.SSLContext | None) -> None:
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", 0))
    srv.listen(8)
    port_holder.append(srv.getsockname()[1])

    def loop() -> None:
        while True:
            conn, _ = srv.accept()
            threading.Thread(target=lambda c=conn: run(c), daemon=True).start()

    def run(conn: socket.socket) -> None:
        try:
            if context:
                conn = context.wrap_socket(conn, server_side=True)
            handler(conn.makefile("rwb", buffering=0))
        except Exception:
            pass
        finally:
            conn.close()

    threading.Thread(target=loop, daemon=True).start()


def imap(f) -> None:
    f.write(b"* OK fake IMAP ready\r\n")
    while True:
        line = f.readline()
        if not line:
            return
        tag, _, rest = line.decode().strip().partition(" ")
        cmd = rest.split(" ")[0].upper()
        if cmd == "CAPABILITY":
            f.write(b"* CAPABILITY IMAP4rev1 AUTH=PLAIN\r\n" + tag.encode() + b" OK done\r\n")
        elif cmd == "LOGIN":
            ok = rest.split(" ")[-1].strip('"') == GOOD
            f.write(tag.encode() + (b" OK logged in\r\n" if ok else b" NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)\r\n"))
        elif cmd in ("SELECT", "EXAMINE"):
            f.write(b"* 1 EXISTS\r\n" + tag.encode() + b" OK [READ-ONLY] selected\r\n")
        elif cmd == "UID" and "SEARCH" in rest.upper():
            f.write(b"* SEARCH 7\r\n" + tag.encode() + b" OK done\r\n")
        elif cmd == "UID" and "FETCH" in rest.upper():
            head = b"Subject: Ferry at six\r\nFrom: Sam <sam@example.com>\r\nDate: Thu, 8 Oct 2026 18:00:00 +0000\r\n\r\n"
            f.write(b"* 1 FETCH (UID 7 FLAGS () BODY[HEADER.FIELDS (SUBJECT FROM DATE)] {" + str(len(head)).encode() + b"}\r\n"
                    + head + b")\r\n" + tag.encode() + b" OK done\r\n")
        elif cmd == "LOGOUT":
            f.write(b"* BYE\r\n" + tag.encode() + b" OK bye\r\n")
            return
        else:
            f.write(tag.encode() + b" BAD unknown\r\n")


def smtp(f) -> None:
    f.write(b"220 fake SMTP ready\r\n")
    while True:
        line = f.readline()
        if not line:
            return
        cmd = line.decode().strip()
        up = cmd.upper()
        if up.startswith(("EHLO", "HELO")):
            f.write(b"250-fake\r\n250 AUTH PLAIN LOGIN\r\n")
        elif up.startswith("AUTH PLAIN"):
            parts = base64.b64decode(cmd.split(" ")[2]).split(b"\0")
            f.write(b"235 ok\r\n" if parts[-1].decode() == GOOD else b"535 5.7.8 Username and Password not accepted\r\n")
        elif up.startswith("QUIT"):
            f.write(b"221 bye\r\n")
            return
        else:
            f.write(b"250 ok\r\n")


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp())
    cert, key = tmp / "cert.pem", tmp / "key.pem"
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2", "-subj", "/CN=localhost",
                    "-addext", "subjectAltName=DNS:localhost", "-keyout", str(key), "-out", str(cert)],
                   check=True, capture_output=True)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    imap_port: list[int] = []
    smtp_port: list[int] = []
    serve(imap_port, imap, context)
    serve(smtp_port, smtp, context)
    # A port that accepts and then says nothing.
    silent = socket.socket()
    silent.bind(("127.0.0.1", 0))
    silent.listen(1)
    closed = socket.socket()
    closed.bind(("127.0.0.1", 0))
    closed_port = closed.getsockname()[1]
    closed.close()

    # The keyring: secret-tool keeping passwords in a file.
    fakebin = tmp / "bin"
    fakebin.mkdir()
    (fakebin / "secret-tool").write_text("#!/bin/sh\nf=\"$FAKE_KEYRING\"\ncase \"$1\" in store) cat > \"$f\";; lookup) cat \"$f\" 2>/dev/null || exit 1;; esac\n")
    (fakebin / "secret-tool").chmod(0o755)
    env = dict(os.environ, SSL_CERT_FILE=str(cert), XDG_CONFIG_HOME=str(tmp / "config"),
               XDG_STATE_HOME=str(tmp / "state"),
               FAKE_KEYRING=str(tmp / "keyring"), PATH=f"{fakebin}:{os.environ['PATH']}")

    def setup(**over: object) -> dict:
        data = {"email": "me@gmail.com", "password": GOOD, "imap_host": "localhost", "imap_port": imap_port[0],
                "imap_security": "ssl", "smtp_host": "localhost", "smtp_port": smtp_port[0], "smtp_security": "ssl", **over}
        p = subprocess.run([sys.executable, str(HELPER), "setup"], input=json.dumps(data), capture_output=True,
                           text=True, env=env, timeout=60)
        return json.loads(p.stdout.strip().splitlines()[-1])

    r = setup(password="my google password")
    check(not r["ok"] and "app password" in r["error"] and "myaccount.google.com/apppasswords" in r["error"],
          f"a wrong Gmail password asks for an app password: {r.get('error')}")
    check(not (tmp / "config/golden-gate/mail.json").exists(), "nothing is kept after a failed setup")

    r = setup(email="me@example.org", password="nope")
    check(not r["ok"] and "turned down the user name or password" in r["error"], f"another provider: {r.get('error')}")

    r = setup(email="me@outlook.com", password="nope")
    check(not r["ok"] and "Microsoft" in r["error"], f"Outlook explains Microsoft's sign-in: {r.get('error')}")

    r = setup(imap_host="no-such-host.invalid")
    check(not r["ok"] and "couldn't find" in r["error"] and "no-such-host.invalid" in r["error"], f"unknown server: {r.get('error')}")

    r = setup(imap_host="127.0.0.1", imap_port=closed_port)
    check(not r["ok"] and "refused" in r["error"], f"refused port: {r.get('error')}")

    r = setup(imap_host="127.0.0.1", imap_port=silent.getsockname()[1], imap_security="ssl")
    check(not r["ok"] and ("didn't answer" in r["error"] or "secure connection" in r["error"]), f"silent server: {r.get('error')}")

    r = setup(smtp_host="no-such-host.invalid")
    check(not r["ok"] and "outgoing" in r["error"], f"a wrong outgoing server is caught at setup: {r.get('error')}")

    r = setup(password="abcd efgh ijkl mnop")
    check(r["ok"], f"an app password pasted with its spaces connects: {r}")
    cfg = json.loads((tmp / "config/golden-gate/mail.json").read_text())
    check(cfg["imap_security"] == "ssl" and cfg["email"] == "me@gmail.com", "the account is kept")

    # The ports say which security they speak (the helper picks SSL for 993).
    from importlib import util
    spec = util.spec_from_file_location("mailhelper", HELPER)
    mod = util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    check(mod.security_for(993, "starttls") == "ssl" and mod.security_for(587, "ssl") == "starttls"
          and mod.security_for(465, "starttls") == "ssl" and mod.security_for(2525, "starttls") == "starttls",
          "port and SSL/TLS choices that disagree are put right")

    p = subprocess.run([sys.executable, str(HELPER), "list"], capture_output=True, text=True, env=env, timeout=60)
    r = json.loads(p.stdout.strip().splitlines()[-1])
    check(r["ok"] and r["messages"] and r["messages"][0]["subject"] == "Ferry at six" and r["messages"][0]["unread"],
          f"the inbox lists the server's messages: {r}")

    qml = (ROOT / "apps/mail.qml").read_text()
    check("objectName: \"mailSetupError\"" in qml and "text: mail.error" in qml, "the setup screen shows the error")
    check("Connecting…" in qml, "the setup screen says it's connecting")
    check("objectName: \"mailInboxError\"" in qml, "the inbox shows why it couldn't refresh")

    print("Mail setup: " + ("all checks passed" if not failures else f"{len(failures)} failed"))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
