#!/usr/bin/env python3
"""Validated FaceTime invitation joining + separate WebRTC meeting links.

We never claim to initiate Apple's proprietary FaceTime signaling on Linux.
Join an existing link through a supported WebRTC browser, or create a secure
unpredictable room on a configured Jitsi-compatible meeting host.
"""
import json
import os
import secrets
import sys
from urllib.parse import urlsplit


def create() -> dict:
    host = os.environ.get("GG_VIDEO_CALL_SERVER", "https://meet.jit.si").rstrip("/")
    parsed = urlsplit(host)
    if parsed.scheme != "https" or not parsed.hostname or parsed.query or parsed.fragment or parsed.username:
        raise ValueError("Video meeting server must be a simple HTTPS origin.")
    room = "GoldenGate-" + secrets.token_urlsafe(20).replace("-", "x").replace("_", "y")
    return {"url": host + "/" + room, "type": "webrtc", "host": parsed.hostname}


def join(link: str) -> dict:
    parsed = urlsplit(link.strip())
    if parsed.scheme != "https" or parsed.hostname != "facetime.apple.com" or not parsed.path.strip("/"):
        raise ValueError("Paste an Apple FaceTime link beginning https://facetime.apple.com/.")
    if parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError("Not a valid FaceTime invitation.")
    return {"url": link.strip(), "type": "facetime", "note": "The FaceTime host must admit you to the call."}


def main(args) -> int:
    try:
        if args == ["create"]:
            result = create()
        elif len(args) == 2 and args[0] == "join":
            result = join(args[1])
        else:
            raise ValueError("Usage: call-links.py create | join FACETIME_LINK")
        print(json.dumps({"ok": True, **result}))
        return 0
    except ValueError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
