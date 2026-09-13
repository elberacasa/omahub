#!/bin/bash

# keyboard/omahub-key and keyboard/mac-screenshot-keys share one block in bindings.lua.

source "$(dirname "$0")/../base-test.sh"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf -- '-- my own binding\no.bind("SUPER + E", "Files", "nautilus")\n' >"$bindings"
original=$(cat "$bindings")

blocks() {
  grep -c -e '^-- omahub:keymap:start$' "$bindings" || true
}

assert_eq "omahub key starts off" "$(omahub get keyboard/omahub-key | jq -c .value)" "false"
assert_eq "mac keys start off" "$(omahub get keyboard/mac-screenshot-keys | jq -c .value)" "false"

assert_eq "turning the omahub key on reports on" "$(omahub set keyboard/omahub-key on | jq -c .value)" "true"
assert_eq "one block after the first change" "$(blocks)" "1"
assert_true "the user's own binding is kept" grep -qF 'o.bind("SUPER + E", "Files", "nautilus")' "$bindings"

omahub set keyboard/mac-screenshot-keys on >/dev/null
assert_eq "both layers still share one block" "$(blocks)" "1"
assert_true "the block loads both layers in order" grep -qF '{ "hotkey", "mac" }' "$bindings"

omahub set keyboard/omahub-key off >/dev/null
assert_eq "the omahub key turns off on its own" "$(omahub get keyboard/omahub-key | jq -c .value)" "false"
assert_eq "the mac keys stay on" "$(omahub get keyboard/mac-screenshot-keys | jq -c .value)" "true"

omahub set keyboard/mac-screenshot-keys on >/dev/null
assert_eq "setting the same value twice keeps one block" "$(blocks)" "1"

omahub reset keyboard/mac-screenshot-keys >/dev/null
omahub reset keyboard/omahub-key >/dev/null
assert_eq "resetting both removes the block" "$(blocks)" "0"
assert_eq "resetting both restores the file" "$(cat "$bindings")" "$original"

if omahub set keyboard/omahub-key maybe 2>/dev/null; then
  fail "an invalid value is rejected"
else
  pass "an invalid value is rejected"
fi

finish
