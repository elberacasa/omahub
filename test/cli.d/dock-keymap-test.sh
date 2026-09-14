#!/bin/bash

# keymaps/dock.lua: SUPER + D and the dock's own key set, so arrows and Enter reach the dock while SUPER
# is still held from SUPER + D.

source "$(dirname "$0")/../base-test.sh"

lua=$(command -v lua || command -v luajit || true)
if [[ -z $lua ]]; then
  pass "lua is not installed, so the dock keymap checks are skipped"
  finish
fi

results=$("$lua" - "$OMAHUB_PATH/keymaps/dock.lua" <<'EOF'
local where = "global"
local binds = { global = {}, submap = {} }
local submaps = {}

hl = {
  dsp = { submap = function(name) return { submap = name } end },
  define_submap = function(name, fn)
    submaps[#submaps + 1] = name
    where = "submap"
    fn()
    where = "global"
  end,
}
o = { bind = function(keys) table.insert(binds[where], keys) end }

dofile(arg[1])

local function check(name, ok)
  print((ok and "true" or "false") .. "\t" .. name)
end

check("SUPER + D reaches the dock", table.concat(binds.global, ", ") == "SUPER + D")
check("the dock defines one key set of its own", #submaps == 1 and submaps[1] == "omahub-dock")
check("inside it, only SUPER + D stays with Hyprland, so arrows and Enter reach the dock", table.concat(binds.submap, ", ") == "SUPER + D")
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
