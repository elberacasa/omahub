#!/bin/bash

# New projects: `omahub project new` and the projects/new action create a folder in the
# projects folder, start git, and open the agent or editor there.

source "$(dirname "$0")/../base-test.sh"

cat >"$TEST_ROOT/bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
command -v "$1" >/dev/null
EOF

# Launchers record where and what they were asked to open.
cat >"$TEST_ROOT/bin/omarchy-agent" <<'EOF'
#!/bin/bash
echo "agent $PWD" >"$HOME/launched"
EOF

cat >"$TEST_ROOT/bin/omarchy-launch-editor" <<'EOF'
#!/bin/bash
echo "editor $1" >"$HOME/launched"
EOF

chmod +x "$TEST_ROOT"/bin/*
mkdir -p "$HOME/Projects"

launched() {
  cat "$HOME/launched" 2>/dev/null
}

assert_eq "project new prints the new folder" "$(omahub project new "My App" --no-open)" "$HOME/Projects/My-App"
assert_eq "spaces become dashes and git starts" "$([[ -d $HOME/Projects/My-App/.git ]] && echo yes)" "yes"

if omahub project new "My App" --no-open 2>"$TEST_ROOT/stderr"; then
  fail "an existing project is never overwritten"
else
  pass "an existing project is never overwritten"
fi
assert_true "the refusal names the folder" grep -q "My-App already exists" "$TEST_ROOT/stderr"

if omahub project new "../escape" --no-open 2>/dev/null; then
  fail "a name cannot leave the projects folder"
else
  pass "a name cannot leave the projects folder"
fi

omahub project new api >/dev/null
assert_eq "the agent starts in the new project" "$(launched)" "agent $HOME/Projects/api"
omahub project new site --editor >/dev/null
assert_eq "--editor opens the project in the editor" "$(launched)" "editor $HOME/Projects/site"

mkdir -p "$HOME/Mono"
git -C "$HOME/Mono" init -q
omahub set projects/folder "$HOME/Mono" >/dev/null
omahub project new pkg --no-open >/dev/null
assert_eq "no nested git inside a repository" "$([[ -e $HOME/Mono/pkg/.git ]] && echo nested || echo clean)" "clean"
omahub reset projects/folder >/dev/null

catalog=$(omahub settings --json)
assert_eq "new project is an action with a prompt" "$(jq -c '.[] | select(.id == "projects/new") | [.kind, .action, .prompt, .closes]' <<<"$catalog")" '["action","Create","Project name",true]'
assert_eq "default agent offers Omarchy's menu for more" "$(jq -r '.[] | select(.id == "projects/default-agent") | .more' <<<"$catalog")" "setup.default.agent"

assert_eq "the action says where projects go" "$(omahub get projects/new | jq -r .label)" "In ~/Projects"
assert_eq "set creates the project" "$(omahub set projects/new "Side Quest" | jq -r .label)" "Created ~/Projects/Side-Quest"
for _ in $(seq 20); do
  if [[ $(launched) == "agent $HOME/Projects/Side-Quest" ]]; then
    break
  fi
  sleep 0.1
done
assert_eq "the action starts the agent there" "$(launched)" "agent $HOME/Projects/Side-Quest"

finish
