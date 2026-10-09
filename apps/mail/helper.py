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
import socket
import ssl
import subprocess
import sys
import tempfile
from email.message import EmailMessage
from html.parser import HTMLParser

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "golden-gate/mail.json"
DRAFT = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state")) / "golden-gate/mail-draft.json"


def draft_fields(data: object) -> dict[str, str]:
    if not isinstance(data, dict) or any(not isinstance(data.get(k, ""), str) for k in ("to", "subject", "body")):
        raise ValueError("The saved draft is damaged; it was left untouched.")
    return {k: data.get(k, "") for k in ("to", "subject", "body")}


def cmd_draft(save: bool = False) -> int:
    try:
        if save:
            # Validate an existing file before replacing it, including on a
            # new session. A damaged draft must never be silently discarded.
            if DRAFT.exists():
                draft_fields(json.loads(DRAFT.read_text(encoding="utf-8")))
            data = draft_fields(json.load(sys.stdin))
            atomic_json(DRAFT, data)  # mkstemp keeps message content mode 0600
        else:
            try:
                data = draft_fields(json.loads(DRAFT.read_text(encoding="utf-8")))
            except FileNotFoundError:
                data = draft_fields({})
        return emit(True, draft=data)
    except (OSError, ValueError) as exc:
        return emit(False, error="Mail couldn't keep or restore your draft: " + str(exc))


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


# The usual ports say which security they speak; a port and an SSL/TLS
# choice that disagree (993 with STARTTLS, 587 with SSL) is fixed here
# rather than failing with an SSL "wrong version number" or a hang.
IMPLICIT_TLS_PORTS = {993, 465, 995}
STARTTLS_PORTS = {143, 587, 25}


def security_for(port: int, chosen: str) -> str:
    if port in IMPLICIT_TLS_PORTS:
        return "ssl"
    if port in STARTTLS_PORTS:
        return "starttls"
    return chosen if chosen in ("ssl", "starttls") else "ssl"


APP_PASSWORDS = {
    ("gmail.com", "googlemail.com"): "Google turned down that password. Gmail needs an app password, not your Google password: "
        "turn on 2-Step Verification, make one at myaccount.google.com/apppasswords, and paste its 16 letters here.",
    ("icloud.com", "me.com", "mac.com"): "Apple turned down that password. iCloud Mail needs an app-specific password: "
        "make one at account.apple.com under Sign-In and Security, and paste it here.",
    ("yahoo.com", "ymail.com", "rocketmail.com"): "Yahoo turned down that password. Yahoo Mail needs an app password: "
        "make one under Account Security › Generate app password, and paste it here.",
    ("aol.com",): "AOL turned down that password. AOL Mail needs an app password: "
        "make one under Account Security › Generate app password, and paste it here.",
}
MICROSOFT = ("outlook.com", "hotmail.com", "live.com", "msn.com", "office365.com", "outlook.office365.com")


def domain_of(cfg: dict[str, object]) -> str:
    return str(cfg.get("email") or "").rsplit("@", 1)[-1].lower()


