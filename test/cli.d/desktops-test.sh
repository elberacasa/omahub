#!/bin/bash

# desktops/: what the terminals under a window are running, read from the process table, /proc, and
# .git, and how a desktop reads from its windows. Everything shown is a fact, never a guess.

source "$(dirname "$0")/../base-test.sh"

context="$OMAHUB_PATH/desktops/context.sh"
started=()

# A terminal: `script` gives the command a terminal device, the way a terminal window does. The process
# given to context.sh is `script` itself, so the command sits under it like a terminal's shell does.
start_terminal() {
  local folder="$1" command="$2"
  script -qfec "cd '$folder' && exec $command" /dev/null >/dev/null 2>&1 &
  terminal=$!
  started+=("$terminal")
  for _ in $(seq 40); do
    [[ -n $(pgrep -P "$terminal") ]] && break
    sleep 0.05
  done
  sleep 0.15
}

# An app whose terminals sit deep under its own process, as an editor's integrated terminal does.
start_app() {
  local folder="$1" command="$2"
  bash -c "script -qfec \"cd '$folder' && exec $command\" /dev/null >/dev/null 2>&1; true" &
  app=$!
  started+=("$app")
  sleep 0.4
}

stop_all() {
  local pid
  for pid in "${started[@]}"; do
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  pkill -f "$TEST_ROOT/bin/" 2>/dev/null || true
  wait 2>/dev/null || true
  started=()
}
trap stop_all EXIT

if ! command -v script >/dev/null 2>&1; then
  pass "script is not installed, so the terminal checks are skipped"
