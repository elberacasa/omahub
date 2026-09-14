#!/bin/bash

# The hub on the live desktop, with settings made only for these checks, so no real setting ever
# changes: opening on a setting, Space changing it, a change that fails going back with a reason,
# search, and Esc. The sandbox removes the check settings when it ends.

source "$(dirname "$0")/../live-lib.sh"

checks="$HOME/.config/omahub/settings/zz-check"
store="$HOME/.config/omahub/zz-check-switch"
mkdir -p "$checks"

cat >"$checks/switch" <<'EOF'
#!/bin/bash

# omahub:title=Check switch
# omahub:summary=A setting live checks turn on and off
# omahub:section=zz-check
# omahub:kind=toggle
# omahub:order=1

set -euo pipefail
source "${OMAHUB_PATH:?run this through omahub}/lib/settings.sh"

store="$HOME/.config/omahub/zz-check-switch"
case "${1:-}" in
  get) ;;
  set)
    case "${2:-}" in
      on | true) echo on >"$store" ;;
      off | false) rm -f "$store" ;;
      *) omahub_fail "'${2:-}' is not on or off" ;;
    esac
    ;;
  reset) rm -f "$store" ;;
  *) omahub_fail "usage: omahub get|set|reset zz-check/switch" ;;
esac
if [[ -f $store ]]; then omahub_state true "On"; else omahub_state false "Off"; fi
EOF

cat >"$checks/broken" <<'EOF'
#!/bin/bash

# omahub:title=Check broken switch
# omahub:summary=A setting whose changes always fail
# omahub:section=zz-check
# omahub:kind=toggle
# omahub:order=2

set -euo pipefail
source "${OMAHUB_PATH:?run this through omahub}/lib/settings.sh"

case "${1:-}" in
  get) omahub_state false "Off" ;;
  set) omahub_fail "This check setting cannot change" ;;
  reset) omahub_state false "Off" ;;
  *) omahub_fail "usage: omahub get|set|reset zz-check/broken" ;;
esac
EOF
chmod +x "$checks/switch" "$checks/broken"
rm -f "$store"

section "The hub opens on a setting"
agent call open '{"setting":"zz-check/switch"}' >/dev/null
check "the hub opens with the cursor on the check switch" '.omahub.hub.opened and .omahub.hub.row == "zz-check/switch" and (.omahub.hub.loading | not)' 4
check "the switch reads off" '.omahub.hub.rowValue == false' 2

section "Space turns a setting on and off"
agent call open '{"setting":"zz-check/switch"}' >/dev/null
check "the cursor is on the check switch" '.omahub.hub.row == "zz-check/switch"' 4
agent chord space
check "Space turns it on" '.omahub.hub.rowValue == true' 1
sleep 0.5
if [[ -f $store ]]; then echo "  ok    the setting stored on"; else echo "  FAIL  the setting stored on"; LIVE_FAILURES=$((LIVE_FAILURES + 1)); fi
agent chord space
check "Space again turns it off" '.omahub.hub.rowValue == false' 2
sleep 0.5
if [[ ! -f $store ]]; then echo "  ok    the setting stored off"; else echo "  FAIL  the setting stored off"; LIVE_FAILURES=$((LIVE_FAILURES + 1)); fi

section "A change that fails goes back and says why"
agent call open '{"setting":"zz-check/broken"}' >/dev/null
check "the cursor is on the broken switch" '.omahub.hub.row == "zz-check/broken" and (.omahub.hub.loading | not)' 4
agent chord space
check "the row says why the change failed" '.omahub.hub.rowError != null' 4
check "the row goes back to off" '.omahub.hub.rowValue == false and .omahub.hub.busy == null' 4

section "Search finds settings and Esc steps back"
agent call open '{"setting":"zz-check/switch"}' >/dev/null
check "the hub is open" '.omahub.hub.opened and (.omahub.hub.loading | not)' 4
agent chord /
for letter in c h e c k; do
  agent chord "$letter"
done
check "typing searches every setting" '.omahub.hub.searching and .omahub.hub.query == "check" and (.omahub.hub.rows | index("zz-check/switch")) != null' 2
agent chord Escape
check "Esc clears the search first" '.omahub.hub.opened and .omahub.hub.query == ""' 2
agent chord Escape
check "Esc again closes the hub" '.omahub.hub.opened | not' 2

section "The hub and its welcome fit on the screen"
for view in hub welcome; do
  if [[ $view == "welcome" ]]; then
    agent call open '{"view":"welcome"}' >/dev/null
  else
    agent call open '{"setting":"zz-check/switch"}' >/dev/null
  fi
  check "the $view opens" ".omahub.hub.opened and .omahub.hub.view == \"$view\"" 3
  sleep 0.5
  check "its card is fully on the screen" '.omahub.hub.card as $c | .omahub.hub.panel as $p
    | $c.x >= 0 and $c.y >= 0 and $c.x + $c.width <= $p.width + 1 and $c.y + $c.height <= $p.height + 1' 1
  agent shot screen >/dev/null
  agent call dismiss >/dev/null
  sleep 0.4
done

finish_live