def friendly(exc: BaseException, cfg: dict[str, object], server: str = "imap") -> str:
    """What went wrong, in words someone can act on (the raw text was shown before)."""
    host = str(cfg.get(server + "_host") or "")
    port = cfg.get(server + "_port") or ""
    text = str(exc)
    low = text.lower()
    kind = "incoming (IMAP)" if server == "imap" else "outgoing (SMTP)"
    auth = isinstance(exc, smtplib.SMTPAuthenticationError) or (
        isinstance(exc, imaplib.IMAP4.error)
        and any(k in low for k in ("authenticationfailed", "invalid credentials", "login failed", "authentication failed",
                                  "application-specific password", "authenticate failed", "incorrect", "web login required",
                                  "logondenied", "no login")))
    if auth:
        domain = domain_of(cfg)
        if domain in MICROSOFT or host.endswith("office365.com") or host.endswith("outlook.com"):
            return ("Microsoft turned down the password. Outlook, Hotmail and Live accounts no longer let mail apps sign in "
                    "with a password; they need Microsoft's own sign-in, which Mail doesn't have yet.")
        for domains, message in APP_PASSWORDS.items():
            if domain in domains:
                return message
        return "The " + kind + " server turned down the user name or password. Check both (some providers need an app password)."
    if isinstance(exc, socket.gaierror):
        return "Mail couldn't find the " + kind + " server “" + host + "”. Check its name, and that this computer is online."
    if isinstance(exc, ConnectionRefusedError):
        return "“" + host + "” refused the connection on port " + str(port) + ". Check the port number."
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return "“" + host + "” didn't answer on port " + str(port) + ". Check the server and port, and that this computer is online."
    if isinstance(exc, ssl.SSLCertVerificationError):
        return ("The " + kind + " server's certificate couldn't be checked. If the date and time on this computer are wrong, "
                "set them in Settings › Date & Time and try again.")
    if isinstance(exc, ssl.SSLError):
        return "A secure connection to “" + host + "” on port " + str(port) + " couldn't be made (" + (exc.reason or text) + ")."
    if isinstance(exc, OSError) and getattr(exc, "errno", None) in (101, 113):
        return "This computer isn't online, so Mail can't reach “" + host + "”."
    if isinstance(exc, UnicodeEncodeError):
        return "The server only takes passwords in plain English letters, digits and symbols."
    return text or exc.__class__.__name__


def imap_client(cfg: dict[str, object], password: str) -> imaplib.IMAP4:
    host = str(cfg.get("imap_host") or "")
    port = int(cfg.get("imap_port") or 993)
    user = str(cfg.get("username") or cfg.get("email") or "")
    security = security_for(port, str(cfg.get("imap_security") or "ssl"))
    if security == "ssl":
        client: imaplib.IMAP4 = imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context(), timeout=20)
    else:
        client = imaplib.IMAP4(host, port, timeout=20)
        client.starttls(ssl_context=ssl.create_default_context())
    client.login(user, password)
    return client


def smtp_client(cfg: dict[str, object], password: str) -> smtplib.SMTP:
    host = str(cfg.get("smtp_host") or "")
    port = int(cfg.get("smtp_port") or 465)
    user = str(cfg.get("username") or cfg.get("email") or "")
    security = security_for(port, str(cfg.get("smtp_security") or "ssl"))
    context = ssl.create_default_context()
    if security == "ssl":
        client: smtplib.SMTP = smtplib.SMTP_SSL(host, port, context=context, timeout=25)
    else:
        client = smtplib.SMTP(host, port, timeout=25)
        client.ehlo()
        client.starttls(context=context)
        client.ehlo()
    try:
        client.login(user, password)
    except BaseException:
        client.close()
        raise
    return client


def cmd_setup() -> int:
    cfg: dict[str, object] = {}
    server = "imap"
    try:
        data = json.load(sys.stdin)
        email_addr = str(data.get("email") or "").strip()
        username = str(data.get("username") or email_addr).strip()
        imap_host = str(data.get("imap_host") or "").strip()
        smtp_host = str(data.get("smtp_host") or "").strip()
        password = str(data.get("password") or "")
        # App passwords are shown in groups ("abcd efgh ijkl mnop"); the
        # spaces aren't part of them.
        if re.fullmatch(r"[a-z]{4}( [a-z]{4}){3}", password.strip()):
            password = password.replace(" ", "")
        if "@" not in email_addr or not imap_host or not smtp_host or not password:
            return emit(False, error="Enter your email address, mail servers and password.")
        imap_port = int(data.get("imap_port") or 993)
        smtp_port = int(data.get("smtp_port") or 465)
        cfg = {
            "email": email_addr,
            "username": username,
            "imap_host": imap_host,
            "imap_port": imap_port,
            "imap_security": security_for(imap_port, str(data.get("imap_security") or "ssl")),
            "smtp_host": smtp_host,
            "smtp_port": smtp_port,
            "smtp_security": security_for(smtp_port, str(data.get("smtp_security") or "ssl")),
        }
        # Verify both servers before keeping anything: a wrong outgoing
        # server used to show up only when the first message failed to send.
        imap_client(cfg, password).logout()
        server = "smtp"
        smtp_client(cfg, password).quit()
        server = "keyring"
        secret_store(email_addr, password)
        atomic_json(CONFIG, cfg)
        return emit(True, account=email_addr)
    except RuntimeError as exc:
        return emit(False, error=str(exc))
    except Exception as exc:
        return emit(False, error=friendly(exc, cfg, server) if server != "keyring" else str(exc))


