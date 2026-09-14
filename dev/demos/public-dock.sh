#!/bin/bash

# Public take of the dock on staged desktops. Run with --stage:
#   dev/demo dev/demos/public-dock.sh 16 --stage
# Over a full-size window the dock is hidden; the pointer wakes it at the bottom edge, sweeps across
# the icons to show magnification, opens the right-click menu, and leaves so the dock slides away.

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/public-dock.log"
mkdir -p "$(dirname "$log")"
: >"$log"

open_showcase_page 1
hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null
pause 1.6

read -r edge_x edge_y <<<"$(center "$(layout dockLayout)" '.edge')"
move "$edge_x" $((edge_y - 320)) 500
pause 0.4
move "$edge_x" "$edge_y" 900
pause 1.1

view=$(layout dockLayout)
echo "shown at the edge: $(jq -r '.shown' <<<"$view")" >>"$log"
first_x=$(jq -r '.overview.x + .overview.width / 2 | floor' <<<"$view")
last_x=$(jq -r '.apps[-1] | .x + .width / 2 | floor' <<<"$view")
row_y=$(jq -r '.apps[0] | .y + .height / 2 | floor' <<<"$view")
move "$first_x" "$row_y" 600
pause 0.3
move "$last_x" "$row_y" 2200
pause 0.3
move "$first_x" "$row_y" 1800
pause 0.4

read -r pin_x pin_y <<<"$(center "$(layout dockLayout)" '.apps[1]')"
move "$pin_x" "$pin_y" 500
pause 0.4
click right
pause 1.8
move "$edge_x" $((edge_y - 420)) 600
pause 0.2
click left
pause 0.6
move "$edge_x" $((edge_y - 520)) 700
pause 1.6
echo "shown after leaving: $(layout dockLayout | jq -r '.shown')" >>"$log"

close_showcase_windows
