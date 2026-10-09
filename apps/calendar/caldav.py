#!/usr/bin/env python3
"""Read-only CalDAV calendar collection sync.

caldav.py status | configure < JSON-on-stdin | sync | disconnect
The username and URL live in a private JSON config. Passwords live only in
the desktop Secret Service keyring (secret-tool), never JSON, logs or argv.
Only HTTPS calendar collection URLs are accepted, no automatic redirects.
Remote data is a separate, replace-on-success cache; local events aren't edited.
"""
from __future__ import annotations
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import helper as local

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "golden-gate/calendar/caldav.json"
CACHE = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "golden-gate/calendar/caldav-events.json"
SECRET_ATTR = ("service", "citronos-calendar-caldav", "account", "default")
DAV_XML = b"""<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
 <d:prop><d:getetag/><c:calendar-data/></d:prop>
 <c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"/></c:comp-filter></c:filter>
</c:calendar-query>"""
MAX_BYTES = 6 * 1024 * 1024
MAX_EVENTS = 5000


def emit(ok, **fields):
    print(json.dumps({"ok": ok, **fields}, separators=(",", ":")))
    return 0 if ok else 1


def private_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".caldav-")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_config():
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    if not isinstance(data, dict) or not isinstance(data.get("url"), str) or not isinstance(data.get("username"), str):
        raise ValueError("CalDAV configuration is damaged. It has been preserved.")
    validate_url(data["url"])
    return data


def validate_url(value):
    if not isinstance(value, str):
        raise ValueError("Enter an HTTPS calendar collection URL.")
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError("Use an HTTPS calendar collection URL without embedded credentials or a fragment.")
    if parsed.port not in (None, 443, 8443):
        raise ValueError("Use HTTPS on port 443 or 8443.")
    if len(value) > 2000:
        raise ValueError("Calendar URL is too long.")
    return value


