#!/bin/bash

# Get or set the folder screenshots are saved to, and move a screenshot there.
#
#   screenshot-dir.sh get                    Print the current folder
#   screenshot-dir.sh set <folder>           Save future screenshots there
#   screenshot-dir.sh reset                  Go back to Omarchy's default folder
#   screenshot-dir.sh places                 Print quick folder choices as JSON
#   screenshot-dir.sh move <file> [folder]   Move a screenshot and make its folder the default.
#                                            Without a folder, ask with the desktop folder chooser.
#
# The choice is stored the way Omarchy documents it: OMARCHY_SCREENSHOT_DIR in
# ~/.config/uwsm/default, inside a marked block. That file is read at login, so a copy
# also goes to Omahub's state for capture.sh to use right away.

set -euo pipefail

ENV_FILE="$HOME/.config/uwsm/default"
STATE_FILE="$HOME/.local/state/omahub/screenshot-dir"
START="# omahub:screenshot-dir:start"
END="# omahub:screenshot-dir:end"

fail() {
  echo "screenshot-dir.sh: $*" >&2
  exit 1
}

remove_block() {
  [[ -f $ENV_FILE ]] || return 0
  sed -i "/^$START\$/,/^$END\$/d" "$ENV_FILE"
  [[ -s $ENV_FILE ]] || rm -f "$ENV_FILE"
}

# Back up only when the file holds something besides our block and differs from the last backup.
backup_env_file() {
  [[ -s $ENV_FILE ]] || return 0
  sed "/^$START\$/,/^$END\$/d" "$ENV_FILE" | grep -q . || return 0

  local latest
  latest=$(ls -t "$ENV_FILE".bak.* 2>/dev/null | head -1 || true)
  if [[ -z $latest ]] || ! cmp -s "$ENV_FILE" "$latest"; then
    cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
  fi
}

current() {
  if [[ -f $STATE_FILE ]]; then
    cat "$STATE_FILE"
  elif [[ -n ${OMARCHY_SCREENSHOT_DIR:-} ]]; then
    echo "$OMARCHY_SCREENSHOT_DIR"
  else
    [[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
    echo "${XDG_PICTURES_DIR:-$HOME/Pictures}"
  fi
}

set_folder() {
  local dir
  dir=$(realpath -m -- "$1")
  mkdir -p "$dir" "$(dirname "$ENV_FILE")" "$(dirname "$STATE_FILE")"
  backup_env_file
  remove_block
  printf '%s\nexport OMARCHY_SCREENSHOT_DIR=%q\n%s\n' "$START" "$dir" "$END" >>"$ENV_FILE"
  printf '%s\n' "$dir" >"$STATE_FILE"
  echo "$dir"
}

places() {
  local now pictures
  now=$(current)
  now=${now%/}
  pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")

  {
    printf '%s\n' "$now" "$pictures/Screenshots" "$pictures"
    for kind in DOWNLOAD DOCUMENTS DESKTOP; do
      xdg-user-dir "$kind" 2>/dev/null || true
    done
  } | while IFS= read -r dir; do
    dir=${dir%/}
    if [[ -n $dir && ( $dir == "$now" || ( -d $dir && $dir != "$HOME" ) ) ]]; then
      printf '%s\n' "$dir"
    fi
  done | awk '!seen[$0]++' | head -5 | jq -R -s --arg now "$now" --arg home "$HOME" '
    split("\n") | map(select(length > 0)) | map({
      path: .,
      name: (if . == $home then "Home" else (split("/") | last) end),
      current: (. == $now)
    })'
}

move_file() {
  local file="$1" dir="${2:-}" base stem ext target n=1
  [[ -f $file ]] || fail "no such file: $file"

  if [[ -z $dir ]]; then
    dir=$(omarchy-file-select --directory --title "Save screenshots to") || exit 0
  fi
  dir=$(set_folder "$dir")

  base=$(basename -- "$file")
  target="$dir/$base"
  if [[ $(realpath -- "$file") != "$(realpath -m -- "$target")" ]]; then
    stem=${base%.*}
    ext=${base##*.}
    while [[ -e $target ]]; do
      target="$dir/$stem-$n.$ext"
      n=$((n + 1))
    done
    mv -- "$file" "$target"
  fi
  printf '%s\n' "$target"
}

case "${1:-get}" in
  get) current ;;
  set)
    [[ -n ${2:-} ]] || fail "usage: screenshot-dir.sh set <folder>"
    set_folder "$2"
    ;;
  reset)
    remove_block
    rm -f "$STATE_FILE"
    current
    ;;
  places) places ;;
  move)
    [[ -n ${2:-} ]] || fail "usage: screenshot-dir.sh move <file> [folder]"
    move_file "$2" "${3:-}"
    ;;
  *) fail "unknown command '$1', expected get, set, reset, places, or move" ;;
esac
