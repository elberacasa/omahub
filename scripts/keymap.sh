#!/bin/bash

# Switch the Hyprland keyboard layout that Omahub manages.
#
#   keymap.sh status    Print the active layout: mac, omarchy, or off
#   keymap.sh mac       Omahub hotkey plus the Mac layout
#   keymap.sh omarchy   Omahub hotkey on top of Omarchy's defaults
#   keymap.sh off       Remove everything Omahub added
#
# Omahub owns only the marked block in ~/.config/hypr/bindings.lua. The file is backed up
# before every change, and restored if Hyprland reports config errors after reloading.

set -euo pipefail

BINDINGS="$HOME/.config/hypr/bindings.lua"
START="-- omahub:keymap:start"
END="-- omahub:keymap:end"

fail() {
  echo "keymap.sh: $*" >&2
  exit 1
}

current_layout() {
  if ! grep -qxF -e "$START" "$BINDINGS"; then
    echo "off"
  elif sed -n "/^$START\$/,/^$END\$/p" "$BINDINGS" | grep -qF '"mac"'; then
    echo "mac"
  else
    echo "omarchy"
  fi
}

remove_block() {
  sed -i "/^$START\$/,/^$END\$/d" "$BINDINGS"
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$BINDINGS"
}

append_block() {
  local files="$1"

  cat >>"$BINDINGS" <<EOF

$START
-- Managed by Omahub. Switch layouts in Omahub instead of editing this block.
do
  local dir = (os.getenv("HOME") or "") .. "/.config/omarchy/plugins/io.github.elberacasa.omahub/keymaps/"
  for _, name in ipairs({ $files }) do
    local path = dir .. name .. ".lua"
    local file = io.open(path)
    if file then
      file:close()
      dofile(path)
    end
  end
end
$END
EOF
}

reload_or_restore() {
  local backup="$1"

  hyprctl reload >/dev/null
  if [[ -n $(hyprctl configerrors 2>/dev/null | grep -v '^\s*$') ]]; then
    cp "$backup" "$BINDINGS"
    hyprctl reload >/dev/null
    fail "Hyprland reported config errors, restored $backup"
  fi
}

[[ -f $BINDINGS ]] || fail "missing $BINDINGS"

target="${1:-status}"

case "$target" in
  status)
    current_layout
    exit 0
    ;;
  mac) files='"hotkey", "mac"' ;;
  omarchy) files='"hotkey"' ;;
  off) files="" ;;
  *) fail "unknown layout '$target', expected status, mac, omarchy, or off" ;;
esac

[[ $(current_layout) == "$target" ]] && exit 0

backup="$BINDINGS.bak.$(date +%s)"
cp "$BINDINGS" "$backup"

remove_block
[[ -n $files ]] && append_block "$files"

reload_or_restore "$backup"
echo "$target"
