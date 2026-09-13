#!/bin/bash

# Agent subscriptions in Omarchy's Agents bar panel. Omarchy owns the panel and its settings:
# these helpers read the widget's providers from shell.json and change them with `omarchy bar set`.

OMAHUB_AGENTS_WIDGET="omarchy.agents"

omahub_agents_providers() {
  local config="$HOME/.config/omarchy/shell.json"
  if [[ -s $config ]]; then
    jq -c --arg id "$OMAHUB_AGENTS_WIDGET" '[.bar.layout[]?[]? | objects | select(.id == $id)][0].providers // {}' "$config"
  else
    echo '{}'
  fi
}

# Omarchy shows every provider unless its settings say enabled is false.
omahub_agents_enabled() {
  omahub_agents_providers | jq -e --arg provider "$1" '.[$provider].enabled != false' >/dev/null
}

omahub_agents_write() {
  if ! omarchy bar set "$OMAHUB_AGENTS_WIDGET" providers "$1" --json >/dev/null; then
    omahub_fail "Omarchy could not update the Agents panel. Is the shell running?"
  fi
}

omahub_agents_set() {
  local provider="$1" enabled="$2" providers
  providers=$(omahub_agents_providers | jq -c --arg provider "$provider" --argjson enabled "$enabled" \
    '.[$provider] = ((.[$provider] // {}) + {enabled: $enabled})')
  omahub_agents_write "$providers"
}

# Drop the provider from the settings, so Omarchy's own default applies again.
omahub_agents_forget() {
  local provider="$1" providers
  providers=$(omahub_agents_providers)
  if jq -e --arg provider "$provider" 'has($provider)' <<<"$providers" >/dev/null; then
    omahub_agents_write "$(jq -c --arg provider "$provider" 'del(.[$provider])' <<<"$providers")"
  fi
}

# The get, set, and reset verbs of a toggle that shows or hides one subscription.
omahub_agents_toggle_setting() {
  local provider="$1" id="$2" verb="${3:-}" value="${4:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true) omahub_agents_set "$provider" true ;;
        off | false) omahub_agents_set "$provider" false ;;
        *) omahub_fail "usage: omahub set $id on|off" ;;
      esac
      ;;
    reset) omahub_agents_forget "$provider" ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if omahub_agents_enabled "$provider"; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}
