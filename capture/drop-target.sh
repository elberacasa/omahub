#!/bin/bash

# Report where the pointer is, relative to the focused monitor, and whether a window is under it.
# Omahub Capture asks after a drag ends, because Qt on Wayland reports many accepted drops as ignored.

set -euo pipefail

cursor=$(hyprctl cursorpos -j)
monitor=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')
clients=$(hyprctl clients -j)

jq -nc --argjson cursor "$cursor" --argjson monitor "$monitor" --argjson clients "$clients" '
  ($monitor.activeWorkspace.id) as $workspace
  | ($monitor.specialWorkspace.id // 0) as $special
  | {
      x: ($cursor.x - $monitor.x),
      y: ($cursor.y - $monitor.y),
      window: any($clients[];
        .mapped and (.hidden | not)
        and (.workspace.id == $workspace or (.workspace.id == $special and $special != 0))
        and $cursor.x >= .at[0] and $cursor.x < .at[0] + .size[0]
        and $cursor.y >= .at[1] and $cursor.y < .at[1] + .size[1])
    }'
