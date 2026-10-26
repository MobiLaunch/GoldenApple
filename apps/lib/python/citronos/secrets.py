"""The login keyring (the Secret Service, GNOME Keyring), through libsecret's
secret-tool: it asks to unlock the keyring when it must, which a helper can't
do itself. Secrets go to it on stdin, never in arguments; nothing here logs.

    secrets.store("CitronOS Mail", password, service="golden-gate-mail", account=a)
    secrets.lookup(service="golden-gate-mail", account=a)   # "" if there's none
    secrets.clear(service="golden-gate-mail", account=a)
    secrets.search(app="org.goldengate.Web")                 # [{"attributes", "secret"}]

A missing secret-tool, a keyring that doesn't answer (locked, waiting) and a
refused write raise SecretError with code "missing", "timeout" or "failed".
"""
from __future__ import annotations

from . import proc

TIMEOUT = 20


class SecretError(Exception):
    def __init__(self, message: str, code: str):
        super().__init__(message)
        self.code = code


def _attrs(attributes: dict) -> list[str]:
    if not attributes:
        raise ValueError("A keyring item needs at least one attribute.")
    out = []
    for key, value in attributes.items():
        if not isinstance(value, str) or not key:
            raise ValueError("Keyring attributes are names with text values.")
        out += [key, value]
    return out


def _tool(args: list[str], secret: str = "", timeout: float = TIMEOUT) -> proc.Result:
    result = proc.run(["secret-tool", *args], timeout=timeout, input=secret)
    if result.missing:
        raise SecretError("The keyring can't be reached: secret-tool (libsecret) isn't installed.", "missing")
    if result.timed_out:
        raise SecretError("The keyring didn't answer. It may be waiting to be unlocked.", "timeout")
    return result


def lookup(timeout: float = TIMEOUT, **attributes: str) -> str:
    result = _tool(["lookup", *_attrs(attributes)], timeout=timeout)
    return result.stdout.rstrip("\n") if result.ok else ""


def store(label: str, secret: str, timeout: float = TIMEOUT, **attributes: str) -> None:
    if not isinstance(secret, str) or not secret:
        raise ValueError("There's nothing to save in the keyring.")
    result = _tool(["store", "--label=" + label, *_attrs(attributes)], secret=secret, timeout=timeout)
    if not result.ok:
        raise SecretError("The keyring didn't save it. Unlock your login keyring and try again.", "failed")


def clear(timeout: float = TIMEOUT, **attributes: str) -> None:
    """Removes the matching items; having none is fine."""
    result = _tool(["clear", *_attrs(attributes)], timeout=timeout)
    if not result.ok and result.stderr.strip():
        raise SecretError("The keyring didn't remove it. Unlock your login keyring and try again.", "failed")


def search(timeout: float = TIMEOUT, **attributes: str) -> list[dict]:
    """Every matching item, as {"attributes": {…}, "secret": "…"}, in keyring order."""
    result = _tool(["search", "--all", *_attrs(attributes)], timeout=timeout)
    if not result.ok:
        return []
    # secret-tool prints each item's "[path]", label, "secret = …" and dates
    # on stdout, and its "attribute.x = value" lines on stderr, items in the
    # same order in both.
    items: list[dict] = []
    for line in result.stdout.splitlines():
        if line.startswith("[") and line.endswith("]"):
            items.append({"attributes": {}, "secret": ""})
        elif items and line.startswith("secret = "):
            items[-1]["secret"] = line[len("secret = "):]
    n = -1
    for line in result.stderr.splitlines():
        if line.startswith("[") and line.endswith("]"):
            n += 1
        elif 0 <= n < len(items) and line.startswith("attribute.") and " = " in line:
            key, value = line[len("attribute."):].split(" = ", 1)
            items[n]["attributes"][key] = value
    return items
