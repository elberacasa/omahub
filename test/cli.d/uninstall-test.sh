#!/bin/bash

# omahub uninstall puts back what settings changed and removes Omahub's data, and never runs
# without a confirmation.

source "$(dirname "$0")/../base-test.sh"

state="$HOME/.local/state/omahub"
command="$HOME/.local/bin/omahub"
skill="$HOME/.agents/skills/omahub"

omahub set agents/command on >/dev/null
omahub set agents/skill on >/dev/null
omahub set dock/show on >/dev/null
assert_true "settings left things to clean up" test -L "$command" -a -L "$skill" -a -d "$state"

if omahub uninstall </dev/null >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
  fail "uninstall without a terminal or --yes refuses"
else
  pass "uninstall without a terminal or --yes refuses"
fi
assert_true "the refusal says how to confirm" grep -q -- "--yes" "$TEST_ROOT/stderr"
assert_true "a refusal changes nothing" test -L "$command" -a -L "$skill" -a -d "$state"

if omahub uninstall --yes >"$TEST_ROOT/stdout" 2>"$TEST_ROOT/stderr"; then
  pass "uninstall with --yes succeeds"
else
  fail "uninstall with --yes succeeds: $(cat "$TEST_ROOT/stderr")"
fi
assert_eq "the command link is gone" "$([[ -e $command || -L $command ]] && echo left || echo clean)" "clean"
assert_eq "the skill link is gone" "$([[ -e $skill || -L $skill ]] && echo left || echo clean)" "clean"
assert_eq "Omahub's data is gone" "$([[ -e $state ]] && echo left || echo clean)" "clean"
assert_true "it says how to remove the plugin" grep -q "omarchy plugin remove io.github.elberacasa.omahub" "$TEST_ROOT/stdout"
assert_true "the command link was reset last" test "$(grep '^Reset ' "$TEST_ROOT/stdout" | tail -1)" = "Reset agents/command"

if omahub uninstall --maybe 2>/dev/null; then
  fail "an unknown option fails"
else
  pass "an unknown option fails"
fi

finish
