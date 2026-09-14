#!/bin/bash

# The dock's settings and pinned apps live in one JSON file that the dock watches, so a change from
# the hub, the terminal, or an agent shows at once. Pins are desktop entry ids, in order, and start
# from Omarchy's default terminal, browser, file manager, and editor.

OMAHUB_DOCK_FILE="$OMAHUB_STATE_DIR/dock.json"

omahub_dock_read() {
  if [[ -s $OMAHUB_DOCK_FILE ]] && jq -e 'type == "object"' "$OMAHUB_DOCK_FILE" >/dev/null 2>&1; then
    cat "$OMAHUB_DOCK_FILE"
  else
    echo '{}'
  fi
}

# Apply a jq program to the dock file, for example: omahub_dock_update --arg id x '.pins += [$id]'.
# An empty result removes the file, so reset leaves no trace. The dock is told to reload right away.
omahub_dock_update() {
  local next
  next=$(omahub_dock_read | jq -c "$@")
  mkdir -p "$OMAHUB_STATE_DIR"
  if [[ $next == "{}" ]]; then
    rm -f "$OMAHUB_DOCK_FILE"
  else
    printf '%s\n' "$next" >"$OMAHUB_DOCK_FILE"
  fi
  omarchy-shell shell call "$OMAHUB_PLUGIN_ID" dockReload "" >/dev/null 2>&1 || true
}

omahub_dock_flag() {
  local key="$1" default="$2"
  omahub_dock_read | jq -r --arg key "$key" --argjson default "$default" 'if has($key) then .[$key] else $default end'
}

omahub_dock_app_dirs() {
  local dir
  printf '%s\n' "$HOME/.local/share/applications"
  while IFS= read -r -d ':' dir; do
    if [[ -n $dir ]]; then
      printf '%s\n' "$dir/applications"
    fi
  done <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:"
}

omahub_dock_app_exists() {
  local id="$1" dir
  if [[ ! $id =~ ^[A-Za-z0-9][A-Za-z0-9._@+-]*$ ]]; then
    return 1
  fi
  while IFS= read -r dir; do
    if [[ -f $dir/$id.desktop ]]; then
      return 0
    fi
  done < <(omahub_dock_app_dirs)
  return 1
}

# The desktop entry for a command: a file named after it, or the first entry that runs it.
omahub_dock_entry_for_command() {
  local command="$1" dir file
  if [[ -z $command ]]; then
    return 0
  fi
  if omahub_dock_app_exists "$command"; then
    printf '%s\n' "$command"
    return 0
  fi
  while IFS= read -r dir; do
    file=$(grep -l -E "^Exec=(\S*/)?$command( |$)" "$dir"/*.desktop 2>/dev/null | head -1 || true)
    if [[ -n $file ]]; then
      basename "$file" .desktop
      return 0
    fi
  done < <(omahub_dock_app_dirs)
}

omahub_dock_default_pins() {
  local terminal browser files editor
  terminal=$(omahub_dock_entry_for_command "$(omarchy-default-terminal 2>/dev/null || true)")
  browser=$(xdg-settings get default-web-browser 2>/dev/null || true)
  files=$(xdg-mime query default inode/directory 2>/dev/null || true)
  editor=$(omahub_dock_entry_for_command "$(omarchy-default-editor 2>/dev/null || true)")
  printf '%s\n' "$terminal" "${browser%.desktop}" "${files%.desktop}" "$editor" \
    | while IFS= read -r id; do
        if [[ -n $id ]] && omahub_dock_app_exists "$id"; then
          printf '%s\n' "$id"
        fi
      done \
    | awk '!seen[$0]++' | jq -Rsc 'split("\n") | map(select(length > 0))'
}

omahub_dock_ensure_pins() {
  if [[ $(omahub_dock_read | jq 'has("pins")') != "true" ]]; then
    omahub_dock_update --argjson pins "$(omahub_dock_default_pins)" '.pins = $pins'
  fi
}

omahub_dock_pins() {
  if [[ $(omahub_dock_read | jq 'has("pins")') == "true" ]]; then
    omahub_dock_read | jq -c '.pins'
  else
    omahub_dock_default_pins
  fi
}

omahub_dock_pin() {
  local id="$1"
  if ! omahub_dock_app_exists "$id"; then
    omahub_fail "no app named '$id'. Use the name of its .desktop file, such as org.gnome.Nautilus"
  fi
  omahub_dock_ensure_pins
  omahub_dock_update --arg id "$id" 'if (.pins | index($id)) then . else .pins += [$id] end'
}

omahub_dock_unpin() {
  omahub_dock_ensure_pins
  omahub_dock_update --arg id "$1" '.pins -= [$id]'
}

# The get, set, and reset verbs of a dock switch stored under <key>, with its default.
omahub_dock_toggle_setting() {
  local key="$1" default="$2" id="$3" verb="${4:-}" value="${5:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true)
          if [[ $key == "show" ]]; then
            omahub_dock_ensure_pins
          fi
          omahub_dock_update --arg key "$key" '.[$key] = true'
          ;;
        off | false) omahub_dock_update --arg key "$key" '.[$key] = false' ;;
        *) omahub_fail "usage: omahub set $id on|off" ;;
      esac
      ;;
    reset) omahub_dock_update --arg key "$key" 'del(.[$key])' ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if [[ $(omahub_dock_flag "$key" "$default") == "true" ]]; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}
