#!/usr/bin/env python3
"""CitronOS's changes to hyprbars (hyprland-plugins), applied by anchor so
they carry across plugin versions; exits non-zero if an anchor is gone, rather
than building bars for every window.

1. A bar only for windows that leave their title bar to the compositor:
   Wayland apps that draw their own (GTK, libadwaita, CitronOS's apps) never
   ask for one through xdg-decoration; Qt, Electron and the like do, and
   Hyprland answers "server side" and draws nothing. X11 windows keep
   hyprbars' own rule (a bar unless they ask for no border).
2. One of each button: the session sets its buttons again after every config
   reload and appearance change (gg-hyprglass-sync), which would otherwise
   add them again.

Two generations of hyprbars: the one for Hyprland 0.56 (hyprland.conf, the
hyprbars-button keyword, the window's fields) and the one for 0.57 and later
(Lua, hl.plugin.hyprbars.add_button, the window's backend and metadata).

    patch.py path/to/hyprland-plugins/hyprbars/main.cpp
"""
import re
import sys

ACCESS = '''
// CitronOS: a bar only for windows that leave their title bar to the
// compositor (see distro/hyprbars/patch.py). The protocol keeps its
// decorations private, so reach the table through an explicit template
// instantiation, which may name a private member.
using GGDecorationMap = std::unordered_map<wl_resource*, UP<CXDGDecoration>>;
template <GGDecorationMap CXDGDecorationProtocol::*Member>
struct SGGDecorationsAccess {
    friend GGDecorationMap& ggDecorations(CXDGDecorationProtocol& protocol) {
        return protocol.*Member;
    }
};
template struct SGGDecorationsAccess<&CXDGDecorationProtocol::m_decorations>;
GGDecorationMap& ggDecorations(CXDGDecorationProtocol& protocol);

'''

# Hyprland 0.56: the window's own fields.
WANTS_BAR_056 = '''static bool ggWantsBar(PHLWINDOW window) {
    // CitronOS's own windows draw their traffic lights themselves.
    for (const auto& cls : {window->m_initialClass, window->m_class}) {
        if (cls.starts_with("org.goldengate.") || cls.starts_with("org.quickshell"))
            return false;
    }
    if (window->m_isX11)
        return !window->m_X11DoesntWantBorders;
    const auto SURFACE = window->m_xdgSurface.lock();
    if (!SURFACE || !PROTO::xdgDecoration)
        return false;
    const auto TOPLEVEL = SURFACE->m_toplevel.lock();
    if (!TOPLEVEL)
        return false;
    for (const auto& [resource, decoration] : ggDecorations(*PROTO::xdgDecoration)) {
        if (decoration && CXDGToplevelResource::fromResource(resource) == TOPLEVEL)
            return true;
    }
    return false;
}

'''

# Hyprland 0.57 and later: the window's backend and metadata. Its xdg surface
# is the backend's own, so a decoration is matched by the wl_surface instead.
WANTS_BAR_057 = '''static bool ggWantsBar(PHLWINDOW window) {
    // CitronOS's own windows draw their traffic lights themselves.
    for (const auto& cls : {window->metadata().initialAppID(), window->metadata().appID()}) {
        if (cls.starts_with("org.goldengate.") || cls.starts_with("org.quickshell"))
            return false;
    }
    const auto& BACKEND = window->backend();
    if (BACKEND.isX11())
        return !BACKEND.traits().suggestsNoBorder;
    const auto SURFACE = BACKEND.surface();
    if (!SURFACE || !PROTO::xdgDecoration)
        return false;
    for (const auto& [resource, decoration] : ggDecorations(*PROTO::xdgDecoration)) {
        if (!decoration)
            continue;
        const auto TOPLEVEL = CXDGToplevelResource::fromResource(resource);
        const auto XDG      = TOPLEVEL ? TOPLEVEL->m_owner.lock() : nullptr;
        if (XDG && XDG->m_surface.lock() == SURFACE)
            return true;
    }
    return false;
}

'''

DEDUPE_056 = '''    // CitronOS sets its buttons again after every config reload: keep one of each.
    if (std::ranges::any_of(g_pGlobalState->buttons, [&](const auto& b) { return b.cmd == vars[3] && b.icon == vars[2] && b.size == size; }))
        return result;

'''

DEDUPE_057 = '''    // CitronOS sets its buttons again whenever the appearance changes: keep one of each.
    if (std::ranges::any_of(g_pGlobalState->buttons, [&](const auto& b) { return b.cmd == button.cmd && b.icon == button.icon && b.size == button.size; }))
        return 0;

'''

INCLUDES_056 = "#include <hyprland/src/protocols/XDGShell.hpp>\n#include <hyprland/src/protocols/XDGDecoration.hpp>\n"
INCLUDES_057 = INCLUDES_056 + ("#include <hyprland/src/desktop/view/window/WindowBackend.hpp>\n"
                               "#include <hyprland/src/desktop/view/window/WindowMetadata.hpp>\n")

# (onNewWindow's test for every window, where a button is added, what goes in)
GENERATIONS = {
    "0.56": (r"if \(!window->m_X11DoesntWantBorders\) \{",
             r"g_pGlobalState->buttons\.push_back\(SHyprButton\{",
             WANTS_BAR_056, DEDUPE_056, INCLUDES_056),
    "0.57": (r"if \(true\) \{",
             r"g_pGlobalState->buttons\.push_back\(std::move\(button\)\);",
             WANTS_BAR_057, DEDUPE_057, INCLUDES_057),
}


def main(path: str) -> int:
    src = open(path, encoding="utf-8").read()
    if "ggWantsBar" in src:
        return 0                                        # already patched
    includes = list(re.finditer(r"^#include <hyprland/src/[^>]+>\n", src, re.M))
    for test, add, wants_bar, dedupe, extra in GENERATIONS.values():
        new_window = re.search(r"^static void onNewWindow\(PHLWINDOW window\) \{\n(\s*)" + test, src, re.M)
        push = re.search(r"^([ \t]*)" + add, src, re.M)
        if new_window and push:
            break
    else:
        # Name what's missing from the generation that comes closest.
        missing = []
        for test, add, *_ in GENERATIONS.values():
            gone = [name for name, m in (
                ("includes", includes),
                ("onNewWindow", re.search(r"^static void onNewWindow\(PHLWINDOW window\) \{\n(\s*)" + test, src, re.M)),
                ("buttons.push_back", re.search(r"^([ \t]*)" + add, src, re.M))) if not m]
            if not missing or len(gone) < len(missing):
                missing = gone
        print("hyprbars changed upstream; anchors missing: " + ", ".join(missing), file=sys.stderr)
        return 1
    if not includes:
        print("hyprbars changed upstream; anchors missing: includes", file=sys.stderr)
        return 1
    # Back to front, so earlier offsets stay valid.
    if push.start() > new_window.start():
        src = src[:push.start()] + dedupe + src[push.start():]
    head = src[:new_window.start()]
    rest = src[new_window.start():]
    rest = re.sub(test, "if (ggWantsBar(window)) {", rest, count=1)
    if push.start() < new_window.start():
        head = head[:push.start()] + dedupe + head[push.start():]
    src = head + ACCESS.lstrip("\n") + wants_bar + rest
    end = includes[-1].end()
    src = src[:end] + extra + src[end:]
    open(path, "w", encoding="utf-8").write(src)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
