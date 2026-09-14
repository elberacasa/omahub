#!/bin/bash

# Desktop activity on the live desktop: a terminal running an agent in a git project names its desktop
# after the project, shows Working while the agent uses the processor, and Your turn once it waits. The
# agent is a small stand-in script named like one, so no real agent runs.

source "$(dirname "$0")/../live-lib.sh"

away=$(agent state .sandbox.away)
studio="$LIVE_ROOT/tmp/agent/activity"
project="$studio/orbit-api"
flag="$studio/busy"
rm -rf "$studio"
mkdir -p "$project/src" "$studio/bin"
git -C "$project" init -q -b feature/search

# Named claude, so the overview reads it as an agent. It works while the flag file exists, and waits
# otherwise, like an agent waiting for your reply. Waiting is a read with a timeout on a pipe nothing
# writes to, which starts no process and uses no processor, as a real agent waiting does.
mkfifo "$studio/idle"
cat >"$studio/bin/claude" <<'EOF'
#!/bin/bash
exec 3<>"$2"
while true; do
  if [[ -f $1 ]]; then
    for _ in {1..20000}; do :; done
  else
    read -r -t 0.3 _ <&3 || true
  fi
done
EOF
chmod +x "$studio/bin/claude"
touch "$flag"

hyprctl eval "hl.exec_cmd('foot --app-id=omahub-demo-agent --title=Agent --working-directory=$project $studio/bin/claude $flag $studio/idle', { workspace = '$away silent' })" >/dev/null
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

section "An agent at work names its desktop and shows Working"
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the overview is open" '.omahub.overview.opened' 2
check "the desktop is named after the agent's project" "[$desktop][0].title == \"orbit-api\" and [$desktop][0].branch == \"feature/search\"" 4
check "its badge says Working" "[$desktop][0].activity == \"working\"" 4
agent shot screen >/dev/null

section "An agent that stops working shows Your turn"
# Each section starts from rest, which closes the overview, so it opens again on the working agent.
agent focus a
agent call open '{"overview":"open"}' >/dev/null
check "the badge still says Working" "[$desktop][0].activity == \"working\"" 4
rm -f "$flag"
check "its badge says Your turn" "[$desktop][0].activity == \"waiting\"" 5
agent shot screen >/dev/null
touch "$flag"
check "and Working again when it starts again" "[$desktop][0].activity == \"working\"" 5
agent chord Escape
check "the overview closes" '.omahub.overview.opened | not' 2

finish_live
