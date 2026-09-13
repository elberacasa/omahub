#!/bin/bash

# A keyboard change is undone when an action that had a key would lose it.

source "$(dirname "$0")/../base-test.sh"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf -- '-- my own binding\n' >"$bindings"
original=$(cat "$bindings")

# Omarchy's binding list alternates between the "before" and "after" files, the way it is read
# once before a change and once after.
cat >"$TEST_ROOT/bin/omarchy" <<EOF
#!/bin/bash
count=\$(cat "$TEST_ROOT/calls" 2>/dev/null || echo 0)
echo \$((count + 1)) >"$TEST_ROOT/calls"
if (( count % 2 == 0 )); then
  cat "$TEST_ROOT/before"
else
  cat "$TEST_ROOT/after"
fi
EOF

printf 'SUPER + J                → Toggle window split\n' >"$TEST_ROOT/before"
printf '' >"$TEST_ROOT/after"
if omahub set keyboard/omahub-key on 2>"$TEST_ROOT/stderr"; then
  fail "a change that drops an action fails"
else
  pass "a change that drops an action fails"
fi
assert_true "the failure names the action" grep -q "Toggle window split" "$TEST_ROOT/stderr"
assert_eq "the file is restored" "$(cat "$bindings")" "$original"
assert_eq "the layer stays off" "$(omahub get keyboard/omahub-key | jq -c .value)" "false"

printf 'SUPER + J                → Toggle window split\n' >"$TEST_ROOT/before"
printf 'SUPER SHIFT ALT + J      → Toggle window split\nSUPER + A                → Omahub\n' >"$TEST_ROOT/after"
assert_eq "a change that relocates an action succeeds" "$(omahub set keyboard/omahub-key on | jq -c .value)" "true"

printf 'SUPER + A                → Omahub\nSUPER + J                → Toggle window split\n' >"$TEST_ROOT/before"
printf 'SUPER + J                → Toggle window split\n' >"$TEST_ROOT/after"
assert_eq "turning a layer off may remove its own actions" "$(omahub set keyboard/omahub-key off | jq -c .value)" "false"

finish
