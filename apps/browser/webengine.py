"""Starting Qt WebEngine for Web, with or without PySide6's WebEngine binding.

Web's pages are Qt's own QML WebEngineView (the C++ QML module); from
PySide6's WebEngine binding it only needs QtWebEngineQuick.initialize() and,
for tracker blocking, the request interceptor. When Arch updates Qt and
PySide6 out of step, that binding stops loading ("could not import module
'PySide6.QtWebEngineCore'", an undefined symbol) while Qt WebEngine itself
works: Web then calls Qt's initialize() directly and runs without tracker
blocking, rather than not starting at all.

    bindings = initialize()   # before QGuiApplication; True with the binding
"""
from __future__ import annotations

import ctypes
import ctypes.util
import os

# QtWebEngineQuick::initialize(), as the C++ library exports it.
INITIALIZE = "_ZN16QtWebEngineQuick10initializeEv"


class Unavailable(RuntimeError):
    pass


def _library() -> ctypes.CDLL:
    candidates = []
    try:
        import PySide6
        # A pip-installed PySide6 carries its own Qt next to it.
        candidates.append(os.path.join(PySide6.__path__[0], "Qt", "lib", "libQt6WebEngineQuick.so.6"))
    except ImportError:
        pass
    found = ctypes.util.find_library("Qt6WebEngineQuick")
    candidates += [c for c in (found, "libQt6WebEngineQuick.so.6") if c]
    errors = []
    for path in candidates:
        if os.sep in path and not os.path.exists(path):
            continue
        try:
            return ctypes.CDLL(path, mode=os.RTLD_NOW | os.RTLD_GLOBAL)
        except OSError as exc:
            errors.append(str(exc))
    raise Unavailable("; ".join(errors) or "libQt6WebEngineQuick isn't installed")


def initialize() -> bool:
    """Qt WebEngine's start-up call. True when PySide6's binding is there
    (tracker blocking works), False when Qt's own was used instead. Raises
    Unavailable when Qt WebEngine can't start at all."""
    try:
        from PySide6.QtWebEngineQuick import QtWebEngineQuick
    except ImportError:
        lib = _library()
        try:
            getattr(lib, INITIALIZE)()
        except AttributeError:
            raise Unavailable("libQt6WebEngineQuick has no QtWebEngineQuick::initialize()") from None
        return False
    QtWebEngineQuick.initialize()
    return True
