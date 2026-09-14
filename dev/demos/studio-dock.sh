#!/bin/bash

# The dock: Add apps finds btop and keeps it, an icon drags to a new place, and another drags off to go.

source "$(dirname "$0")/studio-lib.sh"

case "${1:-}" in
  setup)
    rest
    ;;
  take)
    pause 0.8
    agent chord SUPER+D
    pause 0.7
    agent chord space
    pause 0.8
    for _ in $(seq 8); do
      agent state '.omahub.dock.menuEntry' | grep -q "Add apps" && break
      agent chord Down
      pause 0.15
    done
    pause 0.4
    agent chord Return
    pause 1.0
    agent type "btop"
    pause 0.8
    agent chord Return
    pause 1.2
    agent chord Escape
    pause 0.4
    agent chord SUPER+D
    pause 0.8
    first=$(agent state '.omahub.dock.apps[0].id')
    spot=$(agent state '.omahub.dock.apps[2] | "\((.x + .width / 2 + 12) | floor),\((.y + .height / 2) | floor)"')
    agent drag "dock.app:$first" "$spot"
    pause 1.2
    gone=$(agent state '[.omahub.dock.apps[] | select(.windows == 0)][0].id')
    spot=$(agent state ".omahub.dock.apps[] | select(.id == \"$gone\") | \"\((.x + .width / 2) | floor),\((.y + .height / 2 - 240) | floor)\"")
    agent drag "dock.app:$gone" "$spot"
    pause 1.6
    park
    pause 0.6
    ;;
esac
