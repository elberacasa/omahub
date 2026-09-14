#!/bin/bash

# The block Omahub writes into bindings.lua loads each keyboard layer on its own, so a layer that
# breaks, for example after Omarchy renames a helper, is noted and skipped instead of stopping the
# rest of the file.

source "$(dirname "$0")/../base-test.sh"
source "$OMAHUB_PATH/lib/settings.sh"
source "$OMAHUB_PATH/lib/keymap.sh"

lua=$(command -v lua || command -v luajit || true)
if [[ -z $lua ]]; then
  pass "lua is not installed, so the keyboard block checks are skipped"
  finish
fi

layers="$HOME/.config/omarchy/plugins/$OMAHUB_PLUGIN_ID/keymaps"
mkdir -p "$layers" "$HOME/.local/state/omahub"
printf 'loaded = (loaded or "") .. "first "\n' >"$layers/first.lua"
printf 'o.bind("SUPER + X", "Renamed helper", "true")\n' >"$layers/broken.lua"
printf 'loaded = (loaded or "") .. "last"\n' >"$layers/last.lua"

{
  omahub_keymap_block '"first", "broken", "missing", "last"'
  printf 'print(loaded)\n'
} >"$TEST_ROOT/block.lua"

if output=$("$lua" "$TEST_ROOT/block.lua" 2>"$TEST_ROOT/stderr"); then
  pass "a broken layer does not stop the block"
else
  fail "a broken layer does not stop the block: $(cat "$TEST_ROOT/stderr")"
fi
assert_eq "the layers around it still load, in order" "$output" "first last"
assert_true "the broken layer is noted by name" grep -q '^broken: ' "$HOME/.local/state/omahub/keymap-errors"
assert_eq "only the broken layer is noted" "$(wc -l <"$HOME/.local/state/omahub/keymap-errors")" "1"

finish
