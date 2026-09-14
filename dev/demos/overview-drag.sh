#!/bin/bash

# Moving a window between desktops in the overview: drag its preview onto another desktop.

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/overview-drag.log"
mkdir -p "$(dirname "$log")"
: >"$log"

open_demo_window drag 9
open_demo_window stay 6
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
pause 0.9

summon '{"overview":"open"}'
pause 1.4

view=$(layout overviewLayout)
read -r from_x from_y <<<"$(center "$view" '.cards[0]')"
read -r to_x to_y <<<"$(center "$view" '.desktops[] | select(.id == 6)')"
echo "drag from $from_x,$from_y to $to_x,$to_y" >>"$log"

drag "$from_x" "$from_y" "$to_x" "$to_y" 900
pause 1.3

echo "window now on workspace: $(hyprctl clients -j | jq -r '.[] | select(.class == "omahub-demo-drag") | .workspace.id')" >>"$log"
key Escape
pause 0.6
