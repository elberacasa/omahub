#!/bin/bash

# Agents in the dock, filmed as a day building Omahub: bring the studio up with dev/studio up --terminals.
# Four worktrees sit on desktops 1 to 4, each with an agent and a terminal beside it: pets in the top bar,
# a stats overlay, a file tree, and the dock's menu. You give the sleeping Claude on desktop 1 its next
# task and its pet wakes, the stats agent finishes under the pointer and a click on its pet goes there,
# the file tree agent asks to run the tests and is allowed from its tile, SUPER + TAB and 4 go to Codex,
# which gets a note typed into it, and desktop 1's agent finishes as the pointer comes back to its pet.
#
# It is a mockup of real use with the clock sped up: pets nap after six seconds, and every turn is written by
# the scene. The agents are dev/demos/agent-replica.py, drawn like Claude Code and Codex and launched as
# scripts named claude and codex, so they never talk to a model or an account. Their session records are
# written where Claude Code and Codex keep them, only for these studio projects, and cleanup deletes every
# one. The studio's sandbox puts every setting back when the studio comes down.

source "$(dirname "$0")/studio-lib.sh"

PETS="$STUDIO_ROOT/tmp/studio/pets"
PROJECTS="$HOME/Code"
OMAHUB="$STUDIO_ROOT/bin/omahub"
STATE_DIR="$HOME/.local/state/omahub"
CODEX_DAY="$HOME/.codex/sessions/$(date +%Y/%m/%d)"
NAP_SECONDS=6
CODEX_MODEL="gpt-6-codex"
# Terminals in the video: foot as it opens for anyone, with text large enough to read on a phone.
TERMINAL_FONT="monospace:size=13"
STAND_INS="omahub omahub-stats omahub-files omahub-menu"

encoded() {
  printf '%s' "$1" | sed 's/[^a-zA-Z0-9]/-/g'
}

record_key() {
  printf '%s' "$1" | sha1sum | cut -c1-16
}

claude_log() {
  printf '%s\n' "$HOME/.claude/projects/$(encoded "$PROJECTS/$1")/omahub-studio.jsonl"
}

iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z
}

claude_write() {
  local log
  log=$(claude_log "$1")
  mkdir -p "$(dirname "$log")"
  grep -qxF "$(dirname "$log")" "$PETS/created" 2>/dev/null || dirname "$log" >>"$PETS/created"
  printf '%s\n' "$2" >>"$log"
}

claude_prompt() {
  claude_write "$1" "$(jq -nc --arg ts "$(iso "$2")" --arg text "$3" '{type: "user", timestamp: $ts, message: {role: "user", content: $text}}')"
}

claude_tool() {
  claude_write "$1" "$(jq -nc --arg name "$2" '{type: "assistant", message: {model: "claude-opus-5", stop_reason: "tool_use", content: [{type: "tool_use", name: $name}]}}')"
}

claude_done() {
  claude_write "$1" "$(jq -nc --arg text "$2" '{type: "assistant", message: {model: "claude-opus-5", stop_reason: "end_turn", content: [{type: "text", text: $text}]}}')"
  claude_write "$1" '{"type":"system","subtype":"turn_duration"}'
}

codex_start() {
  local id log
  id=$(cat /proc/sys/kernel/random/uuid)
  mkdir -p "$CODEX_DAY"
  log="$CODEX_DAY/rollout-$(date +%Y-%m-%dT%H-%M-%S)-$id.jsonl"
  printf '%s\n' "$log" >>"$PETS/created"
  {
    jq -nc --arg cwd "$PROJECTS/$1" --arg id "$id" '{type: "session_meta", payload: {id: $id, cwd: $cwd}}'
    jq -nc --arg model "$CODEX_MODEL" '{type: "turn_context", payload: {model: $model}}'
    jq -nc --argjson at "$2" '{type: "event_msg", payload: {type: "task_started", started_at: $at}}'
    jq -nc '{type: "response_item", payload: {type: "custom_tool_call", name: "apply_patch"}}'
  } >"$log"
}

