#!/usr/bin/env python3
"""CitronOS's disks, for Files' sidebar and Disk Utility.

  disks.py snapshot                   every disk and volume, as JSON
  disks.py usage PATH                 size, used and free space of PATH's volume
  disks.py largest PATH               the biggest folders directly in PATH (du -x)
  disks.py mount DEVICE               mount a volume (udisks: no root needed)
  disks.py unmount DEVICE
  disks.py eject DISK                 unmount its volumes, then power it off
  disks.py check DEVICE               First Aid: a read-only filesystem check
  disks.py repair DEVICE              First Aid: repair the filesystem
  disks.py erase DEVICE FORMAT NAME   erase a volume, or a removable disk whole

Reading needs nothing special (lsblk, findmnt, statvfs). Changing goes
through udisks2 over D-Bus, which asks for a password itself (polkit) when
one is needed. Nothing that holds the running system (/, /home, /boot, swap,
the live USB) can be erased, checked, repaired, unmounted or ejected here.
Every command prints one JSON object: {"ok": true, ...} or {"ok": false, "error": "..."}.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys

# Mounts that hold the running system.
SYSTEM_MOUNTS = ("/", "/home", "/boot", "/boot/efi", "/efi", "/usr", "/var", "[SWAP]",
                 "/run/archiso/bootmnt", "/run/archiso/cowspace", "/run/archiso/airootfs")
# What Erase can make, as Disk Utility names them.
FORMATS = {
    "exfat": "ExFAT",
    "vfat": "MS-DOS (FAT)",
    "ext4": "Linux (ext4)",
    "btrfs": "Btrfs",
    "ntfs": "Windows NT (NTFS)",
}
LABEL_LIMIT = {"vfat": 11, "exfat": 15, "ext4": 16, "btrfs": 255, "ntfs": 32}
UDISKS = "org.freedesktop.UDisks2"


def run(cmd: list[str], timeout: float = 20, **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)


def human(n: int | float) -> str:
    n = float(n or 0)
    for unit in ("bytes", "KB", "MB", "GB", "TB", "PB"):
        if n < 1000 or unit == "PB":
            return f"{n:.0f} {unit}" if unit in ("bytes", "KB") else f"{n:.1f} {unit}".replace(".0 ", " ")
        n /= 1000
    return ""


def os_name() -> str:
    try:
        for line in open("/etc/os-release", encoding="utf-8"):
            if line.startswith("NAME="):
                return line.split("=", 1)[1].strip().strip('"') or "System"
    except OSError:
        pass
    return "System"


def usage(path: str) -> dict:
    st = os.statvfs(path)
    size = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    used = size - st.f_bfree * st.f_frsize
    return {"size": size, "used": used, "free": free}


def mount_table() -> dict[str, tuple[str, str]]:
    """Mount point → (source, filesystem), from the kernel."""
    out = {}
    try:
        for line in open("/proc/self/mounts", encoding="utf-8"):
            src, target, fstype = line.split()[:3]
            out[target.replace("\\040", " ")] = (src, fstype)
    except OSError:
        pass
    return out


def is_system(mounts: list[str]) -> bool:
    return any(m in SYSTEM_MOUNTS for m in mounts)


def display_name(dev: dict, mounts: list[str], system_name: str) -> str:
    if dev.get("label"):
        return dev["label"]
    if dev.get("partlabel"):
        return dev["partlabel"]
    if "/" in mounts:
        return system_name
    if "/home" in mounts:
        return "Home"
    if any(m.startswith("/boot") or m == "/efi" for m in mounts):
        return "Boot"
    if "[SWAP]" in mounts:
        return "Swap"
    return human(dev.get("size") or 0) + " Volume"


def disk_name(dev: dict) -> str:
    model = " ".join((dev.get("model") or "").split())
    if model:
        return model
    tran = (dev.get("tran") or "").upper()
    kind = {"USB": "USB", "NVME": "NVMe", "SATA": "SATA", "MMC": "SD Card", "VIRTIO": "Virtual"}.get(tran, "")
    return f"{human(dev.get('size') or 0)} {kind} Disk".replace("  ", " ")


def parse(tree: dict, mounts: dict[str, tuple[str, str]] | None = None, system_name: str | None = None,
          root_usage=None) -> dict:
    """Disks and their volumes from `lsblk -J -b -o …` (see COLUMNS)."""
    mounts = mount_table() if mounts is None else mounts
    system_name = system_name or os_name()
    root_usage = root_usage or (lambda path: usage(path))
    disks = []
    for dev in tree.get("blockdevices", []):
        if dev.get("type") not in ("disk", "rom") or dev["name"].startswith(("zram", "loop", "ram")):
            continue
        if dev.get("type") == "rom" and not dev.get("fstype"):
            continue
        children = dev.get("children") or []
        removable = bool(dev.get("rm") or dev.get("hotplug")) or (dev.get("tran") or "") in ("usb", "mmc")
        volumes = []
        # A disk without partitions can carry the filesystem itself.
        for part in (children or [dev]):
            if part.get("type") not in ("part", "disk", "rom", "crypt", "lvm"):
                continue
            points = [m for m in (part.get("mountpoints") or []) if m]
            for child in part.get("children") or []:            # LUKS / LVM inside a partition
                points += [m for m in (child.get("mountpoints") or []) if m]
            fstype = part.get("fstype") or next((mounts[m][1] for m in points if m in mounts), "")
            if not fstype and not points and part is dev:
                continue                                        # an empty disk: no volume to show
            first = next((m for m in points if m != "[SWAP]"), "")
            size, used, free = part.get("fssize"), part.get("fsused"), part.get("fsavail")
            if first and size is None:
                try:
                    u = root_usage(first)
                    size, used, free = u["size"], u["used"], u["free"]
                except OSError:
                    pass
            volumes.append({
                "name": display_name(part, points, system_name),
                "device": part["path"],
                "disk": dev["path"],
                "fstype": fstype or "",
                "format": FORMATS.get(fstype, fstype.upper() if fstype else "Unknown"),
                "label": part.get("label") or "",
                "uuid": part.get("uuid") or "",
                "capacity": part.get("size") or 0,
                "size": size or part.get("size") or 0,
                "used": used or 0,
                "free": free or 0,
                "mountpoint": first,
                "mounted": bool(points),
                "system": is_system(points),
                "removable": removable,
                "readonly": bool(part.get("ro")),
                "partition": part is not dev,
                "swap": "[SWAP]" in points or fstype == "swap",
            })
        disks.append({
            "name": disk_name(dev),
            "device": dev["path"],
            "model": " ".join((dev.get("model") or "").split()),
            "size": dev.get("size") or 0,
            "transport": dev.get("tran") or "",
            "removable": removable,
            "readonly": bool(dev.get("ro")),
            "system": any(v["system"] for v in volumes),
            "volumes": volumes,
        })
    # The live system's / is an overlay with no disk of its own: show it anyway.
    if not any(v["mountpoint"] == "/" for d in disks for v in d["volumes"]):
        try:
            u = root_usage("/")
            src, fstype = mounts.get("/", ("", ""))
            disks.insert(0, {"name": system_name, "device": "", "model": "", "size": u["size"], "transport": "",
                             "removable": False, "readonly": False, "system": True, "volumes": [{
                                 "name": system_name, "device": "", "disk": "", "fstype": fstype, "format": fstype,
                                 "label": "", "uuid": "", "capacity": u["size"], "size": u["size"], "used": u["used"],
                                 "free": u["free"], "mountpoint": "/", "mounted": True, "system": True,
                                 "removable": False, "readonly": False, "partition": False, "swap": False}]})
        except OSError:
            pass
    # The system's disk first, then other internal disks, then external ones.
    disks.sort(key=lambda d: (not d["system"], d["removable"]))
    return {"disks": disks, "systemName": system_name}


COLUMNS = "NAME,PATH,PKNAME,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS,FSSIZE,FSUSED,FSAVAIL,RM,HOTPLUG,RO,TRAN,MODEL,PARTLABEL"


def snapshot() -> dict:
    # GG_DISKS_FIXTURE: a JSON file of {"lsblk", "mounts", "systemName",
    # "usage"} read instead of this computer's disks (tests, screenshots).
    fixture = os.environ.get("GG_DISKS_FIXTURE")
    if fixture:
        with open(fixture, encoding="utf-8") as f:
            data = json.load(f)
        mounts = {k: tuple(v) for k, v in data.get("mounts", {}).items()}
        return parse(data["lsblk"], mounts, data.get("systemName"), lambda path: data["usage"])
    p = run(["lsblk", "-J", "-b", "-o", COLUMNS])
    if p.returncode != 0:
        raise RuntimeError("Couldn't read the disks (lsblk).")
    return parse(json.loads(p.stdout or "{}"))


def find(device: str) -> tuple[dict, dict | None]:
    """The disk and (if it's one) the volume named by device."""
    for disk in snapshot()["disks"]:
        if disk["device"] == device:
            return disk, None
        for vol in disk["volumes"]:
            if vol["device"] == device:
                return disk, vol
    raise RuntimeError("That disk is no longer connected.")


def object_path(device: str) -> str:
    """udisks' D-Bus object for /dev/NAME: anything but letters and digits as _xx."""
    name = os.path.basename(device)
    return "/org/freedesktop/UDisks2/block_devices/" + "".join(c if c.isalnum() else f"_{ord(c):02x}" for c in name)


def udisks(device: str, interface: str, method: str, *args: str, timeout: float = 600) -> str:
    if not shutil.which("gdbus"):
        raise RuntimeError("Disk changes need gdbus (glib2).")
    p = run(["gdbus", "call", "--system", "--dest", UDISKS, "--object-path", object_path(device),
             "--method", f"{UDISKS}.{interface}.{method}", *args], timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(udisks_error(p.stderr))
    return p.stdout.strip()


def udisks_error(text: str) -> str:
    if "NotAuthorized" in text or "not authorized" in text.lower():
        return "You weren't allowed to change this disk."
    if "ServiceUnknown" in text or "was not provided by any .service" in text or "connecting to the udisks daemon" in text:
        return "Disk changes need the udisks2 service. Install udisks2 with Software Update."
    if "DeviceBusy" in text or "target is busy" in text:
        return "The disk is in use. Quit the apps using it and try again."
    if "UnknownMethod" in text or "No such interface" in text:
        return "This disk doesn't support that."
    m = re.search(r"GDBus\.Error:[\w.]+:\s*(.+)", text)
    return (m.group(1) if m else text.strip() or "The disk didn't respond.")[:200]


def udisksctl(*args: str, timeout: float = 120) -> str:
    if not shutil.which("udisksctl"):
        raise RuntimeError("Mounting needs udisks2. Install it with Software Update.")
    p = run(["udisksctl", *args], timeout=timeout)
    if p.returncode != 0:
        raise RuntimeError(udisks_error(p.stderr or p.stdout))
    return p.stdout.strip()


def guarded(device: str, what: str, whole: bool = False) -> tuple[dict, dict | None]:
    """The disk and volume, unless what would be changed holds the running
    system. `whole`: the change reaches every volume on the disk (eject)."""
    disk, vol = find(device)
    target = disk if vol is None or whole else vol
    if target["system"]:
        raise RuntimeError(f"{target['name']} holds the running system, so it can't be {what}.")
    return disk, vol


def mount(device: str) -> dict:
    disk, vol = find(device)
    if vol is None:
        raise RuntimeError("Choose a volume to mount.")
    if vol["mounted"]:
        return {"mountpoint": vol["mountpoint"]}
    out = udisksctl("mount", "-b", device)
    m = re.search(r" at (.+?)\.?$", out)
    return {"mountpoint": m.group(1) if m else ""}


def unmount(device: str) -> dict:
    disk, vol = guarded(device, "unmounted")
    if vol is None:
        raise RuntimeError("Choose a volume to unmount.")
    if vol["mounted"]:
        udisksctl("unmount", "-b", device)
    return {}


def eject(device: str) -> dict:
    disk, vol = guarded(device, "ejected", whole=True)
    for v in disk["volumes"]:
        if v["mounted"] and not v["swap"]:
            udisksctl("unmount", "-b", v["device"])
    if disk["removable"]:
        try:
            udisksctl("power-off", "-b", disk["device"])
        except RuntimeError:
            pass                    # unmounted is safe to unplug even if it can't be powered off
    return {}


def check(device: str, repair: bool = False) -> dict:
    disk, vol = guarded(device, "repaired" if repair else "checked")
    if vol is None:
        raise RuntimeError("Choose a volume to check.")
    if vol["mounted"]:
        raise RuntimeError(f"Unmount {vol['name']} first: a volume in use can't be checked.")
    out = udisks(device, "Filesystem", "Repair" if repair else "Check", "{}")
    healthy = "true" in out.lower()
    return {"healthy": healthy}


def erase(device: str, fmt: str, name: str) -> dict:
    disk, vol = guarded(device, "erased")
    if fmt not in FORMATS:
        raise RuntimeError("Choose a format.")
    name = name.strip()
    if not name or len(name) > LABEL_LIMIT[fmt] or any(c in name for c in "'\"\\/<>") or not name.isprintable():
        raise RuntimeError(f"Use a name of up to {LABEL_LIMIT[fmt]} letters, without quotes or slashes.")
    label = name.upper() if fmt == "vfat" else name
    options = f"{{'label': <'{label}'>, 'update-partition-type': <true>}}"
    if vol is None and not disk["removable"]:
        raise RuntimeError("Only a removable disk can be erased whole here; erase one of its volumes instead.")
    for v in (disk["volumes"] if vol is None else [vol]):
        if v["mounted"]:
            udisksctl("unmount", "-b", v["device"])
    if vol is not None:
        udisks(device, "Block", "Format", fmt, options)
        return {"device": device}
    # The whole disk: a new GPT partition table and one volume filling it.
    udisks(device, "Block", "Format", "gpt", "{}")
    out = udisks(device, "PartitionTable", "CreatePartitionAndFormat",
                 "0", "0", "", "", "{}", fmt, f"{{'label': <'{label}'>}}")
    return {"device": device, "created": out}


def largest(path: str, limit: int = 12) -> dict:
    """The biggest folders directly in `path`, on its own filesystem."""
    path = os.path.realpath(path)
    try:
        p = run(["du", "-x", "-b", "--max-depth=1", path], timeout=120)
    except subprocess.TimeoutExpired:
        raise RuntimeError("Measuring took too long.")
    rows, total = [], 0
    for line in p.stdout.splitlines():
        size, _, item = line.partition("\t")
        if not size.isdigit():
            continue
        if item == path:
            total = int(size)
        else:
            rows.append({"path": item, "name": os.path.basename(item), "size": int(size)})
    rows.sort(key=lambda r: -r["size"])
    return {"path": path, "total": total, "items": rows[:limit], "partial": p.returncode != 0}


def main(argv: list[str]) -> int:
    cmd, args = (argv[1] if len(argv) > 1 else ""), argv[2:]
    try:
        if cmd == "snapshot":
            out = snapshot()
        elif cmd == "usage" and len(args) == 1:
            out = usage(args[0])
        elif cmd == "largest" and len(args) == 1:
            out = largest(args[0])
        elif cmd == "mount" and len(args) == 1:
            out = mount(args[0])
        elif cmd == "unmount" and len(args) == 1:
            out = unmount(args[0])
        elif cmd == "eject" and len(args) == 1:
            out = eject(args[0])
        elif cmd in ("check", "repair") and len(args) == 1:
            out = check(args[0], repair=cmd == "repair")
        elif cmd == "erase" and len(args) == 3:
            out = erase(*args)
        else:
            raise RuntimeError("usage: disks.py snapshot | usage PATH | largest PATH | mount|unmount|eject|check|repair DEVICE | erase DEVICE FORMAT NAME")
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"ok": False, "error": str(exc) or type(exc).__name__}))
        return 1
    print(json.dumps({"ok": True, **out}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
