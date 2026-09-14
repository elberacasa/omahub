#!/bin/bash

# desktops/DesktopsModel.js quietFocusLua: focusing from a click leaves the pointer where it is, and the
# person's pointer settings always come back, even after several quick clicks.

source "$(dirname "$0")/../base-test.sh"

lua=$(command -v lua || command -v luajit || true)
if ! command -v node >/dev/null 2>&1 || [[ -z $lua ]]; then
  pass "node or lua is not installed, so the quiet focus checks are skipped"
  finish
fi

snippet() {
  node -e '
    const fs = require("fs")
    const source = fs.readFileSync(process.argv[1], "utf8").replace(/^\.pragma library\s*/, "")
    const Model = new Function(source + "\nreturn { quietFocusLua }")()
    process.stdout.write(Model.quietFocusLua(JSON.parse(process.argv[2])))
  ' "$OMAHUB_PATH/desktops/DesktopsModel.js" "$1"
}

snippet '{"window":"address:0xabc"}' >"$TEST_ROOT/window.lua"
snippet '{"workspace":"3"}' >"$TEST_ROOT/workspace.lua"

results=$("$lua" - "$TEST_ROOT/window.lua" "$TEST_ROOT/workspace.lua" <<'EOF'
local config = { ["cursor.warp_on_change_workspace"] = 1, ["cursor.no_warps"] = false }
local focused = {}
local timers = {}

local function reset()
  config = { ["cursor.warp_on_change_workspace"] = 1, ["cursor.no_warps"] = false }
  focused = {}
  timers = {}
  omahub_quiet_focus = nil
end

hl = {
  get_config = function(key) return config[key] end,
  config = function(values)
    for key, value in pairs(values.cursor or {}) do config["cursor." .. key] = value end
  end,
  dispatch = function(dispatcher) focused[#focused + 1] = dispatcher end,
  dsp = { focus = function(spec) return spec end },
  timer = function(callback, options) timers[#timers + 1] = callback end,
}

local function run(path)
  local chunk = assert(loadfile(path))
  chunk()
end

local function check(name, ok)
  print((ok and "true" or "false") .. "\t" .. name)
end

reset()
run(arg[1])
check("the window gets focus", focused[1] and focused[1].window == "address:0xabc")
check("while it moves, the pointer stays put", config["cursor.warp_on_change_workspace"] == 0 and config["cursor.no_warps"] == true)
timers[1]()
check("the person's settings come back afterwards", config["cursor.warp_on_change_workspace"] == 1 and config["cursor.no_warps"] == false)

reset()
run(arg[2])
check("a desktop can get focus the same way", focused[1] and focused[1].workspace == "3")

reset()
run(arg[1])
run(arg[2])
timers[1]()
check("an earlier click's timer leaves the latest click's quiet focus alone", config["cursor.warp_on_change_workspace"] == 0)
timers[2]()
check("after quick clicks, the person's own settings come back, not the quiet ones", config["cursor.warp_on_change_workspace"] == 1 and config["cursor.no_warps"] == false)
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
