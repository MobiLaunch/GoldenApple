"""The rules every CitronOS account is made to: Hello (setup/account-helper.py)
and the installer (installer/helper.py) both check with these, before
anything is created or erased.

Root helpers load this file from beside themselves by path (they run with
python -I, so it can't be found on sys.path); keep it dependency-free."""
from __future__ import annotations

import re

NAME = re.compile(r"[a-z_][a-z0-9_-]{0,30}")
# System accounts and groups, and names that mean something to the system
# whether or not this image has them yet.
RESERVED = {
    "root", "bin", "daemon", "adm", "lp", "sync", "shutdown", "halt", "mail", "news", "uucp", "operator",
    "games", "gopher", "ftp", "nobody", "dbus", "polkitd", "systemd-journal", "systemd-network",
    "systemd-resolve", "systemd-timesync", "systemd-coredump", "systemd-oom", "uuidd", "avahi", "colord",
    "git", "http", "rtkit", "sddm", "usbmux", "geoclue", "flatpak", "pipewire", "wheel", "users", "sudo",
    "admin", "audio", "video", "input", "kvm", "render", "disk", "tty", "utmp", "lock", "network", "storage",
    "optical", "scanner", "power", "log", "proc", "mem", "kmem", "floppy", "rfkill", "sgx", "tss", "alpm",
    "nm-openconnect", "nm-openvpn", "brlapi", "cups", "gdm", "lightdm", "ntp", "postfix", "sshd", "tor",
}


def check_username(name: object, taken: set[str] | frozenset[str] = frozenset()) -> str:
    """Why name can't be a new account's name, or "". `taken`: names
    already used by an account or group where the account will be made."""
    if not isinstance(name, str) or not NAME.fullmatch(name):
        return "Use a lowercase account name, starting with a letter, up to 31 characters."
    if name in RESERVED or name in taken:
        return f"“{name}” is already used by the system. Choose a different account name."
    return ""


def check_password(password: object) -> str:
    if not isinstance(password, str) or not 8 <= len(password) <= 256:
        return "Use a password of 8–256 characters."
    if any(c in password for c in "\n\r\0"):
        return "A password can't contain line breaks."
    if any(ord(c) < 32 or ord(c) == 127 for c in password):
        return "A password can't contain control characters."
    return ""


def check_full_name(full: object) -> str:
    if not isinstance(full, str) or not full.strip() or len(full.strip()) > 80 \
            or any(ord(c) < 32 or ord(c) == 127 or c in ":," for c in full):
        return "Enter a full name without colons, commas, or control characters."
    return ""


def names_in(*files: str) -> set[str]:
    """The first field of each line of passwd/group-style files that exist."""
    out: set[str] = set()
    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                out |= {line.split(":", 1)[0] for line in f if ":" in line}
        except OSError:
            pass
    return out
