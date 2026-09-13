#!/bin/bash

# Take a screenshot with Omarchy and show it as Omahub's floating thumbnail.
# Usage: capture.sh [smart|region|windows|fullscreen]

set -euo pipefail

ID="io.github.elberacasa.omahub"
mode="${1:-region}"

# A folder chosen in Capture applies right away, before the next login picks it up.
folder_state="$HOME/.local/state/omahub/screenshot-dir"
if [[ -f $folder_state ]]; then
  export OMARCHY_SCREENSHOT_DIR="$(<"$folder_state")"
fi

if ! path=$(omarchy-capture-screenshot "$mode" save) || [[ -z $path || ! -f $path ]]; then
  exit 0
fi

payload=$(jq -nc --arg path "$path" '{capture: {path: $path}}')

if ! omarchy-shell shell summon "$ID" "$payload" >/dev/null 2>&1; then
  omarchy-notification-send "Screenshot saved" "$path" --image "$path"
fi
