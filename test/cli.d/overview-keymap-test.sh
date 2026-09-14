#!/bin/bash

# keymaps/overview.lua: SUPER + TAB and the overview's own key set, which keeps Omarchy's SUPER
# shortcuts from acting on windows behind the overview while it is open.

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

hl = {
  dsp = {
    focus = function(spec) return { focus = spec } end,
    submap = function(name) return { submap = name } end,
  },
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
    table.insert(binds[where], { keys = keys, release = options and options.release or false })
  end,
}

dofile(arg[1])

local function keys(list)
  local out = {}
  for _, bind in ipairs(list) do out[#out + 1] = bind.keys .. (bind.release and " (release)" or "") end
  return table.concat(out, ", ")
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
