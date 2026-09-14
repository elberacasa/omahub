#!/bin/bash

# The dock keeps its switches and pinned apps in one JSON file that the dock watches. Pins start
# from Omarchy's default apps. When an auto-hiding dock steps aside is tested in dock-model-test.sh.

source "$(dirname "$0")/../base-test.sh"

printf '#!/bin/bash\nexit 0\n' >"$TEST_ROOT/bin/omarchy-shell"
printf '#!/bin/bash\necho foot\n' >"$TEST_ROOT/bin/omarchy-default-terminal"
printf '#!/bin/bash\necho cursor\n' >"$TEST_ROOT/bin/omarchy-default-editor"
printf '#!/bin/bash\necho chromium.desktop\n' >"$TEST_ROOT/bin/xdg-settings"
printf '#!/bin/bash\necho org.gnome.Nautilus.desktop\n' >"$TEST_ROOT/bin/xdg-mime"
chmod +x "$TEST_ROOT"/bin/*

apps="$HOME/.local/share/applications"
mkdir -p "$apps"
for app in foot chromium org.gnome.Nautilus cursor obsidian; do
  printf '[Desktop Entry]\nName=%s\nExec=%s\n' "$app" "$app" >"$apps/$app.desktop"
done
export XDG_DATA_DIRS="$TEST_ROOT/no-system-apps"

bindings="$HOME/.config/hypr/bindings.lua"
mkdir -p "$(dirname "$bindings")"
printf -- '-- my own binding\n' >"$bindings"

dock_file="$HOME/.local/state/omahub/dock.json"
defaults='["foot","chromium","org.gnome.Nautilus","cursor"]'

assert_eq "the dock starts off" "$(omahub get dock/show | jq -r .value)" "false"
assert_eq "turning it on succeeds" "$(omahub set dock/show on | jq -r .value)" "true"
assert_true "the dock brings its key, SUPER + D" grep -qF '"dock"' "$bindings"
assert_eq "pins start from Omarchy's default apps" "$(jq -c .pins "$dock_file")" "$defaults"
assert_eq "omahub dock pins lists them" "$(omahub dock pins)" "$defaults"

omahub dock pin obsidian >/dev/null
omahub dock pin obsidian >/dev/null
assert_eq "pinning adds an app once, at the end" "$(omahub dock pins)" '["foot","chromium","org.gnome.Nautilus","cursor","obsidian"]'
omahub dock unpin foot >/dev/null
assert_eq "unpinning removes it" "$(omahub dock pins | jq -r 'index("foot")')" "null"
if omahub dock pin not-an-app 2>"$TEST_ROOT/stderr"; then
  fail "an app that does not exist cannot be pinned"
else
  pass "an app that does not exist cannot be pinned"
fi
assert_true "the refusal names the app" grep -q "no app named 'not-an-app'" "$TEST_ROOT/stderr"

assert_eq "automatically hide starts on" "$(omahub get dock/autohide | jq -r .value)" "true"
assert_eq "it turns off" "$(omahub set dock/autohide off | jq -r .value)" "false"
assert_eq "the dock file says so" "$(jq -r .autohide "$dock_file")" "false"
assert_eq "reset turns it back on" "$(omahub reset dock/autohide | jq -r .value)" "true"
assert_eq "reset removes the key" "$(jq -r 'has("autohide")' "$dock_file")" "false"
assert_eq "magnification starts on" "$(omahub get dock/magnify | jq -r .value)" "large"
assert_eq "the dock apps setting stays out of the hub" "$(omahub settings --json | jq -r '.[] | select(.id == "dock/pins") | .hidden')" "true"

assert_eq "size starts on Medium" "$(omahub get dock/size | jq -r .label)" "Medium"
assert_eq "size offers three choices" "$(omahub options dock/size | jq -c 'map(.value)')" '["small","medium","large"]'
assert_eq "size changes" "$(omahub set dock/size large | jq -r .label)" "Large"
assert_eq "the dock file keeps the size" "$(jq -r .size "$dock_file")" "large"
if omahub set dock/size huge 2>/dev/null; then
  fail "an unknown size fails"
else
  pass "an unknown size fails"
fi
assert_eq "size resets to Medium" "$(omahub reset dock/size | jq -r .value)" "medium"

assert_eq "magnification starts on Large" "$(omahub get dock/magnify | jq -r .value)" "large"
assert_eq "magnification can be subtle" "$(omahub set dock/magnify subtle | jq -r .label)" "Subtle"
assert_eq "on, from the old switch, means Large" "$(omahub set dock/magnify on | jq -r .value)" "large"
assert_eq "off turns it off" "$(omahub set dock/magnify off | jq -r .value)" "off"
jq '.magnify = false' "$dock_file" >"$dock_file.tmp" && mv "$dock_file.tmp" "$dock_file"
assert_eq "a switch saved off before reads as Off" "$(omahub get dock/magnify | jq -r .value)" "off"
jq '.magnify = true' "$dock_file" >"$dock_file.tmp" && mv "$dock_file.tmp" "$dock_file"
assert_eq "a switch saved on before reads as Large" "$(omahub get dock/magnify | jq -r .value)" "large"
omahub reset dock/magnify >/dev/null

assert_eq "the dock starts at the bottom" "$(omahub get dock/position | jq -r .value)" "bottom"
assert_eq "position offers the Mac's three edges" "$(omahub options dock/position | jq -c 'map(.value)')" '["left","bottom","right"]'
assert_eq "the dock can sit on the left" "$(omahub set dock/position left | jq -r .label)" "Left"
assert_eq "the dock file keeps the position" "$(jq -r .position "$dock_file")" "left"
if omahub set dock/position top 2>/dev/null; then
  fail "an edge the dock does not use fails"
else
  pass "an edge the dock does not use fails"
fi
omahub reset dock/position >/dev/null

assert_eq "icon tiles start off" "$(omahub get dock/tiles | jq -r .value)" "false"
assert_eq "icon tiles turn on" "$(omahub set dock/tiles on | jq -r .value)" "true"
omahub reset dock/tiles >/dev/null
assert_eq "the hub lists dock settings in the Mac's order" \
  "$(omahub settings --json | jq -c '[.[] | select(.section == "dock" and (.hidden | not))] | sort_by(.order) | map(.id | ltrimstr("dock/"))')" \
  '["show","size","magnify","position","tiles","autohide","indicators","recents","bounce"]'

for setting in indicators recents bounce; do
  assert_eq "dock/$setting starts on" "$(omahub get "dock/$setting" | jq -r .value)" "true"
  assert_eq "dock/$setting turns off" "$(omahub set "dock/$setting" off | jq -r .value)" "false"
  assert_eq "dock/$setting is saved" "$(jq -r --arg key "$setting" '.[$key]' "$dock_file")" "false"
  omahub reset "dock/$setting" >/dev/null
done

assert_eq "resetting pins returns to the defaults" "$(omahub reset dock/pins | jq -c .value)" "$defaults"
omahub reset dock/show >/dev/null
assert_eq "resetting the dock leaves no file" "$([[ -e $dock_file ]] && echo left || echo clean)" "clean"
assert_eq "turning the dock off takes its key away" "$(grep -c '"dock"' "$bindings" || true)" "0"

finish
