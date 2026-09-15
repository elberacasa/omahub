#!/bin/bash

# The pet parade, for a looping teaser: all seven pets on the stage in their own colors pop in one after
# another, type in a wave, finish with a cascade of hops, one calls you and is answered, they doze off, and
# they wake back to where the loop began. Nothing reads or touches an agent.
#
#   bash dev/demos/pets-parade.sh [pixel]    run it while recording, for example
#   dev/take pets-parade 16 --quiet --run "bash dev/demos/pets-parade.sh 14"

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PIXEL="${1:-14}"
LOOKS=(blob cat gem bunny fox owl robot)

stage() {
  "$ROOT/dev/pet-stage" "$@" >/dev/null
}

# Every pet at once in one mood, as a stage payload.
all() {
  jq -nc --arg mood "$1" --argjson pixel "$PIXEL" \
    '{pixel: $pixel, gap: 5, background: "theme", pets: (["blob", "cat", "gem", "bunny", "fox", "owl", "robot"] | map({look: ., mood: $mood}))}'
}

# One pet after another into a mood, a beat apart, left to right.
wave() {
  local mood="$1" beat="$2" index
  for index in "${!LOOKS[@]}"; do
    stage mood "$index" "$mood"
    sleep "$beat"
  done
}

stage show "$(all "")"
sleep 0.6
wave agent 0.09
sleep 0.7
wave working 0.07
sleep 1.6
wave done 0.14
sleep 1.1
stage mood 4 waiting
sleep 1.3
stage mood 4 working
sleep 0.5
stage mood 4 done
sleep 0.9
wave idle 0.08
sleep 2.2
wave agent 0.06
sleep 0.9
stage close
