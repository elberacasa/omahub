#!/bin/bash

# Desktops in the dock: the tiles name each desktop by its project, a click goes to lumen-docs where Claude
# works, and btop dropped on X's desktop opens there.

source "$(dirname "$0")/studio-lib.sh"

edge() {
  agent state '.omahub.dock.edge | "\(.x),\(.y)"'
}

case "${1:-}" in
  setup)
    # Magnified icons shift the tiles as the pointer moves, so the drop lands on a tile that holds still.
    "$STUDIO_ROOT/bin/omahub" set dock/magnify off >/dev/null
    rest
    ;;
  take)
    pause 0.6
    agent point "$(edge)"
    pause 0.9
    agent point dock.desktop:1
    pause 1.0
    agent point dock.desktop:2
    pause 0.9
    agent click dock.desktop:2
    pause 1.8
    agent point "$(edge)"
    pause 0.9
    agent drag dock.app:omahub-studio-btop dock.desktop:3
    pause 2.8
    park
    pause 0.6
    ;;
  cleanup)
    # The btop the take opened beside X.
    hyprctl clients -j | jq -r '.[] | select(.title == "btop" and .workspace.id == 3) | .address' |
      while IFS= read -r address; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
      done
    sleep 0.5
    "$STUDIO_ROOT/bin/omahub" reset dock/magnify >/dev/null
    rest
    ;;
esac
