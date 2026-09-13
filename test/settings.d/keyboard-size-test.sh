#!/bin/bash

# keyboard/size detects the keyboard and recommends layers for it.

source "$(dirname "$0")/../base-test.sh"

export OMAHUB_INPUT_DEVICES="$TEST_ROOT/devices"

keyboard() {
  cat <<EOF
I: Bus=$1 Vendor=$2 Product=$3 Version=0110
N: Name="$4"
H: Handlers=sysrq kbd leds event3
B: EV=120013

EOF
}

mouse() {
  cat <<EOF
I: Bus=0003 Vendor=046d Product=c099 Version=0111
N: Name="Example Mouse"
H: Handlers=mouse2 event8
B: EV=17
B: KEY=$1 0 0 0 0

EOF
}

virtual_keyboard() {
  cat <<'EOF'
I: Bus=0003 Vendor=0fac Product=0ade Version=0000
N: Name="keyd virtual keyboard"
H: Handlers=sysrq kbd leds event16
B: EV=120003

EOF
}

recommends() {
  omahub get keyboard/size | jq -e --arg id "$1" '.recommended | index($id) != null'
}

{ virtual_keyboard; keyboard 0003 2e3c c365 "WIN 60 HE"; mouse 1f0000; } >"$OMAHUB_INPUT_DEVICES"
state=$(omahub get keyboard/size)
assert_eq "a known keyboard is detected by id" "$(jq -r .value <<<"$state")" "60"
assert_eq "its source is the known list" "$(jq -r .source <<<"$state")" "known"
assert_eq "virtual keyboards are skipped" "$(jq -r .keyboard <<<"$state")" "WIN 60 HE"
assert_true "a compact keyboard recommends Vim focus" recommends keyboard/vim-focus
assert_true "a mouse with side buttons recommends mouse buttons" recommends keyboard/mouse-buttons

{ keyboard 0003 3434 0280 "Keychron K8 Pro TKL"; mouse 70000; } >"$OMAHUB_INPUT_DEVICES"
assert_eq "an unknown keyboard is sized from its name" "$(omahub get keyboard/size | jq -r .value)" "tkl"
assert_eq "its source is the name" "$(omahub get keyboard/size | jq -r .source)" "name"
if recommends keyboard/vim-focus >/dev/null; then
  fail "a keyboard with arrows does not recommend Vim focus"
else
  pass "a keyboard with arrows does not recommend Vim focus"
fi
if recommends keyboard/mouse-buttons >/dev/null; then
  fail "a mouse without side buttons does not recommend mouse buttons"
else
  pass "a mouse without side buttons does not recommend mouse buttons"
fi

keyboard 0011 0001 0001 "AT Translated Set 2 keyboard" >"$OMAHUB_INPUT_DEVICES"
assert_eq "a built-in keyboard is a laptop" "$(omahub get keyboard/size | jq -r .value)" "laptop"

keyboard 0003 1234 5678 "USB Keyboard" >"$OMAHUB_INPUT_DEVICES"
assert_eq "an unrecognized keyboard has no size" "$(omahub get keyboard/size | jq -c .value)" "null"
assert_eq "and says so" "$(omahub get keyboard/size | jq -r .label)" "Unknown"

assert_eq "choosing a size wins over detection" "$(omahub set keyboard/size 75 | jq -r '"\(.value) \(.source)"')" "75 chosen"
assert_eq "options mark the chosen size" "$(omahub options keyboard/size | jq -r '.[] | select(.current) | .value')" "75"
assert_eq "options list every size" "$(omahub options keyboard/size | jq length)" "6"
assert_eq "reset returns to detection" "$(omahub reset keyboard/size | jq -r .source)" "unknown"

if omahub set keyboard/size huge 2>/dev/null; then
  fail "an invalid size is rejected"
else
  pass "an invalid size is rejected"
fi

finish
