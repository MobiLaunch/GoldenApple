"""Saved website passwords for CitronOS Web, kept in the system keyring.

Qt WebEngine has no password manager of its own, so Web keeps logins the way
Mail keeps its account password: in the Secret Service (GNOME Keyring), through
`secret-tool`, unlocked with your login. Each login is stored under the site's
origin (scheme, host and port: a password saved for https://example.com is
never offered to http://example.com or another host) and the Web profile it
was saved in.
"""
from __future__ import annotations

import subprocess
from urllib.parse import urlsplit

APP = "org.goldengate.Web"
SCHEMA = "org.goldengate.Web.Password"


def origin_of(url: str) -> str:
    """https://accounts.example.com:8443/path → https://accounts.example.com:8443"""
    try:
        parts = urlsplit(url or "")
    except ValueError:
        return ""
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return ""
    host = parts.hostname.lower()
    default = {"http": 80, "https": 443}[parts.scheme]
    try:
        port = parts.port
    except ValueError:
        return ""
    return f"{parts.scheme}://{host}" + (f":{port}" if port and port != default else "")


class Passwords:
    def __init__(self, profile: str, runner=subprocess.run):
        self.profile = profile
        self._run = runner
        self.error = ""

    def _attrs(self, origin: str, username: str | None = None) -> list[str]:
        attrs = ["app", APP, "profile", self.profile, "origin", origin]
        if username is not None:
            attrs += ["username", username]
        return attrs

    def _call(self, args: list[str], secret: str | None = None) -> subprocess.CompletedProcess | None:
        try:
            p = self._run(["secret-tool", *args], input=secret if secret is not None else "",
                          capture_output=True, text=True, timeout=20)
        except FileNotFoundError:
            self.error = "Web can't reach the keyring (secret-tool, from libsecret, isn't installed)."
            return None
        except subprocess.TimeoutExpired:
            self.error = "The keyring didn't answer. It may be waiting to be unlocked."
            return None
        if p.returncode != 0 and p.stderr.strip():
            self.error = p.stderr.strip().splitlines()[-1]
        return p

    def logins(self, origin: str = "") -> list[dict]:
        """[{origin, username}] for one site, or for every site when origin is empty."""
        args = ["search", "--all", "app", APP, "profile", self.profile]
        if origin:
            args += ["origin", origin]
        p = self._call(args)
        if p is None or p.returncode != 0:
            return []
        # secret-tool prints each item's label and secret on stdout but its
        # "attribute.x = value" lines on stderr, so items are told apart there:
        # every item carries the same attributes, and a repeated one starts
        # the next item.
        found, item = [], {}
        for line in p.stderr.splitlines():
            if not line.startswith("attribute.") or " = " not in line:
                continue
            key, value = line[len("attribute."):].split(" = ", 1)
            if key in item:
                found.append(item)
                item = {}
            item[key] = value
        if item:
            found.append(item)
        found = [{"origin": i["origin"], "username": i.get("username", "")}
                 for i in found if i.get("origin") and i.get("app") == APP and i.get("profile") == self.profile]
        unique = {(i["origin"], i["username"]): i for i in found}
        return sorted(unique.values(), key=lambda i: (i["origin"], i["username"].lower()))

    def password(self, origin: str, username: str) -> str | None:
        p = self._call(["lookup", *self._attrs(origin, username)])
        if p is None or p.returncode != 0:
            return None
        # secret-tool ends its output with a line break when it writes to a
        # terminal (and some builds always do). A web password can't contain
        # one, so a single trailing break is never part of the secret.
        secret = p.stdout
        return secret[:-1] if secret.endswith("\n") else secret

    def credentials(self, origin: str) -> list[dict]:
        """[{username, password}] saved for this site."""
        out = []
        for login in self.logins(origin):
            secret = self.password(origin, login["username"])
            if secret is not None:
                out.append({"username": login["username"], "password": secret})
        return out

    def save(self, origin: str, username: str, password: str) -> bool:
        if not origin or not password:
            return False
        host = urlsplit(origin).hostname or origin
        label = f"Web: {host}" + (f" ({username})" if username else "")
        p = self._call(["store", "--label", label, *self._attrs(origin, username)], secret=password)
        return p is not None and p.returncode == 0

    def remove(self, origin: str, username: str) -> bool:
        p = self._call(["clear", *self._attrs(origin, username)])
        return p is not None and p.returncode == 0
