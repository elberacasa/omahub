#!/bin/bash

# desktops/: what a terminal is working on, read from /proc and .git, and how a desktop reads from
# its windows.

source "$(dirname "$0")/../base-test.sh"

context="$OMAHUB_PATH/desktops/context.sh"

# A terminal: `script` gives the command a terminal device, the way a terminal window does.
start_terminal() {
  local folder="$1"
  script -qfec "cd '$folder' && exec sleep 30" /dev/null >/dev/null 2>&1 &
  terminal=$!
  for _ in $(seq 30); do
    pgrep -P "$terminal" >/dev/null && break
    sleep 0.05
  done
  sleep 0.1
}

stop_terminal() {
  pkill -P "$terminal" 2>/dev/null || true
  kill "$terminal" 2>/dev/null || true
  wait "$terminal" 2>/dev/null || true
}

if ! command -v script >/dev/null 2>&1; then
  pass "script is not installed, so the terminal checks are skipped"
else
  project="$TEST_ROOT/work/orbit-api"
  mkdir -p "$project/src"
  git -C "$project" init -q -b feature/search
  start_terminal "$project/src"
  output=$("$context" "0xabc=$terminal")
  assert_eq "a terminal in a git folder reads its project" "$(jq -r '.[0].project' <<<"$output")" "orbit-api"
  assert_eq "and its branch" "$(jq -r '.[0].branch' <<<"$output")" "feature/search"
  assert_eq "and the command in front" "$(jq -r '.[0].command' <<<"$output")" "sleep"
  assert_eq "the folder is a name, never a path" "$(jq -r '.[0].folder' <<<"$output")" "src"
  assert_eq "the window's address comes back with it" "$(jq -r '.[0].address' <<<"$output")" "0xabc"
  if [[ $output != *"$TEST_ROOT"* ]]; then
    pass "nothing printed shows where the folder lives"
  else
    fail "nothing printed shows where the folder lives"
  fi
  stop_terminal

  outside=$(mktemp -d)
  start_terminal "$outside"
  assert_eq "a terminal outside git has no project" "$("$context" "0xdef=$terminal" | jq -r '.[0].project')" ""
  stop_terminal
  rm -rf "$outside"
fi

# An app: no terminal device, so it is not read as a terminal.
sleep 30 </dev/null >/dev/null 2>&1 &
app=$!
assert_eq "a window without a terminal is left out" "$("$context" "0x9=$app")" "[]"
kill "$app" 2>/dev/null || true
wait "$app" 2>/dev/null || true

assert_eq "a window that is gone is left out" "$("$context" "0x1=999999999")" "[]"
assert_eq "nonsense is left out" "$("$context" "0x1=abc")" "[]"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the desktop model checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/desktops/DesktopsModel.js" <<'EOF'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Model = new Function(source + "\nreturn { projectFromTitle, windowContext, busy, summary, appIndex, entryFor }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

check("an editor title names its project", Model.projectFromTitle("cursor", "main.ts - orbit-api - Cursor") === "orbit-api")
check("a title with only the project works", Model.projectFromTitle("Cursor", "orbit-api - Cursor") === "orbit-api")
check("an unsaved marker is ignored", Model.projectFromTitle("code", "● app.tsx - lumen - Visual Studio Code") === "lumen")
check("other apps' titles are not read as projects", Model.projectFromTitle("chromium", "Docs - Orbit - Chromium") === "")

check("an agent in front is an agent", Model.windowContext({ appId: "foot" }, { command: "claude", project: "orbit-api", branch: "main" }).kind === "agent")
check("a build tool in front is a build", Model.windowContext({ appId: "foot" }, { command: "cargo" }).kind === "build")
check("an editor app is an editor", Model.windowContext({ appId: "cursor", title: "a - orbit-api - Cursor" }).kind === "editor")
check("a branch only comes with a project read from git", Model.windowContext({ appId: "cursor", title: "a - x - Cursor" }).branch === "")

check("a command using a tenth of a processor is busy", Model.busy(100, 110, 1000))
check("a command using almost nothing is not", !Model.busy(100, 100, 1000))
check("without an earlier look nothing is busy", !Model.busy(undefined, 110, 1000))

const windows = [
  { address: "a", appId: "cursor", appName: "Cursor", focus: 1 },
  { address: "b", appId: "foot", appName: "Terminal", focus: 0 },
  { address: "c", appId: "chromium", appName: "Chromium", focus: 2, media: true }
]
const contexts = {
  a: { project: "orbit-api", branch: "", kind: "editor" },
  b: { project: "orbit-api", branch: "feature/search", kind: "agent", busy: true },
  c: { project: "", kind: "" }
}
const desktop = Model.summary({ id: 2, windows: windows }, contexts, "")
check("a desktop is named after its project", desktop.title === "orbit-api" && !desktop.named)
check("with the branch git reports", desktop.branch === "feature/search")
check("apps come in the order they were last used, once each", desktop.apps.map(app => app.appId).join(",") === "foot,cursor,chromium")
check("a working agent shows, and a waiting one does not", desktop.activity.agentWorking && !desktop.activity.agentWaiting)
check("media playing shows", desktop.activity.media)
check("a name given by the person wins", Model.summary({ id: 2, windows: windows }, contexts, "Launch week").title === "Launch week")

const idle = Model.summary({ id: 3, windows: [{ address: "d", appId: "foot", appName: "Terminal", focus: 0 }] },
  { d: { project: "lumen", kind: "agent", busy: false } }, "")
check("an agent that is not busy is waiting for you", idle.activity.agentWaiting && !idle.activity.agentWorking)
const unknown = Model.summary({ id: 3, windows: [{ address: "d", appId: "foot", focus: 0 }] }, { d: { project: "lumen", kind: "agent" } }, "")
check("an agent looked at only once shows neither working nor waiting", !unknown.activity.agentWaiting && !unknown.activity.agentWorking)

const plain = Model.summary({ id: 4, windows: [{ address: "e", appId: "chrome-web.whatsapp.com__-Default", appName: "WhatsApp", focus: 0 }] }, {}, "")
check("a desktop without a project is named after its app", plain.title === "WhatsApp" && plain.project === "")
check("an empty desktop has no title", Model.summary({ id: 5, windows: [] }, {}, "").title === "")

const tool = Model.summary({ id: 7, windows: [{ address: "t", appId: "foot", appName: "Foot", focus: 0 }] }, { t: { project: "", command: "btop", kind: "" } }, "")
check("a terminal running a tool outside a project names the desktop after the tool", tool.title === "btop")
check("a project still wins over a tool", Model.summary({ id: 8, windows: [{ address: "t", appId: "foot", focus: 0 }] },
  { t: { project: "orbit-api", command: "nvim", kind: "editor" } }, "").title === "orbit-api")

const index = Model.appIndex([
  { id: "WhatsApp", name: "WhatsApp", execString: "omarchy-launch-webapp https://web.whatsapp.com/" },
  { id: "org.gnome.Nautilus", name: "Files", startupClass: "org.gnome.Nautilus" },
  { id: "foot.desktop", name: "Foot" }
])
check("a web app window finds its web app by site", (Model.entryFor("chrome-web.whatsapp.com__-Default", index) || {}).name === "WhatsApp")
check("a window finds its app by startup class", (Model.entryFor("org.gnome.Nautilus", index) || {}).name === "Files")
check("a window finds its app by id, without .desktop", (Model.entryFor("foot", index) || {}).name === "Foot")
check("a window with no app finds nothing", Model.entryFor("omahub-demo-a", index) === null)

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
