#!/bin/bash

# keyboard/overview is a keyboard layer: SUPER + TAB opens the overview, and Omarchy's Next
# workspace keeps a key on SUPER + CTRL + ALT + TAB.

source "$(dirname "$0")/../base-test.sh"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf 'o.bind("SUPER + RETURN", "Terminal", "uwsm-app -- xdg-terminal-exec")\n' >"$bindings"
layer="$OMAHUB_PATH/keymaps/overview.lua"

assert_eq "the overview starts off" "$(omahub get keyboard/overview | jq -r .value)" "false"
assert_eq "turning it on succeeds" "$(omahub set keyboard/overview on | jq -r .value)" "true"
assert_true "the bindings block loads the overview layer" grep -qF '"overview"' "$bindings"
assert_true "SUPER + TAB opens the overview" grep -qF 'o.bind("SUPER + TAB", "Overview"' "$layer"
assert_true "Next workspace moves to SUPER + CTRL + ALT + TAB" grep -qF 'o.bind("SUPER + CTRL + ALT + TAB", "Next workspace"' "$layer"
assert_true "the key it takes is released first" grep -qF 'hl.unbind("SUPER + TAB")' "$layer"

assert_eq "reset turns it off" "$(omahub reset keyboard/overview | jq -r .value)" "false"
assert_eq "reset leaves the user's bindings as they were" "$(cat "$bindings")" 'o.bind("SUPER + RETURN", "Terminal", "uwsm-app -- xdg-terminal-exec")'

finish
