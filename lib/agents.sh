#!/bin/bash

# Omarchy's Agents bar widget. Omarchy owns the widget and its settings: these helpers find it on
# the bar, read its entry from shell.json, and change options with `omarchy bar set`.

OMAHUB_AGENTS_SOURCE="omarchy.agents"

# The Agents widget on the bar: Omarchy's own, or a copy made with `omarchy plugin clone`.
omahub_agents_widget() {
  local config="$HOME/.config/omarchy/shell.json" id
  while IFS= read -r id; do
    if [[ -s $config ]] && jq -e --arg id "$id" 'any(.bar.layout[]?[]?; type == "object" and .id == $id)' "$config" >/dev/null; then
      echo "$id"
      return
    fi
  done < <(omarchy plugin list --json 2>/dev/null \
    | jq -r --arg source "$OMAHUB_AGENTS_SOURCE" '.[]? | select(.id == $source or .clonedFrom == $source) | .id')
  echo "$OMAHUB_AGENTS_SOURCE"
}

omahub_agents_entry() {
  local config="$HOME/.config/omarchy/shell.json"
  if [[ -s $config ]]; then
    jq -c --arg id "$(omahub_agents_widget)" '[.bar.layout[]?[]? | objects | select(.id == $id)][0] // {}' "$config"
  else
    echo '{}'
  fi
}

omahub_agents_providers() {
  omahub_agents_entry | jq -c '.providers // {}'
}

# True when the widget's manifest offers the option, so a switch never writes a key it ignores.
omahub_agents_supports() {
  local key="$1" manifest
  manifest=$(omarchy-plugin-catalog 2>/dev/null \
    | jq -r --arg id "$(omahub_agents_widget)" '.[]? | select(.id == $id) | .manifestPath // empty')
  [[ -n $manifest ]] && jq -e --arg key "$key" 'any(.barWidget.schema[]?; .key == $key)' "$manifest" >/dev/null
}

# Set one option on the widget: omahub_agents_write <key> <json value>.
omahub_agents_write() {
  if ! omarchy bar set "$(omahub_agents_widget)" "$1" "$2" --json >/dev/null; then
    omahub_fail "Omarchy could not update the Agents widget. Is the shell running?"
  fi
}

# Omarchy shows every provider unless its settings say enabled is false.
omahub_agents_enabled() {
  omahub_agents_providers | jq -e --arg provider "$1" '.[$provider].enabled != false' >/dev/null
}

omahub_agents_set() {
  local provider="$1" enabled="$2" providers
  providers=$(omahub_agents_providers | jq -c --arg provider "$provider" --argjson enabled "$enabled" \
    '.[$provider] = ((.[$provider] // {}) + {enabled: $enabled})')
  omahub_agents_write providers "$providers"
}

# Drop the provider from the settings, so Omarchy's own default applies again.
omahub_agents_forget() {
  local provider="$1" providers
  providers=$(omahub_agents_providers)
  if jq -e --arg provider "$provider" 'has($provider)' <<<"$providers" >/dev/null; then
    omahub_agents_write providers "$(jq -c --arg provider "$provider" 'del(.[$provider])' <<<"$providers")"
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

omahub_agents_bar_display() {
  if ! omahub_agents_supports barDisplay; then
    omahub_fail "your Agents widget has no Limits mode yet"
  fi
  omahub_agents_write barDisplay "\"$1\""
}

# The get, set, and reset verbs of the toggle that shows every subscription's limit on the bar.
omahub_agents_bar_limits_setting() {
  local id="$1" verb="${2:-}" value="${3:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true) omahub_agents_bar_display Limits ;;
        off | false) omahub_agents_bar_display Icon ;;
        *) omahub_fail "usage: omahub set $id on|off" ;;
      esac
      ;;
    reset)
      if omahub_agents_supports barDisplay; then
        omahub_agents_bar_display Icon
      fi
      ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if [[ $(omahub_agents_entry | jq -r '.barDisplay // "Icon"') == "Limits" ]]; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}

# Every limit the bar can show: the fixed choices, then each model limit a subscription reports
# today, such as "Fable Weekly", read from the records Omarchy's usage collectors write.
omahub_agents_bar_limit_choices() {
  local usage="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage"
  printf '%s\n' Auto Weekly Session Fullest
  if [[ -d $usage ]]; then
    find "$usage" -maxdepth 1 -name '*.json' -exec jq -r '.limits[]? | .title // empty' {} + 2>/dev/null | sort -u
  fi
}

omahub_agents_bar_limit() {
  omahub_agents_entry | jq -r '.barLimit // "Auto"'
}

# The get, options, set, and reset verbs of the choice of which limit the bar shows.
omahub_agents_bar_limit_setting() {
  local id="$1" verb="${2:-}" value="${3:-}" current choice

  case "$verb" in
    get) ;;
    options)
      current=$(omahub_agents_bar_limit)
      { omahub_agents_bar_limit_choices; echo "$current"; } | awk '!seen[$0]++' | while IFS= read -r choice; do
        jq -nc --arg value "$choice" --arg current "$current" '{value: $value, label: $value, current: ($value == $current)}'
      done | jq -sc '.'
      return
      ;;
    set)
      if ! grep -qxF -- "$value" <<<"$(omahub_agents_bar_limit_choices)"; then
        omahub_fail "usage: omahub set $id <limit>. Run 'omahub options $id' to list them."
      fi
      if ! omahub_agents_supports barLimit; then
        omahub_fail "your Agents widget cannot choose its bar limit yet"
      fi
      omahub_agents_write barLimit "$(jq -nc --arg value "$value" '$value')"
      ;;
    reset)
      if omahub_agents_supports barLimit; then
        omahub_agents_write barLimit '"Auto"'
      fi
      ;;
    *) omahub_fail "usage: omahub get|set|options|reset $id" ;;
  esac

  current=$(omahub_agents_bar_limit)
  omahub_state "$(jq -nc --arg value "$current" '$value')" "$current"
}
