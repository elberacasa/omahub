#!/bin/bash

# Agents settings that change Omarchy's Agents bar widget through `omarchy bar set`: which
# subscriptions it shows, and whether the bar shows their limits.

source "$(dirname "$0")/../base-test.sh"

for command in claude codex fireworks update; do
  printf '#!/bin/bash\n' >"$TEST_ROOT/bin/omarchy-agent-usage-$command"
  chmod +x "$TEST_ROOT/bin/omarchy-agent-usage-$command"
done

config="$HOME/.config/omarchy/shell.json"
mkdir -p "$(dirname "$config")"
echo '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"omarchy.agents"}]}}}' >"$config"

# Omarchy, reduced to what these settings use: the plugin list, and bar set storing a widget
# option on its shell.json entry.
cat >"$TEST_ROOT/bin/omarchy" <<'EOF'
#!/bin/bash
config="$HOME/.config/omarchy/shell.json"
if [[ $1 == "plugin" && $2 == "list" ]]; then
  cat "$HOME/plugins.json" 2>/dev/null || echo '[]'
elif [[ $1 == "bar" && $2 == "set" && $6 == "--json" ]]; then
  jq --arg id "$3" --arg key "$4" --argjson value "$5" \
    '.bar.layout.right |= map(if .id == $id then .[$key] = $value else . end)' "$config" >"$config.tmp"
  mv "$config.tmp" "$config"
fi
EOF

cat >"$TEST_ROOT/bin/omarchy-plugin-catalog" <<EOF
#!/bin/bash
echo '[{"id":"omarchy.agents","manifestPath":"$TEST_ROOT/agents.json"},{"id":"me.agents","manifestPath":"$TEST_ROOT/agents.json"}]'
EOF
chmod +x "$TEST_ROOT/bin/omarchy" "$TEST_ROOT/bin/omarchy-plugin-catalog"
echo '{"barWidget":{"schema":[{"key":"refreshIntervalSec"}]}}' >"$TEST_ROOT/agents.json"

entry() {
  jq -c ".bar.layout.right[0]$1" "$config"
}

assert_eq "each subscription with a collector is listed" "$(omahub settings --json | jq '[.[] | select(.id | endswith("-usage"))] | length')" "3"
assert_eq "subscriptions start on, like Omarchy" "$(omahub get agents/codex-usage | jq -r .value)" "true"

assert_eq "off hides Codex" "$(omahub set agents/codex-usage off | jq -r .value)" "false"
assert_eq "Omarchy's widget setting says so" "$(entry .providers)" '{"codex":{"enabled":false}}'
assert_eq "other subscriptions stay on" "$(omahub get agents/claude-usage | jq -r .value)" "true"

omahub set agents/fireworks-usage off >/dev/null
assert_eq "switches keep each other" "$(entry .providers)" '{"codex":{"enabled":false},"fireworks":{"enabled":false}}'
assert_eq "on shows Codex again" "$(omahub set agents/codex-usage on | jq -r .value)" "true"
assert_eq "reset returns Codex to Omarchy's default" "$(omahub reset agents/codex-usage | jq -r .value)" "true"
assert_eq "reset leaves only the other switch" "$(entry .providers)" '{"fireworks":{"enabled":false}}'

if omahub set agents/claude-usage maybe 2>/dev/null; then
  fail "an unknown value fails"
else
  pass "an unknown value fails"
fi

assert_eq "limits on the bar start off" "$(omahub get agents/bar-limits | jq -r .value)" "false"
if omahub set agents/bar-limits on 2>"$TEST_ROOT/stderr"; then
  fail "limits need a widget that offers them"
else
  pass "limits need a widget that offers them"
fi
assert_true "the failure says the widget has no Limits mode" grep -q "no Limits mode" "$TEST_ROOT/stderr"
assert_eq "reset works on a widget without the mode" "$(omahub reset agents/bar-limits | jq -r .value)" "false"

