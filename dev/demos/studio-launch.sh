#!/bin/bash

# The project launcher: the overview names each desktop by its project, p lists the projects, typing finds
# tidewater, and Enter opens it on a desktop of its own with Cursor and Claude.

source "$(dirname "$0")/studio-lib.sh"

case "${1:-}" in
  setup)
    rest
    ;;
  take)
    pause 0.8
    agent call open '{"overview":"open"}' >/dev/null
    pause 1.8
    agent chord p
    pause 1.0
    agent type "tide"
    pause 1.0
    agent chord Return
    pause 7
    agent call open '{"overview":"open"}' >/dev/null
    pause 2.5
    agent chord Escape
    pause 1.0
    ;;
  cleanup)
    # tidewater's editor and agent windows, which the take opened on the first free desktop. Real windows
    # wait on a hidden special desktop, whose id is below zero, so they are never matched.
    hyprctl clients -j | jq -r '.[] | select(.workspace.id >= 4) | .address' |
      while IFS= read -r address; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
      done
    sleep 1
    rest
    ;;
esac
