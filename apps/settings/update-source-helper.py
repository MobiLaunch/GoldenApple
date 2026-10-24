#!/usr/bin/env python3
"""CitronOS Software Update: change where updates come from.

    update-source-helper.py set-source   as root: save {"repo", "channel",
                                         "branch", "token"} read from stdin
                                         (channel: stable | beta | dev; the
                                         branch is for dev; token null keeps
                                         the saved one, "" removes it)

The source decides what Software Update installs as root, so this runs under
its own polkit action, org.goldengate.update.source, which asks for an
administrator's password every time and is in no passwordless rule. (The
one-click helper, update-helper.py, can't change it.)

Every line on stdout is one JSON event for Settings.
"""
from __future__ import annotations

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import golden_update  # noqa: E402


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}), flush=True)


def set_source() -> int:
    if os.geteuid() != 0:
        emit("error", message="Changing the update source needs administrator authorization.")
        return 77
    try:
        data = json.loads(sys.stdin.readline() or "{}")
        current = golden_update.source()
        repo = str(data.get("repo", "")).strip()
        channel = str(data.get("channel") or current["channel"]).strip()
        # A branch matters only on the development channel.
        branch = str(data.get("branch") or "").strip() or current["branch"]
        token = None if data.get("token") is None else golden_update.clean_token(str(data["token"]))
        # Ask GitHub first, so a token it won't take is refused here, with the
        # reason, instead of being saved and failing quietly later. Without a
        # connection it's saved anyway.
        problem = golden_update.verify_source(repo, branch, current["token"] if token is None else token, channel)
        if problem and problem[1]:
            emit("error", message=problem[0])
            return 1
        golden_update.set_source(repo, branch, token, channel)
    except (ValueError, OSError) as exc:
        emit("error", message=str(exc))
        return 1
    emit("done", message="Saved." if not problem else "Saved, but " + problem[0][0].lower() + problem[0][1:])
    return 0


def main() -> int:
    if sys.argv[1:] != ["set-source"]:
        print("usage: update-source-helper.py set-source", file=sys.stderr)
        return 2
    return set_source()


if __name__ == "__main__":
    raise SystemExit(main())
