#!/usr/bin/env python3
"""Golden Gate Messages backend using the Matrix Client-Server API."""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

CONFIG = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "golden-gate/messages.json"


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


def normalize_server(value: str) -> str:
    server = value.strip()
    if not server:
        return ""
    if not server.startswith(("http://", "https://")):
        server = "https://" + server
    return server.rstrip("/")


def secret_lookup(user_id: str) -> str:
    p = subprocess.run(
        ["secret-tool", "lookup", "service", "golden-gate-messages", "account", user_id],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return p.stdout.rstrip("\n") if p.returncode == 0 else ""


def secret_store(user_id: str, token: str) -> None:
    p = subprocess.run(
        [
            "secret-tool", "store",
            "--label=Golden Gate Messages",
            "service", "golden-gate-messages",
            "account", user_id,
        ],
        input=token,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "The Matrix access token could not be saved to the keyring.")


def request(
    server: str,
    path: str,
    *,
    token: str = "",
    data: dict[str, object] | None = None,
    method: str | None = None,
    timeout: int = 25,
) -> dict[str, object]:
    url = server.rstrip("/") + path
    body = None if data is None else json.dumps(data).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = "Bearer " + token

    req = urllib.request.Request(url, data=body, headers=headers, method=method or ("POST" if body is not None else "GET"))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = response.read().decode("utf-8", errors="replace")
            parsed = json.loads(payload) if payload else {}
            return parsed if isinstance(parsed, dict) else {}
    except urllib.error.HTTPError as exc:
        payload = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(payload)
            message = parsed.get("error") or parsed.get("errcode") or str(exc)
        except Exception:
            message = payload.strip() or str(exc)
        raise RuntimeError(str(message)) from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Could not reach the Matrix server: {exc.reason}") from exc


def configured() -> tuple[dict[str, object], str]:
    cfg = load_config()
    user_id = str(cfg.get("user_id") or "")
    server = str(cfg.get("homeserver") or "")
    if not user_id or not server:
        raise RuntimeError("No Messages account is configured.")
    token = secret_lookup(user_id)
    if not token:
        raise RuntimeError("Messages could not unlock the Matrix access token from the keyring.")
    return cfg, token


def cmd_login() -> int:
    try:
        payload = json.load(sys.stdin)
        server = normalize_server(str(payload.get("homeserver") or ""))
        username = str(payload.get("username") or "").strip()
        password = str(payload.get("password") or "")
        if not server or not username or not password:
            return emit(False, error="Enter your Matrix homeserver, username and password.")

        body = {
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": username},
            "password": password,
            "initial_device_display_name": "Golden Gate",
        }
        result = request(server, "/_matrix/client/v3/login", data=body)
        token = str(result.get("access_token") or "")
        user_id = str(result.get("user_id") or "")
        device_id = str(result.get("device_id") or "")
        if not token or not user_id:
            return emit(False, error="The Matrix server did not return a usable login session.")

        secret_store(user_id, token)
        atomic_json(CONFIG, {"homeserver": server, "user_id": user_id, "device_id": device_id})
        return emit(True, user_id=user_id, homeserver=server)
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_status() -> int:
    cfg = load_config()
    user_id = str(cfg.get("user_id") or "")
    return emit(
        True,
        configured=bool(user_id and secret_lookup(user_id)),
        user_id=user_id,
        homeserver=str(cfg.get("homeserver") or ""),
    )


def room_name(room_id: str, state: list[dict[str, object]], own_user: str) -> str:
    for event in state:
        if event.get("type") == "m.room.name":
            content = event.get("content") or {}
            if isinstance(content, dict) and content.get("name"):
                return str(content["name"])
    for event in state:
        if event.get("type") == "m.room.canonical_alias":
            content = event.get("content") or {}
            if isinstance(content, dict) and content.get("alias"):
                return str(content["alias"])
    for event in state:
        if event.get("type") == "m.room.member" and event.get("state_key") != own_user:
            content = event.get("content") or {}
            if isinstance(content, dict) and content.get("displayname"):
                return str(content["displayname"])
    return room_id


def cmd_sync() -> int:
    try:
        cfg, token = configured()
        server = str(cfg["homeserver"])
        own_user = str(cfg["user_id"])
        filter_data = {
            "room": {
                "timeline": {"limit": 12, "types": ["m.room.message"]},
                "state": {"types": ["m.room.name", "m.room.canonical_alias", "m.room.member"]},
                "ephemeral": {"types": []},
            },
            "presence": {"types": []},
        }
        query = urllib.parse.urlencode({"timeout": "0", "filter": json.dumps(filter_data, separators=(",", ":"))})
        data = request(server, "/_matrix/client/v3/sync?" + query, token=token, timeout=30)
        joined = ((data.get("rooms") or {}).get("join") or {}) if isinstance(data.get("rooms"), dict) else {}
        rooms: list[dict[str, object]] = []

        for room_id, info in joined.items():
            if not isinstance(info, dict):
                continue
            state_events = ((info.get("state") or {}).get("events") or [])
            timeline_events = ((info.get("timeline") or {}).get("events") or [])
            if not isinstance(state_events, list):
                state_events = []
            if not isinstance(timeline_events, list):
                timeline_events = []

            last_body = ""
            last_ts = 0
            unread = 0
            for event in timeline_events:
                if not isinstance(event, dict) or event.get("type") != "m.room.message":
                    continue
                content = event.get("content") or {}
                if not isinstance(content, dict):
                    continue
                body = str(content.get("body") or "")
                if body:
                    last_body = body
                    last_ts = int(event.get("origin_server_ts") or 0)

            unread_info = info.get("unread_notifications") or {}
            if isinstance(unread_info, dict):
                unread = int(unread_info.get("notification_count") or 0)

            rooms.append(
                {
                    "id": room_id,
                    "name": room_name(room_id, state_events, own_user),
                    "preview": last_body,
                    "timestamp": last_ts,
                    "unread": unread,
                }
            )

        rooms.sort(key=lambda r: int(r["timestamp"]), reverse=True)
        return emit(True, rooms=rooms, user_id=own_user)
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_messages(room_id: str) -> int:
    try:
        cfg, token = configured()
        server = str(cfg["homeserver"])
        own_user = str(cfg["user_id"])
        room = urllib.parse.quote(room_id, safe="")
        query = urllib.parse.urlencode({"dir": "b", "limit": "60"})
        data = request(server, f"/_matrix/client/v3/rooms/{room}/messages?{query}", token=token)
        chunk = data.get("chunk") or []
        rows: list[dict[str, object]] = []
        if isinstance(chunk, list):
            for event in reversed(chunk):
                if not isinstance(event, dict) or event.get("type") != "m.room.message":
                    continue
                content = event.get("content") or {}
                if not isinstance(content, dict):
                    continue
                msgtype = str(content.get("msgtype") or "")
                body = str(content.get("body") or "")
                if msgtype not in {"m.text", "m.notice", "m.emote"} or not body:
                    continue
                sender = str(event.get("sender") or "")
                rows.append(
                    {
                        "id": str(event.get("event_id") or ""),
                        "sender": sender,
                        "body": body,
                        "timestamp": int(event.get("origin_server_ts") or 0),
                        "self": sender == own_user,
                    }
                )
        return emit(True, messages=rows)
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_send(room_id: str) -> int:
    try:
        cfg, token = configured()
        server = str(cfg["homeserver"])
        data = json.load(sys.stdin)
        body = str(data.get("body") or "").strip()
        if not body:
            return emit(False, error="Enter a message.")
        room = urllib.parse.quote(room_id, safe="")
        txn = str(int(time.time() * 1000))
        path = f"/_matrix/client/v3/rooms/{room}/send/m.room.message/{txn}"
        request(
            server,
            path,
            token=token,
            data={"msgtype": "m.text", "body": body},
            method="PUT",
        )
        return emit(True)
    except Exception as exc:
        return emit(False, error=str(exc))


def cmd_logout() -> int:
    cfg = load_config()
    user_id = str(cfg.get("user_id") or "")
    token = secret_lookup(user_id) if user_id else ""
    server = str(cfg.get("homeserver") or "")
    if token and server:
        try:
            request(server, "/_matrix/client/v3/logout", token=token, data={})
        except Exception:
            pass
    if user_id:
        subprocess.run(
            ["secret-tool", "clear", "service", "golden-gate-messages", "account", user_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    try:
        CONFIG.unlink()
    except FileNotFoundError:
        pass
    return emit(True)


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1]
    if cmd == "login":
        return cmd_login()
    if cmd == "status":
        return cmd_status()
    if cmd == "sync":
        return cmd_sync()
    if cmd == "messages" and len(sys.argv) == 3:
        return cmd_messages(sys.argv[2])
    if cmd == "send" and len(sys.argv) == 3:
        return cmd_send(sys.argv[2])
    if cmd == "logout":
        return cmd_logout()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
