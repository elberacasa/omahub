#!/bin/bash

# Helpers for live checks. dev/live runs them inside a sandbox with test windows a and b on its home
# desktop and c on its away desktop. Each section starts from rest.

LIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE_FAILURES=0

agent() {
  "$LIVE_ROOT/dev/agent" "$@"
}

# check <name> <jq on dev/agent state> [seconds to wait for it]
check() {
  agent expect "$@" || LIVE_FAILURES=$((LIVE_FAILURES + 1))
}

section() {
  echo "$1"
  agent reset
}

skip() {
  echo "  skip  $1"
}

# The number key that reaches a desktop, 0 for 10.
number_key() {
  echo $(( $1 % 10 ))
}

# The desktop a test window is on, as a jq expression.
on_desktop() {
  echo "(.windows[] | select(.class == \"omahub-demo-$1\") | .desktop)"
}

finish_live() {
  (( LIVE_FAILURES == 0 ))
}