def cmd_status() -> int:
    cfg = load_config()
    email_addr = str(cfg.get("email") or "")
    try:
        return emit(True, configured=bool(email_addr and secret_lookup(email_addr)), account=email_addr)
    except RuntimeError as exc:           # a keyring that never answered
        return emit(False, error=str(exc), account=email_addr)


def parse_header_items(fetched, expected: set[str]) -> dict[str, dict[str, object]]:
    """Read UID FETCH responses without assuming IMAP returns the same order.

    UID FETCH always includes UID in server responses, even when FLAGS and
    partial header fields are requested. Do not associate emails with the
    wrong message if the server reorders the batch.
    """
    result: dict[str, dict[str, object]] = {}
    for part in fetched or []:
        if not isinstance(part, tuple) or len(part) < 2:
            continue
        meta_bytes, raw = part[:2]
        if not isinstance(meta_bytes, (bytes, bytearray)) or not isinstance(raw, bytes):
            continue
        match = re.search(rb"\bUID\s+(\d+)\b", meta_bytes, re.I)
        if not match:
            continue
        uid = match.group(1).decode("ascii")
        if uid not in expected or uid in result:
            continue
        meta = meta_bytes.decode("utf-8", errors="replace")
        msg = email.message_from_bytes(raw, policy=email.policy.default)
        result[uid] = {
            "uid": uid,
            "subject": decode_header(msg.get("Subject")) or "(No Subject)",
            "from": clean_address(msg.get("From")),
            "date": decode_header(msg.get("Date")),
            "unread": "\\Seen" not in meta,
        }
    return result


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
            uids = [s.decode("ascii") for s in (data[0] or b"").split()[-80:]]
            # Previous releases issued 80 sequential network requests, leaving
            # the Mail UI waiting after a successful login. Fetch in groups
            # of at most 25 UIDs, and gracefully retry unsupported batches.
            # Use BODY.PEEK so listing mail does not mark it as read.
            found: dict[str, dict[str, object]] = {}
            spec = "(UID FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])"
            for i in range(0, len(uids), 25):
                group = uids[i:i + 25]
                typ, fetched = client.uid("fetch", ",".join(group), spec)
                if typ == "OK":
                    found.update(parse_header_items(fetched, set(group)))
                # Some non-standard IMAP providers reject UID sets. Retry
                # only the entries absent from the batch rather than dropping
                # them or silently claiming the inbox is empty.
                for uid in group:
                    if uid in found:
                        continue
                    single_typ, single_items = client.uid("fetch", uid, spec)
                    if single_typ != "OK":
                        continue
                    found.update(parse_header_items(single_items, {uid}))
            return emit(True, messages=[found[uid] for uid in reversed(uids) if uid in found],
                        account=str(cfg.get("email") or ""))
        finally:
            try:
                client.logout()
            except Exception:
                pass
    except RuntimeError as exc:
        return emit(False, error=str(exc))
    except Exception as exc:
        return emit(False, error=friendly(exc, load_config()))


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
    except RuntimeError as exc:
        return emit(False, error=str(exc))
    except Exception as exc:
        return emit(False, error=friendly(exc, load_config()))


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

        with smtp_client(cfg, password) as client:
            client.send_message(msg)
        return emit(True)
    except RuntimeError as exc:
        return emit(False, error=str(exc))
    except Exception as exc:
        return emit(False, error=friendly(exc, load_config(), "smtp"))


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1]
    if cmd in ("draft-load", "draft-save"):
        return cmd_draft(cmd == "draft-save")
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
