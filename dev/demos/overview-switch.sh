#!/bin/bash

# The overview as a window switcher. Each SUPER + TAB press summons Omahub with "next", which is
# what this script sends, so the walk across desktops is exactly what the key does. Enter jumps.
# (wtype cannot hold SUPER faithfully: its keys reach Hyprland as different keys.)

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/overview-switch.log"
mkdir -p "$(dirname "$log")"
: >"$log"

open_demo_window one 9
open_demo_window two 6
hyprctl dispatch 'hl.dsp.focus({ workspace = "6" })' >/dev/null
pause 0.5
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
pause 0.9

summon '{"overview":"next"}'
pause 1.3
summon '{"overview":"next"}'
pause 1.2
key Return
pause 1.2

echo "active after the jump: $(hyprctl activewindow -j | jq -r '.class')" >>"$log"
echo "workspace after the jump: $(hyprctl activeworkspace -j | jq -r '.id')" >>"$log"