# A git worktree of the studio's kind, made only when the folder is free, and deleted by cleanup.
project() {
  local dir="$PROJECTS/$1"
  [[ -e $dir ]] && return 0
  mkdir -p "$dir"
  printf '%s\n' "$dir" >>"$PETS/created"
  git -C "$dir" init -q -b "$2"
  printf '# %s\n' "$1" >"$dir/README.md"
  git -C "$dir" add -A
  GIT_AUTHOR_NAME="Omahub" GIT_AUTHOR_EMAIL="studio@omahub.example" GIT_COMMITTER_NAME="Omahub" \
    GIT_COMMITTER_EMAIL="studio@omahub.example" git -C "$dir" commit -q -m "Start $1"
}

# What an agent's screen shows next, as one event for dev/demos/agent-replica.py.
event() {
  printf '%s\n' "$2" >>"$PETS/events-$1"
}

say_user() { event "$1" "$(jq -nc --arg text "$2" '{type: "user", text: $text}')"; }
say_tool() { event "$1" "$(jq -nc --arg name "$2" --arg arg "$3" --arg result "$4" '{type: "tool", name: $name, arg: $arg, result: $result}')"; }
say_diff() { event "$1" "$(jq -nc --argjson rows "$2" '{type: "diff", rows: $rows}')"; }
say_spin() { event "$1" "$(jq -nc --arg label "$2" --argjson elapsed "${3:-0}" '{type: "spin", label: $label, elapsed: $elapsed}')"; }
say_done() { event "$1" "$(jq -nc --arg text "$2" --arg worked "$3" '{type: "done", text: $text, worked: $worked}')"; }
say_ask() { event "$1" "$(jq -nc --arg tool "$2" --arg command "$3" --arg note "$4" '{type: "ask", tool: $tool, command: $command, note: $note}')"; }
say_ask_off() { event "$1" '{"type":"ask_off"}'; }

# A foot terminal with a title no other window has, on a desktop. It is remembered by address, owned as a
# test window so dev/agent drives it, and grouped under the dock's terminal like any foot window.
launch_terminal() {
  local key="$1" title="$2" desktop="$3" command="$4" address=""
  hyprctl eval "hl.exec_cmd('foot -o font=$TERMINAL_FONT --title=\"$title\" $command', { workspace = '$desktop silent' })" >/dev/null
  for _ in $(seq 80); do
    address=$(hyprctl clients -j | jq -r --arg title "$title" '.[] | select(.class == "foot" and .title == $title) | .address' | head -1)
    [[ -n $address ]] && break
    sleep 0.1
  done
  [[ -n $address ]] || { echo "studio-pets: the $title terminal did not open" >&2; exit 1; }
  printf '%s\n' "$address" >"$PETS/address-$key"
  agent own "$address" >/dev/null
}

address_of() {
  cat "$PETS/address-$1"
}

# An agent drawn like Claude Code or Codex, in a terminal on its worktree's desktop.
stand_in() {
  local agent="$1" name="$2" desktop="$3" bin="$PETS/bin/$1"
  if [[ ! -x $bin ]]; then
    mkdir -p "$PETS/bin"
    printf '#!/usr/bin/python3\nimport runpy\nrunpy.run_path("%s", run_name="__main__")\n' "$STUDIO_ROOT/dev/demos/agent-replica.py" >"$bin"
    chmod +x "$bin"
  fi
  : >"$PETS/events-$name"
  launch_terminal "pet-$name" "$name" "$desktop" \
    "env REPLICA_AGENT=$agent REPLICA_EVENTS=$PETS/events-$name REPLICA_SUBMITTED=$PETS/submitted-$name REPLICA_MODEL=$CODEX_MODEL sh -c \"cd $PROJECTS/$name && $bin\""
}

# The terminal beside each agent: what the work looks like so far, in the worktree's folder.
beside() {
  local name="$1" desktop="$2" subtitle="$3" script="$PETS/side-$1.sh"
  {
    printf '#!/bin/bash\nprintf "\\033[?25l"\ncat <<"SIDE"\n'
    printf '%b\n' "$4"
    printf 'SIDE\nexec sleep infinity\n'
  } >"$script"
  chmod +x "$script"
  launch_terminal "side-$name" "$name · $subtitle" "$desktop" "--working-directory=$PROJECTS/$name $script"
}

# The take films only the scene's agents. Any other tile would show a real session, so the scene stops first.
only_stand_ins() {
  local expected others
  expected=$(cat "$PETS"/address-pet-* 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))')
  others=$(agent state "[.omahub.dock.agents[]? | .address | select(. as \$a | $expected | index(\$a) | not)] | length")
  if [[ $others != "0" ]]; then
    echo "studio-pets: $others agent tiles are not the scene's, so nothing is filmed" >&2
    exit 1
  fi
}

