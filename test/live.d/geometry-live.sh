#!/bin/bash

# Every dock surface fits, in every position and magnification: the shelf, its menu, and Add apps sit
# fully on the screen and inside the dock's window, and never cover the shelf. Each state is also saved
# as a screenshot in tmp/agent/shots for a person to look at. The sandbox puts the dock settings back.

source "$(dirname "$0")/../live-lib.sh"

section "The dock is on"
if ! agent state '.omahub.dock.shown' | grep -q true; then
  skip "the dock is off, so its geometry checks do not apply"
  exit 0
fi

# jq: true when rectangle $inner lies inside rectangle $outer, with a pixel of rounding allowed.
inside='def inside($inner; $outer): $inner != null and $outer != null
  and $inner.x >= $outer.x - 1 and $inner.y >= $outer.y - 1
  and $inner.x + $inner.width <= $outer.x + $outer.width + 1
  and $inner.y + $inner.height <= $outer.y + $outer.height + 1;
def apart($a; $b): $a.x + $a.width <= $b.x + 1 or $b.x + $b.width <= $a.x + 1
  or $a.y + $a.height <= $b.y + 1 or $b.y + $b.height <= $a.y + 1;'

omahub_set() {
  OMAHUB_PATH="$LIVE_ROOT" "$LIVE_ROOT/bin/omahub" set "$1" "$2" >/dev/null
}

for position in bottom left right; do
  for magnify in off large; do
    section "Dock on the $position, magnification $magnify"
    omahub_set dock/position "$position"
    omahub_set dock/magnify "$magnify"
    omahub_set dock/autohide off
    check "the dock moves there" ".omahub.dock.position == \"$position\" and .omahub.dock.shown" 3
    sleep 0.5
    check "the shelf is on the screen" "$inside inside(.omahub.dock.shelf; .omahub.dock.screen)" 1
    check "and inside the dock's window" "$inside inside(.omahub.dock.shelf; .omahub.dock.window)" 1

    agent chord SUPER+D
    agent chord space
    check "the menu opens" '.omahub.dock.menu and .omahub.dock.menuCard != null' 2
    sleep 0.4
    check "the whole menu is on the screen" "$inside inside(.omahub.dock.menuCard; .omahub.dock.screen)" 1
    check "and inside the dock's window, so nothing is cut off" "$inside inside(.omahub.dock.menuCard; .omahub.dock.window)" 1
    check "and it does not cover the shelf" "$inside apart(.omahub.dock.menuCard; .omahub.dock.shelf)" 1
    agent shot screen >/dev/null

    for _ in $(seq 10); do
      agent state '.omahub.dock.menuEntry' | grep -q "Add apps" && break
      agent chord Down || break
    done
    agent chord Return || true
    check "Add apps opens" '.omahub.dock.picker != null' 2
    sleep 0.4
    check "the whole panel is on the screen" "$inside inside(.omahub.dock.picker.card; .omahub.dock.screen)" 1
    check "and inside the dock's window" "$inside inside(.omahub.dock.picker.card; .omahub.dock.window)" 1
    check "and it does not cover the shelf" "$inside apart(.omahub.dock.picker.card; .omahub.dock.shelf)" 1
    agent shot screen >/dev/null
    agent reset
  done
done

finish_live
