#!/bin/bash

# The overview's gestures on the live desktop: holding SUPER, picking, walking, moving, dragging, undo.

source "$(dirname "$0")/../live-lib.sh"

home=$(agent state .sandbox.home)
away=$(agent state .sandbox.away)

section "Holding SUPER, pressing a desktop's number, and letting go goes there"
agent focus a
agent hold SUPER
agent chord TAB
check "SUPER + TAB opens the overview while SUPER is held" '.omahub.overview.opened and .omahub.overview.held' 2
if agent state '.omahub.overview.opened' | grep -q true; then
  agent chord "$(number_key "$away")"
  check "the number picks that desktop" ".omahub.overview.choice and .omahub.overview.selected.workspace == $away" 1
  agent let-go SUPER
  check "letting go goes to that desktop and closes" "(.omahub.overview.opened | not) and .desktop == $away" 1
fi

section "Holding SUPER, picking a window on the same desktop, and letting go focuses it"
agent focus a
agent hold SUPER
agent chord TAB
agent chord "$(number_key "$home")"
check "the number shows this desktop" ".omahub.overview.selected.workspace == $home" 1
if agent state '.omahub.overview.selected.address' | grep -q "$(agent state '.focus.address')"; then
  agent chord l
else
  agent chord h
fi
check "the choice is the other test window" '.omahub.overview.selected.address != .focus.address' 1
picked=$(agent state '.omahub.overview.selected.address')
agent let-go SUPER
check "letting go focuses the window picked" "(.omahub.overview.opened | not) and .focus.address == \"$picked\"" 1

section "A slow SUPER + TAB with nothing else stays open to look around"
agent hold SUPER
agent chord TAB
sleep 0.5
agent let-go SUPER
sleep 0.3
check "the overview is still open" '.omahub.overview.opened'

section "A quick SUPER + TAB flips to the last window without showing the overview"
agent focus a
agent focus b
check "b has focus" '.focus.class == "omahub-demo-b"' 1
agent chord SUPER+TAB
check "a has focus and the overview stays closed" '.focus.class == "omahub-demo-a" and (.omahub.overview.opened | not)' 1

section "Shift + a number moves the selected window at once, and u puts it back"
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview shows this desktop with a selected" ".omahub.overview.opened and .omahub.overview.selected.workspace == $home" 2
agent chord "SHIFT+$(number_key "$away")"
check "the window is on the other desktop" "[.windows[] | select(.test and .desktop == $away)] | length == 2" 0.3
check "the move offers undo" '.omahub.overview.undo != null' 1
agent chord u
check "u brings it back" "[.windows[] | select(.test and .desktop == $home)] | length == 2" 1

section "Moving a window while holding SUPER keeps the overview open to keep organizing"
agent focus a
agent hold SUPER
agent chord TAB
agent chord "$(number_key "$home")"
agent chord "SHIFT+$(number_key "$away")"
check "the window moves" "[.windows[] | select(.test and .desktop == $away)] | length == 2" 1
agent let-go SUPER
sleep 0.3
check "letting go leaves the overview open" '.omahub.overview.opened'
agent chord u
check "u brings it back" "[.windows[] | select(.test and .desktop == $home)] | length == 2" 1

section "Dragging a card onto a desktop moves the window"
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open on this desktop" ".omahub.overview.opened and .omahub.overview.selected.workspace == $home" 2
agent drag overview.card:b "overview.desktop:$away"
check "b is on the other desktop" "$(on_desktop b) == $away" 1
agent chord u
check "u brings it back" "$(on_desktop b) == $home" 1

section "Esc closes the overview and leaves focus where it was"
agent focus b
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
agent chord Escape
check "Esc closes it and b keeps focus" '(.omahub.overview.opened | not) and .focus.class == "omahub-demo-b"' 1

finish_live
