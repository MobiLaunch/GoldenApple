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
   reload (gg-hyprglass-sync), which would otherwise add them again.

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

static bool ggWantsBar(PHLWINDOW window) {
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

DEDUPE = '''    // CitronOS sets its buttons again after every config reload: keep one of each.
    if (std::ranges::any_of(g_pGlobalState->buttons, [&](const auto& b) { return b.cmd == vars[3] && b.icon == vars[2] && b.size == size; }))
        return result;

'''


def main(path: str) -> int:
    src = open(path, encoding="utf-8").read()
    if "ggWantsBar" in src:
        return 0                                        # already patched
    includes = list(re.finditer(r"^#include <hyprland/src/[^>]+>\n", src, re.M))
    new_window = re.search(r"^static void onNewWindow\(PHLWINDOW window\) \{\n(\s*)if \(!window->m_X11DoesntWantBorders\) \{", src, re.M)
    push = re.search(r"^(\s*)g_pGlobalState->buttons\.push_back\(SHyprButton\{", src, re.M)
    missing = [name for name, m in (("includes", includes), ("onNewWindow", new_window), ("buttons.push_back", push)) if not m]
    if missing:
        print("hyprbars changed upstream; anchors missing: " + ", ".join(missing), file=sys.stderr)
        return 1
    # Back to front, so earlier offsets stay valid.
    src = src[:push.start()] + DEDUPE + src[push.start():]
    head = src[:new_window.start()]
    rest = src[new_window.start():].replace("if (!window->m_X11DoesntWantBorders) {", "if (ggWantsBar(window)) {", 1)
    src = head + ACCESS.lstrip("\n") + rest
    end = includes[-1].end()
    src = src[:end] + "#include <hyprland/src/protocols/XDGShell.hpp>\n#include <hyprland/src/protocols/XDGDecoration.hpp>\n" + src[end:]
    open(path, "w", encoding="utf-8").write(src)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