else
  project="$TEST_ROOT/work/orbit-api"
  mkdir -p "$project/src" "$TEST_ROOT/bin"
  git -C "$project" init -q -b feature/search

  start_terminal "$project/src" "sleep 30"
  output=$("$context" "0xabc=$terminal")
  session='.[0].sessions[0]'
  assert_eq "a terminal in a git folder reads its project" "$(jq -r "$session.project" <<<"$output")" "orbit-api"
  assert_eq "and its branch" "$(jq -r "$session.branch" <<<"$output")" "feature/search"
  assert_eq "and the command in front" "$(jq -r "$session.command" <<<"$output")" "sleep"
  assert_eq "and that command's process" "$(jq -r "$session.pid" <<<"$output")" "$(pgrep -P "$terminal" | head -1)"
  assert_eq "the window's address comes back with it" "$(jq -r '.[0].address' <<<"$output")" "0xabc"
  if [[ $output != *"$TEST_ROOT"* ]]; then
    pass "nothing printed shows where the folder lives"
  else
    fail "nothing printed shows where the folder lives"
  fi
  stop_all

  start_app "$project" "sleep 30"
  assert_eq "a terminal deep under an app's process is found, as in an editor" \
    "$("$context" "0xdef=$app" | jq -r '.[0].sessions[0].project')" "orbit-api"
  stop_all

  # An agent run by a runtime is named by what it runs, like node .../@google/gemini-cli/dist/index.js.
  mkdir -p "$TEST_ROOT/bin/@google/gemini-cli/dist"
  printf '#!/bin/bash\nexec sleep 30\n' >"$TEST_ROOT/bin/@google/gemini-cli/dist/index.js"
  # The runtime sits off PATH, so it never stands in for the real node the model checks below run on.
  mkdir -p "$TEST_ROOT/bin/runtime"
  printf '#!/bin/bash\nsleep 30\n' >"$TEST_ROOT/bin/runtime/node"
  chmod +x "$TEST_ROOT/bin/runtime/node" "$TEST_ROOT/bin/@google/gemini-cli/dist/index.js"
  start_terminal "$project" "$TEST_ROOT/bin/runtime/node $TEST_ROOT/bin/@google/gemini-cli/dist/index.js"
  assert_eq "an agent started through a runtime is named by what it runs" \
    "$("$context" "0x1=$terminal" | jq -r '.[0].sessions[0].command')" "gemini"
  stop_all

  printf '#!/bin/bash\nsleep 30\n' >"$TEST_ROOT/bin/claude"
  chmod +x "$TEST_ROOT/bin/claude"
  start_terminal "$project" "$TEST_ROOT/bin/claude"
  assert_eq "an agent is named by its own name" "$("$context" "0x2=$terminal" | jq -r '.[0].sessions[0].command')" "claude"

  # What an agent is doing comes from its own session record for the folder it works in.
  home="$TEST_ROOT/home"
  folder=$(cd "$project" && pwd -P)
  claude_log="$home/.claude/projects/${folder//[^a-zA-Z0-9]/-}/session.jsonl"
  mkdir -p "${claude_log%/*}"
  printf '%s\n' '{"type":"user","timestamp":"2026-09-15T10:00:00.250Z","message":{"role":"user","content":"Fix the dock"}}' \
    '{"type":"assistant","message":{"model":"claude-fable-5","stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash"}]}}' >"$claude_log"
  output=$(HOME="$home" "$context" "0x2=$terminal")
  assert_eq "a Claude session running a tool is working" "$(jq -r "$session.state" <<<"$output")" "working"
  assert_eq "and names the tool" "$(jq -r "$session.tool" <<<"$output")" "Bash"
  assert_eq "and the model it answers with" "$(jq -r "$session.model" <<<"$output")" "claude-fable-5"
  assert_eq "and when its turn began" "$(jq -r "$session.since" <<<"$output")" "$(date -d 2026-09-15T10:00:00Z +%s)"
  printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"\n\tThe dock is fixed.\nDetails follow."}]}}' \
    '{"type":"system","subtype":"turn_duration"}' >>"$claude_log"
  output=$(HOME="$home" "$context" "0x2=$terminal")
  assert_eq "and done once its turn ends" "$(jq -r "$session.state" <<<"$output")" "done"
  signals="$home/.local/state/omahub/signals"
  mkdir -p "$signals"
  signal_file="$signals/$(printf '%s' "$claude_log" | sha1sum | cut -c1-16).json"
  printf '{"event":"Notification","at":%s}\n' "$EPOCHSECONDS" >"$signal_file"
  assert_eq "an agent whose hook says it asks for your answer is waiting" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.state")" "waiting"
  printf '{"event":"Notification","at":%s}\n' "$(( EPOCHSECONDS - 60 ))" >"$signal_file"
  assert_eq "until its record changes after the ask" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.state")" "done"
  printf '{"event":"Stop","at":%s}\n' "$EPOCHSECONDS" >"$signal_file"
  assert_eq "and only a wait counts as waiting" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.state")" "done"
  rm -f "$signal_file"
  requests="$home/.local/state/omahub/requests"
  mkdir -p "$requests"
  record=$(printf '%s' "$claude_log" | sha1sum | cut -c1-16)
  printf '{"tool":"Bash","detail":"git push origin main","at":%s}\n' "$EPOCHSECONDS" >"$requests/$record.json"
  output=$(HOME="$home" "$context" "0x2=$terminal")
  assert_eq "a session goes by the key its waits and answers use" "$(jq -r "$session.key" <<<"$output")" "$record"
  assert_eq "and an open question shows what it asks to run" "$(jq -c "$session | [.askTool, .askDetail]" <<<"$output")" '["Bash","git push origin main"]'
  printf '{"tool":"Bash","detail":"git push origin main","at":%s}\n' "$(( EPOCHSECONDS - 60 ))" >"$requests/$record.json"
  assert_eq "a question older than the record's last change is over" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.askTool")" ""
  rm -f "$requests/$record.json"
  assert_eq "with how long its record has been quiet" "$(jq -r "$session.quiet | . >= 0 and . < 10" <<<"$output")" "true"
  assert_eq "and the first line it said, on one line" "$(jq -r "$session.message" <<<"$output")" "The dock is fixed."
  printf '%s\n' '{"type":"assistant","isSidechain":true,"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","name":"Read"}]}}' >>"$claude_log"
  assert_eq "a subagent's steps leave the turn done" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.state")" "done"
  touch -d '1 hour ago' "$claude_log"
  assert_eq "a record older than the agent's process says nothing" "$(HOME="$home" "$context" "0x2=$terminal" | jq -r "$session.state")" ""
  assert_eq "an agent without a record says nothing" "$(HOME="$TEST_ROOT/nobody" "$context" "0x2=$terminal" | jq -r "$session.state")" ""
  stop_all

  printf '#!/bin/bash\nsleep 30\n' >"$TEST_ROOT/bin/codex"
  chmod +x "$TEST_ROOT/bin/codex"
  start_terminal "$project" "$TEST_ROOT/bin/codex"
  codex_log="$home/.codex/sessions/2026/09/15/rollout-2026-09-15T10-00-00-0192aaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee.jsonl"
  mkdir -p "${codex_log%/*}"
  printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"$folder\"}}" \
    '{"type":"turn_context","payload":{"model":"gpt-6-astra"}}' \
    '{"type":"event_msg","payload":{"type":"task_started","started_at":1789466400}}' \
    '{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch"}}' >"$codex_log"
  output=$(HOME="$home" "$context" "0x4=$terminal")
  assert_eq "a Codex session calling a tool is working" "$(jq -r "$session.state" <<<"$output")" "working"
  assert_eq "and names the tool" "$(jq -r "$session.tool" <<<"$output")" "apply_patch"
  assert_eq "and the model its turn uses" "$(jq -r "$session.model" <<<"$output")" "gpt-6-astra"
  assert_eq "and when its task began" "$(jq -r "$session.since" <<<"$output")" "1789466400"
  assert_eq "and the session id a reply goes to" "$(jq -r "$session.thread" <<<"$output")" "0192aaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
  printf '%s\n' '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Search ships.\nMore below."}}' >>"$codex_log"
  output=$(HOME="$home" "$context" "0x4=$terminal")
  assert_eq "and done once its task completes" "$(jq -r "$session.state" <<<"$output")" "done"
  assert_eq "with the first line of its last message" "$(jq -r "$session.message" <<<"$output")" "Search ships."
  stop_all

  outside=$(mktemp -d)
  start_terminal "$outside" "sleep 30"
  output=$("$context" "0x3=$terminal")
  assert_eq "a terminal outside git has no project" "$(jq -r '.[0].sessions[0].project' <<<"$output")" ""
  assert_eq "but has its folder's name" "$(jq -r '.[0].sessions[0].folder' <<<"$output")" "${outside##*/}"
  stop_all
  start_terminal "$HOME" "sleep 30"
  assert_eq "and the home folder's name is never shown" "$("$context" "0x3=$terminal" | jq -r '.[0].sessions[0].folder')" ""
  stop_all
  rm -rf "$outside"
