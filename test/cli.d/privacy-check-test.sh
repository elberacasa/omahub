#!/bin/bash

# dev/privacy-check: finds a planted word in an image and a video, passes clean media, and never
# prints the words it found.

source "$(dirname "$0")/../base-test.sh"

check="$OMAHUB_PATH/dev/privacy-check"

if ! command -v tesseract >/dev/null || ! command -v ffmpeg >/dev/null || ! command -v magick >/dev/null; then
  pass "tesseract, ffmpeg, or ImageMagick is missing, so the privacy checks are skipped"
  finish
fi

media="$TEST_ROOT/media"
mkdir -p "$media"
magick -size 1200x300 xc:white -fill black -pointsize 64 -annotate +40+180 "deploy studio-secret-4821 now" "$media/leak.png"
magick -size 1200x300 xc:white -fill black -pointsize 64 -annotate +40+180 "orbit api tests passed" "$media/clean.png"
ffmpeg -loglevel error -loop 1 -i "$media/leak.png" -t 1 -r 4 -pix_fmt yuv420p -vf "scale=1200:300" "$media/leak.mp4"

output=$("$check" "$media/leak.png" --word studio-secret-4821 2>&1 || true)
if [[ $output == *"a word you gave"* ]]; then
  pass "a planted word in an image is found"
else
  fail "a planted word in an image is found"
fi
if [[ $output != *"studio-secret-4821"* ]]; then
  pass "the report names the kind of data, never the data"
else
  fail "the report names the kind of data, never the data"
fi

if "$check" "$media/leak.png" --word studio-secret-4821 >/dev/null 2>&1; then
  fail "a hit fails the check"
else
  pass "a hit fails the check"
fi

output=$("$check" "$media/leak.mp4" --word studio-secret-4821 2>&1 || true)
if [[ $output == *"0.0s: a word you gave"* ]]; then
  pass "a planted word in a video is found with its time"
else
  fail "a planted word in a video is found with its time"
fi

if "$check" "$media/clean.png" --word studio-secret-4821 >/dev/null 2>&1; then
  pass "clean media passes"
else
  fail "clean media passes"
fi

finish
