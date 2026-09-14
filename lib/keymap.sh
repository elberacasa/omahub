#!/bin/bash

# Keyboard layers that Omahub loads from one marked block in ~/.config/hypr/bindings.lua.
# Each layer is a file in keymaps/, loaded in a fixed order. Requires lib/settings.sh.

OMAHUB_BINDINGS="$HOME/.config/hypr/bindings.lua"
OMAHUB_KEYMAP_ORDER=(hotkey thumbnail overview mac vim agents mouse)

omahub_keymap_layers() {
  local names
  names=$(IFS='|'; echo "${OMAHUB_KEYMAP_ORDER[*]}")
  omahub_block_read "$OMAHUB_BINDINGS" keymap "--" | grep -oE "\"($names)\"" | tr -d '"' || true
}

omahub_keymap_has() {
  omahub_keymap_layers | grep -qx -- "$1"
}

omahub_keymap_block() {
  local layers="$1"
  cat <<EOF
-- Managed by Omahub. Change it in Omahub instead of editing this block.
do
  local dir = (os.getenv("HOME") or "") .. "/.config/omarchy/plugins/$OMAHUB_PLUGIN_ID/keymaps/"
  for _, name in ipairs({ $layers }) do
    local path = dir .. name .. ".lua"
    local file = io.open(path)
    if file then
      file:close()
      dofile(path)
    end
  end
end
EOF
}

# Every action Omarchy currently has a key for, one description per line.
omahub_keymap_descriptions() {
  omarchy menu keybindings --print 2>/dev/null \
    | awk -F'→' 'NF > 1 { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2 }' \
    | sort -u
}

# Actions a layer adds with a literal description, which turning the layer off may remove.
omahub_keymap_layer_descriptions() {
  grep -ohE 'o\.bind\("[^"]+", "[^"]+"' "$OMAHUB_PATH/keymaps/$1.lua" 2>/dev/null \
    | sed -E 's/^o\.bind\("[^"]+", "([^"]+)"$/\1/' \
    | sort -u
}

omahub_keymap_restore() {
  cp "$1" "$OMAHUB_BINDINGS"
  rm -f "$1"
  hyprctl reload >/dev/null
}

# Turn one layer on or off and reload Hyprland. The change is undone when Hyprland reports
# config errors, or when any action that had a key loses it.
omahub_keymap_set() {
  local layer="$1" wanted="$2" name layers="" current backup before after allowed missing

  [[ -f $OMAHUB_BINDINGS ]] || omahub_fail "missing $OMAHUB_BINDINGS"

  current=$(omahub_keymap_layers)
  if [[ $wanted == "on" ]] && grep -qx -- "$layer" <<<"$current"; then
    return 0
  elif [[ $wanted == "off" ]] && ! grep -qx -- "$layer" <<<"$current"; then
    return 0
  fi

  for name in "${OMAHUB_KEYMAP_ORDER[@]}"; do
    if [[ $name == "$layer" ]]; then
      if [[ $wanted == "on" ]]; then
        layers+="${layers:+, }\"$name\""
      fi
    elif grep -qx -- "$name" <<<"$current"; then
      layers+="${layers:+, }\"$name\""
    fi
  done

  before=$(omahub_keymap_descriptions)
  omahub_backup "$OMAHUB_BINDINGS" "--"
  backup=$(mktemp)
  cp "$OMAHUB_BINDINGS" "$backup"

  if [[ -n $layers ]]; then
    omahub_keymap_block "$layers" | omahub_block_write "$OMAHUB_BINDINGS" keymap "--"
  else
    omahub_block_remove "$OMAHUB_BINDINGS" keymap "--"
    touch "$OMAHUB_BINDINGS"
  fi

  hyprctl reload >/dev/null
  if [[ -n $(hyprctl configerrors 2>/dev/null | grep -v '^\s*$') ]]; then
    omahub_keymap_restore "$backup"
    omahub_fail "Hyprland reported config errors, so the change was undone"
  fi
  sleep 0.2

  after=$(omahub_keymap_descriptions)
  if [[ $wanted == "off" ]]; then
    allowed=$(omahub_keymap_layer_descriptions "$layer")
  else
    allowed=""
  fi
  missing=$(comm -23 <(sed '/^$/d' <<<"$before") <(sed '/^$/d' <<<"$after") | grep -vxF -f <(sed '/^$/d' <<<"$allowed") || true)

  if [[ -n $missing ]]; then
    omahub_keymap_restore "$backup"
    omahub_fail "the change was undone because these actions would lose their keys: $(paste -sd '|' <<<"$missing" | sed 's/|/, /g')"
  fi
  rm -f "$backup"
}

# Run a toggle setting backed by one layer: omahub_keymap_toggle_setting <layer> <id> <verb> [value]
omahub_keymap_toggle_setting() {
  local layer="$1" id="$2" verb="${3:-}" value="${4:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true) omahub_keymap_set "$layer" on ;;
        off | false) omahub_keymap_set "$layer" off ;;
        *) omahub_fail "usage: omahub set $id on|off" ;;
      esac
      ;;
    reset) omahub_keymap_set "$layer" off ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if omahub_keymap_has "$layer"; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}