echo '{"barWidget":{"schema":[{"key":"barDisplay"},{"key":"refreshIntervalSec"}]}}' >"$TEST_ROOT/agents.json"
assert_eq "limits turn on when the widget offers them" "$(omahub set agents/bar-limits on | jq -r .value)" "true"
assert_eq "the widget shows limits" "$(entry .barDisplay)" '"Limits"'
assert_eq "off goes back to the icon" "$(omahub set agents/bar-limits off | jq -r .value)" "false"
assert_eq "the widget shows the icon" "$(entry .barDisplay)" '"Icon"'

usage="$HOME/.local/state/omarchy/agents/usage"
mkdir -p "$usage"
echo '{"limits":[{"label":"Session (5-hour)","percent":0.2},{"label":"Weekly (7-day)","percent":0.6},{"label":"Fable Weekly","title":"Fable Weekly","percent":0.9}]}' >"$usage/claude.json"
echo '{"limits":[{"label":"Weekly (7-day)","percent":0.3}]}' >"$usage/codex.json"

assert_eq "each subscription with limits has a bar limit" "$(omahub settings --json | jq -c '[.[] | select(.id | endswith("-bar-limit")) | .id] | sort')" '["agents/claude-bar-limit","agents/codex-bar-limit"]'
assert_eq "a bar limit starts on Auto" "$(omahub get agents/claude-bar-limit | jq -r .value)" "Auto"
assert_eq "Claude offers the limits its plan reports" \
  "$(omahub options agents/claude-bar-limit | jq -c 'map(.value)')" '["Auto","Session","Weekly","Fable Weekly","Fullest"]'
assert_eq "Codex offers only its own" "$(omahub options agents/codex-bar-limit | jq -c 'map(.value)')" '["Auto","Weekly"]'
assert_eq "Auto is marked current" "$(omahub options agents/codex-bar-limit | jq -r '.[] | select(.current) | .value')" "Auto"
if omahub set agents/claude-bar-limit Weekly 2>"$TEST_ROOT/stderr"; then
  fail "a bar limit needs a widget that offers the choice"
else
  pass "a bar limit needs a widget that offers the choice"
fi
assert_true "the failure says the widget cannot choose" grep -q "cannot choose its bar limit" "$TEST_ROOT/stderr"

echo '{"barWidget":{"schema":[{"key":"barDisplay"},{"key":"barLimit"}]}}' >"$TEST_ROOT/agents.json"
if omahub set agents/codex-bar-limit Session 2>/dev/null; then
  fail "a limit the plan does not report fails"
else
  pass "a limit the plan does not report fails"
fi
assert_eq "a model limit can be chosen" "$(omahub set agents/claude-bar-limit 'Fable Weekly' | jq -r .label)" "Fable Weekly"
assert_eq "the widget stores it on that subscription" "$(entry .providers.claude)" '{"barLimit":"Fable Weekly"}'
assert_eq "other subscriptions stay on Auto" "$(omahub get agents/codex-bar-limit | jq -r .value)" "Auto"
omahub set agents/claude-usage off >/dev/null
omahub reset agents/claude-usage >/dev/null
assert_eq "resetting the usage switch keeps the bar limit" "$(entry .providers.claude)" '{"barLimit":"Fable Weekly"}'
rm "$usage/claude.json"
assert_eq "a chosen limit stays listed after its record goes" \
  "$(omahub options agents/claude-bar-limit | jq -r '.[] | select(.current) | .value')" "Fable Weekly"
assert_eq "reset goes back to Auto" "$(omahub reset agents/claude-bar-limit | jq -r .value)" "Auto"
assert_eq "reset leaves no empty entry" "$(entry '.providers | has("claude")')" "false"

echo '[{"id":"omarchy.agents","clonedFrom":""},{"id":"me.agents","clonedFrom":"omarchy.agents"}]' >"$HOME/plugins.json"
jq '.bar.layout.right[0].id = "me.agents"' "$config" >"$config.tmp"
mv "$config.tmp" "$config"
omahub set agents/codex-usage off >/dev/null
assert_eq "a cloned widget on the bar is the one changed" "$(entry .providers.codex)" '{"enabled":false}'
assert_eq "the clone keeps its limits setting" "$(omahub set agents/bar-limits on | jq -r .value)" "true"

finish
