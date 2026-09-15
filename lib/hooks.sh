#!/bin/bash

# Omahub's hooks in agents' own settings, so an agent says when it waits for your answer: a permission
# prompt notification in Claude Code's ~/.claude/settings.json, and a permission request in Codex's
# ~/.codex/hooks.json. A hook only runs `omahub signal`, which prints nothing and always succeeds, so it
# never changes what the agent does. Omahub adds exactly one hook to each file, last, finds it again by its
# command, and removes only that one. It never marks a Codex hook as trusted: Codex asks you once in /hooks.

OMAHUB_CLAUDE_SETTINGS="$HOME/.claude/settings.json"
OMAHUB_CODEX_HOOKS="$HOME/.codex/hooks.json"
# Present while Omahub is the one that created Codex's hooks file, so turning off removes the file too.
OMAHUB_CODEX_HOOKS_CREATED="$OMAHUB_STATE_DIR/created-codex-hooks"

omahub_hook_command() {
  printf '%s\n' "$HOME/.config/omarchy/plugins/$OMAHUB_PLUGIN_ID/bin/omahub signal"
}

# The command of the hook that lets you answer Claude from the dock, which waits for your answer.
omahub_decide_command() {
  printf '%s\n' "$HOME/.config/omarchy/plugins/$OMAHUB_PLUGIN_ID/bin/omahub decide"
}

# Every agent Omahub can hook, one per line: name, label, settings file, event, and matcher.
omahub_hook_agents() {
  printf '%s\t%s\t%s\t%s\t%s\n' claude Claude "$OMAHUB_CLAUDE_SETTINGS" Notification permission_prompt
  printf '%s\t%s\t%s\t%s\t%s\n' codex Codex "$OMAHUB_CODEX_HOOKS" PermissionRequest "*"
}

# A settings file, or an empty object when there is none. A file that is not a JSON object stops here
# rather than being overwritten.
omahub_hook_read() {
  local file="$1"
  if [[ ! -s $file ]]; then
    echo '{}'
  elif jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    cat "$file"
  else
    omahub_fail "$file is not valid JSON, so Omahub left it alone. Fix it, then try again"
  fi
}

# Hooks default to the signal command; answering from the dock passes its own.
omahub_hook_has() {
  local file="$1" event="$2" command="${3:-$(omahub_hook_command)}"
  [[ -s $file ]] || return 1
  jq -e --arg event "$event" --arg command "$command" \
    'any(.hooks[$event][]?.hooks[]?; .command == $command)' "$file" >/dev/null 2>&1
}

# Writes a settings file through a temporary file, only when it changed, after a backup.
omahub_hook_write() {
  local file="$1" next="$2"
  if [[ -s $file ]] && jq -e --argjson next "$next" '. == $next' "$file" >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  omahub_backup "$file" "#"
  jq . <<<"$next" >"$file.omahub-tmp" && mv "$file.omahub-tmp" "$file"
}

omahub_hook_on() {
  local file="$1" event="$2" matcher="$3" command="${4:-$(omahub_hook_command)}" timeout="${5:-10}" current
  current=$(omahub_hook_read "$file")
  if [[ $file == "$OMAHUB_CODEX_HOOKS" && ! -e $file ]]; then
    mkdir -p "$OMAHUB_STATE_DIR"
    touch "$OMAHUB_CODEX_HOOKS_CREATED"
  fi
  omahub_hook_write "$file" "$(jq -c --arg event "$event" --arg matcher "$matcher" --arg command "$command" --argjson timeout "$timeout" '
    if any(.hooks[$event][]?.hooks[]?; .command == $command) then .
    else .hooks[$event] = ((.hooks[$event] // []) + [{
      matcher: $matcher,
      hooks: [{type: "command", command: $command, timeout: $timeout}]
    }]) end' <<<"$current")"
}

omahub_hook_off() {
  local file="$1" event="$2" command="${3:-$(omahub_hook_command)}" current next
  [[ -e $file ]] || return 0
  current=$(omahub_hook_read "$file")
  next=$(jq -c --arg event "$event" --arg command "$command" '
    if (.hooks[$event] | type) != "array" then .
    else
      .hooks[$event] |= (map(if (.hooks | type) == "array" then .hooks |= map(select(.command != $command)) else . end)
        | map(select((.hooks | type) != "array" or (.hooks | length) > 0)))
      | if (.hooks[$event] | length) == 0 then del(.hooks[$event]) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    end' <<<"$current")
  if [[ $file == "$OMAHUB_CODEX_HOOKS" && $next == "{}" && -e $OMAHUB_CODEX_HOOKS_CREATED ]]; then
    rm -f "$file" "$OMAHUB_CODEX_HOOKS_CREATED"
    return 0
  fi
  omahub_hook_write "$file" "$next"
}
