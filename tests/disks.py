#!/usr/bin/env python3
"""apps/lib/disks/disks.py, which Files and Disk Utility share: disks and
volumes read from lsblk, named as on a Mac, the running system recognised and
never changed, and every change made through udisks (no root, no mkfs here)."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("disks", ROOT / "apps/lib/disks/disks.py")
disks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(disks)

GB = 1000 ** 3


def dev(name, kind="part", size=GB, fstype=None, label=None, mounts=(), tran=None, model=None, rm=False,
        children=None, fssize=None, fsused=None, fsavail=None, partlabel=None):
    return {"name": name, "path": "/dev/" + name, "type": kind, "size": size, "fstype": fstype, "label": label,
            "uuid": None, "mountpoints": list(mounts) or [None], "fssize": fssize, "fsused": fsused,
            "fsavail": fsavail, "rm": rm, "hotplug": rm, "ro": False, "tran": tran, "model": model,
            "partlabel": partlabel, "children": children}


# A live USB session: / is an overlay; the stick it booted from, an internal
# NVMe with Windows and a spare partition, and an external backup drive.
LIVE = {"blockdevices": [
    dev("loop0", "loop", fstype="squashfs", mounts=["/run/archiso/airootfs"]),
    dev("sda", "disk", 32 * GB, tran="usb", model="Kingston DataTraveler", rm=True, children=[
        dev("sda1", size=2 * GB, fstype="iso9660", label="CITRON_2026", mounts=["/run/archiso/bootmnt"]),
        dev("sda2", size=100 * 1000 ** 2, fstype="vfat", label="CITRON_EFI")]),
    dev("nvme0n1", "disk", 1000 * GB, tran="nvme", model="Samsung SSD 990 PRO 1TB", children=[
        dev("nvme0n1p1", size=GB, fstype="vfat", partlabel="EFI system partition"),
        dev("nvme0n1p2", size=500 * GB, fstype="ntfs", label="Windows"),
        dev("nvme0n1p3", size=499 * GB, fstype="ext4")]),
    dev("sdb", "disk", 2000 * GB, tran="usb", model="SanDisk Extreme", rm=True, children=[
        dev("sdb1", size=2000 * GB, fstype="exfat", label="BACKUP", mounts=["/run/media/live/BACKUP"],
            fssize=2000 * GB, fsused=800 * GB, fsavail=1200 * GB)]),
    dev("zram0", "disk", 4 * GB, mounts=["[SWAP]"]),
]}
LIVE_MOUNTS = {"/": ("airootfs", "overlay")}

# Installed: CitronOS on the NVMe, /home on its own partition.
INSTALLED = {"blockdevices": [
    dev("nvme0n1", "disk", 1000 * GB, tran="nvme", model="WD Black SN850X", children=[
        dev("nvme0n1p1", size=GB, fstype="vfat", mounts=["/boot"]),
        dev("nvme0n1p2", size=200 * GB, fstype="ext4", mounts=["/"], fssize=200 * GB, fsused=40 * GB, fsavail=150 * GB),
        dev("nvme0n1p3", size=799 * GB, fstype="ext4", mounts=["/home"], fssize=799 * GB, fsused=300 * GB, fsavail=450 * GB)]),
]}


def fake_usage(path):
    return {"size": 16 * GB, "used": 4 * GB, "free": 12 * GB}


def live():
    return disks.parse(LIVE, LIVE_MOUNTS, "CitronOS", fake_usage)


class Reading(unittest.TestCase):
    def test_live_session(self):
        snap = live()
        names = [d["name"] for d in snap["disks"]]
        self.assertEqual(names, ["CitronOS", "Kingston DataTraveler", "Samsung SSD 990 PRO 1TB", "SanDisk Extreme"],
                         "the system first (its overlay, the stick it booted from), then internal, then external")
        system, stick, nvme, backup = snap["disks"]
        self.assertTrue(system["system"] and system["volumes"][0]["mountpoint"] == "/")
        self.assertTrue(stick["system"], "the live USB holds the running system")
        self.assertFalse(nvme["system"])
        self.assertEqual([v["name"] for v in nvme["volumes"]], ["EFI system partition", "Windows", "499 GB Volume"])
        self.assertEqual(nvme["volumes"][1]["format"], "Windows NT (NTFS)")
        self.assertFalse(any(v["mounted"] for v in nvme["volumes"]))
        vol = backup["volumes"][0]
        self.assertEqual((vol["name"], vol["mountpoint"], vol["free"]), ("BACKUP", "/run/media/live/BACKUP", 1200 * GB))
        self.assertTrue(backup["removable"] and vol["removable"])
        self.assertNotIn("zram0", json.dumps(snap), "swap in memory isn't a disk")
        self.assertNotIn("loop0", json.dumps(snap))

    def test_installed_system(self):
        snap = disks.parse(INSTALLED, {}, "CitronOS", fake_usage)
        self.assertEqual(len(snap["disks"]), 1)
        vols = {v["name"]: v for v in snap["disks"][0]["volumes"]}
        self.assertEqual(set(vols), {"Boot", "CitronOS", "Home"})
        self.assertTrue(all(v["system"] for v in vols.values()))
        self.assertEqual(vols["Home"]["free"], 450 * GB)

    def test_names(self):
        self.assertEqual(disks.human(1_500_000_000), "1.5 GB")
        self.assertEqual(disks.human(2 * GB), "2 GB")
        self.assertEqual(disks.human(512), "512 bytes")
        self.assertEqual(disks.object_path("/dev/sdb1"), "/org/freedesktop/UDisks2/block_devices/sdb1")
        self.assertEqual(disks.object_path("/dev/dm-0"), "/org/freedesktop/UDisks2/block_devices/dm_2d0")


class Changing(unittest.TestCase):
    def setUp(self):
        self.calls = []

        def run(cmd, timeout=20, **kw):
            self.calls.append(cmd)
            out = "Mounted /dev/nvme0n1p2 at /run/media/live/Windows" if cmd[:2] == ["udisksctl", "mount"] else "(true,)"
            return subprocess.CompletedProcess(cmd, 0, out, "")

        for target, value in (("run", run), ("snapshot", live)):
            p = patch.object(disks, target, value)
            p.start()
            self.addCleanup(p.stop)
        w = patch.object(disks.shutil, "which", return_value="/usr/bin/x")
        w.start()
        self.addCleanup(w.stop)

    def refused(self, fn, *args):
        with self.assertRaises(RuntimeError) as ctx:
            fn(*args)
        self.assertEqual(self.calls, [], "nothing was run")
        return str(ctx.exception)

    def test_the_running_system_is_never_changed(self):
        self.assertIn("holds the running system", self.refused(disks.eject, "/dev/sda"))
        self.assertIn("holds the running system", self.refused(disks.eject, "/dev/sda2"), "not even another volume on it")
        self.assertIn("holds the running system", self.refused(disks.erase, "/dev/sda1", "exfat", "X"))
        self.assertIn("holds the running system", self.refused(disks.unmount, "/dev/sda1"))
        self.assertIn("holds the running system", self.refused(disks.check, "/dev/sda1"))

    def test_mount_and_eject(self):
        self.assertEqual(disks.mount("/dev/nvme0n1p2"), {"mountpoint": "/run/media/live/Windows"})
        self.assertEqual(self.calls, [["udisksctl", "mount", "-b", "/dev/nvme0n1p2"]])
        self.calls.clear()
        disks.eject("/dev/sdb")
        self.assertEqual(self.calls, [["udisksctl", "unmount", "-b", "/dev/sdb1"], ["udisksctl", "power-off", "-b", "/dev/sdb"]])

    def test_first_aid(self):
        self.assertIn("Unmount BACKUP first", self.refused(disks.check, "/dev/sdb1"))
        self.assertEqual(disks.check("/dev/nvme0n1p3"), {"healthy": True})
        self.assertEqual(self.calls[0][-3:], ["--method", "org.freedesktop.UDisks2.Filesystem.Check", "{}"])
        self.assertIn("/org/freedesktop/UDisks2/block_devices/nvme0n1p3", self.calls[0])

    def test_erase_a_volume(self):
        disks.erase("/dev/sdb1", "exfat", "Photos")
        self.assertEqual(self.calls[0], ["udisksctl", "unmount", "-b", "/dev/sdb1"], "unmounted first")
        fmt = self.calls[1]
        self.assertEqual(fmt[fmt.index("--method") + 1:], ["org.freedesktop.UDisks2.Block.Format", "exfat",
                                                            "{'label': <'Photos'>, 'update-partition-type': <true>}"])
        self.assertIn("--system", fmt)

    def test_erase_names_and_formats(self):
        self.assertIn("up to 11 letters", self.refused(disks.erase, "/dev/sdb1", "vfat", "A very long name"))
        self.assertIn("without quotes", self.refused(disks.erase, "/dev/sdb1", "exfat", "it's"))
        self.assertIn("Choose a format", self.refused(disks.erase, "/dev/sdb1", "zfs", "X"))
        disks.erase("/dev/sdb1", "vfat", "camera")
        self.assertIn("{'label': <'CAMERA'>, 'update-partition-type': <true>}", self.calls[-1], "FAT names are capitals")

    def test_erase_a_whole_disk(self):
        # An internal disk is never wiped whole, and nothing on it is touched in refusing.
        self.assertIn("Only a removable disk", self.refused(disks.erase, "/dev/nvme0n1", "ext4", "Data"))
        disks.erase("/dev/sdb", "exfat", "Travel")
        methods = [c[c.index("--method") + 1] for c in self.calls if "--method" in c]
        self.assertEqual(methods, ["org.freedesktop.UDisks2.Block.Format", "org.freedesktop.UDisks2.PartitionTable.CreatePartitionAndFormat"])
        self.assertIn("gpt", self.calls[-2])
        self.assertIn("{'label': <'Travel'>}", self.calls[-1])

    def test_errors_read_plainly(self):
        self.assertEqual(disks.udisks_error("GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain: Not authorized"),
                         "You weren't allowed to change this disk.")
        self.assertIn("in use", disks.udisks_error("GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: target is busy"))
        self.assertIn("udisks2", disks.udisks_error("GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name was not provided by any .service files"))


class Command(unittest.TestCase):
    def test_json_out(self):
        out = subprocess.run(["python3", str(ROOT / "apps/lib/disks/disks.py"), "usage", "/"], capture_output=True, text=True)
        data = json.loads(out.stdout)
        self.assertTrue(data["ok"])
        self.assertGreater(data["size"], 0)
        bad = subprocess.run(["python3", str(ROOT / "apps/lib/disks/disks.py"), "erase"], capture_output=True, text=True)
        self.assertFalse(json.loads(bad.stdout)["ok"])
        tmp = Path(__import__("tempfile").mkdtemp())
        (tmp / "big").mkdir()
        (tmp / "big/file").write_bytes(b"x" * 200_000)
        (tmp / "small").mkdir()
        (tmp / "small/file").write_bytes(b"x" * 1000)
        top = json.loads(subprocess.run(["python3", str(ROOT / "apps/lib/disks/disks.py"), "largest", str(tmp)],
                                        capture_output=True, text=True).stdout)
        self.assertEqual([i["name"] for i in top["items"]], ["big", "small"])
        self.assertGreaterEqual(top["total"], 201_000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
