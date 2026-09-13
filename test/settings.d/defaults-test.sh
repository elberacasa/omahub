#!/bin/bash

# Developer defaults: default agent, editor, and projects folder, plus `omahub agent` and
# `omahub edit`, against stubbed Omarchy commands.

source "$(dirname "$0")/../base-test.sh"

# Omarchy's default commands, reduced to their case tables and the files they keep.
cat >"$TEST_ROOT/bin/omarchy-default-agent" <<'EOF'
#!/bin/bash
if (( $# == 0 )); then
  if [[ -f $HOME/.config/omarchy/defaults/agent ]]; then
    cat "$HOME/.config/omarchy/defaults/agent"
  fi
  exit 0
fi
case "$1" in
claude | claude-code) agent="claude"; name="Claude Code" ;;
codex) agent="codex"; name="Codex" ;;
zork) agent="zork"; name="Zork" ;;
esac
EOF

cat >"$TEST_ROOT/bin/omarchy-default-editor" <<'EOF'
#!/bin/bash
file="$HOME/.local/state/omarchy/defaults/editor"
if (( $# == 0 )); then
  if [[ -f $file ]]; then
    cat "$file"
  else
    echo "nvim"
  fi
  exit 0
fi
case "$1" in
cursor) editor="cursor"; name="Cursor"; glyph= ;;
nvim) editor="nvim"; name="Neovim"; glyph= ;;
notepadx) editor="notepadx"; name="Notepad X"; glyph= ;;
esac
mkdir -p "$(dirname "$file")"
printf '%s\n' "$editor" >"$file"
EOF

cat >"$TEST_ROOT/bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
command -v "$1" >/dev/null
EOF

# Launchers record where and what they were asked to start.
for launcher in omarchy-agent omarchy-launch-tui omarchy-launch-editor claude codex cursor nvim; do
  printf '#!/bin/bash\necho "$PWD $*" >"$HOME/launched"\n' >"$TEST_ROOT/bin/$launcher"
done

cat >"$TEST_ROOT/bin/omarchy-file-select" <<'EOF'
#!/bin/bash
mkdir -p "$HOME/Work/picked"
echo "$HOME/Work/picked"
EOF

chmod +x "$TEST_ROOT"/bin/*

launched() {
  cat "$HOME/launched"
}

agent_file="$HOME/.config/omarchy/defaults/agent"
editor_file="$HOME/.local/state/omarchy/defaults/editor"

assert_eq "the default agent starts unchosen" "$(omahub get agents/default-agent | jq -r .label)" "Not chosen"
assert_eq "options list only installed agents" "$(omahub options agents/default-agent | jq -r 'map(.label) | join(",")')" "Claude Code,Codex"

assert_eq "set chooses an agent" "$(omahub set agents/default-agent codex | jq -r .label)" "Codex"
assert_eq "Omarchy's defaults file names it" "$(cat "$agent_file")" "codex"
if omahub set agents/default-agent zork 2>"$TEST_ROOT/stderr"; then
  fail "an agent that is not installed is refused"
else
  pass "an agent that is not installed is refused"
fi
assert_true "the refusal says how to install it" grep -q "omarchy default agent zork" "$TEST_ROOT/stderr"
assert_eq "reset forgets an agent chosen only in Omahub" "$(omahub reset agents/default-agent | jq -r .label)" "Not chosen"
assert_eq "reset leaves no defaults file" "$([[ -e $agent_file ]] && echo left || echo clean)" "clean"

mkdir -p "$(dirname "$agent_file")"
echo "claude" >"$agent_file"
omahub set agents/default-agent codex >/dev/null
assert_eq "reset restores the agent chosen before" "$(omahub reset agents/default-agent | jq -r .value)" "claude"

assert_eq "the editor follows Omarchy's default" "$(omahub get agents/editor | jq -r .label)" "Neovim"
assert_eq "options list only installed editors" "$(omahub options agents/editor | jq -r 'map(.label) | join(",")')" "Cursor,Neovim"
assert_eq "set chooses Cursor" "$(omahub set agents/editor cursor | jq -r .label)" "Cursor"
assert_eq "reset returns to Omarchy's default editor" "$(omahub reset agents/editor | jq -r .label)" "Neovim"
assert_eq "reset leaves no editor file" "$([[ -e $editor_file ]] && echo left || echo clean)" "clean"

assert_eq "projects default to ~/Projects" "$(omahub get agents/projects-folder | jq -r .label)" "~/Projects"
mkdir -p "$HOME/Work"
assert_eq "an existing Work folder is used" "$(omahub get agents/projects-folder | jq -r .label)" "~/Work"
assert_eq "set creates a new projects folder" "$(omahub set agents/projects-folder "$HOME/Code/new" | jq -r .label)" "~/Code/new"
assert_eq "the new folder exists" "$([[ -d $HOME/Code/new ]] && echo yes)" "yes"
assert_eq "options mark the current folder" "$(omahub options agents/projects-folder | jq -r 'map(select(.current)) | .[0].label')" "new"
assert_eq "reset goes back to the found folder" "$(omahub reset agents/projects-folder | jq -r .label)" "~/Work"

echo "claude" >"$agent_file"
omahub agent
assert_eq "agent starts the default agent in the projects folder" "$(launched)" "$HOME/Work --pick"
omahub agent codex
assert_eq "agent starts another installed agent there" "$(launched)" "$HOME/Work --app-id=org.omarchy.agent codex"
omahub agent codex --pick
assert_eq "--pick starts it in the chosen folder" "$(launched)" "$HOME/Work/picked --app-id=org.omarchy.agent codex"
if omahub agent zork 2>/dev/null; then
  fail "agent refuses an agent that is not installed"
else
  pass "agent refuses an agent that is not installed"
fi

omahub edit
assert_eq "edit opens the projects folder in the editor" "$(launched | awk '{ print $NF }')" "$HOME/Work"

finish
