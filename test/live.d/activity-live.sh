#!/bin/bash

# Agents on the live desktop: a terminal running an agent in a git project names its desktop after the
# project and puts the agent on the desktop's badge. The agent is a small stand-in script named like one,
# so no real agent runs. Omahub shows only what it can read for certain, so the badge never claims the
# agent is working or waiting.

source "$(dirname "$0")/../live-lib.sh"

away=$(agent state .sandbox.away)
studio="$LIVE_ROOT/tmp/agent/activity"
project="$studio/orbit-api"
rm -rf "$studio"
mkdir -p "$project/src" "$studio/bin"
git -C "$project" init -q -b feature/search

# Without exec, so the running process keeps the agent's name, as a real agent's does.
printf '#!/bin/bash\nsleep 600\n' >"$studio/bin/claude"
chmod +x "$studio/bin/claude"

hyprctl eval "hl.exec_cmd('foot --app-id=omahub-demo-agent --title=Agent --working-directory=$project $studio/bin/claude', { workspace = '$away silent' })" >/dev/null
for _ in $(seq 50); do
  hyprctl clients -j | jq -e 'any(.[]; .class == "omahub-demo-agent")' >/dev/null && break
  sleep 0.1
done

finish_activity() {
  for address in $(hyprctl clients -j | jq -r '.[] | select(.class == "omahub-demo-agent") | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
  done
  # A script can outlive its closed terminal, so the stand-in is stopped by name too.
  pkill -f "$studio/bin/claude" 2>/dev/null || true
  rm -rf "$studio"
}
trap finish_activity EXIT

desktop=".omahub.overview.desktops[] | select(.id == $away)"

section "An agent in a project names its desktop and shows on its badge"
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
check "the desktop is named after the agent's project" "[$desktop][0].title == \"orbit-api\" and [$desktop][0].branch == \"feature/search\"" 4
check "its badge shows the agent" "[$desktop][0].activity == \"agent\"" 4
agent shot screen >/dev/null
agent chord Escape
check "the overview closes" '.omahub.overview.opened | not' 2

section "Closing the agent's terminal clears its badge"
for address in $(hyprctl clients -j | jq -r '.[] | select(.class == "omahub-demo-agent") | .address'); do
  hyprctl dispatch "hl.dsp.window.close({ window = \"address:$address\" })" >/dev/null
done
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
# Only the sandbox's desktop: agents the person runs on their own desktops keep their badges.
check "its desktop no longer shows the agent" "[$desktop][0].activity != \"agent\"" 4
agent chord Escape

finish_live
