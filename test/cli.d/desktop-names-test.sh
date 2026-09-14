#!/bin/bash

# omahub desktop: names people give desktops, kept by Omahub.

source "$(dirname "$0")/../base-test.sh"

assert_eq "no names to start" "$(omahub desktop names)" "{}"
assert_eq "a desktop gets a name" "$(omahub desktop name 3 'Launch week')" '{"3":"Launch week"}'
assert_eq "names are listed" "$(omahub desktop names)" '{"3":"Launch week"}'
assert_eq "spaces around a name are dropped" "$(omahub desktop name 4 '  orbit api  ' | jq -r '.["4"]')" "orbit api"
assert_eq "a name with no text clears it" "$(omahub desktop name 4 '')" '{"3":"Launch week"}'
assert_eq "clearing the last name removes the file" "$(omahub desktop name 3 >/dev/null; ls "$HOME/.local/state/omahub/desktops.json" 2>/dev/null | wc -l)" "0"

if omahub desktop name zero "Nope" 2>"$TEST_ROOT/stderr"; then
  fail "a desktop number must be a number"
else
  pass "a desktop number must be a number"
fi
if omahub desktop name 2 "$(printf 'x%.0s' {1..41})" 2>/dev/null; then
  fail "a name longer than 40 characters is refused"
else
  pass "a name longer than 40 characters is refused"
fi

omahub desktop name 5 "$(printf 'one\ntwo')" >/dev/null
assert_eq "a name stays on one line" "$(omahub desktop names | jq -r '.["5"]')" "onetwo"

finish
