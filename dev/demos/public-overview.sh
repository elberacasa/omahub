#!/bin/bash

# Public take of the overview on staged desktops. Run with --stage:
#   dev/demo dev/demos/public-overview.sh 22 --stage
# A slow SUPER + TAB opens the overview on the window used before, l and h walk desktops, a drag
# moves the demo page to another desktop, and a click goes there.

source "$(dirname "$0")/../demo-lib.sh"

log="$DEMO_ROOT/tmp/demos/public-overview.log"
mkdir -p "$(dirname "$log")"
: >"$log"

note() {
  echo "$(date +%s.%N) $1: desktop $(hyprctl activeworkspace -j | jq -r .id), overview $(layout overviewLayout | jq -c '{opened, cycling, selected: .selected.title, cards: [.cards[].title]}')" >>"$log"
  echo "  focus history: $(hyprctl clients -j | jq -c '[.[] | select(.title == "Moonshot" or (.class | startswith("omahub-demo-"))) | {title, ws: .workspace.id, focus: .focusHistoryID}] | sort_by(.focus)')" >>"$log"
}

# Desktop 1 holds a single window, so going back to it cannot refocus a second one there, and the
# page on desktop 2 is the window used before.
open_showcase_terminal help 1 "clear; $DEMO_ROOT/bin/omahub --help"
open_showcase_page 2
open_showcase_terminal banner 3 "clear; cat $DEMO_ROOT/assets/omahub.txt"
open_showcase_terminal notes 3 "clear; cat $DEMO_ROOT/dev/demos/pages/notes.txt"
page() {
  hyprctl clients -j | jq -r '.[] | select(.title == "Moonshot") | .address'
}
focus_window() {
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null
}
focus_window "$(page)"
pause 0.6
focus_window "$(hyprctl clients -j | jq -r '.[] | select(.class == "omahub-demo-help") | .address')"
pause 1.2
note start

summon '{"overview":"next"}'
pause 0.9
omarchy-shell shell call "$DEMO_OMAHUB_ID" overviewRelease "" >/dev/null
pause 1.4
note browse
key l
pause 1.0
note l
key h
pause 1.0
note h

view=$(layout overviewLayout)
read -r from_x from_y <<<"$(center "$view" '.cards[] | select(.title == "Moonshot")')"
read -r to_x to_y <<<"$(center "$view" '.desktops[] | select(.id == 3)')"
echo "drag $from_x,$from_y to $to_x,$to_y" >>"$log"
drag "$from_x" "$from_y" "$to_x" "$to_y" 1100
pause 1.2
echo "page now on desktop: $(hyprctl clients -j | jq -r '.[] | select(.title == "Moonshot") | .workspace.id')" >>"$log"

key 3
pause 1.1
note three
view=$(layout overviewLayout)
read -r card_x card_y <<<"$(center "$view" '.cards[] | select(.title == "Moonshot")')"
move "$card_x" "$card_y" 700
pause 0.4
click left
pause 1.5
echo "landed on desktop: $(hyprctl activeworkspace -j | jq -r '.id')" >>"$log"

close_showcase_windows
