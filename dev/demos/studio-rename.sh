#!/bin/bash

# Desktops named by their project: the overview shows orbit-api on its branch and lumen-docs with
# Claude at work, then r gives a desktop a name of your own.

source "$(dirname "$0")/studio-lib.sh"

case "${1:-}" in
  setup)
    rest
    ;;
  take)
    pause 0.8
    agent call open '{"overview":"open"}' >/dev/null
    pause 1.8
    agent chord 2
    pause 1.2
    agent chord r
    pause 0.6
    agent type "Launch week"
    pause 0.8
    agent chord Return
    pause 1.6
    agent chord Escape
    pause 1.0
    ;;
esac
