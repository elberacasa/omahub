#!/bin/bash

# Omarchy's Agents bar widget. Omarchy owns the widget and its settings: these helpers find it on
# the bar, read its entry from shell.json, and change options with `omarchy bar set`.

OMAHUB_AGENTS_SOURCE="omarchy.agents"

# Omarchy's shell config, or an empty object when it is missing or not valid JSON, so a half-written
# or hand-edited file reads as Omarchy's defaults instead of failing every Agents setting.
omahub_agents_config() {
  local config="$HOME/.config/omarchy/shell.json"
  if [[ -s $config ]] && jq -e 'type == "object"' "$config" >/dev/null 2>&1; then
    cat "$config"
  else
    echo '{}'
  fi
}

# The Agents widget on the bar: Omarchy's own, or a copy made with `omarchy plugin clone`.
omahub_agents_widget() {
  local config id
  config=$(omahub_agents_config)
  while IFS= read -r id; do
    if jq -e --arg id "$id" 'any(.bar.layout[]?[]?; type == "object" and .id == $id)' <<<"$config" >/dev/null 2>&1; then
      echo "$id"
      return
    fi
  done < <(omarchy plugin list --json 2>/dev/null \
    | jq -r --arg source "$OMAHUB_AGENTS_SOURCE" '.[]? | select(.id == $source or .clonedFrom == $source) | .id' 2>/dev/null)
  echo "$OMAHUB_AGENTS_SOURCE"
}

omahub_agents_entry() {
  omahub_agents_config | jq -c --arg id "$(omahub_agents_widget)" '[.bar.layout[]?[]? | objects | select(.id == $id)][0] // {}'
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

# Change one subscription's options: omahub_agents_provider_write <provider> <jq filter on its entry>.
# An entry left empty is dropped, so Omarchy's own defaults apply again.
omahub_agents_provider_write() {
  local provider="$1" filter="$2" providers
  providers=$(omahub_agents_providers | jq -c --arg provider "$provider" \
    ".[\$provider] = ((.[\$provider] // {}) | $filter) | if .[\$provider] == {} then del(.[\$provider]) else . end")
  if [[ $providers != "$(omahub_agents_providers)" ]]; then
    omahub_agents_write providers "$providers"
  fi
}

# Omarchy shows every provider unless its settings say enabled is false.
omahub_agents_enabled() {
  omahub_agents_providers | jq -e --arg provider "$1" '.[$provider].enabled != false' >/dev/null
}

# The get, set, and reset verbs of a toggle that shows or hides one subscription.
omahub_agents_toggle_setting() {
  local provider="$1" id="$2" verb="${3:-}" value="${4:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true) omahub_agents_provider_write "$provider" '.enabled = true' ;;
        off | false) omahub_agents_provider_write "$provider" '.enabled = false' ;;
        *) omahub_fail "usage: omahub set $id on|off" ;;
      esac
      ;;
    reset) omahub_agents_provider_write "$provider" 'del(.enabled)' ;;
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

# The limits one subscription reports today, titled the way the Agents widget titles them: Session,
# Weekly, and Monthly for the plan, and a model limit by its own name, such as "Fable Weekly".
omahub_agents_limit_titles() {
  local record="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/$1.json"
  # A record in a shape this does not know reads as no limits, never as a failure.
  if [[ -s $record ]] && jq -e 'type == "object"' "$record" >/dev/null 2>&1; then
    jq -r '(.limits // []) | if type == "array" then .[] else empty end | objects
      | select(((.percent // -1) | tonumber? // -1) >= 0)
      | if (.title // "") != "" then .title
        else (.label // "") as $label | ($label | ascii_downcase) as $text
          | if ($text | test("month|30-day")) then "Monthly"
            elif ($text | test("week|7-day|seven")) then "Weekly"
            elif ($text | test("session|[0-9]+\\s*-?\\s*h(our)?\\b|[0-9]+\\s*-?\\s*m(in(ute)?s?)?\\b")) then "Session"
            else ($label | sub("\\s*\\(.*\\)\\s*"; "") | if . == "" then "Limit" else . end)
            end
        end' "$record" 2>/dev/null | awk '!seen[$0]++'
  fi
}

# What the bar can show for one subscription: Auto, each limit it reports, and Fullest when there
# is more than one to compare.
omahub_agents_bar_limit_choices() {
  local titles
  titles=$(omahub_agents_limit_titles "$1")
  echo Auto
  if [[ -n $titles ]]; then
    echo "$titles"
    if (( $(wc -l <<<"$titles") > 1 )); then
      echo Fullest
    fi
  fi
}

omahub_agents_bar_limit() {
  omahub_agents_providers | jq -r --arg provider "$1" '.[$provider].barLimit // "Auto"'
}

# The get, options, set, and reset verbs of the choice of which limit the bar shows for one
# subscription.
omahub_agents_bar_limit_setting() {
  local provider="$1" id="$2" verb="${3:-}" value="${4:-}" current

  case "$verb" in
    get) ;;
    options)
      current=$(omahub_agents_bar_limit "$provider")
      { omahub_agents_bar_limit_choices "$provider"; echo "$current"; } | awk '!seen[$0]++' \
        | jq -Rnc --arg current "$current" '[inputs | {value: ., label: ., current: (. == $current)}]'
      return
      ;;
    set)
      if ! grep -qxF -- "$value" <<<"$(omahub_agents_bar_limit_choices "$provider")"; then
        omahub_fail "usage: omahub set $id <limit>. Run 'omahub options $id' to list the limits this plan reports."
      fi
      if ! omahub_agents_supports barLimit; then
        omahub_fail "your Agents widget cannot choose its bar limit yet"
      fi
      omahub_agents_provider_write "$provider" ".barLimit = $(jq -nc --arg value "$value" '$value')"
      ;;
    reset) omahub_agents_provider_write "$provider" 'del(.barLimit)' ;;
    *) omahub_fail "usage: omahub get|set|options|reset $id" ;;
  esac

  current=$(omahub_agents_bar_limit "$provider")
  omahub_state "$(jq -nc --arg value "$current" '$value')" "$current"
}
