#!/bin/bash

# Dragging a window whose title keeps changing, like a terminal running a coding agent. A busy title
# must never interrupt the drag.

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/overview-drag-busy.log"
mkdir -p "$(dirname "$log")"
: >"$log"

app="omahub-demo-busy"
hyprctl eval "hl.exec_cmd('foot --app-id=$app bash $DEMO_ROOT/dev/demos/busy-title.sh', { workspace = '9 silent' })" >/dev/null
for _ in $(seq 50); do
  if hyprctl clients -j | jq -e --arg app "$app" 'any(.[]; .class == $app)' >/dev/null; then
    break
  fi
  sleep 0.1
done
open_demo_window stay 6
hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })' >/dev/null
pause 0.9

title() {
  hyprctl clients -j | jq -r --arg app "$app" '.[] | select(.class == $app) | .title'
}
first=$(title)
pause 0.3
echo "titles change: $first -> $(title)" >>"$log"

summon '{"overview":"open"}'
pause 1.4

view=$(layout overviewLayout)
read -r from_x from_y <<<"$(center "$view" '.cards[0]')"
read -r to_x to_y <<<"$(center "$view" '.desktops[] | select(.id == 6)')"

drag "$from_x" "$from_y" "$to_x" "$to_y" 1400
pause 1.3

echo "window now on workspace: $(hyprctl clients -j | jq -r --arg app "$app" '.[] | select(.class == $app) | .workspace.id')" >>"$log"
key Escape
pause 0.6
