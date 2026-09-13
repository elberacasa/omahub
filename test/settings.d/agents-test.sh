#!/bin/bash

# agents/skill and agents/command link into place and only ever remove their own links.

source "$(dirname "$0")/../base-test.sh"

skill="$HOME/.agents/skills/omahub"
command="$HOME/.local/bin/omahub"

assert_eq "the skill starts off" "$(omahub get agents/skill | jq -r .value)" "false"
assert_eq "turning the skill on links it" "$(omahub set agents/skill on | jq -r .value)" "true"
assert_eq "the link points at the skill" "$(readlink "$skill")" "$OMAHUB_PATH/agents/skills/omahub"
assert_true "the skill names itself in its front matter" grep -qx 'name: omahub' "$skill/SKILL.md"
assert_eq "turning it on again changes nothing" "$(omahub set agents/skill on | jq -r .value)" "true"
assert_eq "reset turns it off" "$(omahub reset agents/skill | jq -r .value)" "false"
assert_eq "reset leaves no link" "$([[ -L $skill ]] && echo left || echo clean)" "clean"

mkdir -p "$(dirname "$command")"
printf '#!/bin/bash\n' >"$command"
if omahub set agents/command on 2>"$TEST_ROOT/stderr"; then
  fail "a file already in place blocks the command link"
else
  pass "a file already in place blocks the command link"
fi
assert_true "the failure says what to move" grep -q "already exists" "$TEST_ROOT/stderr"
omahub reset agents/command >/dev/null
assert_eq "reset never removes a file Omahub did not create" "$(cat "$command")" "#!/bin/bash"
rm -f "$command"

omahub set agents/command on >/dev/null
assert_eq "the linked command runs" "$("$command" version)" "$(jq -r .version "$OMAHUB_PATH/manifest.json")"
omahub set agents/command off >/dev/null
assert_eq "off removes the command" "$([[ -e $command || -L $command ]] && echo left || echo clean)" "clean"

finish
