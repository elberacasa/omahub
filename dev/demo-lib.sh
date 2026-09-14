#!/bin/bash

# Helpers for demo scripts, so a demo reads like a storyboard: keys, the pointer, throwaway
# windows, and Omahub itself. dev/demo runs scripts from dev/demos/, which source this file.

DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_POINTER="$DEMO_ROOT/tmp/bin/omahub-pointer"
DEMO_OMAHUB_ID="io.github.elberacasa.omahub"

# Build the pointer client on first use, and again whenever its source changes.
demo_build_pointer() {
  local source="$DEMO_ROOT/dev/pointer" build="$DEMO_ROOT/tmp/pointer" protocol
  protocol="$source/wlr-virtual-pointer-unstable-v1.xml"
  if [[ -x $DEMO_POINTER && $DEMO_POINTER -nt $source/pointer.c ]]; then
    return 0
  fi
  mkdir -p "$build" "$(dirname "$DEMO_POINTER")"
  wayland-scanner client-header "$protocol" "$build/wlr-virtual-pointer-unstable-v1-client-protocol.h"
  wayland-scanner private-code "$protocol" "$build/wlr-virtual-pointer-unstable-v1-protocol.c"
  gcc -O2 -Wall -Wextra -I"$build" -o "$DEMO_POINTER" "$source/pointer.c" \
    "$build/wlr-virtual-pointer-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client)
}

# The right and bottom edges of the whole layout, which absolute pointer moves are measured in.
demo_extent() {
  hyprctl monitors -j | jq -r '"\(map(.x + (.width / .scale)) | max | floor) \(map(.y + (.height / .scale)) | max | floor)"'
}

pointer() {
  local extent from
  extent=$(demo_extent)
  from=$(hyprctl cursorpos -j | jq -r '"\(.x) \(.y)"')
  "$DEMO_POINTER" --extent $extent --from $from "$@"
}

# move <x> <y> [ms]
move() {
  pointer move "$1" "$2" "${3:-500}"
}

# click [left|right|middle]
click() {
  pointer click "${1:-left}"
}

# drag <x1> <y1> <x2> <y2> [ms]: glide to the start, hold, glide to the end, let go.
drag() {
  pointer move "$1" "$2" 400 down left wait 140 move "$3" "$4" "${5:-800}" wait 180 up left
}

key() {
  wtype -k "$1"
}

# keys_held <modifier> <wtype key arguments...>, for example: keys_held logo -k Tab -k Tab
keys_held() {
  local modifier="$1"
  shift
  wtype -M "$modifier" "$@" -m "$modifier"
}

type_text() {
  wtype -d "${2:-90}" "$1"
}

pause() {
  sleep "$1"
}

summon() {
  omarchy-shell shell summon "$DEMO_OMAHUB_ID" "$1" >/dev/null
}

# layout <overviewLayout|dockLayout>: where Omahub's pieces are on screen, as JSON.
layout() {
  omarchy-shell shell call "$DEMO_OMAHUB_ID" "$1" ""
}

# center <json> <jq path>: the middle of one element, as "x y".
center() {
  jq -r "$2 | \"\((.x + .width / 2) | floor) \((.y + .height / 2) | floor)\"" <<<"$1"
}

# open_demo_window <name> <workspace>: a throwaway terminal, closed again when the demo ends.
open_demo_window() {
  local app="omahub-demo-$1"
  hyprctl eval "hl.exec_cmd('foot --app-id=$app', { workspace = '$2 silent' })" >/dev/null
  for _ in $(seq 50); do
    if hyprctl clients -j | jq -e --arg app "$app" 'any(.[]; .class == $app)' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

DEMO_STASH_FILE="$DEMO_ROOT/tmp/demos/stash.tsv"

# Move every real window to a hidden desktop so a public take shows only demo windows, remembering
# each window's desktop. demo_restore_windows puts them all back.
demo_stash_windows() {
  local address workspace
  demo_restore_windows
  mkdir -p "$(dirname "$DEMO_STASH_FILE")"
  hyprctl clients -j | jq -r '.[] | select((.class | startswith("omahub-demo-")) | not) | select(.workspace.id > 0) | "\(.address)\t\(.workspace.id)"' >"$DEMO_STASH_FILE"
  while IFS=$'\t' read -r address workspace; do
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:omahub-stash\", window = \"address:$address\", follow = false })" >/dev/null
  done <"$DEMO_STASH_FILE"
}

demo_restore_windows() {
  local address workspace
  if [[ ! -s $DEMO_STASH_FILE ]]; then
    return 0
  fi
  while IFS=$'\t' read -r address workspace; do
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$workspace\", window = \"address:$address\", follow = false })" >/dev/null
  done <"$DEMO_STASH_FILE"
  rm -f "$DEMO_STASH_FILE"
}

close_demo_windows() {
  local address
  for address in $(hyprctl clients -j | jq -r '.[] | select(.class | startswith("omahub-demo-")) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
  done
}
