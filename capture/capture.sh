#!/bin/bash

# Take a screenshot with Omarchy and show it as a floating thumbnail.
# Usage: capture.sh [region|windows|fullscreen]

set -euo pipefail

ID="io.github.elberacasa.omahub-capture"
mode="${1:-region}"

# A folder chosen in Capture applies right away, before the next login picks it up.
folder_state="$HOME/.local/state/omahub/screenshot-dir"
[[ -f $folder_state ]] && export OMARCHY_SCREENSHOT_DIR="$(<"$folder_state")"

path=$(omarchy-capture-screenshot "$mode" save) || exit 0
[[ -n $path && -f $path ]] || exit 0

payload=$(jq -nc --arg path "$path" '{path: $path}')

if ! omarchy-shell shell summon "$ID" "$payload" >/dev/null 2>&1; then
  omarchy-notification-send "Screenshot saved" "$path" --image "$path"
fi
