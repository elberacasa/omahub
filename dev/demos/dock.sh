#!/bin/bash

# The dock over a full-size window: hidden, revealed from the bottom edge, a click on an app, and
# its right-click menu.

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/dock.log"
mkdir -p "$(dirname "$log")"
: >"$log"

open_demo_window dock 9
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
pause 1.4

echo "shown before the edge: $(layout dockLayout | jq -r '.shown')" >>"$log"
read -r edge_x edge_y <<<"$(center "$(layout dockLayout)" '.edge')"
move "$edge_x" $((edge_y - 220)) 450
move "$edge_x" "$edge_y" 650
pause 1.0

view=$(layout dockLayout)
echo "shown at the edge: $(jq -r '.shown' <<<"$view")" >>"$log"

read -r app_x app_y <<<"$(center "$view" '.apps[] | select(.id | startswith("omahub-demo-dock"))')"
move "$app_x" "$app_y" 500
pause 0.6
click left
pause 0.9
echo "active after the click: $(hyprctl activewindow -j | jq -r '.class')" >>"$log"

read -r pin_x pin_y <<<"$(center "$(layout dockLayout)" '.apps[0]')"
move "$pin_x" "$pin_y" 500
pause 0.5
click right
pause 1.4

move "$edge_x" $((edge_y - 400)) 500
pause 0.2
click left
pause 0.9