def secret_tool(*args, value=None):
    try:
        proc = subprocess.run(["secret-tool", *args, *SECRET_ATTR],
                              input=(value + "\n") if value is not None else None,
                              text=True, capture_output=True, timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError("The desktop Secret Service is unavailable or locked.") from exc
    if proc.returncode:
        raise RuntimeError("The desktop Secret Service refused the credential request.")
    return proc.stdout.rstrip("\r\n")


def decode_start(raw, params):
    """Convert DTSTART to the signed-in machine's local calendar day/time."""
    all_day = params.get("VALUE") == "DATE" or bool(re.fullmatch(r"\d{8}", raw))
    if all_day:
        date = dt.datetime.strptime(raw, "%Y%m%d").date()
        return date.isoformat(), ""
    if not re.fullmatch(r"\d{8}T\d{6}Z?", raw):
        raise ValueError("unsupported date-time")
    base = dt.datetime.strptime(raw.rstrip("Z"), "%Y%m%dT%H%M%S")
    if raw.endswith("Z"):
        aware = base.replace(tzinfo=dt.timezone.utc)
    elif "TZID" in params:
        aware = base.replace(tzinfo=ZoneInfo(params["TZID"]))
    else:
        # Floating time is already in the signed-in user's timezone.
        return base.date().isoformat(), base.strftime("%H:%M")
    loc = aware.astimezone()
    return loc.date().isoformat(), loc.strftime("%H:%M")


def unescape(text):
    return (text.replace("\\n", " ").replace("\\N", " ").replace("\\,", ",")
            .replace("\\;", ";").replace("\\\\", "\\"))


def event_properties(lines):
    data = {}
    for line in lines:
        header, sep, value = line.partition(":")
        if not sep:
            continue
        tokens = header.split(";")
        key = tokens[0].upper()
        params = {}
        for token in tokens[1:]:
            name, _, part = token.partition("=")
            params[name.upper()] = part.strip('"')
        if key in ("UID", "SUMMARY", "DTSTART", "RRULE", "RECURRENCE-ID", "RDATE", "EXDATE"):
            data[key] = (value, params)
    return data


def parse_ics(ics):
    """Return supported VEVENT masters; unsupported recurrence is skipped."""
    if not isinstance(ics, str) or len(ics) > MAX_BYTES:
        raise ValueError("Calendar entry is too large.")
    unfolded = []
    for line in ics.replace("\r\n", "\n").split("\n"):
        if line.startswith((" ", "\t")) and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    entries, active = [], None
    for line in unfolded:
        if line == "BEGIN:VEVENT":
            active = []
        elif line == "END:VEVENT" and active is not None:
            entries.append(event_properties(active))
            active = None
            if len(entries) > MAX_EVENTS:
                raise ValueError("CalDAV response contains too many events.")
        elif active is not None:
            active.append(line)
    # Never show a recurring master as if it had no changed instances.
    changed_uids = {r["UID"][0] for r in entries if "UID" in r and
                    any(p in r for p in ("RECURRENCE-ID", "RDATE", "EXDATE"))}
    supported = []
    unsupported = 0
    for row in entries:
        if "UID" not in row or "DTSTART" not in row:
            unsupported += 1
            continue
        if row["UID"][0] in changed_uids or "RECURRENCE-ID" in row:
            unsupported += 1
            continue
        try:
            date, time = decode_start(*row["DTSTART"])
            freq, until = "never", ""
            if "RRULE" in row:
                parts = {}
                for field in row["RRULE"][0].split(";"):
                    key, sep, value = field.partition("=")
                    if not sep or key in parts:
                        raise ValueError("unsupported RRULE")
                    parts[key] = value
                if set(parts) - {"FREQ", "UNTIL", "INTERVAL", "WKST"}:
                    raise ValueError("complex recurrence")
                if parts.get("INTERVAL", "1") != "1":
                    raise ValueError("interval recurrence")
                freq = parts.get("FREQ", "").lower()
                if freq not in ("daily", "weekly", "monthly", "yearly"):
                    raise ValueError("unknown recurrence")
                if parts.get("UNTIL"):
                    raw = parts["UNTIL"]
                    if re.fullmatch(r"\d{8}", raw):
                        until = dt.datetime.strptime(raw, "%Y%m%d").date().isoformat()
                    elif re.fullmatch(r"\d{8}T\d{6}Z", raw):
                        until = dt.datetime.strptime(raw, "%Y%m%dT%H%M%SZ").date().isoformat()
                    else:
                        raise ValueError("complex UNTIL")
            title = unescape(row.get("SUMMARY", ("Untitled event", {}))[0]).strip() or "Untitled event"
            uid = row["UID"][0]
            event = {
                "id": "caldav-" + hashlib.sha256(uid.encode("utf-8")).hexdigest()[:24],
                "title": title[:500], "date": date, "time": time, "calendar": "CalDAV",
                "repeat": freq, "until": until, "remote": True, "reminder": -1
            }
            if local.check(event):
                raise ValueError("invalid event")
        except (TypeError, ValueError, ZoneInfoNotFoundError):
            unsupported += 1
            continue
        supported.append(event)
    return supported, unsupported


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        raise ValueError("CalDAV redirected to another address. Enter the final HTTPS collection URL.")


def fetch_events(url, username, password):
    auth = base64.b64encode((username + ":" + password).encode("utf-8")).decode("ascii")
    req = urllib.request.Request(url, data=DAV_XML, method="REPORT",
             headers={"Authorization": "Basic " + auth, "Depth": "1",
                      "Content-Type": "application/xml; charset=utf-8", "Accept": "application/xml"})
    opener = urllib.request.build_opener(NoRedirect())
    with opener.open(req, timeout=20) as resp:
        if resp.status != 207:
            raise ValueError("CalDAV server didn't return a multistatus calendar response.")
        raw = resp.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("CalDAV calendar response exceeds the safe size limit.")
    xml = ET.fromstring(raw)
    if xml.tag != "{DAV:}multistatus":
        raise ValueError("CalDAV server returned an unexpected document.")
    rows, ignored = [], 0
    for response in xml.findall("{DAV:}response"):
        for payload in response.findall(".//{urn:ietf:params:xml:ns:caldav}calendar-data"):
            if payload.text is None:
                continue
            found, rejected = parse_ics(payload.text)
            rows.extend(found)
            ignored += rejected
            if len(rows) > MAX_EVENTS:
                raise ValueError("Too many events in the CalDAV collection.")
    if not xml.findall("{DAV:}response"):
        raise ValueError("CalDAV response contained no collection entries.")
    return rows, ignored


def command(name):
    try:
        if name == "status":
            config = read_config()
            return emit(True, configured=config is not None,
                        url=config["url"] if config else "", username=config["username"] if config else "")
        if name == "configure":
            data = json.load(sys.stdin)
            if not isinstance(data, dict):
                raise ValueError("Invalid account data.")
            url = validate_url(data.get("url"))
            username = data.get("username", "")
            password = data.get("password", "")
            if not isinstance(username, str) or not username.strip() or len(username) > 200:
                raise ValueError("Enter the CalDAV username.")
            if not isinstance(password, str) or not password or len(password) > 1024:
                raise ValueError("Enter a password or app-specific password.")
            secret_tool("store", "--label=CitronOS Calendar", value=password)
            private_json(CONFIG, {"url": url, "username": username.strip()})
            return emit(True, configured=True)
        if name == "sync":
            config = read_config()
            if not config:
                raise ValueError("Connect a CalDAV calendar first.")
            password = secret_tool("lookup")
            if not password:
                raise RuntimeError("No CalDAV password was found in Secret Service.")
            rows, ignored = fetch_events(config["url"], config["username"], password)
            with local.locked():
                private_json(CACHE, rows)
            return emit(True, count=len(rows), skipped=ignored)
        if name == "disconnect":
            secret_tool("clear")
            CONFIG.unlink(missing_ok=True)
            with local.locked():
                CACHE.unlink(missing_ok=True)
            return emit(True, configured=False)
        raise ValueError("Choose status, configure, sync, or disconnect.")
    except urllib.error.HTTPError as exc:
        return emit(False, error=f"CalDAV server returned HTTP {exc.code}. Check the collection URL and login.")
    except (OSError, RuntimeError, ValueError, ET.ParseError, urllib.error.URLError, json.JSONDecodeError) as exc:
        return emit(False, error=str(exc))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(emit(False, error="Choose status, configure, sync, or disconnect."))
    raise SystemExit(command(sys.argv[1]))
