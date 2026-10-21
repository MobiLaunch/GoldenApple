#!/usr/bin/env python3
"""CitronOS graphical installer backend.

Disk discovery is always read-only. The destructive install operation is only
accepted in the ArchISO live session, as root, with an exact confirmation token.
It clones the tested live CitronOS root filesystem to a fresh GPT/UEFI target,
then removes live-only state and provisions the installed account.
"""
from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import sys
import time
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "settings"))
import golden_update  # noqa: E402  (shared list of live-only files)


def load_rules():
    """setup/account_rules.py, by path: the same rules Hello uses."""
    import importlib.util
    path = pathlib.Path(__file__).resolve().parent.parent / "setup/account_rules.py"
    spec = importlib.util.spec_from_file_location("account_rules", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


rules = load_rules()
# The live account is removed from the installed copy before yours is made.
LIVE_USER = "golden"

TARGET = pathlib.Path("/mnt/golden-gate")
# Every event of the install, for after a failure (and copied onto the
# installed system as /var/log/citronos-install.log when it succeeds).
LOG = pathlib.Path(os.environ.get("GG_INSTALL_LOG", "/run/citronos-install.log"))


def emit(event: str, **payload: object) -> None:
    line = json.dumps({"event": event, **payload}, separators=(",", ":"))
    try:
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(time.strftime("%H:%M:%S ") + line + "\n")
    except OSError:
        pass
    # The window may have gone (closed, crashed): the install carries on.
    try:
        print(line, flush=True)
    except (OSError, ValueError):
        pass


def identity(d: dict[str, Any]) -> str:
    """What tells this disk from another put in its place: model, serial, size."""
    return "|".join(str(d.get(k) or "").strip() for k in ("model", "serial", "size"))


def run(args: list[str], *, input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
    )


def disks() -> int:
    p = run(["lsblk", "-J", "-b", "-d", "-o", "PATH,MODEL,SERIAL,SIZE,TYPE,TRAN,RM,RO"])
    out: list[dict[str, Any]] = []
    boot_disk = live_device()
    for d in json.loads(p.stdout).get("blockdevices", []):
        path = str(d.get("path") or "")
        if d.get("type") != "disk" or d.get("rm") in (1, True) or d.get("ro") in (1, True):
            continue
        # Some USB media report RM=0. Never offer the disk that actually backs
        # the running ArchISO, regardless of how the kernel classifies it.
        if boot_disk and path == boot_disk:
            continue
        size = int(d.get("size") or 0)
        if size < 32 * 1024**3:
            continue
        out.append(
            {
                "path": path,
                "model": (d.get("model") or "Storage Device").strip(),
                "size": size,
                "transport": d.get("tran") or "",
                "identity": identity(d),
            }
        )
    print(json.dumps(out))
    return 0


def partition_path(device: str, number: int) -> str:
    return f"{device}p{number}" if device[-1:].isdigit() else f"{device}{number}"


def live_device() -> str:
    candidates = [
        ["/usr/bin/findmnt", "-n", "-o", "SOURCE", "/run/archiso/bootmnt"],
        ["/usr/bin/findmnt", "-n", "-o", "SOURCE", "/run/archiso/cowspace"],
    ]
    for command in candidates:
        try:
            source = run(command, check=False).stdout.strip()
        except OSError:
            continue
        if source.startswith("/dev/"):
            parent = run(["lsblk", "-no", "PKNAME", source], check=False).stdout.strip()
            return "/dev/" + parent if parent else source
    return ""



def preflight() -> int:
    required = [
        "lsblk", "findmnt", "wipefs", "sgdisk", "partprobe", "udevadm",
        "mkfs.fat", "mkfs.ext4", "mount", "umount", "swapoff", "rsync", "arch-chroot",
        "genfstab", "bootctl", "mkinitcpio", "useradd", "userdel", "chpasswd",
        "passwd", "systemctl", "blkid", "lsinitcpio",
    ]
    missing = [name for name in required if shutil.which(name) is None]
    live = pathlib.Path("/run/archiso").is_dir()
    uefi = pathlib.Path("/sys/firmware/efi").is_dir()
    print(json.dumps({
        "ok": live and uefi and not missing,
        "live": live,
        "uefi": uefi,
        "missing": missing,
        "live_device": live_device() if live else "",
    }, separators=(",", ":")))
    return 0


def validate_payload(data: dict[str, Any]) -> tuple[str, str, str]:
    if not pathlib.Path("/run/archiso").is_dir():
        raise RuntimeError("CitronOS can only install itself from the live environment.")
    if os.geteuid() != 0:
        raise RuntimeError("The installer backend must run with administrator privileges.")

    device = str(data.get("device") or "")
    username = str(data.get("username") or "").strip()
    password = str(data.get("password") or "")
    problem = account_problem(data)
    if problem:
        raise RuntimeError(problem)

    if not re.fullmatch(r"/dev/(?:sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+|mmcblk\d+)", device):
        raise RuntimeError("The selected destination is not a supported physical disk.")
    if not pathlib.Path(device).exists():
        raise RuntimeError("The selected disk is no longer available.")
    if live_device() == device:
        raise RuntimeError("The live installer drive cannot be selected as the destination.")

    metadata = run(["lsblk", "-dn", "-b", "-o", "TYPE,RO,SIZE", device], check=False)
    fields = metadata.stdout.split()
    if metadata.returncode != 0 or len(fields) < 3 or fields[0] != "disk":
        raise RuntimeError("The selected destination is no longer a physical disk.")
    if fields[1] == "1":
        raise RuntimeError("The selected destination is read-only.")
    try:
        if int(fields[2]) < 32 * 1024**3:
            raise RuntimeError("CitronOS requires a destination of at least 32 GB.")
    except ValueError:
        raise RuntimeError("The selected disk size could not be verified.")
    if data.get("confirm") != "ERASE:" + device:
        raise RuntimeError("The erase confirmation did not match the selected disk.")
    # The disk confirmed must be the disk at that path now, not another one
    # plugged in since and given the same name.
    now = run(["lsblk", "-J", "-b", "-d", "-o", "MODEL,SERIAL,SIZE", device], check=False)
    try:
        current = identity((json.loads(now.stdout).get("blockdevices") or [{}])[0])
    except (ValueError, AttributeError):
        current = ""
    if not data.get("identity") or data.get("identity") != current:
        raise RuntimeError("The disk at " + device + " isn't the one you chose. Choose the destination again.")
    return device, username, password


def live_people(root: str = "/") -> set[str]:
    """People's accounts made in the live session (uid 1000–59999): like the
    live account, they're not carried onto the installed system."""
    out = set()
    try:
        for line in open(pathlib.Path(root) / "etc/passwd", encoding="utf-8", errors="replace"):
            f = line.split(":")
            if len(f) > 2 and f[2].isdigit() and 1000 <= int(f[2]) < 60000:
                out.add(f[0])
    except OSError:
        pass
    return out | {LIVE_USER}


def taken_names(root: str = "/") -> set[str]:
    """Accounts and groups the installed system will already have: the live
    system's, which is what gets copied, less the people's accounts made in
    the live session (removed from the copy before yours is made)."""
    base = pathlib.Path(root)
    return rules.names_in(str(base / "etc/passwd"), str(base / "etc/group")) - live_people(root)


def account_problem(data: dict[str, Any], root: str = "/") -> str:
    """Why this account can't be made on the installed system, or ""."""
    username, password = data.get("username"), data.get("password")
    if isinstance(username, str):
        username = username.strip()
    return rules.check_username(username, taken_names(root)) or rules.check_password(password)


def check_account() -> int:
    """The account page's check (no root needed): the same rules the install
    applies before anything is erased."""
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    problem = account_problem(data if isinstance(data, dict) else {})
    print(json.dumps({"ok": not problem, "error": problem}, separators=(",", ":")))
    return 0


LAST_STAGE = {"message": ""}


def stage(progress: float, message: str, detail: str = "") -> None:
    LAST_STAGE["message"] = message
    emit("progress", progress=progress, message=message, detail=detail)


def _walk_block_nodes(nodes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for node in nodes:
        out.append(node)
        out.extend(_walk_block_nodes(node.get("children") or []))
    return out


def release_device(device: str) -> None:
    """Unmount target filesystems and disable target swap before repartitioning."""
    probe = run(["lsblk", "-J", "-o", "PATH,MOUNTPOINTS", device], check=False)
    if probe.returncode != 0:
        return
    try:
        nodes = _walk_block_nodes(json.loads(probe.stdout).get("blockdevices", []))
    except json.JSONDecodeError:
        return

    # Deactivate swap first; mounted filesystems are then released deepest-first.
    for node in reversed(nodes):
        path = str(node.get("path") or "")
        if path:
            run(["swapoff", path], check=False)

    mounts: list[str] = []
    for node in nodes:
        for mountpoint in node.get("mountpoints") or []:
            if mountpoint:
                mounts.append(str(mountpoint))
    for mountpoint in sorted(set(mounts), key=len, reverse=True):
        run(["umount", "-R", mountpoint], check=False)


def wait_for_partitions(*paths: str, timeout: float = 10.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if all(pathlib.Path(path).exists() for path in paths):
            return
        run(["udevadm", "settle"], check=False)
        time.sleep(0.2)
    missing = [path for path in paths if not pathlib.Path(path).exists()]
    raise RuntimeError("The new partition table did not appear: " + ", ".join(missing))


def install() -> int:
    # Once started, the install runs to its end or its error: closing the
    # window, a hang-up or a plain kill don't stop it half way through.
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM, signal.SIGPIPE):
        signal.signal(sig, signal.SIG_IGN)
    erased = False
    try:
        LOG.write_text("", encoding="utf-8")
    except OSError:
        pass
    try:
        payload = json.load(sys.stdin)
        device, username, password = validate_payload(payload)
        hostname = str(payload.get("hostname") or "golden-gate").strip() or "golden-gate"

        if not pathlib.Path("/sys/firmware/efi").exists():
            raise RuntimeError("This installer currently requires a UEFI booted system.")

        boot = partition_path(device, 1)
        root = partition_path(device, 2)

        stage(0.03, "Preparing destination", "Unmounting old filesystems…")
        subprocess.run(["umount", "-R", str(TARGET)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        TARGET.mkdir(parents=True, exist_ok=True)
        release_device(device)

        # Nothing destructive happens before all validation above succeeds.
        stage(0.07, "Erasing destination", device)
        erased = True
        emit("erasing", device=device)
        run(["wipefs", "-a", device])
        run(["sgdisk", "--zap-all", device])
        run(["sgdisk", "-n", "1:1MiB:+1GiB", "-t", "1:ef00", "-c", "1:CitronOS EFI", device])
        run(["sgdisk", "-n", "2:0:0", "-t", "2:8304", "-c", "2:CitronOS", device])
        run(["partprobe", device], check=False)
        run(["udevadm", "settle"])
        wait_for_partitions(boot, root)

        stage(0.12, "Creating filesystems", "Formatting the EFI and system volumes…")
        run(["mkfs.fat", "-F", "32", "-n", "CITRONOS", boot])
        run(["mkfs.ext4", "-F", "-L", "GoldenGate", root])

        run(["mount", root, str(TARGET)])
        (TARGET / "boot").mkdir(parents=True, exist_ok=True)
        run(["mount", boot, str(TARGET / "boot")])

        stage(0.20, "Copying CitronOS", "Installing the live system onto the destination…")
        excludes = [
            "/dev/*", "/proc/*", "/sys/*", "/tmp/*", "/run/*", "/mnt/*", "/media/*",
            "/boot/*", "/lost+found", "/root/*", "/home/*", "/var/log/*",
            "/var/cache/pacman/pkg/*",
        ]
        rsync = [
            "rsync", "-aHAX", "--numeric-ids", "--delete-excluded",
            "--info=progress2", "--outbuf=L",
        ]
        for item in excludes:
            rsync.extend(["--exclude", item])
        rsync.extend(["/", str(TARGET) + "/"])
        copy = subprocess.Popen(
            rsync,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env={**os.environ, "LC_ALL": "C"},
        )
        assert copy.stdout is not None
        last_percent = -1
        percent_re = re.compile(r"\b(\d{1,3})%")
        last_copy_error = ""
        for line in copy.stdout:
            clean = line.strip()
            if not clean:
                continue
            if "rsync error" in clean.lower():
                last_copy_error = clean
                emit("log", message=clean)
            match = percent_re.search(clean)
            if match:
                percent = max(0, min(100, int(match.group(1))))
                if percent >= last_percent + 2 or percent == 100:
                    last_percent = percent
                    stage(
                        0.20 + 0.37 * (percent / 100.0),
                        "Copying CitronOS",
                        f"{percent}% of system files copied",
                    )
        if copy.wait() != 0:
            raise RuntimeError(
                "The live system could not be copied to the destination."
                + (f" {last_copy_error}" if last_copy_error else "")
            )

        stage(0.58, "Converting live system", "Removing live-session state…")
        # The live ISO's boot hooks, autologin, cloud-init, volatile logs, the
        # tmpfs keyring, sshd… (golden_update.LIVE_LEFTOVERS). archiso.conf
        # above all: left in place, it made the installed initramfs wait for
        # the live USB's volume and stop at boot.
        golden_update.remove_live_leftovers(TARGET)
        golden_update.ensure_keyring(TARGET)
        shutil.rmtree(TARGET / "home/golden", ignore_errors=True)

        # The live account must not survive onto the installed system, and the
        # inherited ArchISO root account must never remain passwordless.
        for person in sorted(live_people(str(TARGET))):
            run(["arch-chroot", str(TARGET), "userdel", "-f", "-r", person], check=False)
            run(["arch-chroot", str(TARGET), "groupdel", person], check=False)
        run(["arch-chroot", str(TARGET), "passwd", "-l", "root"], check=False)

        (TARGET / "etc/hostname").write_text(hostname + "\n", encoding="utf-8")
        (TARGET / "etc/machine-id").write_text("", encoding="utf-8")
        (TARGET / "var/lib/systemd/random-seed").unlink(missing_ok=True)
        run(["arch-chroot", str(TARGET), "systemd-machine-id-setup"])

        stage(0.66, "Creating your account", username)
        # Checked again on the copy itself, just before the account is made.
        problem = rules.check_username(username, rules.names_in(str(TARGET / "etc/passwd"), str(TARGET / "etc/group")))
        if problem:
            raise RuntimeError(problem)
        run(["arch-chroot", str(TARGET), "useradd", "-m", "-G", "wheel", "-s", "/bin/bash", username])
        # Password never appears in argv, logs or a temporary file.
        run(["arch-chroot", str(TARGET), "chpasswd"], input_text=f"{username}:{password}\n")
        sudoers = TARGET / "etc/sudoers.d/20-golden-wheel"
        sudoers.write_text("%wheel ALL=(ALL:ALL) ALL\n", encoding="utf-8")
        sudoers.chmod(0o440)

        # Installed sessions start through SDDM, not the live tty autostart.
        bash_profile = TARGET / "etc/skel/.bash_profile"
        bash_profile.write_text('[[ -f ~/.bashrc ]] && . ~/.bashrc\n', encoding="utf-8")
        user_profile = TARGET / "home" / username / ".bash_profile"
        user_profile.write_text(bash_profile.read_text(encoding="utf-8"), encoding="utf-8")

        # Carry the user's live-session appearance, Dock, accessibility and input
        # choices into the installed account without carrying the live account.
        live_home = pathlib.Path("/home/golden")
        for relative in [
            pathlib.Path(".config/golden-gate"),
            pathlib.Path(".config/hypr/golden-gate/input.conf"),
            pathlib.Path(".config/hypr/golden-gate/accessibility.conf"),
            pathlib.Path(".config/hypr/golden-gate/displays.conf"),
            pathlib.Path(".config/gtk-3.0"),
            pathlib.Path(".config/gtk-4.0"),
            pathlib.Path(".config/ghostty"),
            pathlib.Path(".config/environment.d/90-golden-formats.conf"),   # region formats from Hello
        ]:
            src = live_home / relative
            dst = TARGET / "home" / username / relative
            if not src.exists():
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_dir():
                shutil.rmtree(dst, ignore_errors=True)
                shutil.copytree(src, dst, symlinks=True)
            else:
                shutil.copy2(src, dst)

        gg = TARGET / "home" / username / ".config/golden-gate"
        gg.mkdir(parents=True, exist_ok=True)
        # Setup is finished only if you finished it (in the live session, and
        # carried over above). If not, Hello runs at your first login, without
        # its account step: this is your account.
        (gg / "account-ready").write_text(username + "\n", encoding="utf-8")
        run(["arch-chroot", str(TARGET), "chown", "-R", f"{username}:{username}", f"/home/{username}"])

        stage(0.74, "Preparing startup", "Installing the kernel and generating initramfs…")
        kernel = TARGET / "boot/vmlinuz-linux"
        if not kernel.exists():
            candidates = sorted((TARGET / "usr/lib/modules").glob("*/vmlinuz"))
            if not candidates:
                raise RuntimeError("The installed Linux kernel could not be located.")
            shutil.copy2(candidates[-1], kernel)

        # The live ISO's /boot is intentionally not cloned onto FAT. Put the
        # kernel on the target ESP first so the normal linux.preset can resolve
        # /boot/vmlinuz-linux when mkinitcpio runs.
        mkinit = TARGET / "etc/mkinitcpio.conf"
        mkinit.write_text(
            'MODULES=()\nBINARIES=()\nFILES=()\n'
            'HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)\n',
            encoding="utf-8",
        )
        run(["arch-chroot", str(TARGET), "mkinitcpio", "-P"])

        stage(0.82, "Installing boot files", "Configuring systemd-boot…")
        bootctl = run(["arch-chroot", str(TARGET), "bootctl", "install"], check=False)
        if bootctl.returncode != 0:
            # Some otherwise-valid UEFI firmware exposes efivarfs read-only or
            # refuses new NVRAM entries. systemd-boot still installs the
            # architecture fallback loader when EFI-variable writes are skipped.
            fallback = run(
                ["arch-chroot", str(TARGET), "bootctl", "--no-variables", "install"],
                check=False,
            )
            if fallback.returncode != 0:
                detail = (fallback.stdout or bootctl.stdout or "").strip().splitlines()
                raise RuntimeError(
                    "The boot loader could not be installed."
                    + (f" {detail[-1]}" if detail else "")
                )

        partuuid = run(["blkid", "-s", "PARTUUID", "-o", "value", root]).stdout.strip()
        if not partuuid:
            raise RuntimeError("The installed root partition has no PARTUUID.")
        loader = TARGET / "boot/loader"
        (loader / "entries").mkdir(parents=True, exist_ok=True)
        (loader / "loader.conf").write_text("default golden-gate.conf\ntimeout 3\nconsole-mode max\n", encoding="utf-8")
        (loader / "entries/golden-gate.conf").write_text(
            "title CitronOS\n"
            "linux /vmlinuz-linux\n"
            "initrd /initramfs-linux.img\n"
            f"options root=PARTUUID={partuuid} rw quiet splash\n",
            encoding="utf-8",
        )

        stage(0.89, "Enabling services", "Network, Bluetooth, login and power management…")
        for service in [
            "NetworkManager.service",
            "bluetooth.service",
            "sddm.service",
            "keyd.service",
            "power-profiles-daemon.service",
            "avahi-daemon.service",          # AirPlay Receiver and AirDrop discovery
        ]:
            enabled = run(
                ["arch-chroot", str(TARGET), "systemctl", "enable", service],
                check=False,
            )
            if enabled.returncode != 0:
                detail = enabled.stdout.strip().splitlines()
                raise RuntimeError(
                    f"Could not enable {service}."
                    + (f" {detail[-1]}" if detail else "")
                )

        stage(0.94, "Writing filesystem table", "Finalizing the installation…")
        fstab = run(["genfstab", "-U", str(TARGET)]).stdout
        (TARGET / "etc/fstab").write_text(fstab, encoding="utf-8")
        run(["arch-chroot", str(TARGET), "plymouth-set-default-theme", "golden-gate"], check=False)
        run(["arch-chroot", str(TARGET), "mkinitcpio", "-P"])

        stage(0.97, "Verifying installation", "Checking boot files and account state…")
        required_paths = [
            TARGET / "boot/vmlinuz-linux",
            TARGET / "boot/initramfs-linux.img",
            TARGET / "boot/EFI/BOOT/BOOTX64.EFI",
            TARGET / "boot/loader/loader.conf",
            TARGET / "boot/loader/entries/golden-gate.conf",
            TARGET / "etc/fstab",
            TARGET / "home" / username,
            TARGET / "usr/share/golden-gate/apps",
        ]
        missing = [str(path.relative_to(TARGET)) for path in required_paths if not path.exists()]
        if missing:
            raise RuntimeError("Installation verification failed; missing: " + ", ".join(missing))
        # The installed boot image must not carry the live ISO's hooks: they
        # wait for the USB stick and stop the boot when it isn't there.
        listing = run(["lsinitcpio", str(TARGET / "boot/initramfs-linux.img")], check=False).stdout
        if "hooks/archiso" in listing:
            raise RuntimeError("The boot image was built with the live ISO's hooks; it would not start.")

        stage(0.99, "Syncing data", "Making sure everything is safely written to disk…")
        os.sync()

        try:
            shutil.copy2(LOG, TARGET / "var/log/citronos-install.log")
        except OSError:
            pass
        emit("done", progress=1.0, message="CitronOS is installed.", device=device)
        return 0

    except Exception as exc:
        message = str(exc)
        if isinstance(exc, subprocess.CalledProcessError):
            tail = (exc.stdout or "").strip().splitlines()
            message = f"{exc.cmd[0]} failed" + (f": {tail[-1]}" if tail else f" (exit {exc.returncode}).")
        emit("error", message=message, erased=erased, stage=LAST_STAGE["message"], log=str(LOG))
        return 1
    finally:
        subprocess.run(["umount", "-R", str(TARGET)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    if sys.argv[1] == "preflight":
        return preflight()
    if sys.argv[1] == "disks":
        return disks()
    if sys.argv[1] == "check-account":
        return check_account()
    if sys.argv[1] == "install":
        return install()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