fi

sleep 30 </dev/null >/dev/null 2>&1 &
lone=$!
assert_eq "a window without a terminal is left out" "$("$context" "0x9=$lone")" "[]"
kill "$lone" 2>/dev/null || true
wait "$lone" 2>/dev/null || true

assert_eq "a window that is gone is left out" "$("$context" "0x1=999999999")" "[]"
assert_eq "nonsense is left out" "$("$context" "0x1=abc")" "[]"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the desktop model checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/desktops/DesktopsModel.js" <<'EOF'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { projectFromTitle, windowContext, summary, appIndex, entryFor, agentLabel, activityState, activityLabel, family, sessions, duration, stateLine }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

check("an editor title names its project", Model.projectFromTitle("cursor", "main.ts - orbit-api - Cursor") === "orbit-api")
check("a title with only the project works", Model.projectFromTitle("Cursor", "orbit-api - Cursor") === "orbit-api")
check("an unsaved marker is ignored", Model.projectFromTitle("code", "● app.tsx - lumen - Visual Studio Code") === "lumen")
check("other apps' titles are not read as projects", Model.projectFromTitle("chromium", "Docs - Orbit - Chromium") === "")

// Windows and their terminals.
const cursorSessions = { sessions: [
  { terminal: "pts/1", command: "claude", project: "omahub", branch: "main" },
  { terminal: "pts/2", command: "codex", project: "orbit-api", branch: "feature/search" }
] }
const omahubWindow = Model.windowContext({ appId: "cursor", title: "Dock.qml - omahub - Cursor" }, cursorSessions)
check("an editor window only claims the agents in its own project", omahubWindow.project === "omahub" && omahubWindow.agent === "claude")
const orbitWindow = Model.windowContext({ appId: "cursor", title: "server.ts - orbit-api - Cursor" }, cursorSessions)
check("and the other window of the same app claims its own", orbitWindow.agent === "codex" && orbitWindow.branch === "feature/search")
const nvimWindow = Model.windowContext({ appId: "foot", title: "nvim" }, { sessions: [
  { terminal: "pts/4", command: "nvim", project: "tidewater", branch: "perf/cache" },
  { terminal: "pts/5", command: "codex", project: "tidewater", branch: "perf/cache" }
] })
check("an agent in a terminal inside Neovim is found and wins over the editor", nvimWindow.kind === "agent" && nvimWindow.agent === "codex")
check("an agent is never working or waiting unless it said so", !omahubWindow.agentWorking && !omahubWindow.agentWaiting)
const reported = Model.windowContext({ appId: "foot" }, { sessions: [{ command: "claude", project: "lumen", state: "waiting" }] })
check("an agent that reports waiting shows waiting", reported.agentWaiting && !reported.agentWorking)
const busy = Model.windowContext({ appId: "foot" }, { sessions: [{ command: "claude", project: "lumen", state: "working", tool: "mcp__browser__navigate" }] })
check("an agent running a tool shows working, with the tool's short name", busy.agentWorking && !busy.agentDone && busy.agentTool === "navigate")
const finished = Model.windowContext({ appId: "foot" }, { sessions: [{ command: "codex", project: "lumen", state: "done", quiet: 42 }] })
check("an agent whose turn ended shows done, and for how long", finished.agentDone && !finished.agentWorking && finished.agentQuiet === 42)
check("a turn that ended moments ago is done", Model.activityState({ agent: "codex", agentDone: true, agentQuiet: 42 }) === "done")
check("a nap time of its own changes when an agent counts as idle, and 0 means never",
  Model.activityState({ agent: "codex", agentDone: true, agentQuiet: 600 }, 900) === "done"
  && Model.activityState({ agent: "codex", agentDone: true, agentQuiet: 1000 }, 900) === "idle"
  && Model.activityState({ agent: "codex", agentDone: true, agentQuiet: 99999 }, 0) === "done"
  && Model.activityLabel({ agent: "codex", agentDone: true, agentQuiet: 600 }, 60) === "Codex is idle")
