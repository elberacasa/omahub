#!/bin/bash

# dev/agent, its virtual keyboard, and the live checks: they parse, the keyboard builds, and nothing
# acts on the desktop without a sandbox.

source "$(dirname "$0")/../base-test.sh"

agent="$OMAHUB_PATH/dev/agent"

contains() {
  local name="$1" file="$2" text="$3"
  if grep -qF -- "$text" "$file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

for function in inspect dismiss; do
  contains "Omahub.qml answers $function" "$OMAHUB_PATH/Omahub.qml" "function $function("
  contains "dev/agent uses $function" "$agent" "$function"
done
contains "the hub reports its state" "$OMAHUB_PATH/hub/Hub.qml" "function stateJson("
contains "the thumbnail reports its state" "$OMAHUB_PATH/capture/Capture.qml" "function stateJson("

if bash -n "$agent" && bash -n "$OMAHUB_PATH/dev/live" && bash -n "$OMAHUB_PATH/test/live-lib.sh"; then
  pass "dev/agent, dev/live, and the live helpers parse"
else
  fail "dev/agent, dev/live, and the live helpers parse"
fi

for check in "$OMAHUB_PATH"/test/live.d/*-live.sh; do
  if bash -n "$check"; then
    pass "${check##*/} parses"
  else
    fail "${check##*/} parses"
  fi
done

for action in "chord u" "hold SUPER" "click dock.overview" "drag 1,1 2,2" "call dismiss"; do
  # shellcheck disable=SC2086
  output=$("$agent" $action 2>&1 || true)
  if [[ $output == *"start a sandbox first"* ]]; then
    pass "dev/agent $action needs a sandbox"
  else
    fail "dev/agent $action needs a sandbox"
  fi
done

if command -v gcc >/dev/null && command -v wayland-scanner >/dev/null && pkg-config --exists wayland-client xkbcommon; then
  build="$TEST_ROOT/keyboard"
  mkdir -p "$build"
  protocol="$OMAHUB_PATH/dev/keyboard/virtual-keyboard-unstable-v1.xml"
  wayland-scanner client-header "$protocol" "$build/virtual-keyboard-unstable-v1-client-protocol.h"
  wayland-scanner private-code "$protocol" "$build/virtual-keyboard-unstable-v1-protocol.c"
  # shellcheck disable=SC2046
  if gcc -O2 -Wall -Wextra -Werror -I"$build" -o "$build/omahub-keyboard" "$OMAHUB_PATH/dev/keyboard/keyboard.c" \
      "$build/virtual-keyboard-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client xkbcommon) 2>"$build/errors"; then
    pass "the virtual keyboard builds without warnings"
  else
    fail "the virtual keyboard builds without warnings: $(head -3 "$build/errors")"
  fi
else
  pass "gcc, wayland-scanner, or xkbcommon is missing, so the keyboard build is skipped"
fi

finish
