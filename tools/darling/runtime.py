#!/usr/bin/env python3
"""Verify staged runtime identity and the PIP load path; never execute binaries."""
import argparse
import json
from pathlib import Path
import stat
import struct

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "third_party/darling/source.lock.json"
PIP_NAME = "/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP"


def pip_install_name(binary):
    """Read the x86_64 Mach-O dylib ID, including an x86_64 fat slice."""
    with binary.open("rb") as stream:
        header = stream.read(32)
        if header[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            count = struct.unpack_from(">I", header, 4)[0]
            if not 1 <= count <= 16:
                raise ValueError("Invalid Mach-O slice count")
            wide = header[:4] == b"\xca\xfe\xba\xbf"
            width = 32 if wide else 20
            stream.seek(8)
            slices = stream.read(width * count)
            offset = None
            for i in range(count):
                if struct.unpack_from(">I", slices, width * i)[0] == 0x01000007:
                    offset = struct.unpack_from(">Q" if wide else ">I", slices, width * i + 8)[0]
                    size = struct.unpack_from(">Q" if wide else ">I", slices, width * i + (16 if wide else 12))[0]
                    break
            if offset is None:
                raise ValueError("PIP lacks an x86_64 slice")
            stream.seek(0, 2)
            if offset < 8 + count * width or size < 32 or offset + size > stream.tell():
                raise ValueError("Invalid Mach-O slice bounds")
            stream.seek(offset)
            header = stream.read(32)
        else:
            offset = 0
            stream.seek(0, 2)
            size = stream.tell()
        if len(header) != 32 or header[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("PIP is not a little-endian 64-bit Mach-O library")
        _, cpu, _, kind, count, command_bytes, _, _ = struct.unpack("<8I", header)
        if cpu != 0x01000007 or kind != 6:
            raise ValueError("PIP must be an x86_64 Mach-O dylib")
        if count > 4096 or command_bytes > 1048576 or command_bytes > size - 32:
            raise ValueError("Invalid Mach-O load-command bounds")
        stream.seek(offset + 32)
        commands = stream.read(command_bytes)
    at = 0
    identity = None
    for _ in range(count):
        if at + 8 > len(commands):
            raise ValueError("Truncated Mach-O load commands")
        command, length = struct.unpack_from("<II", commands, at)
        if length < 8 or at + length > len(commands):
            raise ValueError("Invalid Mach-O load command")
        if command == 0xD:  # LC_ID_DYLIB
            if length < 24 or identity is not None:
                raise ValueError("Invalid dylib identity command")
            name_offset = struct.unpack_from("<I", commands, at + 8)[0]
            if not 24 <= name_offset < length:
                raise ValueError("Invalid dylib name offset")
            name = commands[at + name_offset:at + length]
            if b"\0" not in name:
                raise ValueError("Unterminated dylib identity")
            identity = name.split(b"\0", 1)[0].decode("utf-8")
        at += length
    if at != command_bytes or identity is None:
        raise ValueError("Missing dylib identity or invalid command size")
    return identity


def verify_stage(stage, prefix="/usr/local", lock=None):
    stage = Path(stage).resolve()
    if prefix not in ("/usr", "/usr/local"):
        raise ValueError("Unsupported runtime prefix")
    wanted = lock if lock is not None else json.loads(LOCK.read_text())
    provenance = json.loads((stage / "golden-gate-darling-build.json").read_text())
    if (provenance.get("schema") != 1 or provenance.get("source_lock") != wanted
            or provenance.get("install_prefix") != prefix
            or provenance.get("components") != ["cli", "gui_frameworks"]
            or not isinstance(provenance.get("swift_runtime"), bool)
            or provenance.get("host") != {"system": "Linux", "machine": "x86_64"}):
        raise ValueError("Staged provenance does not match the locked runtime")
    base = stage / prefix.lstrip("/")
    host_paths = ("bin/darling", "bin/darlingserver", "libexec/darling/usr/libexec/darling/mldr")
    for relative in host_paths:
        binary = base / relative
        if not binary.is_file() or binary.is_symlink() or not binary.stat().st_mode & 0o111:
            raise ValueError(f"Missing host executable: {relative}")
        with binary.open("rb") as stream:
            header = stream.read(64)
        if (len(header) != 64 or header[:6] != b"\x7fELF\x02\x01"
                or struct.unpack_from("<H", header, 18)[0] != 62):
            raise ValueError(f"Host executable is not x86_64 ELF: {relative}")
    if not (base / "bin/darling").stat().st_mode & stat.S_ISUID:
        raise ValueError("Darling launcher lost upstream's required setuid mode")
    framework = base / "libexec/darling/System/Library/PrivateFrameworks/PIP.framework"
    binary = framework / "Versions/A/PIP"
    if binary.is_symlink() or not binary.is_file():
        raise ValueError("Missing installed PIP binary")
    if pip_install_name(binary) != PIP_NAME:
        raise ValueError("PIP dylib identity differs from IINA's required install name")
    for relative, target in (("Versions/Current", "A"), ("PIP", "Versions/Current/PIP")):
        link = framework / relative
        if not link.is_symlink() or str(link.readlink()) != target or link.resolve() != (
                framework / ("Versions/A" if relative == "Versions/Current" else "Versions/A/PIP")).resolve():
            raise ValueError(f"Invalid PIP framework link: {relative}")
    return {"passed": True, "install_prefix": prefix, "pip_install_name": PIP_NAME,
            "swift_runtime": provenance["swift_runtime"],
            "checks": ["locked-provenance", "host-elf-architecture", "launcher-mode",
                       "pip-architecture-and-install-name", "framework-links"],
            "gui_compatibility": "unverified"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument("--install-prefix", choices=("/usr", "/usr/local"), default="/usr/local")
    args = parser.parse_args()
    try:
        print(json.dumps(verify_stage(args.stage, args.install_prefix), indent=2))
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, f"Runtime verification failed: {error}\n")


if __name__ == "__main__":
    main()
