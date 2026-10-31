pragma Singleton
// Hyprland dispatches for whichever Hyprland CitronOS runs on (T-2.3). In
// Lua mode (Hyprland 0.57 and later read only Lua) Hyprland runs what it's
// sent as `hl.dispatch(<it>)`, so a dispatch goes as Lua: CitronOS's reader
// (compositor/hyprland/hyprlang.lua, `citronos`) makes "workspace 2" its
// dispatcher. With hyprland.conf (0.56) it goes as it is. gg-hyprctl does the
// same for scripts and Settings, and says which mode this is.
//
// Quickshell-only (Hyprland, Process): the plain Qt Quick apps that share
// apps/lib never import it.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: hypr

    property bool lua: false

    Process {
        running: true
        command: ["gg-hyprctl", "mode"]
        stdout: StdioCollector { onStreamFinished: hypr.lua = text.trim() === "lua" }
    }

    // A Lua long string holding s, whatever s holds: its brackets are ones
    // s doesn't close ([==[…]==]), so nothing in s is read as Lua.
    function luaString(s) {
        let eq = ""
        while (s.indexOf("]" + eq + "]") >= 0 || s.endsWith("]" + eq)) eq += "="
        return "[" + eq + "[" + s + "]" + eq + "]"
    }

    // A hyprctl dispatch line: "workspace 2", "exec gg-settings".
    function dispatch(line) {
        const text = String(line)
        Hyprland.dispatch(lua ? "citronos.dsp(" + luaString(text) + ")" : text)
    }
}
