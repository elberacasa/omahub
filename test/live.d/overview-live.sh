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

section "Walking on with TAB and back with SHIFT + TAB, then letting go, jumps"
agent focus b
agent focus a
agent hold SUPER
agent chord TAB
sleep 0.3
agent chord TAB
sleep 0.3
agent chord SHIFT+TAB
sleep 0.4
check "SHIFT + TAB walks back to b" '.omahub.overview.opened and .omahub.overview.selected.address == (.windows[] | select(.class == "omahub-demo-b") | .address)' 1
agent let-go SUPER
check "letting go focuses b and closes" '(.omahub.overview.opened | not) and .focus.class == "omahub-demo-b"' 1

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

section "Clicking another desktop goes there and leaves the pointer where it clicked"
warp_before=$(hyprctl getoption cursor:warp_on_change_workspace -j | jq -c '.int')
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
agent point "overview.desktop:$away"
sleep 0.3
before=$(agent state '.pointer | "\(.x) \(.y)"')
agent click "overview.desktop:$away"
check "the other desktop comes forward" "(.omahub.overview.opened | not) and .desktop == $away" 2
sleep 0.2
read -r bx by <<<"$before"
check "the pointer stays where it clicked" "(.pointer.x - $bx | fabs) <= 3 and (.pointer.y - $by | fabs) <= 3" 0
sleep 0.6
if [[ $(hyprctl getoption cursor:warp_on_change_workspace -j | jq -c '.int') == "$warp_before" ]]; then
  echo "  ok    Omarchy's pointer setting is back afterwards"
else
  echo "  FAIL  Omarchy's pointer setting is back afterwards"
  LIVE_FAILURES=$((LIVE_FAILURES + 1))
fi

section "Esc closes the overview and leaves focus where it was"
agent focus b
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
agent chord Escape
check "Esc closes it and b keeps focus" '(.omahub.overview.opened | not) and .focus.class == "omahub-demo-b"' 1

finish_live
