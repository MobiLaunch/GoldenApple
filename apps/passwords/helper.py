#!/usr/bin/env python3
"""Passwords: the backend (apps/passwords.qml), one command per run, JSON out.

Everything stays in the system keyring (the Secret Service, through
secret-tool), unlocked with your login:
  website passwords   Web's own items (app org.goldengate.Web, per Web
                      profile and site origin), so a password saved in Web
                      shows here and one added here fills in Web
  notes and codes     beside each, an org.goldengate.Passwords "extra" item
                      ({"notes": …, "totp": base32 secret})
  recently deleted    org.goldengate.Passwords "deleted" items, kept 30 days
Wi-Fi passwords are NetworkManager's (read only).

Secrets are only ever sent for the one item asked for (show, copy, edit);
the list carries names, user names and flags.

    helper.py list                      → {"items", "wifi", "deleted"} (weak/reused flags)
    helper.py secret   (stdin: {id})    → {"password", "notes", "totp"}
    helper.py save     (stdin: {...})   → {"id"}
    helper.py delete   (stdin: {id})    restore (stdin: {id})   purge (stdin: {id})
    helper.py codes                      → {"codes": [{id, code, remaining, period}]}
    helper.py generate                   → {"password"}
    helper.py wifi-secret (stdin: {id})  → {"password"}
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import secrets
import struct
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "browser"))
from passwords import APP as WEB, origin_of  # noqa: E402

APP = "org.goldengate.Passwords"
KEEP_DELETED = 30 * 86400
RUN = subprocess.run


def emit(ok: bool = True, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")), flush=True)
    return 0 if ok else 1


def tool(args: list[str], secret: str | None = None) -> subprocess.CompletedProcess:
    try:
        return RUN(["secret-tool", *args], input=secret if secret is not None else "", capture_output=True,
                   text=True, timeout=30)
    except FileNotFoundError:
        raise RuntimeError("Passwords can't reach the keyring (secret-tool, from libsecret, isn't installed).") from None
    except subprocess.TimeoutExpired:
        raise RuntimeError("The keyring didn't answer. It may be waiting to be unlocked.") from None


def search(*attrs: str) -> list[dict]:
    """Every item matching, as {attributes…, "secret": …}."""
    p = tool(["search", "--all", *attrs])
    if p.returncode != 0:
        return []
    # secret-tool prints each item's "[path]", label, secret and dates on
    # stdout and its "attribute.x = value" lines on stderr; items are in the
    # same order in both.
    secrets_, attrs_list = [], []
    item: dict | None = None
    for line in p.stdout.splitlines():
        if line.startswith("[") and line.endswith("]"):
            item = {}
            secrets_.append(item)
        elif item is not None and " = " in line:
            key, value = line.split(" = ", 1)
            if key in ("secret", "created", "modified", "label"):
                item[key] = value
    current: dict = {}
    for line in p.stderr.splitlines():
        if not line.startswith("attribute.") or " = " not in line:
            continue
        key, value = line[len("attribute."):].split(" = ", 1)
        if key in current:
            attrs_list.append(current)
            current = {}
        current[key] = value
    if current:
        attrs_list.append(current)
    out = []
    for i, attrs_ in enumerate(attrs_list):
        extra = secrets_[i] if i < len(secrets_) else {}
        out.append({**attrs_, "secret": extra.get("secret", ""), "modified": extra.get("modified", "")})
    return out


def lookup(*attrs: str) -> str | None:
    p = tool(["lookup", *attrs])
    if p.returncode != 0:
        return None
    return p.stdout[:-1] if p.stdout.endswith("\n") else p.stdout


def store(label: str, secret: str, *attrs: str) -> None:
    p = tool(["store", "--label", label, *attrs], secret)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "The keyring wouldn't save it.")


def clear(*attrs: str) -> None:
    tool(["clear", *attrs])


# ------------------------------------------------------------------- ids
def web_id(profile: str, origin: str, username: str) -> str:
    return "w:" + json.dumps([profile, origin, username], separators=(",", ":"))


def parse_id(item_id: str) -> tuple[str, list[str]]:
    kind, _, rest = item_id.partition(":")
    try:
        return kind, json.loads(rest)
    except ValueError:
        return kind, []


def title_of(origin: str) -> str:
    host = urlsplit(origin).hostname or origin
    return host[4:] if host.startswith("www.") else host


def extra_attrs(profile: str, origin: str, username: str) -> list[str]:
    return ["app", APP, "kind", "extra", "profile", profile, "origin", origin, "username", username]


def web_attrs(profile: str, origin: str, username: str) -> list[str]:
    return ["app", WEB, "profile", profile, "origin", origin, "username", username]


def extras(profile: str, origin: str, username: str) -> dict:
    raw = lookup(*extra_attrs(profile, origin, username))
    try:
        data = json.loads(raw) if raw else {}
        return data if isinstance(data, dict) else {}
    except ValueError:
        return {}


# ------------------------------------------------------------------- TOTP
def totp_parse(text: str) -> dict:
    """A base32 secret or an otpauth:// URI → {secret, digits, period, issuer, account}."""
    text = (text or "").strip()
    if text.lower().startswith("otpauth://"):
        u = urlsplit(text)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        label = unquote(u.path.lstrip("/"))
        issuer, _, account = label.partition(":") if ":" in label else ("", "", label)
        return {"secret": q.get("secret", "").replace(" ", "").upper(), "digits": int(q.get("digits", 6)),
                "period": int(q.get("period", 30)), "issuer": q.get("issuer", issuer), "account": account}
    return {"secret": re.sub(r"[\s-]", "", text).upper(), "digits": 6, "period": 30, "issuer": "", "account": ""}


