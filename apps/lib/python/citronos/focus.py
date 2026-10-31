"""Focus (Do Not Disturb) and per-app notification choices, as
apps/lib/FocusPolicy.js has them for the shell and Settings; citronos-notifyd
decides with these. tests/notifyd.py runs the same cases through both, so
the two can't drift apart.

Times are milliseconds since the epoch, like JavaScript's Date.now().
"""
from __future__ import annotations

import datetime
from urllib.parse import quote

BUILT_IN = ("clock", "calendar", "messages", "mail", "software", "airdrop")


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def schedule_window(policy: dict | None, now: float) -> dict | None:
    """The scheduled Focus window now falls in, if any. A schedule belongs to
    its start day, including one across midnight; local dates, not 24-hour
    offsets, so a DST change doesn't move it."""
    s = (policy or {}).get("schedule")
    if not isinstance(s, dict) or s.get("enabled") is not True:
        return None
    days, start, end = s.get("days"), s.get("start"), s.get("end")
    if not isinstance(days, list) or not days or not _is_int(start) or not _is_int(end) \
            or not 0 <= start < 1440 or not 0 <= end < 1440 or start == end:
        return None
    today = datetime.datetime.fromtimestamp(now / 1000).date()
    for offset in (-1, 0):
        day = today + datetime.timedelta(days=offset)
        if (day.weekday() + 1) % 7 not in days:          # JavaScript's getDay(): Sunday is 0
            continue
        begins = datetime.datetime.combine(day, datetime.time(start // 60, start % 60)).timestamp() * 1000
        end_day = day + datetime.timedelta(days=1 if end <= start else 0)
        ends = datetime.datetime.combine(end_day, datetime.time(end // 60, end % 60)).timestamp() * 1000
        if begins <= now < ends:
            return {"start": begins, "end": ends}
    return None


def state(policy: dict | None, now: float) -> dict:
    policy = policy or {}
    session = policy.get("session")
    scheduled = schedule_window(policy, now)
    if isinstance(session, dict):
        until = session.get("until", 0)
        until = until if isinstance(until, (int, float)) and not isinstance(until, bool) else float("nan")
        if session.get("on") is True and until >= 0 and (until == 0 or now < until):
            return {"active": True, "until": until, "source": "manual"}
        pause = session.get("pauseUntil", 0)
        if isinstance(pause, (int, float)) and not isinstance(pause, bool) and pause > now:
            return {"active": False, "until": 0, "source": "paused"}
    elif policy.get("dnd") is True:
        return {"active": True, "until": 0, "source": "manual"}       # a pre-upgrade permanent choice
    if scheduled:
        return {"active": True, "until": scheduled["end"], "source": "schedule"}
    return {"active": False, "until": 0, "source": "off"}


def canonical_app(key) -> str:
    key = str(key or "").lower()
    return "org.goldengate." + key if key in BUILT_IN else key


def app_key(key) -> str:
    """encodeURIComponent, with dots escaped too (a dotted key would nest)."""
    return quote(canonical_app(key), safe="-_.!~*'()").replace(".", "%2E")


def app_choice(choices: dict | None, key) -> dict:
    choices = choices if isinstance(choices, dict) else {}
    canonical = canonical_app(key)
    short = canonical.split(".")[-1]
    found = choices.get(canonical)
    if found is None and canonical_app(short) == canonical:
        found = choices.get(short)
    return found if isinstance(found, dict) else {}


def allows(policy: dict | None, key, urgency: int) -> bool:
    """Whether Focus lets this app's notification through."""
    policy = policy or {}
    allowed = policy.get("allowedApps") if isinstance(policy.get("allowedApps"), dict) else {}
    return allowed.get(app_key(key)) is True or (policy.get("allowCritical") is True and urgency == 2)
