#!/bin/bash

# Agents in the dock, filmed as a day of work: bring the studio up with dev/studio up --terminals. Four
# projects sit on desktops 1 to 4, each with a stand-in agent and a terminal beside it. You give orbit-api's
# sleeping Claude a task and its pet wakes, harbor's Claude finishes under the pointer and a click on its pet
# goes there, beacon's Claude asks to run the tests and is allowed from its tile, SUPER + TAB and 4 go to
# tidewater, and its Codex gets a reply typed from its tile.
#
# It is a mockup of real use with the clock sped up: pets nap after six seconds instead of minutes, and every
# turn is written by the scene. The agents are small scripts named claude and codex that show a session and
# wait, so no real agent is ever sent anything. Their session records are written in the folders Claude Code
# and Codex keep them in, only for these studio projects, and cleanup deletes every one. The Codex reply is
# typed and never sent. The studio's sandbox puts every setting back when the studio comes down.

source "$(dirname "$0")/studio-lib.sh"

PETS="$STUDIO_ROOT/tmp/studio/pets"
PROJECTS="$HOME/Code"
OMAHUB="$STUDIO_ROOT/bin/omahub"
STATE_DIR="$HOME/.local/state/omahub"
CODEX_DAY="$HOME/.codex/sessions/$(date +%Y/%m/%d)"
NAP_SECONDS=6
# Terminals in the video: foot as it opens for anyone, with text large enough to read on a phone.
TERMINAL_FONT="monospace:size=14"

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
    jq -nc '{type: "turn_context", payload: {model: "gpt-6-astra"}}'
    jq -nc --argjson at "$2" '{type: "event_msg", payload: {type: "task_started", started_at: $at}}'
    jq -nc '{type: "response_item", payload: {type: "custom_tool_call", name: "apply_patch"}}'
  } >"$log"
}

# A git project of the studio's kind, made only when the folder is free, and deleted by cleanup.
project() {
  local dir="$PROJECTS/$1"
  [[ -e $dir ]] && return 0
  mkdir -p "$dir"
  printf '%s\n' "$dir" >>"$PETS/created"
  git -C "$dir" init -q -b "$2"
  printf '# %s\n' "$1" >"$dir/README.md"
  git -C "$dir" add -A
  GIT_AUTHOR_NAME="Orbit Team" GIT_AUTHOR_EMAIL="team@orbit.example" GIT_COMMITTER_NAME="Orbit Team" \
    GIT_COMMITTER_EMAIL="team@orbit.example" git -C "$dir" commit -q -m "Start $1"
}

# What a stand-in's terminal shows: a line of its session, in the terminal's own colors.
say() {
  printf '%b\n' "$2" >>"$PETS/screen-$1"
}

prompt_line() { say "$1" "\n  \033[1m>\033[0m $2"; }
tool_line() { say "$1" "  \033[34m●\033[0m \033[1m$2\033[0m  \033[2m$3\033[0m"; }
note_line() { say "$1" "    \033[2m$2\033[0m"; }
reply_line() { say "$1" "\n  $2"; }
ask_line() { say "$1" "\n  \033[31m●\033[0m \033[1mAllow $2?\033[0m  \033[2m$3\033[0m"; }

# The prompt marker without a line end, so what is typed into the terminal lands right after it.
prompt_open() {
  printf '%b' "\n  \033[1m>\033[0m " >>"$PETS/screen-$1"
}

# A stand-in agent: a script named after the agent that shows its session and waits, in a terminal on its
# project's desktop. Typing into it shows on screen, the way typing a prompt does.
stand_in() {
  local agent="$1" name="$2" branch="$3" desktop="$4" bin="$PETS/bin/$1"
  if [[ ! -x $bin ]]; then
    mkdir -p "$PETS/bin"
    cat >"$bin" <<'STANDIN'
#!/bin/bash
printf '\033[?25l'
tail -n +1 -f "$PETS_SCREENS/screen-${PWD##*/}"
STANDIN
    chmod +x "$bin"
  fi
  local label="Claude"
  [[ $agent == "codex" ]] && label="Codex"
  : >"$PETS/screen-$name"
  say "$name" "\n  \033[1m$label\033[0m  \033[2m$name · $branch\033[0m"
  launch_terminal "pet-$name" "$name" "$desktop" "env PETS_SCREENS=$PETS sh -c \"cd $PROJECTS/$name && $bin\""
}

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

