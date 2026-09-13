#!/bin/bash

# capture/screenshot-folder keeps Omarchy's OMARCHY_SCREENSHOT_DIR in a marked block and resets
# without a trace.

source "$(dirname "$0")/../base-test.sh"

unset OMARCHY_SCREENSHOT_DIR
mkdir -p "$HOME/Pictures" "$HOME/Downloads"

cat >"$TEST_ROOT/bin/xdg-user-dir" <<'EOF'
#!/bin/bash
case "$1" in
  PICTURES) echo "$HOME/Pictures" ;;
  DOWNLOAD) echo "$HOME/Downloads" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/xdg-user-dir"

env_file="$HOME/.config/uwsm/default"

assert_eq "the default folder is Pictures" "$(omahub get capture/screenshot-folder | jq -r .label)" "~/Pictures"
assert_eq "options mark the current folder" "$(omahub options capture/screenshot-folder | jq -r 'map(select(.current)) | .[0].label')" "Pictures"
assert_eq "options offer Downloads" "$(omahub options capture/screenshot-folder | jq -r 'map(select(.label == "Downloads")) | length')" "1"

assert_eq "set prints the new folder" "$(omahub set capture/screenshot-folder "$HOME/Downloads" | jq -r .value)" "$HOME/Downloads"
assert_eq "get reads it back" "$(omahub get capture/screenshot-folder | jq -r .label)" "~/Downloads"
assert_eq "Omarchy's variable is set for the next login" "$(grep -c '^export OMARCHY_SCREENSHOT_DIR=' "$env_file")" "1"

omahub set capture/screenshot-folder "$HOME/Shots" >/dev/null
assert_eq "set creates a missing folder" "$([[ -d $HOME/Shots ]] && echo yes)" "yes"
assert_eq "changing the folder keeps one block" "$(grep -c '^export OMARCHY_SCREENSHOT_DIR=' "$env_file")" "1"

if omahub set capture/screenshot-folder 2>/dev/null; then
  fail "set without a folder fails"
else
  pass "set without a folder fails"
fi

assert_eq "reset goes back to Pictures" "$(omahub reset capture/screenshot-folder | jq -r .label)" "~/Pictures"
assert_eq "reset leaves no trace" "$([[ -e $env_file || -e $HOME/.local/state/omahub/screenshot-dir ]] && echo left || echo clean)" "clean"

finish
