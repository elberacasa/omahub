#!/bin/bash

# Keyboard layers that Omahub loads from one marked block in ~/.config/hypr/bindings.lua.
# A layer is a file in keymaps/: "hotkey" adds SUPER + A, "mac" adds the Mac screenshot keys.
# Requires lib/settings.sh.

OMAHUB_BINDINGS="$HOME/.config/hypr/bindings.lua"
OMAHUB_KEYMAP_ORDER=(hotkey mac)

omahub_keymap_layers() {
  omahub_block_read "$OMAHUB_BINDINGS" keymap "--" | grep -oE '"(hotkey|mac)"' | tr -d '"' || true
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

# Turn one layer on or off, then reload Hyprland. Restores the backup if Hyprland reports
# config errors afterwards.
omahub_keymap_set() {
  local layer="$1" wanted="$2" name layers="" current backup

  [[ -f $OMAHUB_BINDINGS ]] || omahub_fail "missing $OMAHUB_BINDINGS"

  current=$(omahub_keymap_layers)
  for name in "${OMAHUB_KEYMAP_ORDER[@]}"; do
    if [[ $name == "$layer" ]]; then
      if [[ $wanted == "on" ]]; then
        layers+="${layers:+, }\"$name\""
      fi
    elif grep -qx -- "$name" <<<"$current"; then
      layers+="${layers:+, }\"$name\""
    fi
  done

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
    cp "$backup" "$OMAHUB_BINDINGS"
    hyprctl reload >/dev/null
    rm -f "$backup"
    omahub_fail "Hyprland reported config errors, so the change was undone"
  fi
  rm -f "$backup"
}
