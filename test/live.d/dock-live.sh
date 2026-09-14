#!/bin/bash

# The dock on the live desktop: SUPER + D, its menu, Add apps, and dragging icons. Changes to the kept
# apps are put back when the sandbox ends.

source "$(dirname "$0")/../live-lib.sh"

section "The dock is on"
if ! agent state '.omahub.dock.shown' | grep -q true; then
  skip "the dock is off, so its checks do not apply"
  exit 0
fi
check "the dock shows at least three apps" '(.omahub.dock.apps | length) >= 3'

section "SUPER + D reaches the dock from the keyboard and gives it back"
agent chord SUPER+D
check "the dock has the keyboard and its key set" '.omahub.dock.keyboard and .keyset == "omahub-dock"' 1
cursor=$(agent state '.omahub.dock.cursor')
agent chord Right
check "Right moves the cursor" ".omahub.dock.cursor == $((cursor + 1)) or .omahub.dock.cursor == $cursor and $cursor == ((.omahub.dock.apps | length) - 1)" 1
agent chord space
check "Space opens the menu and it stays open" '.omahub.dock.menu' 1
sleep 0.5
check "the menu is still open half a second later" '.omahub.dock.menu and .omahub.dock.keyboard'
agent chord Escape
check "Esc closes the menu and keeps the keyboard" '(.omahub.dock.menu | not) and .omahub.dock.keyboard' 1
agent chord SUPER+D
check "SUPER + D again gives the keyboard back" '(.omahub.dock.keyboard | not) and .keyset == "default"' 1

section "Add apps searches, keeps, and removes apps"
agent chord SUPER+D
agent chord space
for _ in $(seq 8); do
  agent state '.omahub.dock.menuEntry' | grep -q "Add apps" && break
  agent chord Down || break
done
check "the menu reaches Add apps" '.omahub.dock.menuEntry == "Add apps…"' 1
agent chord Return || true
check "Add apps opens with apps listed" '.omahub.dock.picker != null and .omahub.dock.picker.rows > 0' 1
if agent state '.omahub.dock.picker != null' | grep -q true; then
  for letter in z z q x; do
    agent chord "$letter" || break
  done
  check "a search with no match lists nothing" '.omahub.dock.picker.query == "zzqx" and .omahub.dock.picker.rows == 0' 1
  agent chord Escape || true
  check "Esc clears the search first" '.omahub.dock.picker != null and .omahub.dock.picker.query == ""' 1
  for _ in $(seq 40); do
    agent state '.omahub.dock.picker.selected.kept' | grep -q false && break
    agent chord Down || break
  done
  app=$(agent state '.omahub.dock.picker.selected.id // empty')
  if [[ -n $app ]] && agent state '.omahub.dock.picker.selected.kept' | grep -q false; then
    agent chord Return || true
    check "Enter keeps $app" ".omahub.dock.picker.selected.kept and any(.omahub.dock.apps[]; .id == \"$app\")" 2
    agent chord Return || true
    check "Enter again removes it" "(.omahub.dock.picker.selected.kept | not) and (any(.omahub.dock.apps[]; .id == \"$app\") | not)" 2
  else
    skip "every app is already in the dock"
  fi
  agent chord Escape || true
  check "Esc closes Add apps" '.omahub.dock.picker == null' 1
fi

section "Dragging an icon along the dock moves it"
first=$(agent state '.omahub.dock.apps[0].id')
spot=$(agent state '.omahub.dock.apps[2] | "\((.x + .width / 2 + 12) | floor),\((.y + .height / 2) | floor)"')
agent drag "dock.app:$first" "$spot"
check "$first is third" ".omahub.dock.apps[2].id == \"$first\"" 2

section "Dragging a kept icon off the dock removes it"
gone=$(agent state '[.omahub.dock.apps[] | select(.windows == 0)][1].id // [.omahub.dock.apps[] | select(.windows == 0)][0].id')
spot=$(agent state ".omahub.dock.apps[] | select(.id == \"$gone\") | \"\((.x + .width / 2) | floor),\((.y + .height / 2 - 220) | floor)\"")
agent drag "dock.app:$gone" "$spot"
check "$gone is gone from the dock" "any(.omahub.dock.apps[]; .id == \"$gone\") | not" 2

finish_live