check("an agent quiet for five minutes after its turn is idle", Model.activityState({ agent: "codex", agentDone: true, agentQuiet: 300 }) === "idle"
  && Model.activityLabel({ agent: "codex", agentDone: true, agentQuiet: 900 }) === "Codex is idle")
check("the state that most needs a look wins", Model.activityState({ agent: "claude", agentWorking: true, attention: true }) === "attention"
  && Model.activityState({ agent: "claude", agentWorking: true }) === "working" && Model.activityState(null) === "")
check("labels say what the agent is doing", Model.activityLabel({ agent: "claude", agentWorking: true, agentTool: "Bash" }) === "Claude is running Bash"
  && Model.activityLabel({ agent: "codex", agentDone: true }) === "Codex is done" && Model.activityLabel({ agent: "claude" }) === "Claude"
  && Model.activityLabel(null) === "")
check("an editor app without terminals is an editor", Model.windowContext({ appId: "cursor", title: "a - orbit-api - Cursor" }).kind === "editor")
check("a branch only comes with a project read from git", Model.windowContext({ appId: "cursor", title: "a - x - Cursor" }).branch === "")
check("agents go by their own names", Model.agentLabel("claude") === "Claude" && Model.agentLabel("cursor-agent") === "Cursor Agent")

// Desktops.
const windows = [
  { address: "a", appId: "cursor", appName: "Cursor", focus: 1 },
  { address: "b", appId: "foot", appName: "Terminal", focus: 0 },
  { address: "c", appId: "chromium", appName: "Chromium", focus: 2, media: true }
]
const contexts = {
  a: { project: "orbit-api", branch: "", kind: "editor" },
  b: { project: "orbit-api", branch: "feature/search", kind: "agent", command: "claude", agent: "claude" },
  c: { project: "", kind: "" }
}
const desktop = Model.summary({ id: 2, windows: windows }, contexts, "")
check("a desktop is named after its project", desktop.title === "orbit-api" && !desktop.named)
check("with the branch git reports", desktop.branch === "feature/search")
check("apps come in the order they were last used, once each", desktop.apps.map(app => app.appId).join(",") === "foot,cursor,chromium")
check("the agent running on it shows", desktop.activity.agent === "claude")
const agentWindows = [
  { address: "w1", appId: "cursor", title: "a.ts - orbit-api - Cursor", workspace: 2 },
  { address: "w2", appId: "cursor", title: "b.ts - lumen - Cursor", workspace: 1 },
  { address: "w3", appId: "foot", title: "foot", workspace: 3 }
]
const editorSessions = { sessions: [
  { terminal: "pts/1", command: "claude", pid: 11, project: "lumen", branch: "main", state: "working", tool: "Edit", quiet: 3, model: "claude-fable-5",
    since: 1789466400, message: "Reading the dock" },
  { terminal: "pts/2", command: "codex", pid: 12, project: "orbit-api", branch: "search", state: "done", quiet: 40, model: "gpt-6-astra" },
  { terminal: "pts/3", command: "nvim", pid: 13, project: "lumen" }
] }
const agentList = Model.sessions(agentWindows, { w1: editorSessions, w2: editorSessions,
  w3: { sessions: [{ terminal: "pts/4", command: "claude", pid: 21, project: "", state: "done", quiet: 900, model: "" }] } })