# The middle of a stand-in's tile on screen, as "x y".
tile_center() {
  agent state ".omahub.dock.agents[] | select(.project == \"$1\") | \"\\((.x + .width / 2) | floor) \\((.y + .height / 2) | floor)\"" | tr -d '"'
}

# A spot inside a scene's window, as "x y", by its key and fractions of its width and height.
window_spot() {
  hyprctl clients -j | jq -r --arg address "$(address_of "$1")" --argjson fx "$2" --argjson fy "$3" \
    '.[] | select(.address == $address) | "\((.at[0] + .size[0] * $fx) | floor) \((.at[1] + .size[1] * $fy) | floor)"' | head -1
}

ask() {
  local log key
  log=$(claude_log "$1")
  key=$(record_key "$log")
  mkdir -p "$STATE_DIR/requests" "$STATE_DIR/signals"
  jq -nc --arg tool "$2" --arg detail "$3" --argjson at "$EPOCHSECONDS" '{tool: $tool, detail: $detail, at: $at}' >"$STATE_DIR/requests/$key.json"
  jq -nc --argjson at "$EPOCHSECONDS" '{event: "PermissionRequest", at: $at}' >"$STATE_DIR/signals/$key.json"
}

settle() {
  local log key
  log=$(claude_log "$1")
  key=$(record_key "$log")
  rm -f "$STATE_DIR/requests/$key.json" "$STATE_DIR/signals/$key.json" "$STATE_DIR/answers/$key.json"
}

# Waits until what was typed into an agent's input reaches its transcript.
wait_submitted() {
  for _ in $(seq 30); do
    [[ -s $PETS/submitted-$1 ]] && return 0
    sleep 0.05
  done
}

wait_for_agents() {
  for _ in $(seq 40); do
    agent state "$1" | grep -q true && return 0
    sleep 0.5
  done
  echo "studio-pets: the dock shows $(agent state '[.omahub.dock.agents[]? | [.project, .agent]]' | jq -c .)" >&2
  exit 1
}

