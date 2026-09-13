#!/bin/bash

# agents/*-usage show or hide subscriptions in Omarchy's Agents bar panel through `omarchy bar set`.

source "$(dirname "$0")/../base-test.sh"

for provider in claude codex fireworks; do
  printf '#!/bin/bash\n' >"$TEST_ROOT/bin/omarchy-agent-usage-$provider"
  chmod +x "$TEST_ROOT/bin/omarchy-agent-usage-$provider"
done

# Omarchy's bar set, reduced to what these settings use: it stores the widget option in shell.json.
cat >"$TEST_ROOT/bin/omarchy" <<'EOF'
#!/bin/bash
if [[ $1 == "bar" && $2 == "set" && $3 == "omarchy.agents" && $4 == "providers" && $6 == "--json" ]]; then
  config="$HOME/.config/omarchy/shell.json"
  mkdir -p "$(dirname "$config")"
  if [[ ! -s $config ]]; then
    echo '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"omarchy.agents"}]}}}' >"$config"
  fi
  jq --argjson providers "$5" '.bar.layout.right |= map(if .id == "omarchy.agents" then .providers = $providers else . end)' "$config" >"$config.tmp"
  mv "$config.tmp" "$config"
fi
EOF
chmod +x "$TEST_ROOT/bin/omarchy"

providers() {
  jq -c '.bar.layout.right[0].providers' "$HOME/.config/omarchy/shell.json"
}

assert_eq "each subscription with a collector is listed" "$(omahub settings --json | jq '[.[] | select(.id | endswith("-usage"))] | length')" "3"
assert_eq "subscriptions start on, like Omarchy" "$(omahub get agents/codex-usage | jq -r .value)" "true"

assert_eq "off hides Codex" "$(omahub set agents/codex-usage off | jq -r .value)" "false"
assert_eq "Omarchy's widget setting says so" "$(providers)" '{"codex":{"enabled":false}}'
assert_eq "other subscriptions stay on" "$(omahub get agents/claude-usage | jq -r .value)" "true"

omahub set agents/fireworks-usage off >/dev/null
assert_eq "switches keep each other" "$(providers)" '{"codex":{"enabled":false},"fireworks":{"enabled":false}}'
assert_eq "on shows Codex again" "$(omahub set agents/codex-usage on | jq -r .value)" "true"

assert_eq "reset returns Codex to Omarchy's default" "$(omahub reset agents/codex-usage | jq -r .value)" "true"
assert_eq "reset leaves only the other switch" "$(providers)" '{"fireworks":{"enabled":false}}'

if omahub set agents/claude-usage maybe 2>/dev/null; then
  fail "an unknown value fails"
else
  pass "an unknown value fails"
fi

finish
