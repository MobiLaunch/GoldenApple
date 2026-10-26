"""Running another program: never through a shell, always with a timeout,
and gone if the helper that started it is killed.

    result = proc.run(["pactl", "info"], timeout=4)
    if result.ok: …result.stdout…

die_with_parent is the preexec_fn for asyncio's create_subprocess_exec too.
"""
from __future__ import annotations

import ctypes
from dataclasses import dataclass
import signal
import subprocess

PR_SET_PDEATHSIG = 1


def die_with_parent() -> None:
    """In the child, before exec: if the parent dies, the kernel sends the
    child SIGTERM, so nothing is left running (a microphone, a download)."""
    try:
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


@dataclass
class Result:
    code: int | None            # None: it couldn't run, or ran out of time
    stdout: str | bytes
    stderr: str | bytes
    timed_out: bool = False
    missing: bool = False       # the program isn't installed

    @property
    def ok(self) -> bool:
        return self.code == 0


def run(args: list[str], timeout: float, input: str | bytes | None = None, text: bool = True,
        env: dict | None = None, cwd=None) -> Result:
    if isinstance(args, str) or not args:
        raise TypeError("proc.run takes a list of arguments, never a shell command.")
    try:
        p = subprocess.run(list(args), input=input, capture_output=True, text=text, timeout=timeout,
                           env=env, cwd=cwd, preexec_fn=die_with_parent)
    except FileNotFoundError:
        empty = "" if text else b""
        return Result(None, empty, empty, missing=True)
    except subprocess.TimeoutExpired as exc:
        empty = "" if text else b""
        return Result(None, exc.stdout or empty, exc.stderr or empty, timed_out=True)
    return Result(p.returncode, p.stdout, p.stderr)
