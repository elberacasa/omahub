#!/bin/bash

# Omahub's hook in an agent's own settings, so the agent says when it waits on you. The hook only runs
# `omahub signal`, which prints nothing and always succeeds, so it never changes what the agent does.
# Omahub adds exactly one hook, finds it again by its command, and removes only that one.

OMAHUB_CLAUDE_SETTINGS="$HOME/.claude/settings.json"

omahub_hook_command() {
  printf '%s\n' "$HOME/.config/omarchy/plugins/$OMAHUB_PLUGIN_ID/bin/omahub signal"
}

# The settings file, or an empty object when there is none. A file that is not a JSON object stops here
# rather than being overwritten.
omahub_claude_settings_read() {
  if [[ ! -s $OMAHUB_CLAUDE_SETTINGS ]]; then
    echo '{}'
  elif jq -e 'type == "object"' "$OMAHUB_CLAUDE_SETTINGS" >/dev/null 2>&1; then
    cat "$OMAHUB_CLAUDE_SETTINGS"
  else
    omahub_fail "$OMAHUB_CLAUDE_SETTINGS is not valid JSON, so Omahub left it alone. Fix it, then try again"
  fi
}

omahub_claude_hook_has() {
  [[ -s $OMAHUB_CLAUDE_SETTINGS ]] || return 1
  jq -e --arg command "$(omahub_hook_command)" 'any(.hooks.Notification[]?.hooks[]?; .command == $command)' \
    "$OMAHUB_CLAUDE_SETTINGS" >/dev/null 2>&1
}

# Writes the settings through a temporary file, only when they changed, after a backup.
omahub_claude_settings_write() {
  local next="$1"
  if [[ -s $OMAHUB_CLAUDE_SETTINGS ]] && jq -e --argjson next "$next" '. == $next' "$OMAHUB_CLAUDE_SETTINGS" >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$(dirname "$OMAHUB_CLAUDE_SETTINGS")"
  omahub_backup "$OMAHUB_CLAUDE_SETTINGS" "#"
  jq . <<<"$next" >"$OMAHUB_CLAUDE_SETTINGS.omahub-tmp" && mv "$OMAHUB_CLAUDE_SETTINGS.omahub-tmp" "$OMAHUB_CLAUDE_SETTINGS"
}

omahub_claude_hook_on() {
  local current
  current=$(omahub_claude_settings_read)
  omahub_claude_settings_write "$(jq -c --arg command "$(omahub_hook_command)" '
    if any(.hooks.Notification[]?.hooks[]?; .command == $command) then .
    else .hooks.Notification = ((.hooks.Notification // []) + [{
      matcher: "permission_prompt",
      hooks: [{type: "command", command: $command, timeout: 10}]
    }]) end' <<<"$current")"
}

omahub_claude_hook_off() {
  local current
  [[ -e $OMAHUB_CLAUDE_SETTINGS ]] || return 0
  current=$(omahub_claude_settings_read)
  omahub_claude_settings_write "$(jq -c --arg command "$(omahub_hook_command)" '
    if (.hooks.Notification | type) != "array" then .
    else
      .hooks.Notification |= (map(if (.hooks | type) == "array" then .hooks |= map(select(.command != $command)) else . end)
        | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
      | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    end' <<<"$current")"
}
