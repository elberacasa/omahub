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

# glide <x> <y> [ms]: the way a hand moves, curved a little, with a small overshoot that settles.
glide() {
  pointer glide "$1" "$2" "${3:-600}"
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
DEMO_BAR_FILE="$DEMO_ROOT/tmp/demos/bar-display"
DEMO_ACTIVATE_FILE="$DEMO_ROOT/tmp/demos/focus-on-activate"
DEMO_STASH="omahub-stash"

# The Agents widget on the bar, built in or cloned, when it currently shows subscription limits.
demo_agents_widget_showing_limits() {
  local widget
  widget=$(omarchy plugin list --json 2>/dev/null \
    | jq -r '.[] | select(.enabled and (.id == "omarchy.agents" or .clonedFrom == "omarchy.agents")) | .id' | head -1)
  if [[ -n $widget ]] && jq -e --arg id "$widget" \
      '[.bar.layout[]?[]? | objects | select(.id == $id)][0].barDisplay == "Limits"' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
    printf '%s\n' "$widget"
  fi
}

# Move every real window to a hidden desktop so a public take shows only demo windows, remembering
# each window's desktop, and show the Agents widget as its icon so subscription usage stays off
# camera. demo_restore_windows puts all of it back.
demo_stash_windows() {
  local address workspace widget
  demo_restore_windows
  mkdir -p "$(dirname "$DEMO_STASH_FILE")"
  widget=$(demo_agents_widget_showing_limits)
  if [[ -n $widget ]]; then
    printf '%s\n' "$widget" >"$DEMO_BAR_FILE"
    omarchy bar set "$widget" barDisplay Icon >/dev/null
  fi
  # A stashed window asking for attention would bring the hidden desktop into view, so windows may
  # not take focus by activating until the take is over.
  hyprctl getoption misc:focus_on_activate -j | jq -r '.bool == true' >"$DEMO_ACTIVATE_FILE"
  hyprctl eval 'hl.config({ misc = { focus_on_activate = false } })' >/dev/null
  # Moving the focused window away hands focus to the next one, which can be a window already
  # stashed, and focusing it brings the hidden desktop into view. Start from an empty desktop.
  hyprctl dispatch 'hl.dsp.focus({ workspace = "empty" })' >/dev/null
  hyprctl clients -j | jq -r '.[] | select((.class | startswith("omahub-demo-")) | not) | select(.workspace.id > 0) | "\(.address)\t\(.workspace.id)"' >"$DEMO_STASH_FILE"
  while IFS=$'\t' read -r address workspace; do
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:omahub-stash\", window = \"address:$address\", follow = false })" >/dev/null
  done <"$DEMO_STASH_FILE"
}

demo_restore_windows() {
  local address workspace
  if [[ -s $DEMO_BAR_FILE ]]; then
    omarchy bar set "$(<"$DEMO_BAR_FILE")" barDisplay Limits >/dev/null
    rm -f "$DEMO_BAR_FILE"
  fi
  if [[ -s $DEMO_ACTIVATE_FILE ]]; then
    hyprctl eval "hl.config({ misc = { focus_on_activate = $(<"$DEMO_ACTIVATE_FILE") } })" >/dev/null
    rm -f "$DEMO_ACTIVATE_FILE"
  fi
  if [[ ! -s $DEMO_STASH_FILE ]]; then
    return 0
  fi
  while IFS=$'\t' read -r address workspace; do
    hyprctl dispatch "hl.dsp.window.move({ workspace = \"$workspace\", window = \"address:$address\", follow = false })" >/dev/null
  done <"$DEMO_STASH_FILE"
  rm -f "$DEMO_STASH_FILE"
}

# demo_guard_stash <log>: runs until killed. If the hidden desktop ever comes into view, hide it at
# once and note the time, so the take can be thrown away instead of published.
demo_guard_stash() {
  local log="$1"
  : >"$log"
  local shown='any(.[]; .specialWorkspace.name == $name)'
  while true; do
    if hyprctl monitors -j | jq -e --arg name "special:$DEMO_STASH" "$shown" >/dev/null; then
      date +%s.%N >>"$log"
      hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$DEMO_STASH\")" >/dev/null
      # Toggling again while it slides away would show it again, so wait for it to go.
      for _ in $(seq 20); do
        hyprctl monitors -j | jq -e --arg name "special:$DEMO_STASH" "$shown" >/dev/null || break
        sleep 0.05
      done
    fi
    sleep 0.05
  done
}

demo_wait_for() {
  local app="$1"
  for _ in $(seq 80); do
    if hyprctl clients -j | jq -e --arg app "$app" 'any(.[]; .class == $app)' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# Showcase windows for public takes, with nothing personal on screen: no shell prompt, which would
# show a user and host name, and a browser in a throwaway profile.
open_showcase_terminal() {
  local name="$1" workspace="$2" command="$3" app="omahub-demo-$1"
  hyprctl eval "hl.exec_cmd('foot --app-id=$app --title=$name sh -c \"$command; sleep infinity\"', { workspace = '$workspace silent' })" >/dev/null
  demo_wait_for "$app"
}

open_showcase_page() {
  local workspace="$1" profile="$DEMO_ROOT/tmp/demo-browser"
  mkdir -p "$profile"
  hyprctl eval "hl.exec_cmd('chromium --user-data-dir=$profile --no-first-run --no-default-browser-check --class=omahub-demo-page --app=file://$DEMO_ROOT/dev/demos/pages/moonshot.html', { workspace = '$workspace silent' })" >/dev/null
  for _ in $(seq 80); do
    if hyprctl clients -j | jq -e 'any(.[]; .title == "Moonshot")' >/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# Close everything a showcase opened, including the demo browser, which does not take its class.
close_showcase_windows() {
  local address
  for address in $(hyprctl clients -j | jq -r '.[] | select(.title == "Moonshot" or (.class | startswith("omahub-demo-"))) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
  done
}

close_demo_windows() {
  local address
  for address in $(hyprctl clients -j | jq -r '.[] | select(.class | startswith("omahub-demo-")) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
  done
}
