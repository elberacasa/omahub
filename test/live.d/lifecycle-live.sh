#!/bin/bash

# Omahub as an Omarchy plugin on the live desktop: disabling it stops it cleanly, enabling it brings
# everything back, and it survives a shell restart. The sandbox puts Omarchy's plugin settings back
# when it ends.

source "$(dirname "$0")/../live-lib.sh"

id="io.github.elberacasa.omahub"
dock_was_on=$(agent state '.omahub.dock.shown // false')

answers() {
  omarchy-shell shell call "$id" inspect "" >/dev/null 2>&1
}

wait_until() {
  local seconds="$1"
  shift
  for _ in $(seq $((seconds * 10))); do
    if "$@"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

record() {
  if "${@:2}"; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1"
    LIVE_FAILURES=$((LIVE_FAILURES + 1))
  fi
}

no_surfaces() {
  ! hyprctl layers -j | jq -e '[.. | objects | select(has("namespace")) | .namespace] | any(startswith("omahub-"))' >/dev/null
}

# Omahub is keepLoaded, so Omarchy keeps its instance mounted while disabled, as its shell documents.
# What a person sees is what counts: nothing on screen, and nothing that can be summoned.
section "Disabling Omahub stops it cleanly"
omarchy plugin disable "$id" >/dev/null
record "Omarchy lists Omahub as disabled" wait_until 5 bash -c "omarchy plugin list --json | jq -e '.[] | select(.id == \"$id\") | .enabled | not' >/dev/null"
record "no Omahub surface is left on screen" wait_until 5 no_surfaces
record "Hyprland is back in its usual key set" wait_until 3 bash -c '[[ $(hyprctl submap | head -1) == "default" ]]'
omarchy-shell shell summon "$id" '{"overview":"open"}' >/dev/null 2>&1 || true
sleep 1
record "the overview cannot be summoned while disabled" no_surfaces

section "Enabling Omahub brings it back"
omarchy plugin enable "$id" >/dev/null
record "Omahub answers again" wait_until 15 answers
if [[ $dock_was_on == "true" ]]; then
  check "the dock is back" '.omahub.dock.shown' 5
fi
agent call open '{"overview":"open"}' >/dev/null
check "the overview opens" '.omahub.overview.opened' 3
agent chord Escape
check "and closes" '.omahub.overview.opened | not' 2

section "Omahub survives a shell restart"
omarchy restart shell >/dev/null 2>&1 || true
sleep 1
record "Omahub answers after the restart" wait_until 20 answers
if [[ $dock_was_on == "true" ]]; then
  check "the dock is back after the restart" '.omahub.dock.shown' 5
fi
check "Hyprland is in its usual key set after the restart" '.keyset == "default"' 3

finish_live
