#!/bin/bash

# The dock keeps its switches and pinned apps in one JSON file that the dock watches. Pins start
# from Omarchy's default apps, and covered.sh decides when an auto-hiding dock steps aside.

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

dock_file="$HOME/.local/state/omahub/dock.json"
defaults='["foot","chromium","org.gnome.Nautilus","cursor"]'

assert_eq "the dock starts off" "$(omahub get dock/show | jq -r .value)" "false"
assert_eq "turning it on succeeds" "$(omahub set dock/show on | jq -r .value)" "true"
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
assert_eq "magnification starts on" "$(omahub get dock/magnify | jq -r .value)" "true"
assert_eq "the dock apps setting stays out of the hub" "$(omahub settings --json | jq -r '.[] | select(.id == "dock/pins") | .hidden')" "true"

assert_eq "resetting pins returns to the defaults" "$(omahub reset dock/pins | jq -c .value)" "$defaults"
omahub reset dock/show >/dev/null
assert_eq "resetting the dock leaves no file" "$([[ -e $dock_file ]] && echo left || echo clean)" "clean"

cat >"$TEST_ROOT/bin/hyprctl" <<'EOF'
#!/bin/bash
case "$1" in
  monitors) echo '[{"focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1,"activeWorkspace":{"id":1},"specialWorkspace":{"id":0}}]' ;;
  clients) cat "$HOME/clients.json" ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/hyprctl"

covered() {
  echo "$1" >"$HOME/clients.json"
  "$OMAHUB_PATH/dock/covered.sh" 420 90
}

assert_eq "an empty workspace leaves the dock clear" "$(covered '[]')" "clear"
assert_eq "a tiled window reaching the bottom covers it" "$(covered '[{"mapped":true,"hidden":false,"workspace":{"id":1},"at":[10,36],"size":[1900,1034]}]')" "covered"
assert_eq "a window on another workspace does not" "$(covered '[{"mapped":true,"hidden":false,"workspace":{"id":2},"at":[10,36],"size":[1900,1034]}]')" "clear"
assert_eq "a floating window away from the bottom does not" "$(covered '[{"mapped":true,"hidden":false,"workspace":{"id":1},"at":[100,100],"size":[500,400]}]')" "clear"

finish
