-- CitronOS's Hyprland settings for Hyprland 0.57 and later, which read only
-- Lua (hyprland.lua) where earlier versions read hyprland.conf (hyprlang).
-- CitronOS keeps one configuration for both: this reader takes the account's
-- hyprland.conf, the files it sources (CitronOS's own settings, and what
-- Settings and Setup Assistant write in ~/.config/hypr/golden-gate) and the
-- account's own lines, and makes the same settings with hl.* (T-2.3).
--
-- What it reads is the hyprlang CitronOS writes: sections and a:b:c keys,
-- $variables, source, env, exec and exec-once, monitor, bezier, animation,
-- gesture, windowrule and layerrule (0.53+ syntax), and the bind family. A
-- line it can't make is listed in M.problems (and logged), never fatal: the
-- desktop still starts. GG_HYPRLANG_STRICT=1 (the tests) makes it fatal.
--
-- It also gives hyprctl's old commands a Lua form, M.dispatch("workspace 2")
-- and M.keyword("input:kb_layout", "de"), for what CitronOS runs while the
-- desktop is up (hyprctl eval 'citronos.keyword(...)').
local M = { problems = {}, read = { lines = 0, binds = 0, files = 0 } }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function problem(where, what)
  local text = where .. ": " .. what
  M.problems[#M.problems + 1] = text
  print("citronos hyprlang: " .. text)
end

-- ------------------------------------------------------------------ values
-- hyprlang's values are text; hl.config takes the option's own type, which
-- the option's current value says.
local function number(s)
  s = trim(s)
  if s:match("^0x%x+$") then return tonumber(s:sub(3), 16) end
  return tonumber(s)
end

local function boolean(s)
  s = trim(s):lower()
  if s == "true" or s == "yes" or s == "on" or s == "1" then return true end
  if s == "false" or s == "no" or s == "off" or s == "0" then return false end
  return nil
end

-- "rgba(ffffff66) rgba(ffffff11) 45deg" → { colors = {…}, angle = 45 }
local function gradient(s)
  local colors, angle = {}, nil
  for word in s:gmatch("%S+") do
    local deg = word:match("^(%-?[%d.]+)deg$")
    if deg then angle = tonumber(deg) else colors[#colors + 1] = word end
  end
  if #colors <= 1 and not angle then return colors[1] or s end
  return { colors = colors, angle = angle }
end

local function typed(key, text)
  local ok, current = pcall(hl.get_config, key)
  local kind = ok and type(current) or "nil"
  if kind == "number" then
    local n = number(text)
    if n ~= nil then return n end
    local b = boolean(text)
    if b ~= nil then return b and 1 or 0 end
  elseif kind == "boolean" then
    local b = boolean(text)
    if b ~= nil then return b end
  elseif kind == "table" then
    -- A vec2 ("0 12") takes its text as it is; anything else is a gradient.
    if text:match("^%-?[%d.]+%s+%-?[%d.]+$") then return text end
    return gradient(text)
  elseif kind == "string" then
    return text
  end
  -- An option it doesn't know (a plugin's, or a mistake): its best guess,
  -- and hl.config says if it's wrong.
  local b = boolean(text)
  if b ~= nil and not text:match("^%d$") then return b end
  return number(text) or gradient(text)
end

function M.set(key, text, where)
  -- Lua's names for hyprlang's options: input:touchpad:tap-to-click is
  -- input.touchpad.tap_to_click.
  key = key:gsub(":", "."):gsub("%-", "_")
  local value = typed(key, trim(text))
  hl.config({ [key] = value })
end

-- ------------------------------------------------------------------ dispatchers
local function workspace(arg)
  arg = trim(arg)
  return tonumber(arg) or arg
end

local function split_once(s)
  local name, rest = s:match("^%s*(%S+)%s*(.-)%s*$")
  return name or "", rest or ""
end

local DISPATCHERS = {
  exec = function(a) return hl.dsp.exec_cmd(a) end,
  global = function(a) return hl.dsp.global(a) end,
  workspace = function(a) return hl.dsp.focus({ workspace = workspace(a) }) end,
  movetoworkspace = function(a) return hl.dsp.window.move({ workspace = workspace(a) }) end,
  movetoworkspacesilent = function(a) return hl.dsp.window.move({ workspace = workspace(a), follow = false }) end,
  togglespecialworkspace = function(a) return hl.dsp.workspace.toggle_special(trim(a)) end,
  focuswindow = function(a) return hl.dsp.focus({ window = trim(a) }) end,
  focusmonitor = function(a) return hl.dsp.focus({ monitor = trim(a) }) end,
  fullscreen = function(a)
    return hl.dsp.window.fullscreen({ mode = trim(a) == "1" and "maximized" or "fullscreen" })
  end,
  killactive = function() return hl.dsp.window.close() end,
  movewindow = function() return hl.dsp.window.drag() end,
  resizewindow = function() return hl.dsp.window.resize() end,
  dpms = function(a) return hl.dsp.dpms({ action = trim(a) ~= "" and trim(a) or "toggle" }) end,
  exit = function() return hl.dsp.exit() end,
}

-- A hyprlang dispatcher and its argument ("workspace", "e+1") as an hl.dsp
-- object, or nil and why not.
function M.dispatcher(name, arg)
  local make = DISPATCHERS[trim(name):lower()]
  if not make then return nil, "the dispatcher " .. name .. " has no Lua form here" end
  return make(arg or "")
end

-- hyprctl dispatch's old form: "workspace 2", "exec kitty".
function M.dispatch(line)
  local name, arg = split_once(line)
  local d, why = M.dispatcher(name, arg)
  if not d then error(why, 2) end
  return hl.dispatch(d)
end

-- hyprctl keyword's: an option ("input:kb_layout", "de") or a keyword line
-- ("monitor", "eDP-1, preferred, auto, 1").
function M.keyword(key, value)
  M.line(key .. " = " .. value, "hyprctl keyword", {})
end

-- ------------------------------------------------------------------ keywords
-- Fields separated by commas, except inside parentheses (rgba(…), and the
-- expressions of a windowrule's move).
local function fields(s, max)
  local out, depth, cur = {}, 0, {}
  for ch in s:gmatch(".") do
    if ch == "(" then depth = depth + 1 elseif ch == ")" then depth = depth - 1 end
    if ch == "," and depth == 0 and (not max or #out < max - 1) then
      out[#out + 1] = trim(table.concat(cur)); cur = {}
    else
      cur[#cur + 1] = ch
    end
  end
  out[#out + 1] = trim(table.concat(cur))
  return out
end

local BIND_FLAGS = { r = "release", e = "repeating", l = "locked", m = "mouse", n = "non_consuming",
                     t = "transparent", i = "ignore_mods", o = "long_press" }

local function bind(flags, value, where)
  local f = fields(value, 4)
  local mods, key, name, arg = f[1] or "", f[2] or "", f[3] or "", f[4] or ""
  local keys = {}
  for m in mods:gmatch("%S+") do keys[#keys + 1] = m:upper() end
  keys[#keys + 1] = key
  local options = {}
  for c in flags:gmatch(".") do
    if not BIND_FLAGS[c] then return problem(where, "bind flag '" .. c .. "' has no Lua form here") end
    options[BIND_FLAGS[c]] = true
  end
  local d, why = M.dispatcher(name, arg)
  if not d then return problem(where, why) end
  hl.bind(table.concat(keys, " + "), d, next(options) and options or nil)
  M.read.binds = M.read.binds + 1
end

-- "match:class .*, float on, move (…) (…)" → { match = { class = ".*" }, float = true, move = "…" }
local function rule(value)
  local r = { match = {} }
  for _, field in ipairs(fields(value)) do
    local k, v = field:match("^(%S+)%s*(.-)$")
    if k then
      local b = boolean(v)
      local val = (b ~= nil and (v == "on" or v == "off" or v == "true" or v == "false")) and b or (number(v) or v)
      local prop = k:match("^match:(.+)$")
      if prop then
        if prop == "fullscreen" or prop == "float" or prop == "pin" or prop == "xwayland" then
          r.match[prop] = boolean(v)
        else
          r.match[prop] = v
        end
      else
        r[k] = val
      end
    end
  end
  return r
end

local function monitor(value)
  local f = fields(value)
  local m = { output = f[1] or "" }
  if f[2] == "disable" or f[2] == "disabled" then
    m.disabled = true
    return m
  end
  m.mode, m.position = f[2], f[3]
  if f[4] then m.scale = number(f[4]) or f[4] end
  local i = 5
  while f[i] do
    m[f[i]] = number(f[i + 1] or "") or f[i + 1]
    i = i + 2
  end
  return m
end

local function on_start(fn)
  hl.on("hyprland.start", fn)
end

-- One line of hyprlang (already without its comment and with $variables
-- replaced), inside the sections `path` names.
function M.line(text, where, path)
  local key, value = text:match("^([%w_.:%-]+)%s*=%s*(.-)%s*$")
  if not key then return problem(where, "can't read '" .. text .. "'") end
  local prefix = #path > 0 and (table.concat(path, ".") .. ".") or ""
  local lower = key:lower()
  if #path == 0 or (path[1] == "animations" and (lower == "bezier" or lower == "animation")) then
    if lower == "env" then
      local f = fields(value, 2)
      return hl.env(f[1], f[2] or "")
    elseif lower == "exec-once" then
      return on_start(function() hl.exec_cmd(value) end)
    elseif lower == "exec" then
      local run = function() hl.exec_cmd(value) end
      on_start(run)
      return hl.on("config.reloaded", run)
    elseif lower == "monitor" then
      return hl.monitor(monitor(value))
    elseif lower == "bezier" then
      local f = fields(value)
      return hl.curve(f[1], { type = "bezier", points = { { number(f[2]), number(f[3]) }, { number(f[4]), number(f[5]) } } })
    elseif lower == "animation" then
      local f = fields(value)
      local a = { leaf = f[1], enabled = boolean(f[2] or "1") ~= false }
      if a.enabled then
        a.speed = number(f[3] or "")
        a.bezier = f[4]
        if f[5] and f[5] ~= "" then a.style = f[5] end
      end
      return hl.animation(a)
    elseif lower == "gesture" then
      local f = fields(value, 5)
      local g = { fingers = number(f[1]), direction = f[2] }
      if f[3] == "dispatcher" then
        local d, why = M.dispatcher(f[4] or "", f[5] or "")
        if not d then return problem(where, why) end
        g.action = function() hl.dispatch(d) end
      else
        g.action = f[3]
      end
      return hl.gesture(g)
    elseif lower == "windowrule" then
      return hl.window_rule(rule(value))
    elseif lower == "layerrule" then
      return hl.layer_rule(rule(value))
    elseif lower:match("^bind%a*$") then
      return bind(lower:sub(5), value, where)
    elseif lower == "source" then
      return M.load(value, where)
    end
  end
  M.set(prefix .. key, value, where)
end

-- ------------------------------------------------------------------ files
local function expand(p)
  p = trim(p)
  local home = os.getenv("HOME") or ""
  p = p:gsub("^~/", home .. "/"):gsub("%$HOME", home)
  return p
end

function M.exists(p)
  local f = io.open(expand(p), "r")
  if f then f:close() return true end
  return false
end

local vars = {}

local function substitute(s)
  -- Longer names first, so $qs isn't taken for $q.
  local names = {}
  for name in pairs(vars) do names[#names + 1] = name end
  table.sort(names, function(a, b) return #a > #b end)
  for _, name in ipairs(names) do
    s = s:gsub("%$" .. name:gsub("%W", "%%%0"), (vars[name]:gsub("%%", "%%%%")))
  end
  return s
end

-- Read a hyprlang file (and what it sources). A missing file is skipped.
function M.load(file, from)
  local p = expand(file)
  local f = io.open(p, "r")
  if not f then
    print("citronos hyprlang: no " .. p .. (from and (" (sourced by " .. from .. ")") or ""))
    return
  end
  M.read.files = M.read.files + 1
  local path, n = {}, 0
  for raw in f:lines() do
    n = n + 1
    local where = p .. ":" .. n
    -- "##" is hyprlang's escaped "#" (colours aren't written that way here).
    local text = trim((raw:gsub("##", "\0"):gsub("#.*$", ""):gsub("%z", "#")))
    if text == "" then
      -- nothing
    elseif text == "}" then
      table.remove(path)
    elseif text:match("^[%w_.:%-]+%s*{$") then
      path[#path + 1] = text:match("^([%w_.:%-]+)")
    elseif text:match("^%$[%w_]+%s*=") then
      local name, value = text:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
      vars[name] = substitute(value)
    else
      local ok, err = pcall(M.line, substitute(text), where, path)
      if ok then M.read.lines = M.read.lines + 1 else problem(where, tostring(err)) end
    end
  end
  f:close()
end

-- After everything is read: strict mode (the tests) stops at a problem.
function M.finish()
  if os.getenv("GG_HYPRLANG_STRICT") ~= "1" then return end
  io.stderr:write(string.format("citronos hyprlang: %d lines, %d binds, from %d files\n",
                                M.read.lines, M.read.binds, M.read.files))
  if #M.problems > 0 then
    error(#M.problems .. " line(s) without a Lua form:\n" .. table.concat(M.problems, "\n"))
  end
end

return M
