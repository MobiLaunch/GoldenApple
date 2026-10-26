"""The XDG base folders, read when asked (tests and helpers may set them),
and CitronOS's own folder under each."""
from __future__ import annotations

import os
from pathlib import Path

APP = "golden-gate"


def _base(variable: str, fallback: str) -> Path:
    value = os.environ.get(variable, "")
    # The spec ignores relative paths.
    return Path(value) if value and os.path.isabs(value) else Path.home() / fallback


def config_home() -> Path:
    return _base("XDG_CONFIG_HOME", ".config")


def data_home() -> Path:
    return _base("XDG_DATA_HOME", ".local/share")


def cache_home() -> Path:
    return _base("XDG_CACHE_HOME", ".cache")


def state_home() -> Path:
    return _base("XDG_STATE_HOME", ".local/state")


def runtime_dir() -> Path | None:
    """$XDG_RUNTIME_DIR if it's a real folder (in memory, the user's own), else None."""
    value = os.environ.get("XDG_RUNTIME_DIR", "")
    return Path(value) if value and os.path.isabs(value) and os.path.isdir(value) else None


def config(*parts: str) -> Path:
    """~/.config/golden-gate/…"""
    return config_home().joinpath(APP, *parts)


def data(*parts: str) -> Path:
    """~/.local/share/golden-gate/…"""
    return data_home().joinpath(APP, *parts)


def cache(*parts: str) -> Path:
    """~/.cache/golden-gate/…"""
    return cache_home().joinpath(APP, *parts)


def state(*parts: str) -> Path:
    """~/.local/state/golden-gate/…"""
    return state_home().joinpath(APP, *parts)
