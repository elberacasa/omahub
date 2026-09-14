#!/bin/bash

# The screenshot thumbnail on the live desktop, with a generated image instead of a real screenshot:
# it appears, its menu opens from the keyboard and closes, and it leaves on its own.

source "$(dirname "$0")/../live-lib.sh"

section "The thumbnail is on"
if ! command -v magick >/dev/null; then
  skip "ImageMagick is missing, so there is no image to show"
  exit 0
fi

image="$LIVE_ROOT/tmp/agent/capture-check.png"
magick -size 1600x900 gradient:'#1a1b26-#7aa2f7' "$image"

section "A screenshot shows its thumbnail"
agent call open "{\"capture\":{\"path\":\"$image\"}}" >/dev/null
check "the thumbnail shows the file" '.omahub.capture.shown and .omahub.capture.file == "capture-check.png"' 3

section "SHIFT + PRINT opens the thumbnail's menu, and Esc closes it"
agent call open "{\"capture\":{\"path\":\"$image\"}}" >/dev/null
check "the thumbnail shows" '.omahub.capture.shown' 3
agent chord SHIFT+PRINT
check "the menu opens" '.omahub.capture.menu' 2
agent chord Escape
check "Esc closes the menu and keeps the thumbnail" '(.omahub.capture.menu | not) and .omahub.capture.shown' 2

section "The thumbnail leaves on its own"
agent call open "{\"capture\":{\"path\":\"$image\"}}" >/dev/null
check "the thumbnail shows" '.omahub.capture.shown' 3
check "it leaves after a few seconds" '.omahub.capture.shown | not' 15

rm -f "$image"
finish_live
