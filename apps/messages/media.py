#!/usr/bin/env python3
"""Optional real iMessage media delivery using the user's BlueBubbles Mac relay.

BlueFerry's MAP transport CANNOT send attachments; never route media into
its text-only send() call or claim success before a provider acknowledges it.
Requires ~/.config/golden-gate/messages-media.json (0600):
{"provider":"bluebubbles","url":"https://your-mac.example","password":"..."}
"""
from __future__ import annotations

import http.client
import tempfile
import json
import mimetypes
import os
from pathlib import Path
import re
import secrets
import stat
import sys
from urllib.parse import urlencode, urlsplit
import uuid

CONFIG = Path(os.environ.get("GG_MESSAGES_MEDIA_CONFIG",
                             str(Path.home() / ".config/golden-gate/messages-media.json")))
MAX_SIZE = 100 * 1024 * 1024
ALLOWED = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
    ".gif": "image/gif", ".heic": "image/heic", ".webp": "image/webp",
    ".mp4": "video/mp4", ".mov": "video/quicktime",
    ".m4v": "video/x-m4v", ".webm": "video/webm",
}
ADDRESS = re.compile(r"^(?:\+?[0-9][0-9 ()-]{5,30}|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,})$")


def emit(ok: bool, **other) -> int:
    print(json.dumps({"ok": ok, **other}, ensure_ascii=False), flush=True)
    return 0 if ok else 1


def settings() -> dict:
    if not CONFIG.is_file():
        return {}
    info = CONFIG.stat()
    if info.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise ValueError("Media provider settings are not private. Run chmod 600 on messages-media.json.")
    obj = json.loads(CONFIG.read_text(encoding="utf-8"))
    if not isinstance(obj, dict):
        raise ValueError("Media provider configuration must be a JSON object.")
    return obj


def server(config: dict):
    if config.get("provider") != "bluebubbles":
        raise ValueError("Configure a supported attachment provider to send photos and videos.")
    url = urlsplit(str(config.get("url", "")).rstrip("/"))
    if url.scheme not in ("https", "http") or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError("Set a valid BlueBubbles server URL.")
    if url.scheme != "https" and url.hostname not in ("localhost", "127.0.0.1", "::1"):
        raise ValueError("Remote BlueBubbles servers must use HTTPS to protect attachments.")
    if not config.get("password"):
        raise ValueError("BlueBubbles server password is missing.")
    return url


def configure(values: dict) -> None:
    if not isinstance(values, dict):
        raise ValueError("Media configuration must be an object.")
    record = {"provider": "bluebubbles", "url": str(values.get("url", "")).strip().rstrip("/"),
              "password": str(values.get("password", "")).strip()}
    server(record)
    CONFIG.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, filename = tempfile.mkstemp(prefix=".media-", dir=CONFIG.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(record, f)
            f.write("\n")
        os.replace(filename, CONFIG)
    finally:
        if os.path.exists(filename):
            os.unlink(filename)


def validate_file(path: Path) -> tuple[int, str]:
    if path.is_symlink() or not path.is_file():
        raise ValueError("Choose an existing photo or video file, not a symbolic link.")
    suffix = path.suffix.lower()
    if suffix not in ALLOWED:
        raise ValueError("Choose a supported photo or video (JPEG, PNG, GIF, HEIC, WebP, MP4, MOV, M4V, WebM).")
    size = path.stat().st_size
    if size < 1 or size > MAX_SIZE:
        raise ValueError("Attachment must be between 1 byte and 100 MB.")
    return size, ALLOWED[suffix]


def attachment_details(path: Path) -> dict:
    size, mime = validate_file(path)
    return {"path": str(path), "name": path.name, "bytes": size,
            "type": "video" if mime.startswith("video/") else "image", "mime": mime}


def send(config: dict, raw_path: str, recipient: str, caption: str) -> dict:
    url = server(config)
    path = Path(raw_path).expanduser().absolute()
    size, mime = validate_file(path)
    address = recipient.strip()
    # A direct handle only. A guessed group roster is never safe to send to.
    if not ADDRESS.fullmatch(address) or "\r" in address or "\n" in address:
        raise ValueError("Choose an unambiguous phone number or email address for media delivery.")
    boundary = "gg-" + secrets.token_hex(14)
    def field(name: str, value: str) -> bytes:
        return (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n").encode()
    head = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"attachment\"; filename=\"media\"\r\n"
            f"Content-Type: {mime}\r\n\r\n").encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    # BlueBubbles uses chatGuid; for 1:1 chats use the bare address instead
    # of a service-qualified GUID containing semicolons (server parser bug).
    pre = field("chatGuid", address) + field("tempGuid", str(uuid.uuid4()))
    if caption.strip():
        pre += field("message", caption[:4000])
    length = len(pre) + len(head) + size + len(tail)
    api = url.path.rstrip("/") + "/api/v1/message/attachment"
    query = urlencode({"password": str(config["password"])})
    conn = (http.client.HTTPSConnection(url.hostname, url.port, timeout=120)
            if url.scheme == "https" else http.client.HTTPConnection(url.hostname, url.port, timeout=120))
    try:
        conn.putrequest("POST", api + "?" + query)
        conn.putheader("Content-Type", f"multipart/form-data; boundary={boundary}")
        conn.putheader("Content-Length", str(length))
        conn.putheader("Accept", "application/json")
        conn.endheaders()
        conn.send(pre)
        conn.send(head)
        with path.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                conn.send(chunk)
        conn.send(tail)
        response = conn.getresponse()
        data = response.read(512 * 1024)
        if response.status not in (200, 201, 202):
            raise ValueError(f"Relay rejected attachment (HTTP {response.status}).")
        payload = {}
        try:
            payload = json.loads(data) if data else {}
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ValueError("The relay did not return a valid attachment confirmation.")
        if not isinstance(payload, dict) or payload.get("status") in ("error", 400, 401, 403, 500) or payload.get("error"):
            raise ValueError("The relay reported an attachment delivery error.")
        return {"provider": "bluebubbles", "recipient": address, "name": path.name,
                "result": "submitted", "note": "Accepted by relay; final delivery depends on Apple Messages."}
    finally:
        conn.close()


def main(argv: list[str]) -> int:
    try:
        if not argv or argv[0] not in ("status", "inspect", "send", "configure"):
            raise ValueError("Usage: media.py status | inspect FILE | send FILE RECIPIENT [CAPTION] | configure")
        cmd = argv[0]
        if cmd == "configure" and len(argv) == 1:
            # Secrets come from stdin (not argv or journalled process command).
            values = json.loads(sys.stdin.read(8192))
            configure(values)
            return emit(True, ready=True, provider="bluebubbles")
        if cmd == "inspect" and len(argv) == 2:
            return emit(True, **attachment_details(Path(argv[1]).expanduser()))
        if cmd == "status" and len(argv) == 1:
            c = settings()
            if not c:
                return emit(True, ready=False, provider="", reason="Configure a media relay for iMessage photos/videos.")
            server(c)
            return emit(True, ready=True, provider="bluebubbles")
        if cmd == "send" and len(argv) in (3, 4):
            return emit(True, **send(settings(), argv[1], argv[2], argv[3] if len(argv) == 4 else ""))
        raise ValueError("Unsupported media command.")
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError, TimeoutError, ConnectionError,
            http.client.HTTPException) as exc:
        return emit(False, error=str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