case "${1:-}" in
  setup)
    [[ -f $STUDIO_ROOT/tmp/studio/terminals ]] || { echo "bring the studio up in terminals: dev/studio up --terminals" >&2; exit 2; }
    mkdir -p "$PETS"
    : >>"$PETS/created"
    project omahub feature/bar-pets
    project omahub-stats feature/stats-overlay
    project omahub-files feature/file-tree
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
    # The sped up clock: a finished agent's pet dozes off after a few seconds.
    jq --argjson nap "$NAP_SECONDS" '.["pet-naps"] = $nap' "$STATE_DIR/dock.json" >"$PETS/dock.json" && mv "$PETS/dock.json" "$STATE_DIR/dock.json"

    # Desktop 1: pets in the top bar. Its agent finished a while ago and sleeps.
    stand_in claude omahub 1
    beside omahub 1 "git log" "\n  \033[1momahub\033[0m  \033[2mfeature/bar-pets\033[0m\n\n  \033[33ma41c9e2\033[0m  Let sleeping pets doze with drifting z's\n  \033[33m7b85295\033[0m  Give pets their projects' colors\n  \033[33m3eb6b2c\033[0m  Answer agents from their tile\n  \033[33m928c174\033[0m  Describe agent tiles in the README\n  \033[33mcd6d815\033[0m  Find agents in folders outside git"
    say_user omahub "make the dock pets feel alive"
    say_tool omahub Update "dock/AgentPet.qml" "Updated dock/AgentPet.qml with 18 additions and 4 removals"
    say_done omahub "Pets now blink, breathe, and look toward the pointer. Sleeping ones doze with drifting z's." "4m 12s"
    claude_prompt omahub "$(( EPOCHSECONDS - 60 ))" "make the dock pets feel alive"
    claude_done omahub "Pets now blink, breathe, and look toward the pointer."

    # Desktop 2: a stats overlay, nearly done.
    stand_in claude omahub-stats 2
    beside omahub-stats 2 "preview" "\n  \033[1mAgent stats\033[0m  \033[2mtoday\033[0m\n\n  omahub        \033[36m████████████▌\033[0m  48k tokens   9 turns\n  omahub-files  \033[35m███████▎\033[0m       29k tokens   6 turns\n  omahub-menu   \033[34m████▋\033[0m          18k tokens   4 turns\n  omahub-stats  \033[33m██▉\033[0m            11k tokens   3 turns\n\n  \033[2mWaiting on you\033[0m 0     \033[2mDone since lunch\033[0m 7"
    say_user omahub-stats "draw a small overlay with tokens and turns per agent"
    say_tool omahub-stats Read "desktops/context.sh" "Read 312 lines"
    say_tool omahub-stats Write "stats/Overlay.qml" "Wrote 96 lines to stats/Overlay.qml"
    say_spin omahub-stats "Polishing" 94
    claude_prompt omahub-stats "$(( EPOCHSECONDS - 94 ))" "draw a small overlay with tokens and turns per agent"
    claude_tool omahub-stats Write

    # Desktop 3: a file tree with git status, about to ask for the tests.
    stand_in claude omahub-files 3
    beside omahub-files 3 "tree" "\n  \033[1momahub-files\033[0m  \033[2mfeature/file-tree\033[0m\n\n  ▾ files/\n      Tree.qml           \033[33mM\033[0m\n      TreeModel.js       \033[32mA\033[0m\n      git-status.sh      \033[32mA\033[0m\n  ▸ dock/\n  ▸ desktops/\n    manifest.json        \033[33mM\033[0m"
    say_user omahub-files "add a file tree with git status to the hub"
    say_tool omahub-files Read "hub/Hub.qml" "Read 212 lines"
    say_tool omahub-files Update "files/Tree.qml" "Updated files/Tree.qml with 3 additions and 1 removal"
    say_diff omahub-files '[["-", 41, "    color: Color.text"], ["+", 41, "    color: row.status === \"M\" ? Color.warning : Color.text"], ["+", 42, "    font.bold: row.selected"]]'
    say_spin omahub-files "Wiring" 61
    claude_prompt omahub-files "$(( EPOCHSECONDS - 61 ))" "add a file tree with git status to the hub"
    claude_tool omahub-files Edit

    # Desktop 4: Codex on the dock's menu, with its live checks beside it.
    stand_in codex omahub-menu 4
    beside omahub-menu 4 "dev/live" "\n  \033[1mdev/live\033[0m  \033[2mdock menu\033[0m\n\n  \033[32mok\033[0m    the menu opens on right-click\n  \033[32mok\033[0m    size chips change the dock at once\n  \033[32mok\033[0m    position chips move it to any edge\n  \033[32mok\033[0m    Quit sits apart from the chips\n  \033[2m...\033[0m   pet motion chip"
    say_user omahub-menu "give the dock menu chips for size and position"
    say_tool omahub-menu Explored "" "Read Dock.qml, DockModel.js, DockLabel.qml"
    say_tool omahub-menu Edited "dock/Menu.qml (+42 -7)" ""
    say_spin omahub-menu "Working" 140
    codex_start omahub-menu "$(( EPOCHSECONDS - 140 ))"

    wait_for_agents '[.omahub.dock.agents[]? | [.project, .agent]] | sort == [["omahub","idle"],["omahub-files","working"],["omahub-menu","working"],["omahub-stats","working"]]'
    echo "agents: $(agent state '[.omahub.dock.agents[]? | [.project, .agent]]' | jq -c .)"
    only_stand_ins
    park
    hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$(address_of pet-omahub)\" })" >/dev/null
    sleep 0.8
    ;;
  take)
    only_stand_ins
    # Glides curve a little and settle the way a hand does, and typing runs in quick bursts. Positions are
    # read right before each move, so every glide lands where it should.

    # Desktop 1: the next task for the sleeping agent. Its pet wakes as the prompt goes in.
    read -r x y <<<"$(window_spot pet-omahub 0.42 0.55)"
    move "$x" $(( y - 140 )) 1
    pause 0.5
    glide "$x" "$y" 650
    pause 0.3
    agent type "now put the pets in the top bar, smaller but fully working" --human >/dev/null
    pause 0.2
    agent chord Return >/dev/null
    wait_submitted omahub
    say_spin omahub "Thinking" 0
    claude_prompt omahub "$EPOCHSECONDS" "now put the pets in the top bar, smaller but fully working"
    pause 0.8
    say_tool omahub Read "bar/Bar.qml" "Read 148 lines"
    claude_tool omahub Read
    pause 0.6
    say_spin omahub "Crafting" 2
    say_tool omahub Update "bar/BarPets.qml" "Updated bar/BarPets.qml with 12 additions"
    say_diff omahub '[["+", 18, "  AgentPet {"], ["+", 19, "    pixelSize: Math.max(1, Style.space(1))"], ["+", 20, "    mood: root.stateOf(modelData.activity)"], ["+", 21, "  }"]]'
    claude_tool omahub Edit

    # Down to the dock. The stats agent finishes while its card is open: its pet hops and bursts.
    read -r x y <<<"$(tile_center omahub-stats)"
    glide "$x" "$y" 820
    pause 0.7
    say_done omahub-stats "The overlay shows tokens and turns per agent, over any window." "2m 3s"
    claude_done omahub-stats "The overlay shows tokens and turns per agent, over any window."
    pause 1.5

    # A click on the pet goes to its desktop.
    click left
    pause 1.2

    # The file tree agent asks to run the tests. Its tile rings, and it is allowed from the dock.
    say_ask omahub-files Bash "test/all" "Run every Omahub test"
    ask omahub-files Bash "test/all"
    pause 0.9
    read -r x y <<<"$(tile_center omahub-files)"
    glide "$x" "$y" 700
    pause 0.3
    click right
    pause 1.0
    agent chord a >/dev/null
    settle omahub-files
    say_ask_off omahub-files
    say_tool omahub-files Bash "test/all" "All tests passed."
    claude_tool omahub-files Bash
    pause 0.8

    # SUPER + TAB shows every worktree's desktop with its agent. 4, then letting go, goes to Codex.
    read -r x y <<<"$(window_spot side-omahub-stats 0.5 0.45)"
    glide "$x" "$y" 700
    agent hold SUPER >/dev/null
    agent chord TAB >/dev/null
    pause 1.3
    agent chord 4 >/dev/null
    pause 0.6
    agent let-go SUPER >/dev/null
    pause 0.9

    # A note for Codex, typed straight into it.
    read -r x y <<<"$(window_spot pet-omahub-menu 0.45 0.6)"
    glide "$x" "$y" 650
    pause 0.25
    agent type "also add a chip for pet motion" --human >/dev/null
    pause 0.15
    agent chord Return >/dev/null
    wait_submitted omahub-menu
    pause 0.7
    say_tool omahub-menu Edited "dock/Menu.qml (+9 -1)" ""
    pause 0.4

    # Back down to desktop 1's pet as its agent finishes.
    read -r x y <<<"$(tile_center omahub)"
    glide "$x" "$y" 850
    pause 0.5
    say_done omahub "Pets sit in the top bar now, a size smaller, with their card on hover and quick answers." "41s"
    claude_done omahub "Pets sit in the top bar now, a size smaller, with their card on hover and quick answers."
    pause 1.3
    click left
    pause 2.2
    ;;
  cleanup)
    agent chord Escape >/dev/null 2>&1 || true
    agent let-go SUPER >/dev/null 2>&1 || true
    for name in $STAND_INS; do settle "$name"; done
    # The scene's terminals by the addresses it kept, and any window from an older run of the scene.
    { cat "$PETS"/address-* 2>/dev/null; hyprctl clients -j | jq -r '.[] | select(.class | startswith("omahub-demo-")) | .address'; } |
      while IFS= read -r address; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
      done
    sleep 0.5
    if [[ -f $PETS/created ]]; then
      while IFS= read -r path; do
        # Only what this scene made: its worktrees, their Claude records, and its own Codex record.
        case "$path" in
          "$PROJECTS"/omahub | "$PROJECTS"/omahub-stats | "$PROJECTS"/omahub-files | "$PROJECTS"/omahub-menu) rm -rf "$path" ;;
          "$HOME/.claude/projects/$(encoded "$PROJECTS")"-*) rm -rf "$path" ;;
          "$HOME/.codex/sessions/"*/rollout-*.jsonl) rm -f "$path" ;;
        esac
      done <"$PETS/created"
    fi
    rm -rf "$PETS"
    "$OMAHUB" reset dock/pet-naps >/dev/null
    "$OMAHUB" reset dock/autohide >/dev/null
    "$OMAHUB" reset dock/magnify >/dev/null
    "$OMAHUB" reset dock/size >/dev/null
    rest
    ;;
esac