def totp(secret: str, at: float | None = None, digits: int = 6, period: int = 30) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    counter = int((time.time() if at is None else at) // period)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10 ** digits)).zfill(digits)


def valid_totp(text: str) -> bool:
    try:
        spec = totp_parse(text)
        totp(spec["secret"], 0, spec["digits"], spec["period"])
        return bool(spec["secret"])
    except (ValueError, TypeError, base64.binascii.Error):
        return False


# --------------------------------------------------------------- security
COMMON = {"password", "123456", "12345678", "123456789", "qwerty", "abc123", "111111", "letmein", "iloveyou",
          "admin", "welcome", "monkey", "dragon", "football", "baseball", "sunshine", "princess", "000000",
          "password1", "qwerty123", "1q2w3e4r", "passw0rd"}


def weak(password: str) -> bool:
    p = password or ""
    if len(p) < 8 or p.lower() in COMMON:
        return True
    kinds = sum(bool(re.search(r, p)) for r in (r"[a-z]", r"[A-Z]", r"\d", r"[^A-Za-z0-9]"))
    return len(p) < 12 and kinds < 3


def generate() -> str:
    """Apple's shape: three groups of six, a digit and a capital among them."""
    alphabet = "abcdefghijkmnopqrstuvwxyz"
    chars = [secrets.choice(alphabet) for _ in range(18)]
    chars[secrets.randbelow(18)] = secrets.choice("23456789")
    up = secrets.randbelow(18)
    while chars[up].isdigit():
        up = secrets.randbelow(18)
    chars[up] = chars[up].upper()
    return "-".join("".join(chars[i:i + 6]) for i in (0, 6, 12))


# ------------------------------------------------------------------- Wi-Fi
def wifi_networks() -> list[dict]:
    try:
        out = RUN(["nmcli", "-t", "-f", "NAME,UUID,TYPE", "connection", "show"], capture_output=True, text=True,
                  timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    nets = []
    for line in out.splitlines():
        parts = re.split(r"(?<!\\):", line)
        if len(parts) >= 3 and parts[2] == "802-11-wireless":
            name = parts[0].replace("\\:", ":")
            nets.append({"id": "n:" + json.dumps([parts[1]]), "kind": "wifi", "title": name, "username": "",
                         "origin": "", "profile": ""})
    return sorted(nets, key=lambda n: n["title"].lower())


# -------------------------------------------------------------- commands
def cmd_list() -> int:
    now = time.time()
    web = search("app", WEB)
    mine = search("app", APP)
    extras_by = {(i.get("profile", ""), i.get("origin", ""), i.get("username", "")): i
                 for i in mine if i.get("kind") == "extra"}
    items = []
    for i in web:
        profile, origin, username = i.get("profile", "Personal"), i.get("origin", ""), i.get("username", "")
        if not origin:
            continue
        ex = extras_by.get((profile, origin, username))
        data = {}
        if ex:
            try:
                data = json.loads(ex.get("secret") or "{}")
            except ValueError:
                data = {}
        items.append({"id": web_id(profile, origin, username), "kind": "website", "title": title_of(origin),
                      "origin": origin, "username": username, "profile": profile, "modified": i.get("modified", ""),
                      "hasCode": bool(data.get("totp")), "hasNotes": bool(data.get("notes")),
                      "weak": weak(i.get("secret", ""))})
    # Reused: the same password on more than one site (compared here, never sent).
    seen: dict[str, list[dict]] = {}
    for item, raw in zip(items, [i for i in web if i.get("origin")]):
        if raw.get("secret"):
            seen.setdefault(hashlib.sha256(raw["secret"].encode()).hexdigest(), []).append(item)
    for group in seen.values():
        for item in group:
            item["reused"] = len({g["origin"] for g in group}) > 1
    for i in mine:
        if i.get("kind") == "code":
            items.append({"id": "c:" + json.dumps([i.get("label", ""), i.get("account", "")]), "kind": "code",
                          "title": i.get("label", "") or "Verification Code", "username": i.get("account", ""),
                          "origin": "", "profile": "", "hasCode": True, "modified": i.get("modified", "")})
    deleted = []
    for i in mine:
        if i.get("kind") != "deleted":
            continue
        when = float(i.get("deleted") or 0)
        attrs = ["app", APP, "kind", "deleted", "profile", i.get("profile", ""), "origin", i.get("origin", ""),
                 "username", i.get("username", ""), "deleted", i.get("deleted", "")]
        if now - when > KEEP_DELETED:
            clear(*attrs)
            continue
        deleted.append({"id": "d:" + json.dumps([i.get("profile", ""), i.get("origin", ""), i.get("username", ""),
                                                 i.get("deleted", "")]),
                        "kind": "deleted", "title": title_of(i.get("origin", "")), "origin": i.get("origin", ""),
                        "username": i.get("username", ""), "profile": i.get("profile", ""),
                        "daysLeft": max(0, int((when + KEEP_DELETED - now) // 86400))})
    items.sort(key=lambda x: (x["title"].lower(), x["username"].lower()))
    return emit(True, items=items, wifi=wifi_networks(), deleted=sorted(deleted, key=lambda d: d["title"].lower()))


def read_request() -> dict:
    # An item's id comes on the command line (it names the item, it isn't a
    # secret); what's saved comes on stdin, never in argv.
    if len(sys.argv) > 2:
        return {"id": sys.argv[2]}
    try:
        data = json.load(sys.stdin)
        return data if isinstance(data, dict) else {}
    except ValueError:
        return {}


def cmd_secret() -> int:
    kind, key = parse_id(read_request().get("id", ""))
    if kind == "w" and len(key) == 3:
        password = lookup(*web_attrs(*key))
        if password is None:
            return emit(False, error="That password isn't in the keyring any more.")
        data = extras(*key)
        return emit(True, password=password, notes=data.get("notes", ""), totp=data.get("totp", ""))
    if kind == "c" and len(key) == 2:
        secret = lookup("app", APP, "kind", "code", "label", key[0], "account", key[1])
        return emit(True, password="", notes="", totp=secret or "")
    return emit(False, error="Unknown item.")


def cmd_save() -> int:
    """New or changed: {id?, kind, website, username, password, notes, totp}."""
    req = read_request()
    if req.get("kind") == "code":
        label = str(req.get("title") or "").strip()
        spec_text = str(req.get("totp") or "")
        if not label or not valid_totp(spec_text):
            return emit(False, error="Enter a name and a setup key (or an otpauth:// link).")
        account = str(req.get("username") or "")
        old_kind, old = parse_id(str(req.get("id") or ""))
        if old_kind == "c" and len(old) == 2 and old != [label, account]:
            clear("app", APP, "kind", "code", "label", old[0], "account", old[1])
        store("Passwords: " + label, spec_text, "app", APP, "kind", "code", "label", label, "account", account)
        return emit(True, id="c:" + json.dumps([label, account]))
    website = str(req.get("website") or "").strip()
    if website and "://" not in website:
        website = "https://" + website
    origin = origin_of(website)
    username = str(req.get("username") or "")
    password = str(req.get("password") or "")
    if not origin:
        return emit(False, error="Enter the website's address, like example.com.")
    if not password:
        return emit(False, error="Enter a password.")
    totp_text = str(req.get("totp") or "").strip()
    if totp_text and not valid_totp(totp_text):
        return emit(False, error="That verification code setup key isn't valid.")
    old_kind, old = parse_id(str(req.get("id") or ""))
    profile = old[0] if old_kind == "w" and len(old) == 3 else str(req.get("profile") or "Personal")
    host = urlsplit(origin).hostname or origin
    store(f"Web: {host}" + (f" ({username})" if username else ""), password, *web_attrs(profile, origin, username))
    notes = str(req.get("notes") or "")
    if notes or totp_text:
        store(f"Passwords: {host}", json.dumps({"notes": notes, "totp": totp_text}),
              *extra_attrs(profile, origin, username))
    else:
        clear(*extra_attrs(profile, origin, username))
    # Renamed (another site or user name): the old one goes, after the new is safe.
    if old_kind == "w" and len(old) == 3 and old != [profile, origin, username]:
        clear(*web_attrs(*old))
        clear(*extra_attrs(*old))
    return emit(True, id=web_id(profile, origin, username))


def cmd_delete() -> int:
    kind, key = parse_id(read_request().get("id", ""))
    if kind == "c" and len(key) == 2:
        clear("app", APP, "kind", "code", "label", key[0], "account", key[1])
        return emit(True)
    if kind != "w" or len(key) != 3:
        return emit(False, error="Unknown item.")
    password = lookup(*web_attrs(*key))
    if password is None:
        return emit(False, error="That password isn't in the keyring any more.")
    data = extras(*key)
    stamp = str(int(time.time()))
    profile, origin, username = key
    store(f"Passwords (deleted): {title_of(origin)}", json.dumps({"password": password, **data}),
          "app", APP, "kind", "deleted", "profile", profile, "origin", origin, "username", username, "deleted", stamp)
    clear(*web_attrs(*key))
    clear(*extra_attrs(*key))
    return emit(True)


def deleted_attrs(key: list[str]) -> list[str]:
    profile, origin, username, stamp = key
    return ["app", APP, "kind", "deleted", "profile", profile, "origin", origin, "username", username, "deleted", stamp]


def cmd_restore() -> int:
    kind, key = parse_id(read_request().get("id", ""))
    if kind != "d" or len(key) != 4:
        return emit(False, error="Unknown item.")
    raw = lookup(*deleted_attrs(key))
    try:
        data = json.loads(raw or "")
    except ValueError:
        return emit(False, error="That password isn't in Recently Deleted any more.")
    profile, origin, username, _ = key
    host = urlsplit(origin).hostname or origin
    store(f"Web: {host}" + (f" ({username})" if username else ""), data.get("password", ""),
          *web_attrs(profile, origin, username))
    if data.get("notes") or data.get("totp"):
        store(f"Passwords: {host}", json.dumps({"notes": data.get("notes", ""), "totp": data.get("totp", "")}),
              *extra_attrs(profile, origin, username))
    clear(*deleted_attrs(key))
    return emit(True, id=web_id(profile, origin, username))


def cmd_purge() -> int:
    kind, key = parse_id(read_request().get("id", ""))
    if kind != "d" or len(key) != 4:
        return emit(False, error="Unknown item.")
    clear(*deleted_attrs(key))
    return emit(True)


def cmd_codes() -> int:
    now = time.time()
    out = []
    for i in search("app", APP):
        spec_text = ""
        if i.get("kind") == "code":
            spec_text, item_id = i.get("secret", ""), "c:" + json.dumps([i.get("label", ""), i.get("account", "")])
        elif i.get("kind") == "extra":
            try:
                spec_text = json.loads(i.get("secret") or "{}").get("totp", "")
            except ValueError:
                spec_text = ""
            item_id = web_id(i.get("profile", ""), i.get("origin", ""), i.get("username", ""))
        if not spec_text:
            continue
        try:
            spec = totp_parse(spec_text)
            code = totp(spec["secret"], now, spec["digits"], spec["period"])
        except (ValueError, TypeError, base64.binascii.Error):
            continue
        out.append({"id": item_id, "code": code, "period": spec["period"],
                    "remaining": int(spec["period"] - now % spec["period"])})
    return emit(True, codes=out)


def cmd_wifi_secret() -> int:
    kind, key = parse_id(read_request().get("id", ""))
    if kind != "n" or len(key) != 1:
        return emit(False, error="Unknown network.")
    try:
        p = RUN(["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", key[0]],
                capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return emit(False, error="NetworkManager didn't answer.")
    password = p.stdout.strip()
    if p.returncode != 0 or not password:
        return emit(False, error="This network has no password, or it can only be shown to an administrator.")
    return emit(True, password=password)


def main(argv: list[str]) -> int:
    commands = {"list": cmd_list, "secret": cmd_secret, "save": cmd_save, "delete": cmd_delete,
                "restore": cmd_restore, "purge": cmd_purge, "codes": cmd_codes,
                "wifi-secret": cmd_wifi_secret, "generate": lambda: emit(True, password=generate())}
    fn = commands.get(argv[1] if len(argv) > 1 else "")
    if not fn:
        return emit(False, error="usage: helper.py " + "|".join(commands))
    try:
        return fn()
    except RuntimeError as exc:
        return emit(False, error=str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
