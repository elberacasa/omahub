#!/bin/bash

# The omahub command and the settings catalog.

source "$(dirname "$0")/../base-test.sh"

catalog=$(omahub settings --json 2>"$TEST_ROOT/stderr")
assert_true "catalog is a JSON array" jq -e 'type == "array"' <<<"$catalog"
assert_eq "no setting is missing required headers" "$(cat "$TEST_ROOT/stderr")" ""

for id in keyboard/omahub-key keyboard/mac-screenshot-keys; do
  assert_eq "$id is listed" "$(jq -r --arg id "$id" 'map(select(.id == $id)) | length' <<<"$catalog")" "1"
done

shipped=$(find "$OMAHUB_PATH/settings" -type f | wc -l)
assert_eq "every shipped setting is executable and listed" "$(jq length <<<"$catalog")" "$shipped"

mkdir -p "$HOME/.config/omahub/settings/keyboard"
cat >"$HOME/.config/omahub/settings/keyboard/omahub-key" <<'EOF'
#!/bin/bash
# omahub:title=My key
# omahub:summary=A user override
# omahub:section=keyboard
# omahub:kind=toggle
echo '{"value":true,"label":"Mine"}'
EOF
chmod +x "$HOME/.config/omahub/settings/keyboard/omahub-key"
assert_eq "a user setting replaces the shipped one" "$(omahub settings --json | jq -r '.[] | select(.id == "keyboard/omahub-key") | .title')" "My key"
assert_eq "the user setting runs" "$(omahub get keyboard/omahub-key | jq -r .label)" "Mine"
rm -rf "$HOME/.config/omahub"

mkdir -p "$HOME/.config/omahub/settings/extra"
cat >"$HOME/.config/omahub/settings/extra/needs-plugin" <<'EOF'
#!/bin/bash
# omahub:title=Needs a plugin
# omahub:summary=Only shows when a plugin is installed
# omahub:section=extra
# omahub:kind=toggle
# omahub:requires=io.example.missing
EOF
chmod +x "$HOME/.config/omahub/settings/extra/needs-plugin"
assert_eq "a setting whose requirement is missing is hidden" "$(omahub settings --json | jq -r 'map(select(.id == "extra/needs-plugin")) | length')" "0"
rm -rf "$HOME/.config/omahub"

family="$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub-example/settings/extra"
mkdir -p "$family"
cat >"$family/from-family" <<'EOF'
#!/bin/bash
# omahub:title=From a family plugin
# omahub:summary=Shipped by a sibling plugin
# omahub:section=extra
# omahub:kind=toggle
echo '{"value":false,"label":"Off"}'
EOF
chmod +x "$family/from-family"
assert_eq "a family plugin's settings are listed" "$(omahub settings --json | jq -r 'map(select(.id == "extra/from-family")) | length')" "1"
assert_eq "a family plugin's setting runs" "$(omahub get extra/from-family | jq -r .label)" "Off"
rm -rf "$HOME/.config/omarchy/plugins"

if omahub get nope/missing 2>"$TEST_ROOT/stderr"; then
  fail "an unknown setting fails"
else
  pass "an unknown setting fails"
fi
assert_true "the failure explains how to list settings" grep -q "omahub settings" "$TEST_ROOT/stderr"

assert_eq "version comes from the manifest" "$(omahub version)" "$(jq -r .version "$OMAHUB_PATH/manifest.json")"

finish
