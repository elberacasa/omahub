#!/bin/bash

# capture/thumbnail is a keyboard layer: PRINT and Omahub's screenshot keys show the thumbnail
# while it is on, and every screenshot action keeps its key.

source "$(dirname "$0")/../base-test.sh"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf 'o.bind("SUPER + RETURN", "Terminal", "uwsm-app -- xdg-terminal-exec")\n' >"$bindings"

assert_eq "the thumbnail starts off" "$(omahub get capture/thumbnail | jq -r .value)" "false"
assert_eq "turning it on succeeds" "$(omahub set capture/thumbnail on | jq -r .value)" "true"
assert_true "the bindings block loads the thumbnail layer" grep -qF '"thumbnail"' "$bindings"
assert_true "PRINT keeps the Screenshot action" grep -qF 'o.bind("PRINT", "Screenshot"' "$OMAHUB_PATH/keymaps/thumbnail.lua"
assert_true "screenshot keys ask for the thumbnail layer at key press" grep -qF "thumbnail" "$OMAHUB_PATH/keymaps/lib.lua"

assert_eq "reset turns it off" "$(omahub reset capture/thumbnail | jq -r .value)" "false"
assert_eq "reset leaves the user's bindings as they were" "$(cat "$bindings")" 'o.bind("SUPER + RETURN", "Terminal", "uwsm-app -- xdg-terminal-exec")'

finish
