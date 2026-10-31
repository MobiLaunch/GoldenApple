-- CitronOS on Hyprland 0.57 and later, which read only Lua. This file reads
-- the account's hyprland.conf, the same file Hyprland 0.56 reads, with what it
-- sources, through CitronOS's reader (hyprlang.lua). So both versions run the
-- same settings, and Settings and your own lines keep working.
--
-- For now it's in /usr/share/golden-gate/hypr, where no Hyprland looks
-- (packaging/hyprland-lua-check.sh passes it with -c). When the hold on 0.56
-- lifts (T-2.3) it goes to /etc/xdg/hypr/hyprland.lua, which Hyprland finds;
-- not before: 0.56 also takes a hyprland.lua it finds over hyprland.conf,
-- and the title bars' and glass plugins aren't built for 0.57 yet. (What the
-- shell and Settings send while the desktop is up already works on both:
-- apps/lib/hypr/Hypr.qml and gg-hyprctl.)
local hyprlang = dofile("__GG_HYPR__/hyprlang.lua")

-- For hyprctl while the desktop is up: hyprctl eval 'citronos.keyword(…)'.
citronos = hyprlang

local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local conf = config .. "/hypr/hyprland.conf"
if not hyprlang.exists(conf) then
  conf = "__GG_HYPR__/hyprland.conf"     -- an account without one: CitronOS's own
end
hyprlang.load(conf)
hyprlang.finish()
