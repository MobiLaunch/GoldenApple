-- CitronOS: Hyprland configuration (Lua, Hyprland 0.55+; the ISO ships 0.56).
-- Its boot test fails on any config error. Check a change with:
--   Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
--
-- The parts CitronOS writes live beside this file, in golden-gate/*.lua, each
-- loaded with part() below: one that is missing or broken is reported in the
-- journal (report-config-errors.sh) and the rest still loads.
--   motion        animations, blur, shadows, rounding (design/build.mjs, from the tokens)
--   glass         HyprGlass, title bars, window rims (gg-hyprglass-sync, from Settings › Appearance)
--   input         keyboard and trackpad (Setup Assistant, Settings › Keyboard / Trackpad)
--   accessibility Reduce Motion (Settings › Accessibility)
--   windows       window snapping and resize (Settings › Desktop & Dock)
--   machine       virtual machines and computers without a GPU (machine-conf.sh, at login)
--   displays      resolution and scale (Settings › Displays); last, so your choice wins

local function part(name)
    local ok, err = pcall(require, "golden-gate." .. name)
    if not ok then print("golden-gate: " .. name .. ".lua not loaded: " .. tostring(err)) end
end

local apps = "__GG_APPS__"
local qs = "qs -c golden-gate ipc call "

part("motion")

---------------------------------------------------------------------- session
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QS_ICON_THEME", "GoldenGate")
-- No GTK_THEME: when it is set, libadwaita skips its own stylesheet, so GNOME apps
-- lose dark mode, accent colours and the CitronOS theme (~/.config/gtk-4.0/gtk.css).
-- Wallpaper path for the shell (Wallpaper.qml, the glass), the lock screen; filled in by scripts/install.sh
hl.env("GG_WALLPAPER", "__GG_WALLPAPER__")

hl.on("hyprland.start", function()
    hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme GoldenGate")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface font-name 'Golden Gate UI 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface document-font-name 'Golden Gate UI 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface monospace-font-name 'Golden Gate Mono 10'")
    hl.exec_cmd("gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'")
    -- Export the compositor environment after Wayland exists so portals,
    -- Flatpak applications and D-Bus activated services attach to this session.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_DATA_DIRS")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_DATA_DIRS")
    hl.exec_cmd("sh -c 'gnome-keyring-daemon --start --components=secrets >/dev/null 2>&1 || true'")
    -- Upgrade cleanup: prior versions installed a standalone Citron launcher in
    -- a user-specific XDG directory. The system surface replaces it completely.
    hl.exec_cmd([[sh -c 'rm -f "$HOME/.local/share/applications/org.goldengate.Intelligence.desktop"']])
    hl.exec_cmd("gg-apply-preferences")
    -- HyprGlass and the title bars, for the theme and Settings › Appearance:
    -- writes golden-gate/glass.lua when it changed, and Hyprland reloads it.
    hl.exec_cmd("gg-hyprglass-sync")
    -- Read package/Flatpak desktop changes via inotify, acquire GPL-licensed
    -- WhiteSur artwork asynchronously and publish Launchpad's approved icon list.
    hl.exec_cmd([[sh -c 'if command -v gg-icon-resolver >/dev/null 2>&1; then mkdir -p "$HOME/.local/state"; exec gg-icon-resolver watch >>"$HOME/.local/state/golden-gate-icon-resolver.log" 2>&1; fi']])
    -- XDG Login Items: only configured apps that apply to this desktop start.
    -- dex honours Hidden, OnlyShowIn, TryExec and per-user overrides.
    hl.exec_cmd("sh -c 'command -v dex >/dev/null 2>&1 && dex --autostart --environment Hyprland'")
    -- The shell (MacShell's bar and Dock with CitronOS's surfaces, shell/),
    -- restarted if it stops. Its log ($1) is kept under 4 MB (the last one stays
    -- as .old), and a missing ~/.local/state (a new account) is made: without
    -- it the redirect failed and the shell never started.
    hl.exec_cmd([[sh -c 'mkdir -p "${1%/*}"; while :; do [ "$(stat -c %s "$1" 2>/dev/null || echo 0)" -gt 4000000 ] && mv -f "$1" "$1.old"; if touch "$1" 2>/dev/null; then qs -c golden-gate >>"$1" 2>&1; else qs -c golden-gate; fi; logger -t gg-shell "Quickshell exited; restarting in 2s"; sleep 2; done' sh "$HOME/.local/state/golden-gate-shell.log"]])
    -- The lock screen (MacLock, shell-lock/), waiting unlocked for gg-lock.
    hl.exec_cmd("sh -c 'MACLOCK_DAEMON=1 exec qs -c golden-gate-lock'")
    hl.exec_cmd("keyd-application-mapper -d")   -- per-app ⌘ overrides (terminals); needs the keyd group
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("hypridle")
    -- Clipboard history for Spotlight (⇧⌘V); MacShell starts these too if they aren't running.
    hl.exec_cmd("sh -c 'command -v cliphist >/dev/null 2>&1 && exec wl-paste --watch cliphist store'")
    -- AirDrop: be found by, and receive from, devices nearby. Started again if it
    -- stops; while another copy runs (the AirDrop window starts one if needed),
    -- this one steps aside and looks again in 30 seconds.
    hl.exec_cmd("sh -c 'while :; do python3 " .. apps .. "/airdrop/airdropd.py serve; sleep 30; done'")
    -- AirPlay Receiver, when it's on: Hyprland started from a tty never reaches
    -- graphical-session.target, so the enabled user service is started here.
    hl.exec_cmd("sh -c 'systemctl --user -q is-enabled gg-airplay.service && systemctl --user start gg-airplay.service'")
    hl.exec_cmd("sh " .. os.getenv("HOME") .. "/.config/hypr/golden-gate/report-config-errors.sh")   -- config problems in the journal
    hl.exec_cmd("logger -t golden-gate 'session started'")   -- boot tests wait for this
    -- Setup Assistant, once: until ~/.config/golden-gate/setup-done exists (gg.nosetup on
    -- the kernel command line skips it, for tests).
    hl.exec_cmd("sh -c '[ -e \"$HOME/.config/golden-gate/setup-done\" ] || grep -qw gg.nosetup /proc/cmdline || exec qs -n -p " .. apps .. "/setup.qml'")
    -- Offers a report when an app crashes, if you chose to share them in Setup Assistant.
    hl.exec_cmd("bash " .. apps .. "/setup/crash-watch.sh")
end)

------------------------------------------------------------------------- look
-- Liquid Glass (docs/LIQUID-GLASS.md). The values here are the defaults;
-- glass.lua (gg-hyprglass-sync) sets them for the theme and for the Glass and
-- Reduce Transparency settings.
hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 16,
        -- A specular rim: a 1 px edge lit from the top left, as glass catches light.
        border_size = 1,
        col = {
            active_border = { colors = { "rgba(ffffff66)", "rgba(ffffff11)" }, angle = 45 },
            inactive_border = { colors = { "rgba(ffffff22)", "rgba(00000011)" }, angle = 45 },
        },
        layout = "dwindle",
        resize_on_border = true,
        extend_border_grab_area = 12,
        -- Native Hyprland snapping, evaluated during drag/resize (no polling,
        -- overlay surface or fake window texture). This attracts floating windows
        -- to each other and to monitor edges while respecting the visual gaps.
        snap = {
            enabled = true,
            window_gap = 12,
            monitor_gap = 12,
            border_overlap = false,
            respect_gaps = true,
        },
    },
    decoration = {
        -- 2.0 draws circular corners; higher values approach the continuous
        -- "squircle" corner used by the design system.
        rounding_power = 3.4,
        -- Window contents are solid, in front or not: the glass is in their
        -- sidebars and toolbars (drawn see-through by the app) and the shell.
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        dim_inactive = false,
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "rgb(0b1f4f)",
        focus_on_activate = true,
        animate_manual_resizes = true,
        animate_mouse_windowdragging = false,
        -- A lock screen started again (gg-lock) takes over a lock whose process stopped.
        allow_session_lock_restore = true,
    },
    cursor = {
        no_warps = true,
    },
    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
    },
    input = {
        kb_layout = "us",
        follow_mouse = 2,                    -- focus follows click, like a desktop
        natural_scroll = true,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            clickfinger_behavior = true,     -- two-finger click = secondary click
            scroll_factor = 0.6,
        },
    },
})

-- Trackpad, as on a Mac: three (or four) fingers left and right move between
-- desktops, up opens Mission Control, down App Exposé.
for _, fingers in ipairs({ 3, 4 }) do
    hl.gesture({ fingers = fingers, direction = "horizontal", action = "workspace" })
    hl.gesture({ fingers = fingers, direction = "up", action = function() hl.exec_cmd(qs .. "missioncontrol toggle") end })
    hl.gesture({ fingers = fingers, direction = "down", action = function() hl.exec_cmd(qs .. "missioncontrol appExpose") end })
end

---------------------------------------------------------------------- windows
-- A desktop, not a tiler: float every app and center its frame in the
-- usable desktop. The 28px upward bias compensates for the Dock reserving more
-- space than the top menu bar; keep it in sync with apps/lib/WindowGeometry.js.
-- These monitor-local expressions also work on secondary / scaled displays.
-- Do not force a common window SIZE: each app keeps its preferred dimensions,
-- bounded at source by its own maximumSize / maximumHeight.
hl.window_rule({
    name = "gg-float-centered",
    match = { class = ".*" },
    float = true,
    move = { "(monitor_w-window_w)*0.5", "(monitor_h-window_h)*0.5-28" },
})
-- Liquid Glass per app (docs/LIQUID-GLASS.md): terminals a little clearer,
-- as a Terminal profile can be (Reduce Transparency makes them solid too).
hl.window_rule({
    name = "gg-terminal-glass",
    match = { class = [[^(com\.mitchellh\.ghostty|kitty|foot|Alacritty)$]] },
    opacity = "0.97 0.96",
})
-- Never see-through: full-screen windows, video and games, so nothing behind
-- them shows through the picture.
hl.window_rule({ name = "gg-opaque-fullscreen", match = { fullscreen = true }, opaque = true })
hl.window_rule({ name = "gg-opaque-video", match = { content = "^(video|game)$" }, opaque = true })
-- MacShell's Settings window floats and centres itself.

---------------------------------------------------------------- shell surfaces
-- HyprGlass owns blur/refraction for CitronOS's glass layer surfaces. MacShell
-- draws its own Liquid Glass (shell/macshell/liquidglass.frag) over the
-- wallpaper, and asks for Hyprland's blur on its menus only when its "Normal
-- Blur" style is chosen. These surfaces animate their content in QML: a second
-- compositor popin scales the whole surface, softens text and fights it.
for _, ns in ipairs({ "macbar", "macbarbg", "macdock", "macdock-drag", "macspot", "macswitch",
                      "macwall", "macshot", "macwidgets" }) do
    hl.layer_rule({ name = "gg-" .. ns, match = { namespace = "^" .. ns .. "$" }, no_anim = true })
end
hl.layer_rule({ name = "gg-macspot-blur", match = { namespace = "^(macspot|macbarbg|macdock)$" }, blur = true, ignore_alpha = 0.05 })
-- CitronOS's own: Launchpad, Mission Control, the pairing card and the
-- desktop picture are simply there, or animate themselves.
hl.layer_rule({ name = "gg-own", match = { namespace = "^gg-(applications|wallpaper|nearby|missioncontrol|citron|tablet-home|alert)$" }, no_anim = true })

------------------------------------------------------------------------- keys
-- SUPER plays the role of ⌘. keyd (themes/keyd/default.conf) turns ⌘+letter into
-- Ctrl+letter for apps, so ⌘C/⌘V/⌘W/⌘Q behave like on a Mac. Hyprland keeps the
-- keys keyd leaves alone: Space, Tab, M, H, comma, Escape, Return and the number row.
local function ipc(call) return hl.dsp.exec_cmd(qs .. call) end
hl.bind("SUPER + SPACE", ipc("spotlight toggle"))
hl.bind("SUPER + SHIFT + SPACE", ipc("citron toggle"))            -- Summon Citron (⇧⌘Space)
hl.bind("SUPER + CTRL + SPACE", ipc("spotlight emoji"))           -- Emoji & Symbols (⌃⌘Space)
hl.bind("SUPER + SHIFT + V", ipc("spotlight clipboard"))          -- Clipboard history (⇧⌘V)
hl.bind("SUPER + TAB", ipc("switcher next"))
hl.bind("SUPER + SHIFT + TAB", ipc("switcher prev"))
-- Letting go of ⌘ switches: the switcher has the keyboard while it is open.
hl.bind("SUPER + M", hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
hl.bind("SUPER + SHIFT + M", hl.dsp.workspace.toggle_special("minimized"))
hl.bind("SUPER + H", hl.dsp.window.move({ workspace = "special:hidden", follow = false }))
hl.bind("SUPER + ALT + H", ipc("menubar hideOthers"))              -- Hide Others (⌥⌘H)
hl.bind("SUPER + comma", hl.dsp.exec_cmd("gg-settings"))
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("ghostty"))
hl.bind("SUPER + ALT + ESCAPE", hl.dsp.exec_cmd("hyprctl kill"))   -- Force Quit (⌥⌘⎋)
hl.bind("SUPER + CTRL + Q", hl.dsp.exec_cmd("gg-lock"))            -- Lock Screen (⌃⌘Q, passed through by keyd)
hl.bind("SUPER + SHIFT + Q", ipc("session ask logout"))           -- Log Out… (⇧⌘Q), asks first
hl.bind("SUPER + ALT + C", ipc("controlcenter toggle"))
hl.bind("XF86LaunchB", ipc("launchpad toggle"))                    -- Launchpad key (F4 on Apple keyboards)
hl.bind("F4", ipc("launchpad toggle"))
hl.bind("SUPER + ALT + N", ipc("notifications toggleDnd"))
hl.bind("CTRL + ALT + W", ipc("wallpapers toggle"))               -- the wallpaper picker
-- Screenshots as on the Mac: ⇧⌘3 the screen, ⇧⌘4 a part of it, ⇧⌘5 the front
-- window. Screen recording is in Control Center.
hl.bind("SUPER + SHIFT + 3", ipc("screenshot screen"))
hl.bind("SUPER + SHIFT + 4", ipc("screenshot region"))
hl.bind("SUPER + SHIFT + 5", ipc("screenshot window"))
hl.bind("Print", ipc("screenshot region"))
hl.bind("CTRL + left", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("CTRL + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))   -- Zoom (⌥⌘F)
hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- Enter Full Screen (⌃⌘F, passed through by keyd)
-- Window › Move & Resize (gg-tile), with Rectangle's ⌃⌥ keys: halves on the
-- arrows, quarters on U I J K, Fill on Return, Center on C, back on Backspace.
for key, layout in pairs({ left = "left", right = "right", up = "top", down = "bottom",
                           U = "top-left", I = "top-right", J = "bottom-left", K = "bottom-right",
                           RETURN = "fill", C = "center", BACKSPACE = "restore" }) do
    hl.bind("CTRL + ALT + " .. key, hl.dsp.exec_cmd("gg-tile " .. layout))
end
hl.bind("CTRL + up", ipc("missioncontrol toggle"))                 -- Mission Control (⌃↑)
hl.bind("CTRL + down", ipc("missioncontrol appExpose"))            -- App Exposé (⌃↓)
hl.bind("XF86LaunchA", ipc("missioncontrol toggle"))               -- Mission Control key (F3 on Apple keyboards)
hl.bind("F3", ipc("missioncontrol toggle"))

hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media and brightness keys: they change the level, and the menu bar shows it.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q set 6%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q set 6%-"), { locked = true, repeating = true })
-- CitronOS Music has no MPRIS yet: it takes the keys when no MPRIS player does.
local music = "qs -p " .. apps .. "/music.qml ipc call music "
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("sh -c 'playerctl play-pause || " .. music .. "toggle'"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("sh -c 'playerctl next || " .. music .. "next'"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("sh -c 'playerctl previous || " .. music .. "previous'"), { locked = true })

------------------------------------------------------------------ this machine
part("glass")
part("input")
part("accessibility")
part("windows")
-- Screen scale in virtual machines and lighter effects without a GPU; after
-- the settings above, so it overrides them.
part("machine")
part("displays")   -- after machine: your choice wins
