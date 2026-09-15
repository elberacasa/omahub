#!/bin/bash

# Shared by the pets scenes: stand-in agents drawn like Claude Code and Codex, the session records the dock reads,
# their calls and answers, and where their windows and tiles are. Source it after studio-lib.sh.

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
