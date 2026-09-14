#!/bin/bash

# keymaps/overview.lua: SUPER + TAB and the overview's own key set, which keeps Omarchy's SUPER
# shortcuts from acting on windows behind the overview while it is open, and the press numbers that
# pair a quick tap with its release.

source "$(dirname "$0")/../base-test.sh"

lua=$(command -v lua || command -v luajit || true)
if [[ -z $lua ]]; then
  pass "lua is not installed, so the overview keymap checks are skipped"
  finish
fi

results=$("$lua" - "$OMAHUB_PATH/keymaps/overview.lua" <<'EOF'
local where = "global"
local binds = { global = {}, submap = {} }
local submaps = {}
local unbound = {}
local commands = {}
local timers = {}
local down = {}

hl = {
  dsp = {
    focus = function(spec) return { focus = spec } end,
    submap = function(name) return { submap = name } end,
  },
  exec_cmd = function(command) commands[#commands + 1] = command end,
  timer = function(callback, options) timers[#timers + 1] = { callback = callback, options = options } end,
  is_key_down = function(key) return down[key] == true end,
  unbind = function(keys) unbound[#unbound + 1] = keys end,
  define_submap = function(name, fn)
    submaps[#submaps + 1] = name
    where = "submap"
    fn()
    where = "global"
  end,
}
o = {
  bind = function(keys, description, dispatcher, options)
    table.insert(binds[where], { keys = keys, dispatcher = dispatcher, release = options and options.release or false })
  end,
}

dofile(arg[1])

local function keys(list)
  local out = {}
  for _, bind in ipairs(list) do out[#out + 1] = bind.keys .. (bind.release and " (release)" or "") end
  return table.concat(out, ", ")
end

local function find(list, wanted, release)
  for _, bind in ipairs(list) do
    if bind.keys == wanted and bind.release == release then return bind.dispatcher end
  end
end

local function check(name, ok)
  print((ok and "true" or "false") .. "\t" .. name)
end

check("SUPER + TAB opens the overview", keys(binds.global):find("SUPER + TAB", 1, true) ~= nil)
check("Omarchy's SUPER + TAB is taken over", unbound[1] == "SUPER + TAB")
check("the overview defines one key set of its own", #submaps == 1 and submaps[1] == "omahub-overview")
check("inside it, only walking and letting go of SUPER stay with Hyprland", keys(binds.submap) == "SUPER + TAB, SUPER + SUPER_L (release)")
local mouse, numbers = false, false
for _, bind in ipairs(binds.submap) do
  if bind.keys:find("mouse", 1, true) then mouse = true end
  if bind.keys:find("SHIFT", 1, true) then numbers = true end
end
check("no mouse binding inside it, so dragging a card never moves a window", not mouse)
check("no SHIFT binding inside it, so moving a window happens once", not numbers)

local summon = find(binds.global, "SUPER + TAB", false)
local release = find(binds.global, "SUPER + SUPER_L", true)
local held_summon = find(binds.submap, "SUPER + TAB", false)
local ok = type(summon) == "function" and type(release) == "function" and type(held_summon) == "function"
check("walking and letting go are numbered in both key sets", ok)
if ok then
  summon()
  held_summon()
  release()
  check("each SUPER + TAB press gets the next number", commands[1]:find('"press":1', 1, true) ~= nil and commands[2]:find('"press":2', 1, true) ~= nil)
  check("presses summon the overview to walk windows", commands[1]:find('"overview":"next"', 1, true) ~= nil)
  check("letting go of SUPER carries the latest press", commands[3]:find("overviewRelease '2'", 1, true) ~= nil)

  check("SUPER + TAB starts watching SUPER, once however many times TAB is pressed", #timers == 1)
  down["Super_L"] = true
  local sent = #commands
  timers[#timers].callback()
  check("while SUPER is down, nothing is sent and it keeps watching", #commands == sent and #timers == 2)
  down["Super_L"] = false
  timers[#timers].callback()
  check("SUPER coming up sends the release with the latest press, even when the release binding does not fire",
    #commands == sent + 1 and commands[#commands]:find("overviewRelease '2'", 1, true) ~= nil and #timers == 2)
end
EOF
)

while IFS=$'\t' read -r ok name; do
  if [[ $ok == "true" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
done <<<"$results"

finish