# The terminal beside each agent: a dev server, a log, tests, or data, in the project's folder.
beside() {
  local name="$1" desktop="$2" script="$PETS/side-$1.sh"
  {
    printf '#!/bin/bash\nprintf "\\033[?25l"\ncat <<"SIDE"\n'
    printf '%b\n' "$3"
    printf 'SIDE\nexec sleep infinity\n'
  } >"$script"
  chmod +x "$script"
  launch_terminal "side-$name" "$name · $4" "$desktop" "--working-directory=$PROJECTS/$name $script"
}

# The take films only the stand-in agents. Any other tile would show a real project, so the scene stops first.
only_stand_ins() {
  local others
  others=$(agent state '[.omahub.dock.agents[]? | .project | select(. != "orbit-api" and . != "harbor" and . != "beacon" and . != "tidewater")] | length')
  if [[ $others != "0" ]]; then
    echo "studio-pets: $others agent tiles are not stand-ins, so nothing is filmed" >&2
    exit 1
  fi
}

# The middle of a stand-in's tile on screen, as "x y".
tile_center() {
  agent state ".omahub.dock.agents[] | select(.project == \"$1\") | \"\\((.x + .width / 2) | floor) \\((.y + .height / 2) | floor)\"" | tr -d '"'
}

# The middle of a scene's window on screen, as "x y", by its key: pet-<project> or side-<project>.
window_center() {
  hyprctl clients -j | jq -r --arg address "$(address_of "$1")" '.[] | select(.address == $address) | "\((.at[0] + .size[0] / 2) | floor) \((.at[1] + .size[1] / 2) | floor)"' | head -1
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

# Typing at a person's pace: a word at a time, with a short uneven gap after each one.
typed() {
  local word first=1
  for word in $1; do
    (( first )) || agent type " " >/dev/null
    first=0
    agent type "$word" >/dev/null
    sleep "0.$(( RANDOM % 15 + 10 ))"
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
    project orbit-api feature/search
    project harbor main
    project beacon feature/tags
    project tidewater field/tides
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

    stand_in claude orbit-api feature/search 1
    beside orbit-api 1 "\n  \033[1morbit-api\033[0m \033[2mdev server\033[0m\n\n  \033[32m✓\033[0m ready on \033[36mlocalhost:4000\033[0m\n  \033[2mGET  /search?q=tags        200  18ms\033[0m\n  \033[2mGET  /search?q=tags&page=2 200  21ms\033[0m\n  \033[2mGET  /health               200   2ms\033[0m" "dev server"
    stand_in claude harbor main 2
    beside harbor 2 "\n  \033[1mharbor\033[0m \033[2mgit log\033[0m\n\n  \033[33m4f1c2a9\033[0m Rank results by tag\n  \033[33m9b07e3d\033[0m Cache the tag index\n  \033[33m1d44a10\033[0m Split search into modules\n  \033[33mc81f5b2\033[0m Start harbor" "git log"
    stand_in claude beacon feature/tags 3
    beside beacon 3 "\n  \033[1mbeacon\033[0m \033[2mtests\033[0m\n\n  \033[32m✓\033[0m docs build        \033[2m1.2s\033[0m\n  \033[32m✓\033[0m links resolve     \033[2m0.4s\033[0m\n  \033[33m○\033[0m tags pages        \033[2mwaiting\033[0m" "tests"
    stand_in codex tidewater field/tides 4
    beside tidewater 4 "\n  \033[1mtidewater\033[0m \033[2mstation 8443\033[0m\n\n  high  \033[36m06:12\033[0m  3.4 m\n  low   \033[36m12:31\033[0m  0.6 m\n  high  \033[36m18:47\033[0m  3.2 m\n  low   \033[36m00:58\033[0m  0.4 m" "tides"

    # orbit-api finished a while ago and sleeps; the others are mid turn.
    prompt_line orbit-api "Add paging to search"
    tool_line orbit-api Edit "src/routes/search.ts"
    tool_line orbit-api Bash "npm test"
    note_line orbit-api "24 passed"
    reply_line orbit-api "Search pages through results twenty at a time."
    claude_prompt orbit-api "$(( EPOCHSECONDS - 60 ))" "Add paging to search"
    claude_done orbit-api "Search pages through results twenty at a time."
    prompt_line harbor "Rank search results by tag"
    tool_line harbor Read "src/search/rank.ts"
    tool_line harbor Edit "src/search/rank.ts"
    claude_prompt harbor "$(( EPOCHSECONDS - 200 ))" "Rank search results by tag"
    claude_tool harbor Edit
    prompt_line beacon "Tag the docs pages"
    tool_line beacon Edit "docs/guides/tags.md"
    claude_prompt beacon "$(( EPOCHSECONDS - 95 ))" "Tag the docs pages"
    claude_tool beacon Edit
    prompt_line tidewater "Show the next high tide on the card"
    tool_line tidewater apply_patch "src/tides.ts"
    codex_start tidewater "$(( EPOCHSECONDS - 140 ))"

    wait_for_agents '[.omahub.dock.agents[]? | [.project, .agent]] | sort == [["beacon","working"],["harbor","working"],["orbit-api","idle"],["tidewater","working"]]'
    echo "agents: $(agent state '[.omahub.dock.agents[]? | [.project, .agent]]' | jq -c .)"
    only_stand_ins
    park
    hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })' >/dev/null
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$(address_of pet-orbit-api)\" })" >/dev/null
    sleep 0.8
    ;;
  take)
    only_stand_ins
    # Every move is an eased glide with a beat to read before each click, the way a hand works. Positions are
    # read right before each move, so every glide lands where it should.

    # Desktop 1: orbit-api's pet is asleep. A new task goes into its terminal, and it wakes up to work.
    read -r x y <<<"$(window_center pet-orbit-api)"
    move "$x" $(( y - 120 )) 1
    pause 0.9
    move "$x" "$y" 700
    pause 0.4
    prompt_open orbit-api
    typed "Add filters to search"
    pause 0.35
    agent chord Return >/dev/null
    claude_prompt orbit-api "$EPOCHSECONDS" "Add filters to search"
    pause 0.9
    tool_line orbit-api Read "src/routes/search.ts"
    claude_tool orbit-api Read
    pause 0.8
    tool_line orbit-api Edit "src/routes/search.ts"
    claude_tool orbit-api Edit

    # Down to the dock. harbor's turn ends while its card is open: its pet hops and bursts.
    read -r x y <<<"$(tile_center harbor)"
    move "$x" $(( y - 160 )) 900
    move "$x" "$y" 500
    pause 1.1
    tool_line harbor Bash "npm test -- rank"
    note_line harbor "12 passed"
    reply_line harbor "Search now ranks results by tag. The tests pass."
    claude_done harbor "Search now ranks results by tag. The tests pass."
    pause 1.8

    # A click on the pet goes to harbor's desktop.
    click left
    pause 1.6

    # beacon asks to run the tests. Its tile rings, the pointer goes over, and allows it from the dock.
    ask_line beacon Bash "npm test -- --grep tags"
    ask beacon Bash "npm test -- --grep tags"
    pause 1.4
    read -r x y <<<"$(tile_center beacon)"
    move "$x" "$y" 800
    pause 0.6
    click right
    pause 1.8
    agent chord a >/dev/null
    pause 0.2
    settle beacon
    tool_line beacon Bash "npm test -- --grep tags"
    claude_tool beacon Bash
    pause 1.4

    # SUPER + TAB shows every project's desktop with its agent. 4, then letting go, goes to tidewater.
    read -r x y <<<"$(window_center pet-harbor)"
    move "$x" "$y" 900
    pause 0.3
    agent hold SUPER >/dev/null
    agent chord TAB >/dev/null
    pause 1.5
    agent chord 4 >/dev/null
    pause 1.0
    agent let-go SUPER >/dev/null
    pause 1.4

    # A note for Codex, typed from its tile. It is never sent.
    read -r x y <<<"$(tile_center tidewater)"
    move "$x" "$y" 900
    pause 0.6
    click right
    pause 1.0
    typed "Also warn before low tide"
    pause 1.6
    # Esc clears the note, and again closes the panel, so nothing is ever sent.
    agent chord Escape >/dev/null
    pause 0.35
    agent chord Escape >/dev/null
    pause 0.5

    # harbor's pet has dozed off by now. The pointer rests on it, and its card says so.
    read -r x y <<<"$(tile_center harbor)"
    move "$x" "$y" 1000
    pause 2.4
    ;;
  cleanup)
    agent chord Escape >/dev/null 2>&1 || true
    agent let-go SUPER >/dev/null 2>&1 || true
    for name in orbit-api harbor beacon tidewater; do settle "$name"; done
    # The scene's terminals by the addresses it kept, and any window from an older run of the scene.
    { cat "$PETS"/address-* 2>/dev/null; hyprctl clients -j | jq -r '.[] | select(.class | startswith("omahub-demo-")) | .address'; } |
      while IFS= read -r address; do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
      done
    sleep 0.5
    if [[ -f $PETS/created ]]; then
      while IFS= read -r path; do
        # Only what this scene made: its projects, their Claude records, and its own Codex record.
        case "$path" in
          "$PROJECTS"/orbit-api | "$PROJECTS"/harbor | "$PROJECTS"/beacon | "$PROJECTS"/tidewater) rm -rf "$path" ;;
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