check("every agent session shows once, and editors and shells do not", agentList.length === 3)
const folderWindows = [
  { address: "c1", appId: "cursor", title: "omahub - Cursor", workspace: 2 },
  { address: "c2", appId: "cursor", title: "experiment - Cursor", workspace: 8 }
]
const folderSessions = { sessions: [
  { terminal: "pts/2", command: "claude", pid: 31, project: "omahub", state: "working" },
  { terminal: "pts/7", command: "codex", pid: 32, project: "", folder: "experiment", state: "done" }
] }
const byFolder = Model.sessions(folderWindows, { c1: folderSessions, c2: folderSessions })
check("an agent in a folder outside git sits on the window that names the folder, and goes by it",
  byFolder.find(item => item.id === "32").address === "c2" && byFolder.find(item => item.id === "32").project === "experiment")
check("and that editor window counts the agent as its own",
  Model.windowContext(folderWindows[1], folderSessions).agent === "codex" && Model.windowContext(folderWindows[0], folderSessions).agent === "claude")
check("a session sits on the window whose title names its project",
  agentList.find(item => item.id === "11").address === "w2" && agentList.find(item => item.id === "12").address === "w1")
check("sessions come in desktop order", agentList.map(item => item.workspace).join(",") === "1,2,3")
check("each session carries what its agent is doing", Model.activityState(agentList[0].activity) === "working"
  && agentList[0].activity.agentTool === "Edit" && Model.activityState(agentList[2].activity) === "idle")
check("every Claude model shares one pet, and every GPT model another", Model.family("claude-fable-5", "claude") === "anthropic"
  && Model.family("claude-opus-5", "") === "anthropic" && Model.family("gpt-6-astra", "codex") === "openai")
check("durations read the short way", Model.duration(20) === "less than a minute" && Model.duration(240) === "4 min"
  && Model.duration(7500) === "2 h 5 min" && Model.duration(3600) === "1 h")
check("a card says how long an agent has worked, or how long ago it finished",
  Model.stateLine(agentList[0], agentList[0].since + 300) === "Working for 5 min"
  && Model.stateLine(agentList[1], 0) === "Done less than a minute ago" && Model.stateLine(agentList[2], 0) === "Idle for 15 min")
check("an agent without a model is known by its own name", Model.family("", "claude") === "anthropic" && Model.family("", "codex") === "openai")
check("other companies are their own, and unknown models share the generic pet",
  Model.family("kimi-k3", "opencode") === "moonshot" && Model.family("mystery-1", "crush") === "other")
