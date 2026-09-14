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
  or $a.y + $a.height <= $b.y + 1 or $b.y + $b.height <= $a.y + 1;
def along($inner; $usable; $position): if $position == "bottom"
  then $inner.x >= $usable.x - 1 and $inner.x + $inner.width <= $usable.x + $usable.width + 1
  else $inner.y >= $usable.y - 1 and $inner.y + $inner.height <= $usable.y + $usable.height + 1 end;'
# The usable area leaves out every reserved band, the dock's own included, so the shelf is only measured
# along the edge it sits on.

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
    check "and clear of the bar along its edge" "$inside along(.omahub.dock.shelf; .omahub.dock.usable; .omahub.dock.position)" 1
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

section "A crowded dock with desktops still fits clear of the bar"
omahub_set dock/desktops on
omahub_set dock/autohide off
mapfile -t many < <(grep -L -E '^(NoDisplay|Hidden)=true' /usr/share/applications/*.desktop 2>/dev/null | head -40 | xargs -r -n1 basename | sed 's/\.desktop$//')
OMAHUB_PATH="$LIVE_ROOT" "$LIVE_ROOT/bin/omahub" dock order "${many[@]}" >/dev/null
for position in left bottom; do
  omahub_set dock/position "$position"
  omahub_set dock/magnify large
  check "the crowded dock is on the $position" ".omahub.dock.position == \"$position\" and (.omahub.dock.apps | length) >= 12" 3
  sleep 1
  check "the shelf fits clear of the bar" "$inside along(.omahub.dock.shelf; .omahub.dock.usable; .omahub.dock.position)" 1
  middle=$(agent state '.omahub.dock.apps[(.omahub.dock.apps | length) / 2 | floor].id')
  agent point "dock.app:$middle"
  sleep 0.5
  check "and still does with the icons under the pointer magnified" "$inside along(.omahub.dock.shelf; .omahub.dock.usable; .omahub.dock.position)" 1
  away=$(agent state .sandbox.away)
  # Leaving the magnified apps shrinks them and the tiles slide in, so point again once they settle.
  agent point "dock.desktop:$away"
  sleep 0.4
  agent point "dock.desktop:$away"
  sleep 0.4
  check "pointing at a desktop tile lights that tile" ".omahub.dock.hoveredDesktop == $away" 1
  agent shot screen >/dev/null
done
agent reset

finish_live
