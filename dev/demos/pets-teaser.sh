#!/bin/bash

# The omahub pets teaser, one continuous take: bring the studio up with dev/studio up --terminals. The seven pets
# parade on the stage, which clears to an empty desktop whose dock holds three agents working on Omahub on other
# desktops. The pointer opens a pet's card, with its project, branch, and what it is doing, just as that agent
# finishes with a hop. Another pet calls to run the tests and is answered from the dock, and finishes too. The
# stage comes back as an end card: the keycap and the omahub wordmark, "Pets for your coding agents", and the pets.
#
#   bash dev/demos/pets-teaser.sh setup|take|cleanup
#   dev/take pets-teaser 20 --quiet --run "bash dev/demos/pets-teaser.sh take"
#
# The agents are dev/demos/agent-replica.py, so no model or account is touched, and their session records are
# written only for the studio projects and deleted by cleanup.

source "$(dirname "$0")/studio-lib.sh"
source "$(dirname "$0")/pets-lib.sh"

STAND_INS="omahub omahub-stats omahub-menu"
FILMED_DESKTOP=4
LOOKS=(blob cat gem bunny fox owl robot)

stage() {
  "$STUDIO_ROOT/dev/pet-stage" "$@" >/dev/null
}

# Every pet at once in one mood, as a stage payload, with the end card when asked.
parade() {
  jq -nc --arg mood "$1" --argjson title "${2:-false}" --argjson pixel "${3:-14}" \
    '{pixel: $pixel, gap: 5, background: "theme", title: $title, caption: "Pets for your coding agents", pets: (["blob", "cat", "gem", "bunny", "fox", "owl", "robot"] | map({look: ., mood: $mood}))}'
}

wave() {
  local mood="$1" beat="$2" index
  for index in "${!LOOKS[@]}"; do
    stage mood "$index" "$mood"
    sleep "$beat"
  done
}

case "${1:-}" in
  setup)
    [[ -f $STUDIO_ROOT/tmp/studio/terminals ]] || { echo "bring the studio up in terminals: dev/studio up --terminals" >&2; exit 2; }
    mkdir -p "$PETS"
    : >>"$PETS/created"
    project omahub feature/bar-pets
    project omahub-stats feature/stats-overlay
    project omahub-menu feature/dock-menu
    "$OMAHUB" set dock/desktops off >/dev/null
    "$OMAHUB" set dock/agents on >/dev/null
    "$OMAHUB" set dock/autohide off >/dev/null
    "$OMAHUB" set dock/magnify subtle >/dev/null
    "$OMAHUB" set dock/size large >/dev/null
    "$OMAHUB" dock order foot chromium org.gnome.Nautilus >/dev/null
    "$OMAHUB" set dock/pet-motion lively >/dev/null
    "$OMAHUB" reset dock/pet-claude >/dev/null
    "$OMAHUB" reset dock/pet-gpt >/dev/null
    "$OMAHUB" set dock/agent-card project,state,step,message >/dev/null

    stand_in claude omahub 1
    say_user omahub "put the pets in the top bar, smaller but fully working"
    say_spin omahub "Crafting" 48
    claude_prompt omahub "$(( EPOCHSECONDS - 48 ))" "put the pets in the top bar, smaller but fully working"
    claude_tool omahub Edit

    stand_in claude omahub-stats 2
    say_user omahub-stats "draw a small overlay with tokens and turns per agent"
    say_spin omahub-stats "Polishing" 126
    claude_prompt omahub-stats "$(( EPOCHSECONDS - 126 ))" "draw a small overlay with tokens and turns per agent"
    claude_tool omahub-stats Write

    stand_in codex omahub-menu 3
    say_user omahub-menu "give the dock menu chips for size and position"
    say_spin omahub-menu "Working" 140
    codex_start omahub-menu "$(( EPOCHSECONDS - 140 ))"

    wait_for_agents '[.omahub.dock.agents[]? | .agent] | sort == ["working","working","working"]'
    only_stand_ins
    park
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$FILMED_DESKTOP\" })" >/dev/null
    stage show "$(parade "")"
    sleep 0.8
    ;;
  take)
    only_stand_ins
    # The parade.
    pause 0.15
    wave agent 0.05
    pause 0.5
    wave working 0.06
    pause 1.3
    wave done 0.11
    pause 1.1
    stage close
    pause 0.5

    # A pet's card: its project, branch, and work, as its agent finishes.
    read -r x y <<<"$(tile_center omahub-stats)"
    move $(( x + 120 )) $(( y - 260 )) 1
    glide "$x" "$y" 800
    pause 1.1
    say_done omahub-stats "The overlay shows tokens and turns per agent, over any window." "2m 9s"
    claude_done omahub-stats "The overlay shows tokens and turns per agent, over any window."
    pause 1.7

    # A call, answered from the dock.
    say_ask omahub Bash "test/all" "Run every Omahub test"
    ask omahub Bash "test/all"
    pause 0.8
    read -r x y <<<"$(tile_center omahub)"
    glide "$x" "$y" 600
    pause 0.25
    click right
    pause 1.2
    agent chord a >/dev/null
    settle omahub
    say_ask_off omahub
    say_tool omahub Bash "test/all" "All tests passed."
    claude_tool omahub Bash
    pause 1.0
    say_done omahub "Pets sit in the top bar now, with their card on hover and quick answers." "52s"
    claude_done omahub "Pets sit in the top bar now, with their card on hover and quick answers."
    pause 1.5
    read -r x y <<<"$(tile_center omahub-menu)"
    glide $(( x + 180 )) $(( y - 420 )) 700
    pause 0.3

    # The end card, with a last wave of hops.
    stage show "$(parade working true 10)"
    pause 1.4
    wave done 0.07
    pause 1.8
    ;;
  cleanup)
    stage close
    agent chord Escape >/dev/null 2>&1 || true
    for name in $STAND_INS; do settle "$name"; done
    { cat "$PETS"/address-* 2>/dev/null; } |
      while IFS= read -r address; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
      done
    sleep 0.5
    if [[ -f $PETS/created ]]; then
      while IFS= read -r path; do
        case "$path" in
          "$PROJECTS"/omahub | "$PROJECTS"/omahub-stats | "$PROJECTS"/omahub-menu) rm -rf "$path" ;;
          "$HOME/.claude/projects/$(encoded "$PROJECTS")"-*) rm -rf "$path" ;;
          "$HOME/.codex/sessions/"*/rollout-*.jsonl) rm -f "$path" ;;
        esac
      done <"$PETS/created"
    fi
    rm -rf "$PETS"
    "$OMAHUB" reset dock/autohide >/dev/null
    "$OMAHUB" reset dock/magnify >/dev/null
    "$OMAHUB" reset dock/size >/dev/null
    rest
    ;;
  *) sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
