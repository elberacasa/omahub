#!/bin/bash

# Organizing desktops: the overview opens, btop flies to another desktop with Shift + 3, u brings it
# back, 2 shows the desktop where Claude works, and Enter goes there.

source "$(dirname "$0")/studio-lib.sh"

case "${1:-}" in
  setup)
    rest
    ;;
  take)
    pause 0.8
    agent call open '{"overview":"open"}' >/dev/null
    pause 1.2
    agent chord l
    pause 0.8
    agent chord SHIFT+3
    pause 1.6
    agent chord u
    pause 1.4
    agent chord 2
    pause 1.6
    agent chord Return
    pause 1.6
    ;;
esac
