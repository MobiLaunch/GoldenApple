#!/usr/bin/env python3
"""CitronOS Mail backend: manual IMAP/SMTP account with keyring credentials."""
from __future__ import annotations

import email
import email.header
import email.policy
import html
import imaplib
import json
import os
import pathlib
import re
import smtplib
import ssl
import subprocess
import sys
import tempfile
from email.message import EmailMessage
from html.parser import HTMLParser

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "golden-gate/mail.json"


def emit(ok: bool = True, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")), flush=True)
    return 0 if ok else 1


def atomic_json(path: pathlib.Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def load_config() -> dict[str, object]:
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


# A locked keyring asks to be unlocked; give that time, but not forever.
KEYRING_WAIT = 30


def secret_lookup(account: str) -> str:
    try:
        p = subprocess.run(
            ["secret-tool", "lookup", "service", "golden-gate-mail", "account", account],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=KEYRING_WAIT,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("The keyring didn't answer. It may be waiting to be unlocked.") from None
    return p.stdout.rstrip("\n") if p.returncode == 0 else ""


def secret_store(account: str, password: str) -> None:
    try:
        p = subprocess.run(
            [
                "secret-tool", "store",
                "--label=CitronOS Mail",
                "service", "golden-gate-mail",
                "account", account,
            ],
            input=password,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=KEYRING_WAIT,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("The keyring didn't answer, so the password wasn't saved. It may be waiting to be unlocked.") from None
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "The password could not be saved to the keyring.")


def configured() -> tuple[dict[str, object], str]:
    cfg = load_config()
    account = str(cfg.get("email") or "")
    if not account:
        raise RuntimeError("No Mail account is configured.")
    password = secret_lookup(account)
    if not password:
        raise RuntimeError("Mail could not unlock the account password from the keyring.")
    return cfg, password


def decode_header(value: str | None) -> str:
    if not value:
        return ""
    pieces: list[str] = []
    for item, charset in email.header.decode_header(value):
        if isinstance(item, bytes):
            pieces.append(item.decode(charset or "utf-8", errors="replace"))
        else:
            pieces.append(item)
    return "".join(pieces).strip()


def clean_address(value: str | None) -> str:
    return decode_header(value)


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.parts: list[str] = []

    def handle_data(self, data: str) -> None:
        text = data.strip()
        if text:
            self.parts.append(text)

    def value(self) -> str:
        return "\n".join(self.parts)


def body_text(msg: email.message.EmailMessage) -> str:
    plain: str | None = None
    rich: str | None = None
    parts = msg.walk() if msg.is_multipart() else [msg]
    for part in parts:
        disposition = (part.get_content_disposition() or "").lower()
        if disposition == "attachment":
            continue
        ctype = part.get_content_type()
        try:
            content = part.get_content()
        except Exception:
            payload = part.get_payload(decode=True) or b""
            content = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
        if not isinstance(content, str):
            continue
        if ctype == "text/plain" and plain is None:
            plain = content
        elif ctype == "text/html" and rich is None:
            rich = content
    if plain is not None:
        return plain.strip()
    if rich is not None:
        parser = TextExtractor()
        try:
            parser.feed(rich)
            return html.unescape(parser.value()).strip()
        except Exception:
            return re.sub(r"<[^>]+>", "", rich).strip()
    return ""


def imap_client(cfg: dict[str, object], password: str) -> imaplib.IMAP4:
    host = str(cfg.get("imap_host") or "")
    port = int(cfg.get("imap_port") or 993)
    user = str(cfg.get("username") or cfg.get("email") or "")
    security = str(cfg.get("imap_security") or "ssl")
    if security == "ssl":
        client: imaplib.IMAP4 = imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context(), timeout=20)
    else:
        client = imaplib.IMAP4(host, port, timeout=20)
        if security == "starttls":
            client.starttls(ssl_context=ssl.create_default_context())
    client.login(user, password)
    return client


def cmd_setup() -> int:
    try:
        data = json.load(sys.stdin)
        email_addr = str(data.get("email") or "").strip()
        username = str(data.get("username") or email_addr).strip()
        imap_host = str(data.get("imap_host") or "").strip()
        smtp_host = str(data.get("smtp_host") or "").strip()
        password = str(data.get("password") or "")
        if "@" not in email_addr or not imap_host or not smtp_host or not password:
            return emit(False, error="Enter your email address, mail servers and password.")
        cfg: dict[str, object] = {
            "email": email_addr,
            "username": username,
            "imap_host": imap_host,
            "imap_port": int(data.get("imap_port") or 993),
            "imap_security": str(data.get("imap_security") or "ssl"),
            "smtp_host": smtp_host,
            "smtp_port": int(data.get("smtp_port") or 465),
            "smtp_security": str(data.get("smtp_security") or "ssl"),
        }
        # Verify IMAP before persisting anything.
        temp = imap_client(cfg, password)
        temp.logout()
        secret_store(email_addr, password)
        atomic_json(CONFIG, cfg)
        return emit(True, account=email_addr)
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_status() -> int:
    cfg = load_config()
    email_addr = str(cfg.get("email") or "")
    try:
        return emit(True, configured=bool(email_addr and secret_lookup(email_addr)), account=email_addr)
    except RuntimeError as exc:           # a keyring that never answered
        return emit(False, error=str(exc), account=email_addr)


def cmd_list() -> int:
    try:
        cfg, password = configured()
        client = imap_client(cfg, password)
        try:
            typ, _ = client.select("INBOX", readonly=True)
            if typ != "OK":
                raise RuntimeError("Inbox could not be opened.")
            typ, data = client.uid("search", None, "ALL")
            if typ != "OK":
                raise RuntimeError("Inbox could not be searched.")
            uids = (data[0] or b"").split()[-80:]
            rows: list[dict[str, object]] = []
            for uid in reversed(uids):
                typ, fetched = client.uid(
                    "fetch",
                    uid,
                    "(FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])",
                )
                if typ != "OK" or not fetched:
                    continue
                raw = b""
                meta = ""
                for part in fetched:
                    if isinstance(part, tuple):
                        meta = part[0].decode("utf-8", errors="replace")
                        raw += part[1]
                msg = email.message_from_bytes(raw, policy=email.policy.default)
                rows.append(
                    {
                        "uid": uid.decode(),
                        "subject": decode_header(msg.get("Subject")) or "(No Subject)",
                        "from": clean_address(msg.get("From")),
                        "date": decode_header(msg.get("Date")),
                        "unread": "\\Seen" not in meta,
                    }
                )
            return emit(True, messages=rows, account=str(cfg.get("email") or ""))
        finally:
            try:
                client.logout()
            except Exception:
                pass
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_read(uid: str) -> int:
    try:
        cfg, password = configured()
        client = imap_client(cfg, password)
        try:
            if client.select("INBOX")[0] != "OK":
                raise RuntimeError("Inbox could not be opened.")
            typ, fetched = client.uid("fetch", uid, "(BODY.PEEK[])")
            if typ != "OK" or not fetched:
                raise RuntimeError("The message could not be downloaded.")
            raw = next((part[1] for part in fetched if isinstance(part, tuple)), b"")
            msg = email.message_from_bytes(raw, policy=email.policy.default)
            client.uid("store", uid, "+FLAGS", "(\\Seen)")
            return emit(
                True,
                message={
                    "uid": uid,
                    "subject": decode_header(msg.get("Subject")) or "(No Subject)",
                    "from": clean_address(msg.get("From")),
                    "to": clean_address(msg.get("To")),
                    "date": decode_header(msg.get("Date")),
                    "body": body_text(msg),
                },
            )
        finally:
            try:
                client.logout()
            except Exception:
                pass
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_send() -> int:
    try:
        cfg, password = configured()
        data = json.load(sys.stdin)
        recipients = str(data.get("to") or "").strip()
        subject = str(data.get("subject") or "").strip()
        body = str(data.get("body") or "")
        if not recipients:
            return emit(False, error="Enter at least one recipient.")

        msg = EmailMessage()
        msg["From"] = str(cfg.get("email") or "")
        msg["To"] = recipients
        msg["Subject"] = subject
        msg.set_content(body)

        host = str(cfg.get("smtp_host") or "")
        port = int(cfg.get("smtp_port") or 465)
        user = str(cfg.get("username") or cfg.get("email") or "")
        security = str(cfg.get("smtp_security") or "ssl")
        context = ssl.create_default_context()

        if security == "ssl":
            with smtplib.SMTP_SSL(host, port, context=context, timeout=25) as client:
                client.login(user, password)
                client.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=25) as client:
                client.ehlo()
                if security == "starttls":
                    client.starttls(context=context)
                    client.ehlo()
                client.login(user, password)
                client.send_message(msg)
        return emit(True)
    except Exception as exc:
        return emit(False, error=str(exc))


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1]
    if cmd == "setup":
        return cmd_setup()
    if cmd == "status":
        return cmd_status()
    if cmd == "list":
        return cmd_list()
    if cmd == "read" and len(sys.argv) == 3:
        return cmd_read(sys.argv[2])
    if cmd == "send":
        return cmd_send()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
