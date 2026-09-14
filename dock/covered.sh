#!/bin/bash

# Print "covered" when a window on the focused monitor's visible workspace reaches into the band the
# dock uses at the bottom of the screen, and "clear" otherwise. The dock hides only when covered.
# Usage: covered.sh <band width> <band height>

set -euo pipefail

width="$1"
height="$2"
monitor=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')
clients=$(hyprctl clients -j)

jq -nr --argjson monitor "$monitor" --argjson clients "$clients" --argjson width "$width" --argjson height "$height" '
  ($monitor.width / $monitor.scale) as $w
  | ($monitor.height / $monitor.scale) as $h
  | ($monitor.x + ($w - $width) / 2) as $left
  | ($left + $width) as $right
  | ($monitor.y + $h - $height) as $top
  | ($monitor.specialWorkspace.id // 0) as $special
  | [ $clients[]
      | select(.mapped and (.hidden | not))
      | select(.workspace.id == $monitor.activeWorkspace.id or ($special != 0 and .workspace.id == $special))
      | select(.at[0] < $right and .at[0] + .size[0] > $left and .at[1] + .size[1] > $top) ]
  | if length > 0 then "covered" else "clear" end'
