#!/bin/bash

# SUPER + TAB as a window switcher: hold SUPER and walk windows across desktops, forward with TAB and
# back with SHIFT + TAB, let go to land where Claude is at work, then a quick tap flips straight back.

source "$(dirname "$0")/studio-lib.sh"

case "${1:-}" in
  setup)
    rest
    # The windows used most recently, newest first, become lumen-docs and then X.
    focus x
    sleep 0.5
    focus lumen
    sleep 0.5
    rest
    ;;
  take)
    pause 0.9
    agent hold SUPER
    agent chord TAB
    pause 1.2
    agent chord TAB
    pause 1.0
    agent chord SHIFT+TAB
    pause 1.0
    agent let-go SUPER
    pause 1.8
    agent chord SUPER+TAB
    pause 1.8
    ;;
esac
