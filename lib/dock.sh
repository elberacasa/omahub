#!/bin/bash

# The dock's settings and pinned apps live in one JSON file that the dock watches, so a change from
# the hub, the terminal, or an agent shows at once. Pins are desktop entry ids, in order, and start
# from Omarchy's default terminal, browser, file manager, and editor.

OMAHUB_DOCK_FILE="$OMAHUB_STATE_DIR/dock.json"

source "$OMAHUB_PATH/lib/keymap.sh"

# SUPER + D reaches the dock only while it is on. Without a bindings file the dock still works, just
# without its key.
omahub_dock_key() {
  if [[ -f $OMAHUB_BINDINGS ]]; then
    omahub_keymap_set dock "$1"
  fi
}

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

# The current value of a dock choice, one of its values. A switch saved before the setting became a
# choice reads as the default when it was on, and as off when it was off.
omahub_dock_choice() {
  local key="$1" default="$2" choices="$3" value
  value=$(omahub_dock_flag "$key" "\"$default\"")
  if [[ $value == "false" && " $choices " == *" off="* ]]; then
    value="off"
  fi
  if [[ " $choices " != *" $value="* ]]; then
    value="$default"
  fi
  printf '%s\n' "$value"
}

# The get, options, set, and reset verbs of a dock choice stored under <key>. Choices are given as
# "value=Label" words, for example "small=Small medium=Medium large=Large".
omahub_dock_choice_setting() {
  local key="$1" default="$2" choices="$3" id="$4" verb="${5:-}" value="${6:-}" current pair

  case "$verb" in
    get) ;;
    options)
      current=$(omahub_dock_choice "$key" "$default" "$choices")
      for pair in $choices; do
        jq -nc --arg value "${pair%%=*}" --arg label "${pair#*=}" --arg current "$current" \
          '{value: $value, label: $label, current: ($value == $current)}'
      done | jq -sc '.'
      return
      ;;
    set)
      if [[ -z $value || " $choices " != *" $value="* ]]; then
        omahub_fail "'$value' is not one of the choices. Use: omahub set $id $(tr ' ' '\n' <<<"$choices" | cut -d= -f1 | paste -sd '|')"
      fi
      omahub_dock_update --arg key "$key" --arg value "$value" '.[$key] = $value'
      ;;
    reset) omahub_dock_update --arg key "$key" 'del(.[$key])' ;;
    *) omahub_fail "usage: omahub get|set|options|reset $id" ;;
  esac

  current=$(omahub_dock_choice "$key" "$default" "$choices")
  for pair in $choices; do
    if [[ ${pair%%=*} == "$current" ]]; then
      omahub_state "$(jq -nc --arg value "$current" '$value')" "${pair#*=}"
    fi
  done
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
            # The key comes first, so a key that cannot be added leaves the dock off rather than half on.
            omahub_dock_key on
            omahub_dock_ensure_pins
          fi
          omahub_dock_update --arg key "$key" '.[$key] = true'
          ;;
        off | false)
          omahub_dock_update --arg key "$key" '.[$key] = false'
          if [[ $key == "show" ]]; then
            omahub_dock_key off
          fi
          ;;
        *) omahub_fail "'$value' is not on or off. Use: omahub set $id on|off" ;;
      esac
      ;;
    reset)
      omahub_dock_update --arg key "$key" 'del(.[$key])'
      if [[ $key == "show" && $default != "true" ]]; then
        omahub_dock_key off
      fi
      ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if [[ $(omahub_dock_flag "$key" "$default") == "true" ]]; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}