const mixed = Model.summary({ id: 3, windows: [{ address: "x", appId: "foot" }, { address: "y", appId: "foot" }] },
  { x: { agent: "codex", agentDone: true }, y: { agent: "claude", agentWorking: true, agentTool: "Edit" } }, "")
check("a desktop with one agent working and one done reads as working, after the working one",
  mixed.activity.agentWorking && !mixed.activity.agentDone && mixed.activity.agent === "claude" && mixed.activity.agentTool === "Edit")
const resting = Model.summary({ id: 4, windows: [{ address: "x", appId: "foot" }, { address: "y", appId: "foot" }] },
  { x: { agent: "codex", agentDone: true, agentQuiet: 900 }, y: { agent: "claude", agentDone: true, agentQuiet: 20 } }, "")
check("a desktop is only idle once every finished agent on it has been quiet a while", Model.activityState(resting.activity) === "done")
check("media playing shows", desktop.activity.media)
check("a name given by the person wins", Model.summary({ id: 2, windows: windows }, contexts, "Launch week").title === "Launch week")

const tool = Model.summary({ id: 7, windows: [{ address: "t", appId: "foot", appName: "Foot", focus: 0 }] }, { t: { project: "", command: "btop", kind: "" } }, "")
check("a terminal running a tool outside a project names the desktop after the tool", tool.title === "btop")
check("a project still wins over a tool", Model.summary({ id: 8, windows: [{ address: "t", appId: "foot", focus: 0 }] },
  { t: { project: "orbit-api", command: "nvim", kind: "editor" } }, "").title === "orbit-api")

const editorOnly = Model.summary({ id: 3, windows: [{ address: "e", appId: "cursor", appName: "Cursor", focus: 0 }] },
  { e: { project: "lumen-docs", branch: "", kind: "editor" } }, "", { "lumen-docs": "docs/tags" })
check("a project only an editor has open takes its branch from the projects folder", editorOnly.branch === "docs/tags")
check("the branch git reports wins over the projects folder",
  Model.summary({ id: 2, windows: windows }, contexts, "", { "orbit-api": "main" }).branch === "feature/search")
check("a desktop without a project takes no branch", Model.summary({ id: 4, windows: [] }, {}, "", { "": "main" }).branch === "")

const index = Model.appIndex([
  { id: "WhatsApp", name: "WhatsApp", execString: "omarchy-launch-webapp https://web.whatsapp.com/" },
  { id: "org.gnome.Nautilus", name: "Files", startupClass: "org.gnome.Nautilus" },
  { id: "foot.desktop", name: "Foot" }
])
check("a web app window finds its web app by site", (Model.entryFor("chrome-web.whatsapp.com__-Default", index) || {}).name === "WhatsApp")
check("a window finds its app by startup class", (Model.entryFor("org.gnome.Nautilus", index) || {}).name === "Files")
check("a window finds its app by id, without .desktop", (Model.entryFor("foot", index) || {}).name === "Foot")
check("a window with no app finds nothing", Model.entryFor("omahub-demo-a", index) === null)

const plain = Model.summary({ id: 4, windows: [{ address: "e", appId: "chrome-web.whatsapp.com__-Default", appName: "WhatsApp", focus: 0 }] }, {}, "")
check("a desktop without a project is named after its app", plain.title === "WhatsApp" && plain.project === "")
check("an empty desktop has no title", Model.summary({ id: 5, windows: [] }, {}, "").title === "")
const crowded = Model.summary({ id: 6, windows: ["a", "b", "c", "d", "e", "f"].map((id, i) => ({ address: id, appId: "app" + i, focus: i })) }, {}, "")
check("at most four app icons, and a count of the rest", crowded.apps.length === 4 && crowded.moreApps === 2)

console.log(JSON.stringify(checks))
EOF
)

while IFS=$'\t' read -r ok name; do
  if [[ $ok == "true" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
done < <(jq -r '.[] | "\(.ok)\t\(.name)"' <<<"$results")

finish
