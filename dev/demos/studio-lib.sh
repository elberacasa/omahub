#!/bin/bash

# Helpers for studio scenes. A scene runs on the desktops dev/studio up stages, as
# `bash dev/demos/studio-<scene>.sh setup|take`: setup arranges the windows before recording, and take
# is what gets recorded. Keys and the pointer go through dev/agent, so they behave as a person's do.

STUDIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STUDIO_WINDOWS="$STUDIO_ROOT/tmp/studio/windows.json"

source "$STUDIO_ROOT/dev/demo-lib.sh"

[[ -f $STUDIO_WINDOWS ]] || { echo "bring the studio up first: dev/studio up" >&2; exit 2; }

agent() {
  "$STUDIO_ROOT/dev/agent" "$@"
}

# The address of a staged window: orbit, btop, lumen, or x.
window() {
  jq -r ".$1" "$STUDIO_WINDOWS"
}

focus() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$(window "$1")\" })" >/dev/null
}

# The pointer rests on the bar. Omarchy focuses the window under the pointer, so resting anywhere over a
# window would change which window a scene starts from.
park() {
  local spot
  spot=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\((.x + .width / .scale * 0.62) | floor) \(.y + 6)"')
  # shellcheck disable=SC2086
  move $spot 200
}

# Every scene starts from rest, with orbit-api in front on desktop 1. The pointer parks first, since on
# its way to the bar it crosses windows and focuses them.
rest() {
  agent call dismiss >/dev/null 2>&1 || true
  park
  hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null
  focus orbit
  sleep 0.4
}
