#!/usr/bin/env python3
"""Reject unusable packaging output without executing a staged runtime."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


runtime = load("runtime", "tools/darling/runtime.py")
packaging = load("arch_package", "tools/darling/package-arch.py")
build = load("darling_build", "tools/darling/build.py")


def macho(name=runtime.PIP_NAME, cpu=0x01000007):
    text = name.encode() + b"\0"
    length = (24 + len(text) + 7) & ~7
    command = struct.pack("<6I", 0xD, length, 24, 0, 0, 0) + text
    command += b"\0" * (length - len(command))
    return struct.pack("<8I", 0xFEEDFACF, cpu, 3, 6, 1, length, 0, 0) + command


class RuntimeStage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.stage = Path(self.tmp.name) / "stage"
        self.stage.mkdir()
        self.lock = json.loads(runtime.LOCK.read_text())
        self.provenance = {"schema": 1, "source_lock": self.lock, "install_prefix": "/usr",
                           "components": ["cli", "gui_frameworks"],
                           "swift_runtime": False,
                           "host": {"system": "Linux", "machine": "x86_64"}}
        self.write_provenance()
        for relative in ("bin/darling", "bin/darlingserver", "libexec/darling/usr/libexec/darling/mldr"):
            p = self.stage / "usr" / relative
            p.parent.mkdir(parents=True, exist_ok=True)
            header = bytearray(64)
            header[:6] = b"\x7fELF\x02\x01"
            struct.pack_into("<H", header, 18, 62)
            p.write_bytes(header)
            p.chmod(0o4755 if relative == "bin/darling" else 0o755)
        self.framework = self.stage / "usr/libexec/darling/System/Library/PrivateFrameworks/PIP.framework"
        self.pip = self.framework / "Versions/A/PIP"
        self.pip.parent.mkdir(parents=True)
        self.pip.write_bytes(macho())
        (self.framework / "Versions/Current").symlink_to("A")
        (self.framework / "PIP").symlink_to("Versions/Current/PIP")

    def write_provenance(self):
        (self.stage / "golden-gate-darling-build.json").write_text(json.dumps(self.provenance))

    def verify(self):
        return runtime.verify_stage(self.stage, "/usr", self.lock)

    def test_valid_stage_is_not_a_gui_compatibility_claim(self):
        result = self.verify()
        self.assertTrue(result["passed"])
        self.assertEqual(result["gui_compatibility"], "unverified")

    def test_missing_pip(self):
        self.pip.unlink()
        with self.assertRaisesRegex(ValueError, "Missing installed PIP"):
            self.verify()

    def test_wrong_dylib_identity(self):
        self.pip.write_bytes(macho("/tmp/PIP.framework/PIP"))
        with self.assertRaisesRegex(ValueError, "identity differs"):
            self.verify()

    def test_wrong_macho_architecture(self):
        self.pip.write_bytes(macho(cpu=0x0100000C))
        with self.assertRaisesRegex(ValueError, "x86_64 Mach-O"):
            self.verify()

    def test_fat_x86_slice_and_truncation(self):
        thin = macho()
        fat = struct.pack(">II5I", 0xCAFEBABE, 1, 0x01000007, 3, 4096, len(thin), 12)
        self.pip.write_bytes(fat.ljust(4096, b"\0") + thin)
        self.verify()
        self.pip.write_bytes(fat)
        with self.assertRaisesRegex(ValueError, "slice bounds"):
            self.verify()

    def test_lost_launcher_privileges(self):
        (self.stage / "usr/bin/darling").chmod(0o755)
        with self.assertRaisesRegex(ValueError, "setuid mode"):
            self.verify()

    def test_archive_roundtrip_preserves_launcher_mode(self):
        archive = Path(self.tmp.name) / "runtime.tar.gz"
        subprocess.run(["tar", "-C", str(self.stage), "-czf", str(archive), "."], check=True)
        old_stage = Path(self.tmp.name) / "old-unpack"
        old_stage.mkdir()
        # Reproduce the non-root tar default even when tests themselves run as root.
        subprocess.run(["tar", "--no-same-owner", "--no-same-permissions", "-C",
                        str(old_stage), "-xzf", str(archive)], check=True)
        with self.assertRaisesRegex(ValueError, "setuid mode"):
            runtime.verify_stage(old_stage, "/usr", self.lock)
        fresh = Path(self.tmp.name) / "fixed-unpack"
        result = runtime.verify_archive(archive, fresh, "/usr", self.lock)
        self.assertTrue(result["passed"])
        self.assertEqual((fresh / "usr/bin/darling").stat().st_mode & 0o7777, 0o4755)
        self.assertEqual(result["gui_compatibility"], "unverified")
        with self.assertRaises(FileExistsError):
            runtime.verify_archive(archive, fresh, "/usr", self.lock)

    def test_wrong_host_architecture(self):
        p = self.stage / "usr/bin/darlingserver"
        header = bytearray(p.read_bytes())
        struct.pack_into("<H", header, 18, 183)
        p.write_bytes(header)
        with self.assertRaisesRegex(ValueError, "x86_64 ELF"):
            self.verify()

    def test_provenance_and_prefix_mismatch(self):
        self.provenance["source_lock"] = copy.deepcopy(self.lock)
        self.provenance["source_lock"]["darling_commit"] = "0" * 40
        self.write_provenance()
        with self.assertRaisesRegex(ValueError, "provenance"):
            self.verify()
        self.provenance["source_lock"] = self.lock
        self.provenance["install_prefix"] = "/usr/local"
        self.write_provenance()
        with self.assertRaisesRegex(ValueError, "provenance"):
            self.verify()

    def test_bad_framework_links(self):
        link = self.framework / "PIP"
        link.unlink()
        link.symlink_to(self.pip)
        with self.assertRaisesRegex(ValueError, "framework link"):
            self.verify()

    def test_malformed_load_command(self):
        binary = bytearray(macho())
        struct.pack_into("<I", binary, 36, 0xFFFF)
        self.pip.write_bytes(binary)
        with self.assertRaisesRegex(ValueError, "load command"):
            self.verify()

    def test_export_is_reproducible_and_checksummed(self):
        one = packaging.export(Path(self.tmp.name) / "one")
        two = packaging.export(Path(self.tmp.name) / "two")
        archive = one / "golden-gate-darling-source.tar.gz"
        self.assertEqual(archive.read_bytes(), (two / archive.name).read_bytes())
        recipe = (one / "PKGBUILD").read_text()
        self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), recipe)
        self.assertIn("conflicts=('darling' 'darling-bin' 'darling-git')", recipe)
        self.assertNotIn("SKIP", recipe)
        self.assertEqual(subprocess.run(["bash", "-n", str(one / "PKGBUILD")]).returncode, 0)
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                relative = Path(member.name).relative_to("golden-gate-darling")
                self.assertTrue(member.isfile())
                self.assertEqual(tar.extractfile(member).read(), (ROOT / relative).read_bytes())
        with self.assertRaisesRegex(ValueError, "existing files"):
            packaging.export(one)

    def test_nonempty_stage_is_refused_before_build(self):
        result = subprocess.run(["python3", str(ROOT / "tools/darling/build.py"), "stage",
                                 "--source", str(Path(self.tmp.name) / "source"),
                                 "--build", str(Path(self.tmp.name) / "build"),
                                 "--stage", str(self.stage)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("empty staging directory", result.stderr)

    def test_package_function_preserves_modes_and_rejects_missing_framework(self):
        context = packaging.export(Path(self.tmp.name) / "context")
        src = Path(self.tmp.name) / "src"
        src.mkdir()
        with tarfile.open(context / "golden-gate-darling-source.tar.gz") as tar:
            tar.extractall(src, filter="data")
        self.stage.rename(src / "darling-stage")
        (src / "darling").mkdir()
        (src / "darling/LICENSE").write_text("test license fixture\n")
        pkg = Path(self.tmp.name) / "package"
        pkg.mkdir()
        env = {**os.environ, "srcdir": str(src), "pkgdir": str(pkg)}
        result = subprocess.run(["bash", "-c", 'source "$1"; package', "bash", str(context / "PKGBUILD")],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((pkg / "usr/bin/darling").stat().st_mode & 0o7777, 0o4755)
        self.assertEqual(json.loads((pkg / "usr/share/golden-gate/darling/build.json").read_text()), self.provenance)
        self.assertFalse((pkg / "golden-gate-darling-build.json").exists())
        (src / "darling-stage/usr/libexec/darling/System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP").unlink()
        rejected = Path(self.tmp.name) / "rejected"
        rejected.mkdir()
        result = subprocess.run(["bash", "-c", 'source "$1"; package', "bash", str(context / "PKGBUILD")],
                                env={**env, "pkgdir": str(rejected)}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing installed PIP", result.stderr)

    def test_fetch_skips_swift_even_when_already_initialized(self):
        source = Path(self.tmp.name) / "source"
        def output(args, cwd):
            if "--get-regexp" in args:
                return "submodule.coco.path src/external/cocotron\nsubmodule.swift.path src/external/swift"
            if "status" in args:
                return " " + "a" * 40 + " src/external/cocotron\n " + "b" * 40 + " src/external/swift"
            return "asset.dylib" if cwd != source else ""
        for with_swift in (False, True):
            with mock.patch.object(build, "output", side_effect=output), mock.patch.object(build, "run") as run:
                build.fetch_submodules(source, with_swift)
                checkout = run.call_args_list[0]
                self.assertEqual(checkout.kwargs["env"]["GIT_LFS_SKIP_SMUDGE"], "1")
                self.assertEqual("src/external/swift" in checkout.args[0], with_swift)
                pulls = [call for call in run.call_args_list if call.args[0][-2:] == ["lfs", "pull"]]
                self.assertEqual(len(pulls), 2 if with_swift else 1)
                for pull in pulls:
                    self.assertEqual(pull.kwargs["timeout"], 180)
                    self.assertIn("lfs.transfer.maxretries=1", pull.args[0])


if __name__ == "__main__":
    unittest.main()
