#!/bin/bash

# agents/waiting: one hook each in Claude Code's and Codex's settings that says when they wait for your
# answer. Omahub adds exactly those hooks, last, keeps everything else in the files, removes only its own,
# and leaves Codex's trust to Codex. `omahub signal`, which the hooks run, prints nothing and always succeeds.

source "$(dirname "$0")/../base-test.sh"

for agent in claude codex; do
  printf '#!/bin/bash\nexit 0\n' >"$TEST_ROOT/bin/$agent"
  chmod +x "$TEST_ROOT/bin/$agent"
done

claude="$HOME/.claude/settings.json"
codex="$HOME/.codex/hooks.json"
command="$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub signal"
ours() { jq --arg event "$2" --arg command "$command" '[.hooks[$event][]?.hooks[]? | select(.command == $command)] | length' "$1"; }

assert_eq "waiting agents start off" "$(omahub get agents/waiting | jq -r .value)" "false"
assert_eq "turning it off with no settings files creates none" \
  "$(omahub set agents/waiting off | jq -r .value),$([[ -e $claude || -e $codex ]] && echo made || echo none)" "false,none"

mkdir -p "$HOME/.claude" "$HOME/.codex"
cat >"$claude" <<'JSON'
{
  "theme": "dark",
  "hooks": {
    "Notification": [
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "notify-send Claude" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "echo done" }] }
    ]
  }
}
JSON
cat >"$codex" <<'JSON'
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "my-policy" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "echo codex done" }] }
    ]
  }
}
JSON

assert_eq "turning it on says so" "$(omahub set agents/waiting on | jq -r .value)" "true"
assert_eq "Claude gets one hook for permission prompts" \
  "$(jq -c --arg command "$command" '[.hooks.Notification[] | select(.hooks[]?.command == $command) | .matcher]' "$claude")" '["permission_prompt"]'
assert_eq "and keeps every other setting and hook" \
  "$(jq -c '{theme, idle: [.hooks.Notification[] | select(.matcher == "idle_prompt") | .hooks[0].command], stop: .hooks.Stop[0].hooks[0].command}' "$claude")" \
  '{"theme":"dark","idle":["notify-send Claude"],"stop":"echo done"}'
assert_eq "Codex gets one hook for every permission request, after its own, so their trust stays" \
  "$(jq -c --arg command "$command" '.hooks.PermissionRequest | [length, .[0].matcher, .[0].hooks[0].command, .[-1].matcher, .[-1].hooks[0].command == $command]' "$codex")" \
  '[2,"Bash","my-policy","*",true]'
assert_eq "and keeps its other hooks" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$codex")" "echo codex done"
omahub set agents/waiting on >/dev/null
assert_eq "turning it on again adds nothing more" "$(ours "$claude" Notification),$(ours "$codex" PermissionRequest)" "1,1"

assert_eq "turning it off says so" "$(omahub set agents/waiting off | jq -r .value)" "false"
assert_eq "and takes out only Claude's hook from Omahub" \
  "$(jq -c '{theme, notification: (.hooks.Notification | length), stop: (.hooks.Stop | length)}' "$claude")" \
  '{"theme":"dark","notification":1,"stop":1}'
assert_eq "and only Codex's hook from Omahub" \
  "$(jq -c '[.hooks.PermissionRequest[].hooks[0].command, .hooks.Stop[0].hooks[0].command]' "$codex")" '["my-policy","echo codex done"]'

rm -f "$codex"
omahub set agents/waiting on >/dev/null
assert_eq "a Codex hooks file Omahub creates" "$([[ -s $codex ]] && echo made)" "made"
omahub set agents/waiting off >/dev/null
assert_eq "is gone again once it is off" "$([[ -e $codex ]] && echo left || echo gone)" "gone"

printf '{"theme": "light"}\n' >"$claude"
omahub set agents/waiting on >/dev/null
omahub set agents/waiting off >/dev/null
assert_eq "a Claude settings file that had no hooks has none left" "$(jq -c . "$claude")" '{"theme":"light"}'

omahub set agents/waiting on >/dev/null
printf '{}\n' >"$claude"
assert_eq "with only one agent's hook left, it says which" "$(omahub get agents/waiting | jq -c '[.value, .label]')" '[false,"Codex only"]'
omahub set agents/waiting off >/dev/null

# Without Codex anywhere on the PATH, as on a machine that only has Claude Code.
rm -f "$TEST_ROOT/bin/codex"
without_codex=$(tr ':' '\n' <<<"$PATH" | while IFS= read -r dir; do [[ -x $dir/codex ]] || printf '%s\n' "$dir"; done | paste -sd ':')
assert_eq "an agent that is not installed gets no hook" \
  "$(PATH="$without_codex" omahub set agents/waiting on | jq -r .value),$([[ -e $codex ]] && echo made || echo none)" "true,none"
PATH="$without_codex" omahub set agents/waiting off >/dev/null

printf '{ not json\n' >"$claude"
if omahub set agents/waiting on >/dev/null 2>&1; then
  fail "a settings file that is not valid JSON is refused"
else
  pass "a settings file that is not valid JSON is refused"
fi
assert_eq "and left exactly as it was" "$(cat "$claude")" "{ not json"

assert_eq "the signal prints nothing and succeeds on nonsense" "$(printf 'nonsense' | omahub signal; echo "exit $?")" "exit 0"
printf '{"hook_event_name":"PermissionRequest","transcript_path":"/tmp/rollout.jsonl"}' | omahub signal
signal="$HOME/.local/state/omahub/signals/$(printf '%s' /tmp/rollout.jsonl | sha1sum | cut -c1-16).json"
assert_eq "and notes a wait beside the session's record" "$(jq -r .event "$signal")" "PermissionRequest"

finish
