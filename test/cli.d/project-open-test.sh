#!/bin/bash

# omahub project list and open: the projects in the projects folder, and opening one on a free desktop.

source "$(dirname "$0")/../base-test.sh"

# Hyprland reports desktops 1 and 3 in use, and keeps the last command it was sent.
cat >"$TEST_ROOT/bin/hyprctl" <<'EOF'
#!/bin/bash
case "$1" in
  workspaces) echo '[{"id":1,"windows":2},{"id":2,"windows":0},{"id":3,"windows":1},{"id":-98,"windows":1}]' ;;
  eval) printf '%s\n' "$2" >"$HOME/eval" ;;
esac
EOF
chmod +x "$TEST_ROOT/bin/hyprctl"

assert_eq "no projects folder lists nothing" "$(omahub project list)" "[]"

mkdir -p "$HOME/Projects/alpha/.git" "$HOME/Projects/beta" "$HOME/Projects/.hidden"
echo "ref: refs/heads/feature/search" >"$HOME/Projects/alpha/.git/HEAD"
touch -d "2026-01-01 10:00" "$HOME/Projects/alpha/.git/HEAD" "$HOME/Projects/alpha/.git" "$HOME/Projects/alpha"
touch -d "2026-02-01 10:00" "$HOME/Projects/beta"

list=$(omahub project list)
assert_eq "projects come newest first, without hidden folders" "$(jq -r 'map(.name) | join(",")' <<<"$list")" "beta,alpha"
assert_eq "a git project has its branch" "$(jq -r '.[] | select(.name == "alpha") | "\(.git) \(.branch)"' <<<"$list")" "true feature/search"
assert_eq "a plain folder is not a git project" "$(jq -r '.[] | select(.name == "beta") | "\(.git) [\(.branch)]"' <<<"$list")" "false []"

opened=$(omahub project open alpha)
assert_eq "a project opens on the first free desktop" "$(jq -c '{desktop, open}' <<<"$opened")" '{"desktop":2,"open":"both"}'
assert_true "it goes to that desktop" grep -qF 'hl.dispatch(hl.dsp.focus({ workspace = "2" }))' "$HOME/eval"
assert_true "the editor opens the project there" \
  grep -qF "hl.exec_cmd([[omarchy-launch-editor '$HOME/Projects/alpha']], { workspace = \"2\" })" "$HOME/eval"
assert_true "the agent starts in the project there" \
  grep -qF "hl.exec_cmd([[cd '$HOME/Projects/alpha' && exec omarchy-agent --pick]], { workspace = \"2\" })" "$HOME/eval"

omahub project open beta --desktop 7 --agent >/dev/null
assert_eq "--desktop and --agent start only the agent, on that desktop" \
  "$(grep -c 'exec_cmd' "$HOME/eval") $(grep -c 'workspace = "7"' "$HOME/eval")" "1 2"

omahub project open beta --no-focus >/dev/null
assert_eq "--no-focus opens the project without going to its desktop" \
  "$(grep -c 'hl.dsp.focus' "$HOME/eval") $(grep -c 'exec_cmd' "$HOME/eval")" "0 2"

if omahub project open gamma 2>"$TEST_ROOT/stderr"; then
  fail "a project that does not exist is not opened"
else
  pass "a project that does not exist is not opened"
fi
assert_true "the refusal says how to create it" grep -qF "omahub project new gamma" "$TEST_ROOT/stderr"

if omahub project open "../beta" 2>/dev/null; then
  fail "a name cannot leave the projects folder"
else
  pass "a name cannot leave the projects folder"
fi

if omahub project open beta --desktop zero 2>/dev/null; then
  fail "a desktop must be a number"
else
  pass "a desktop must be a number"
fi

# A projects folder with a quote in its path stays one argument to the shell Hyprland starts.
mkdir -p "$HOME/Bob's Projects/app"
omahub set projects/folder "$HOME/Bob's Projects" >/dev/null
omahub project open app --editor >/dev/null
assert_true "a quote in the path is escaped for the shell" \
  grep -qF "omarchy-launch-editor '$HOME/Bob'\\''s Projects/app'" "$HOME/eval"

finish
