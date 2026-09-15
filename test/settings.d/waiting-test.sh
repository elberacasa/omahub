#!/bin/bash

# agents/waiting: one hook in Claude Code's settings that says when Claude waits for your answer. Omahub
# adds exactly that hook, keeps everything else in the file, and removes only its own. `omahub signal`,
# which the hook runs, prints nothing and always succeeds.

source "$(dirname "$0")/../base-test.sh"

# The setting shows only where Claude Code is installed.
printf '#!/bin/bash\nexit 0\n' >"$TEST_ROOT/bin/claude"
chmod +x "$TEST_ROOT/bin/claude"

settings="$HOME/.claude/settings.json"
command="$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub signal"
ours="[.hooks.Notification[]?.hooks[]? | select(.command == \"$command\")] | length"

assert_eq "waiting agents start off" "$(omahub get agents/waiting | jq -r .value)" "false"
assert_eq "turning it off with no settings file creates none" "$(omahub set agents/waiting off | jq -r .value),$([[ -e $settings ]] && echo made || echo none)" "false,none"

mkdir -p "$HOME/.claude"
cat >"$settings" <<'JSON'
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

assert_eq "turning it on says so" "$(omahub set agents/waiting on | jq -r .value)" "true"
assert_eq "it adds one hook for permission prompts" "$(jq -c "[.hooks.Notification[] | select(.hooks[]?.command == \"$command\") | .matcher]" "$settings")" '["permission_prompt"]'
assert_eq "and keeps every other setting and hook" \
  "$(jq -c '{theme, idle: [.hooks.Notification[] | select(.matcher == "idle_prompt") | .hooks[0].command], stop: .hooks.Stop[0].hooks[0].command}' "$settings")" \
  '{"theme":"dark","idle":["notify-send Claude"],"stop":"echo done"}'
omahub set agents/waiting on >/dev/null
assert_eq "turning it on again adds nothing more" "$(jq "$ours" "$settings")" "1"

assert_eq "turning it off says so" "$(omahub set agents/waiting off | jq -r .value)" "false"
assert_eq "and removes only its own hook" \
  "$(jq -c '{theme, notification: (.hooks.Notification | length), stop: (.hooks.Stop | length)}' "$settings")" \
  '{"theme":"dark","notification":1,"stop":1}'

printf '{"theme": "light"}\n' >"$settings"
omahub set agents/waiting on >/dev/null
omahub set agents/waiting off >/dev/null
assert_eq "a file that had no hooks has none left" "$(jq -c . "$settings")" '{"theme":"light"}'

printf '{ not json\n' >"$settings"
if omahub set agents/waiting on >/dev/null 2>&1; then
  fail "a settings file that is not valid JSON is refused"
else
  pass "a settings file that is not valid JSON is refused"
fi
assert_eq "and left exactly as it was" "$(cat "$settings")" "{ not json"

assert_eq "the signal prints nothing and succeeds on nonsense" "$(printf 'nonsense' | omahub signal; echo "exit $?")" "exit 0"
printf '{"hook_event_name":"Notification","transcript_path":"/tmp/session.jsonl"}' | omahub signal
signal="$HOME/.local/state/omahub/signals/$(printf '%s' /tmp/session.jsonl | sha1sum | cut -c1-16).json"
assert_eq "and notes a wait beside the session's record" "$(jq -r .event "$signal")" "Notification"

finish
