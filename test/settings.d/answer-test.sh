#!/bin/bash

# agents/answer-from-dock, `omahub decide`, `omahub answer`, and `omahub reply`: a permission hook in Claude
# Code's settings that waits for an answer from the dock, beside Omahub's waiting hook and never replacing it,
# and the commands the dock answers and replies with.

source "$(dirname "$0")/../base-test.sh"

printf '#!/bin/bash\nexit 0\n' >"$TEST_ROOT/bin/claude"
chmod +x "$TEST_ROOT/bin/claude"

claude="$HOME/.claude/settings.json"
decide="$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub decide"
signal="$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub signal"
state="$HOME/.local/state/omahub"

assert_eq "answering from the dock starts off" "$(omahub get agents/answer-from-dock | jq -r .value)" "false"
omahub set agents/waiting on >/dev/null
assert_eq "turning it on says so" "$(omahub set agents/answer-from-dock on | jq -r .value)" "true"
assert_eq "it adds a permission hook that waits up to two minutes" \
  "$(jq -c --arg c "$decide" '[.hooks.PermissionRequest[] | select(.hooks[0].command == $c) | [.matcher, .hooks[0].timeout]]' "$claude")" '[["*",120]]'
assert_eq "beside the waiting hook, which stays" \
  "$(jq -r --arg c "$signal" '[.hooks.Notification[]?.hooks[]? | select(.command == $c)] | length' "$claude")" "1"
omahub set agents/answer-from-dock on >/dev/null
assert_eq "turning it on again adds nothing more" "$(jq '.hooks.PermissionRequest | length' "$claude")" "1"
assert_eq "turning it off removes only its own hook" \
  "$(omahub set agents/answer-from-dock off | jq -r .value),$(jq -c 'has("hooks") and (.hooks | has("PermissionRequest") | not) and (.hooks | has("Notification"))' "$claude")" "false,true"
assert_eq "and waiting agents are still on" "$(omahub get agents/waiting | jq -r .value)" "true"

transcript="$TEST_ROOT/session.jsonl"
printf '{}\n' >"$transcript"
touch -d '1 minute ago' "$transcript"
key=$(printf '%s' "$transcript" | sha1sum | cut -c1-16)
ask() {
  jq -nc --arg path "$transcript" '{hook_event_name: "PermissionRequest", transcript_path: $path, tool_name: "Bash",
    tool_input: {command: "git push origin main\nsecond line", description: "Push"}}'
}
wait_for_request() {
  for _ in $(seq 40); do
    [[ -f $state/requests/$key.json ]] && return 0
    sleep 0.1
  done
  return 1
}

ask | OMAHUB_DECIDE_WAIT=10 omahub decide >"$TEST_ROOT/allow.out" &
waiter=$!
wait_for_request
assert_eq "a question notes the tool and the first line of what it runs" \
  "$(jq -c '[.tool, .detail]' "$state/requests/$key.json")" '["Bash","git push origin main"]'
assert_eq "and marks the agent as waiting" "$(jq -r .event "$state/signals/$key.json")" "PermissionRequest"
omahub answer "$key" allow
wait "$waiter"
assert_eq "allowing from the dock hands Claude an allow" "$(jq -r '.hookSpecificOutput.decision.behavior' "$TEST_ROOT/allow.out")" "allow"
assert_eq "and the question is gone" "$([[ -e $state/requests/$key.json ]] && echo left || echo gone)" "gone"

ask | OMAHUB_DECIDE_WAIT=10 omahub decide >"$TEST_ROOT/deny.out" &
waiter=$!
wait_for_request
omahub answer "$key" deny
wait "$waiter"
assert_eq "denying hands Claude a deny that says where it came from" \
  "$(jq -c '.hookSpecificOutput.decision | [.behavior, .message]' "$TEST_ROOT/deny.out")" '["deny","Declined from the Omahub dock"]'

ask | OMAHUB_DECIDE_WAIT=10 omahub decide >"$TEST_ROOT/terminal.out" &
waiter=$!
wait_for_request
sleep 2.5
touch "$transcript"
wait "$waiter"
assert_eq "answering in the terminal first leaves the decision to Claude" "$(cat "$TEST_ROOT/terminal.out")" ""

touch -d '1 minute ago' "$transcript"
assert_eq "with no answer in time, it steps aside and prints nothing" "$(ask | OMAHUB_DECIDE_WAIT=1 omahub decide)" ""
assert_eq "nonsense never breaks Claude" "$(printf 'nonsense' | omahub decide; echo "exit $?")" "exit 0"
if omahub answer "$key" allow >/dev/null 2>&1; then
  fail "an answer when nothing is asking is refused"
else
  pass "an answer when nothing is asking is refused"
fi
if omahub answer "$key" maybe >/dev/null 2>&1; then
  fail "an answer that is not allow or deny is refused"
else
  pass "an answer that is not allow or deny is refused"
fi

if omahub reply not-a-session "hello" >/dev/null 2>&1; then
  fail "a reply to something that is not a Codex session id is refused"
else
  pass "a reply to something that is not a Codex session id is refused"
fi
if omahub reply 00000000-0000-4000-8000-000000000000 "   " >/dev/null 2>&1; then
  fail "an empty reply is refused"
else
  pass "an empty reply is refused"
fi

finish
