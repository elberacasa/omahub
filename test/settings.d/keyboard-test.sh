#!/bin/bash

# The keyboard layer settings share one block in bindings.lua.

source "$(dirname "$0")/../base-test.sh"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf -- '-- my own binding\no.bind("SUPER + E", "Files", "nautilus")\n' >"$bindings"
original=$(cat "$bindings")

layers=(omahub-key mac-screenshot-keys vim-focus agent-keys mouse-buttons)

blocks() {
  grep -c -e '^-- omahub:keymap:start$' "$bindings" || true
}

for setting in "${layers[@]}"; do
  assert_eq "$setting starts off" "$(omahub get "keyboard/$setting" | jq -c .value)" "false"
done

assert_eq "turning the omahub key on reports on" "$(omahub set keyboard/omahub-key on | jq -c .value)" "true"
assert_eq "one block after the first change" "$(blocks)" "1"
assert_true "the user's own binding is kept" grep -qF 'o.bind("SUPER + E", "Files", "nautilus")' "$bindings"

for setting in mouse-buttons vim-focus agent-keys mac-screenshot-keys; do
  omahub set "keyboard/$setting" on >/dev/null
done
assert_eq "every layer still shares one block" "$(blocks)" "1"
assert_true "layers load in a fixed order whatever order they were turned on" grep -qF '{ "hotkey", "mac", "vim", "agents", "mouse" }' "$bindings"

omahub set keyboard/omahub-key off >/dev/null
assert_eq "one layer turns off on its own" "$(omahub get keyboard/omahub-key | jq -c .value)" "false"
assert_eq "the others stay on" "$(omahub get keyboard/vim-focus | jq -c .value)" "true"

omahub set keyboard/vim-focus on >/dev/null
assert_eq "setting the same value twice keeps one block" "$(blocks)" "1"

for setting in "${layers[@]}"; do
  omahub reset "keyboard/$setting" >/dev/null
done
assert_eq "resetting every layer removes the block" "$(blocks)" "0"
assert_eq "resetting every layer restores the file" "$(cat "$bindings")" "$original"

if omahub set keyboard/omahub-key maybe 2>/dev/null; then
  fail "an invalid value is rejected"
else
  pass "an invalid value is rejected"
fi

for layer in hotkey mac vim agents mouse; do
  assert_true "keymaps/$layer.lua exists for the $layer layer" test -f "$OMAHUB_PATH/keymaps/$layer.lua"
done

finish
