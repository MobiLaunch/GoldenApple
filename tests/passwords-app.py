#!/usr/bin/env python3
"""Passwords (apps/passwords.qml, apps/passwords/helper.py) against a
stand-in keyring that answers like secret-tool (label and secret on stdout,
attributes on stderr).

Checked: a password saved in Web shows in Passwords and one added in
Passwords is where Web looks (same item), the list never carries a secret,
weak and reused passwords are flagged, notes and a verification code ride
along and the code is right (RFC 6238's test vector), renaming moves the
item, delete keeps it in Recently Deleted and restore brings it back,
standalone codes, generated passwords, and Wi-Fi networks from NetworkManager.
Also that the app locks, copies with a clear-after, and is installed and
found like the other apps."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/passwords/helper.py"
failures: list[str] = []

FAKE_TOOL = r'''#!/usr/bin/env python3
import json, os, sys
db = os.environ["FAKE_KEYRING"]
items = json.load(open(db)) if os.path.exists(db) else []
args = sys.argv[1:]
cmd, rest = args[0], args[1:]
label = ""
if rest[:1] == ["--label"]:
    label, rest = rest[1], rest[2:]
if rest[:1] == ["--all"]:
    rest = rest[1:]
want = dict(zip(rest[::2], rest[1::2]))
match = [i for i in items if all(i["attrs"].get(k) == v for k, v in want.items())]
if cmd == "store":
    secret = sys.stdin.read()
    items = [i for i in items if i["attrs"] != want] + [{"attrs": want, "secret": secret, "label": label}]
    json.dump(items, open(db, "w"))
elif cmd == "lookup":
    if not match: sys.exit(1)
    sys.stdout.write(match[0]["secret"] + "\n")
elif cmd == "clear":
    json.dump([i for i in items if i not in match], open(db, "w"))
elif cmd == "search":
    for n, i in enumerate(match):
        print(f"[/org/freedesktop/secrets/collection/login/{n}]")
        print("label = " + i["label"]); print("secret = " + i["secret"])
        print("created = 2026-10-01 10:00:00"); print("modified = 2026-10-02 11:00:00")
        print("schema = org.freedesktop.Secret.Generic")
        for k, v in i["attrs"].items():
            print(f"attribute.{k} = {v}", file=sys.stderr)
'''

FAKE_NMCLI = r'''#!/bin/sh
case "$*" in
  *"connection show"*uuid*) echo "hunter2-wifi";;
  *NAME,UUID,TYPE*) printf 'Home Wi\\:Fi:1111-aaaa:802-11-wireless\nWired:2222-bbbb:802-3-ethernet\nCafe:3333-cccc:802-11-wireless\n';;
esac
'''


def check(cond: bool, what: str) -> None:
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures.append(what)


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    bin_ = tmp / "bin"
    bin_.mkdir()
    (bin_ / "secret-tool").write_text(FAKE_TOOL)
    (bin_ / "nmcli").write_text(FAKE_NMCLI)
    for f in bin_.iterdir():
        f.chmod(0o755)
    env = dict(os.environ, PATH=f"{bin_}:{os.environ['PATH']}", FAKE_KEYRING=str(tmp / "keyring.json"), XDG_STATE_HOME=str(tmp / "state"))

    def helper(cmd: str, req: dict | None = None) -> dict:
        p = subprocess.run([sys.executable, str(HELPER), cmd], input=json.dumps(req or {}), capture_output=True,
                           text=True, env=env, timeout=60)
        return json.loads(p.stdout.strip().splitlines()[-1])

    def web_save(origin: str, user: str, password: str, profile: str = "Personal") -> None:
        sys.path.insert(0, str(ROOT / "apps/browser"))
        from passwords import Passwords
        os.environ.update(PATH=env["PATH"], FAKE_KEYRING=env["FAKE_KEYRING"], XDG_STATE_HOME=env["XDG_STATE_HOME"])
        assert Passwords(profile).save(origin, user, password)

    # Saved in Web.
    web_save("https://github.com", "jordan", "Tr1cky-Horse-Battery!")
    web_save("https://news.example.com", "jordan", "password1")
    web_save("https://shop.example.org", "j@x.com", "Same-Pass-1234!")
    web_save("https://bank.example.net", "jordan", "Same-Pass-1234!")
    r = helper("list")
    titles = {i["title"]: i for i in r["items"]}
    check(r["ok"] and {"github.com", "news.example.com", "shop.example.org", "bank.example.net"} <= set(titles),
          f"passwords saved in Web are listed: {sorted(titles)}")
    check("Tr1cky" not in json.dumps(r) and "Same-Pass" not in json.dumps(r), "the list carries no password")
    check(titles["news.example.com"]["weak"] and not titles["github.com"]["weak"], "a weak password is flagged")
    check(titles["shop.example.org"]["reused"] and titles["bank.example.net"]["reused"] and not titles["github.com"].get("reused"),
          "a password used on two sites is flagged on both")

    # Added in Passwords: where Web looks, with notes and a code.
    s = helper("save", {"kind": "website", "website": "mail.example.com", "username": "me", "password": "Gen-erated-123",
                        "notes": "recovery: 42", "totp": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"})
    check(s["ok"], f"a new password saves: {s}")
    from passwords import Passwords
    check(Passwords("Personal").password("https://mail.example.com", "me") == "Gen-erated-123",
          "Web finds a password added in Passwords")
    sec = helper("secret", {"id": s["id"]})
    check(sec["password"] == "Gen-erated-123" and sec["notes"] == "recovery: 42" and sec["totp"],
          "its password, notes and code come back for that one item")
    sys.path.insert(0, str(ROOT / "apps/passwords"))
    import helper as H  # noqa: E402
    check(H.totp("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 59, 8) == "94287082", "codes follow RFC 6238 (test vector at T=59)")
    check(H.totp_parse("otpauth://totp/GitHub:jordan?secret=JBSWY3DPEHPK3PXP&issuer=GitHub")["issuer"] == "GitHub",
          "an otpauth:// link is read")
    check(all(H.code_remaining(at, 30) == expected for at, expected in
              ((0, 30), (29, 1), (29.999, 1), (30, 30), (59.999, 1), (60, 30))),
          "verification code counts down 1..30 even at fractional rollover")
    codes = helper("codes")
    check(any(c["id"] == s["id"] and re.fullmatch(r"\d{6}", c["code"]) and 0 < c["remaining"] <= 30 for c in codes["codes"]),
          f"the current code and seconds left: {codes}")

    # Renamed: the old one goes.
    s2 = helper("save", {"id": s["id"], "website": "mail.example.com", "username": "me2", "password": "Gen-erated-123",
                         "notes": "recovery: 42", "totp": ""})
    r = helper("list")
    users = [i["username"] for i in r["items"] if i["title"] == "mail.example.com"]
    check(users == ["me2"], f"a changed user name moves the item: {users}")
    check(not helper("secret", {"id": s2["id"]})["totp"], "a removed code is gone")

    # Delete, restore.
    gh = titles["github.com"]["id"]
    check(helper("delete", {"id": gh})["ok"], "delete")
    r = helper("list")
    check("github.com" not in {i["title"] for i in r["items"]} and [d["title"] for d in r["deleted"]] == ["github.com"]
          and r["deleted"][0]["daysLeft"] in (29, 30),
          f"deleted goes to Recently Deleted for 30 days: {r['deleted']}")
    check(Passwords("Personal").password("https://github.com", "jordan") is None, "Web no longer offers it")
    check(helper("restore", {"id": r["deleted"][0]["id"]})["ok"] and
          Passwords("Personal").password("https://github.com", "jordan") == "Tr1cky-Horse-Battery!", "restore brings it back")
    check(helper("list")["deleted"] == [], "and Recently Deleted is empty again")

    # A newer password at the same identity must survive recovery, creation
    # and rename collisions, with the older deleted item still recoverable.
    helper("delete", {"id": gh})
    old_deleted = helper("list")["deleted"][0]["id"]
    web_save("https://github.com", "jordan", "New-current-password-42!")
    recovery = helper("restore", {"id": old_deleted})
    check(not recovery["ok"] and "already exists" in recovery["error"], "recovery explains an existing current password")
    check(Passwords("Personal").password("https://github.com", "jordan") == "New-current-password-42!",
          "recovery never overwrites the newer credential")
    check(any(d["id"] == old_deleted for d in helper("list")["deleted"]), "the old credential stays in Recently Deleted")
    duplicate = helper("save", {"website": "github.com", "username": "jordan", "password": "collision"})
    check(not duplicate["ok"], "adding a duplicate refuses replacement")
    rename_collision = helper("save", {"id": s2["id"], "website": "github.com", "username": "jordan", "password": "collision"})
    check(not rename_collision["ok"] and Passwords("Personal").password("https://mail.example.com", "me2") == "Gen-erated-123",
          "rename collisions keep both current items")

    # Standalone code.
    c = helper("save", {"kind": "code", "title": "AWS", "username": "root", "totp": "JBSWY3DPEHPK3PXP"})
    check(c["ok"] and any(i["kind"] == "code" and i["title"] == "AWS" for i in helper("list")["items"]), "a code on its own")
    check(not helper("save", {"kind": "code", "title": "Bad", "totp": "not base32!!"})["ok"], "a bad setup key is refused")

    g = helper("generate")["password"]
    check(re.fullmatch(r"[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}-[a-zA-Z0-9]{6}", g) and re.search(r"\d", g) and re.search(r"[A-Z]", g),
          f"a generated password: {g}")
    check(not H.weak(g), "and it isn't weak")

    wifi = helper("list")["wifi"]
    check([w["title"] for w in wifi] == ["Cafe", "Home Wi:Fi"], f"Wi-Fi networks (not wired): {wifi}")
    check(helper("wifi-secret", {"id": wifi[1]["id"]})["password"] == "hunter2-wifi", "a Wi-Fi password is shown on request")

qml = (ROOT / "apps/passwords.qml").read_text()
check("PamContext" in qml and "locked" in qml and "lockTimer" in qml, "the app opens locked and locks again")
check("clearClipboard" in qml, "a copied password is cleared from the clipboard after a while")
desktop = (ROOT / "apps/desktop/org.goldengate.Passwords.desktop").read_text()
check("passwords.qml" in desktop and "Icon=org.goldengate.Passwords" in desktop, "it's an app with its own icon")
check('"org.goldengate.Passwords"' in (ROOT / "shell/Applications.qml").read_text(), "Launchpad has it")
check("passwords:" in (ROOT / "icons/source.mjs").read_text(), "its icon is drawn")

print("Passwords: " + ("all checks passed" if not failures else f"{len(failures)} failed"))
sys.exit(1 if failures else 0)
