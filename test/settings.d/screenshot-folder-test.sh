#!/bin/bash

# capture/screenshot-folder, run through the omahub command against a disposable home.

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
if [[ -z ${OMAHUB_PATH:-} ]]; then
  OMAHUB_PATH="$(cd "$root/.." && pwd)/omahub"
fi
if [[ ! -x $OMAHUB_PATH/bin/omahub ]]; then
  echo "  FAIL  needs an omahub checkout next to this repo, or OMAHUB_PATH pointing at one"
  exit 1
fi

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
unset OMARCHY_SCREENSHOT_DIR
mkdir -p "$HOME/Pictures" "$HOME/Downloads" "$HOME/.config/omarchy/plugins" "$TEST_ROOT/bin"
ln -s "$root" "$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub-capture"

cat >"$TEST_ROOT/bin/xdg-user-dir" <<'EOF'
#!/bin/bash
case "$1" in
  PICTURES) echo "$HOME/Pictures" ;;
  DOWNLOAD) echo "$HOME/Downloads" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/xdg-user-dir"
export PATH="$TEST_ROOT/bin:$PATH"

failures=0

assert_eq() {
  if [[ $2 == "$3" ]]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s: expected [%s], got [%s]\n' "$1" "$3" "$2"
    failures=$((failures + 1))
  fi
}

omahub() {
  "$OMAHUB_PATH/bin/omahub" "$@"
}

env_file="$HOME/.config/uwsm/default"

assert_eq "the hub lists the setting" "$(omahub settings --json | jq -r 'map(select(.id == "capture/screenshot-folder")) | length')" "1"
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
  assert_eq "set without a folder fails" "passed" "failed"
else
  assert_eq "set without a folder fails" "failed" "failed"
fi

assert_eq "reset goes back to Pictures" "$(omahub reset capture/screenshot-folder | jq -r .label)" "~/Pictures"
assert_eq "reset leaves no trace" "$([[ -e $env_file || -e $HOME/.local/state/omahub/screenshot-dir ]] && echo left || echo clean)" "clean"

if (( failures > 0 )); then
  exit 1
fi
