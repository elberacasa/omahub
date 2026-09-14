#!/bin/bash

# Names people give desktops. Omahub keeps them itself, since Hyprland forgets a desktop's name when
# the desktop closes as it empties, and the overview and the dock read them. Requires lib/settings.sh.

OMAHUB_DESKTOPS_FILE="$OMAHUB_STATE_DIR/desktops.json"
OMAHUB_DESKTOP_NAME_LIMIT=40

omahub_desktops_read() {
  if [[ -s $OMAHUB_DESKTOPS_FILE ]] && jq -e 'type == "object"' "$OMAHUB_DESKTOPS_FILE" >/dev/null 2>&1; then
    cat "$OMAHUB_DESKTOPS_FILE"
  else
    echo '{}'
  fi
}

omahub_desktop_names() {
  omahub_desktops_read | jq -c '.names // {}'
}

# omahub_desktop_name <number> [name]: give a desktop a name, or clear it with no name.
omahub_desktop_name() {
  local id="${1:-}" name="${2:-}" next temporary
  if [[ ! $id =~ ^[1-9][0-9]*$ ]]; then
    omahub_fail "'$id' is not a desktop number. Use: omahub desktop name <number> [name]"
  fi
  # One line, without control characters or the spaces around it.
  name=$(printf '%s' "$name" | tr -d '\000-\037\177' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if (( ${#name} > OMAHUB_DESKTOP_NAME_LIMIT )); then
    omahub_fail "Keep a desktop's name to $OMAHUB_DESKTOP_NAME_LIMIT characters"
  fi

  next=$(omahub_desktops_read | jq -c --arg id "$id" --arg name "$name" '
    (if $name == "" then del(.names[$id]) else .names[$id] = $name end)
    | if (.names // {}) == {} then del(.names) else . end')
  mkdir -p "$OMAHUB_STATE_DIR"
  if [[ $next == "{}" ]]; then
    rm -f "$OMAHUB_DESKTOPS_FILE"
  else
    # Written whole and then moved into place, so the overview never reads half a file.
    temporary=$(mktemp "$OMAHUB_STATE_DIR/.desktops.XXXXXX")
    printf '%s\n' "$next" >"$temporary"
    mv "$temporary" "$OMAHUB_DESKTOPS_FILE"
  fi
  omahub_desktop_names
}
