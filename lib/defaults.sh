#!/bin/bash

# Developer defaults: the coding agent and editor Omarchy launches, and the folder new agent
# sessions start in. The agent and editor lists come from Omarchy's own `omarchy default`
# commands, so anything Omarchy learns to launch shows up here without a change to Omahub.

OMAHUB_AGENT_FILE="$HOME/.config/omarchy/defaults/agent"
OMAHUB_EDITOR_FILE="$HOME/.local/state/omarchy/defaults/editor"
OMAHUB_PROJECTS_FILE="$OMAHUB_STATE_DIR/projects-folder"
OMAHUB_PROJECTS_CANDIDATES=(Projects Work Code src dev)

# Print "id<TAB>name" for every choice an Omarchy default command knows, read from its case table.
omahub_defaults_known() {
  local command="$1" key="$2" path
  path=$(command -v "$command") || return 0
  sed -n "s/.*$key=\"\([^\"]*\)\"; name=\"\([^\"]*\)\".*/\1\t\2/p" "$path" | awk -F'\t' '!seen[$1]++'
}

omahub_defaults_label() {
  local command="$1" key="$2" id="$3" name
  name=$(omahub_defaults_known "$command" "$key" | awk -F'\t' -v id="$id" '$1 == id { print $2; exit }')
  echo "${name:-$id}"
}

omahub_defaults_is_known() {
  local command="$1" key="$2" id="$3"
  omahub_defaults_known "$command" "$key" | awk -F'\t' -v id="$id" '$1 == id { found = 1 } END { exit !found }'
}

# Whether a choice is really installed, judged the way `omarchy default agent` judges it.
# Agents such as Hermes install through their own command, which answers --check. Omarchy puts
# a wrapper in ~/.local/bin for every other agent that installs it through mise on first run, so
# a wrapper only counts when mise already has the package it names. Anything else in
# ~/.local/bin is the user's own install.
omahub_defaults_installed() {
  local id="$1" wrapper="$HOME/.local/bin/$1" package
  if omarchy-cmd-present "omarchy-install-$id-cli"; then
    "omarchy-install-$id-cli" --check >/dev/null 2>&1
  elif [[ -f $wrapper ]] && grep -q '^mise use -g' "$wrapper"; then
    package=$(sed -n 's/^mise use -g[^"]*"\([^"]*\)".*/\1/p' "$wrapper" | head -1)
    [[ -n $package ]] && mise where "$package" >/dev/null 2>&1
  elif [[ -x $wrapper ]]; then
    return 0
  else
    omarchy-cmd-present "$id"
  fi
}

# Installed choices, plus the current one, as hub options.
omahub_defaults_options() {
  local command="$1" key="$2" current="$3" id name
  while IFS=$'\t' read -r id name; do
    if [[ $id == "$current" ]] || omahub_defaults_installed "$id"; then
      jq -nc --arg value "$id" --arg label "$name" --arg current "$current" \
        '{value: $value, label: $label, current: ($value == $current)}'
    fi
  done < <(omahub_defaults_known "$command" "$key") | jq -sc '.'
}

# Remember what a defaults file held before Omahub first changed it, so reset can put it back.
omahub_remember_file() {
  local name="$1" file="$2" dir="$OMAHUB_STATE_DIR/before"
  if [[ -e $dir/$name || -e $dir/$name.missing ]]; then
    return 0
  fi
  mkdir -p "$dir"
  if [[ -f $file ]]; then
    cp "$file" "$dir/$name"
  else
    touch "$dir/$name.missing"
  fi
}

omahub_restore_file() {
  local name="$1" file="$2" dir="$OMAHUB_STATE_DIR/before"
  if [[ -e $dir/$name ]]; then
    mkdir -p "$(dirname "$file")"
    mv "$dir/$name" "$file"
  elif [[ -e $dir/$name.missing ]]; then
    rm -f "$file" "$dir/$name.missing"
  fi
  rmdir "$dir" 2>/dev/null || true
}

omahub_default_agent() {
  omarchy-default-agent 2>/dev/null || true
}

omahub_default_agent_state() {
  local agent
  agent=$(omahub_default_agent)
  if [[ -z $agent ]]; then
    omahub_state null "Not chosen"
  else
    omahub_state "$(jq -nc --arg agent "$agent" '$agent')" "$(omahub_defaults_label omarchy-default-agent agent "$agent")"
  fi
}

omahub_default_agent_set() {
  local agent="$1"
  if ! omahub_defaults_is_known omarchy-default-agent agent "$agent"; then
    omahub_fail "usage: omahub set projects/default-agent <agent>. Run 'omahub options projects/default-agent' to list them."
  fi
  if ! omahub_defaults_installed "$agent"; then
    omahub_fail "$(omahub_defaults_label omarchy-default-agent agent "$agent") is not installed. Install it with: omarchy default agent $agent"
  fi

  # `omarchy default agent` also launches the agent, which a setting must not do, so write the
  # file that command keeps, for an agent that is already installed.
  omahub_remember_file default-agent "$OMAHUB_AGENT_FILE"
  mkdir -p "$(dirname "$OMAHUB_AGENT_FILE")"
  printf '%s\n' "$agent" >"$OMAHUB_AGENT_FILE"
}

omahub_default_editor() {
  omarchy-default-editor 2>/dev/null || echo "nvim"
}

omahub_default_editor_state() {
  local editor
  editor=$(omahub_default_editor)
  omahub_state "$(jq -nc --arg editor "$editor" '$editor')" "$(omahub_defaults_label omarchy-default-editor editor "$editor")"
}

omahub_default_editor_set() {
  local editor="$1"
  if ! omahub_defaults_is_known omarchy-default-editor editor "$editor"; then
    omahub_fail "usage: omahub set projects/editor <editor>. Run 'omahub options projects/editor' to list them."
  fi
  if ! omahub_defaults_installed "$editor"; then
    omahub_fail "$(omahub_defaults_label omarchy-default-editor editor "$editor") is not installed. Install it with: omarchy default editor $editor"
  fi
  omahub_remember_file editor "$OMAHUB_EDITOR_FILE"
  omarchy-default-editor "$editor" >/dev/null
}

omahub_home_label() {
  if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then
    echo "~${1#"$HOME"}"
  else
    echo "$1"
  fi
}

# The chosen projects folder, or the first common one that exists.
omahub_projects_folder() {
  local dir
  if [[ -s $OMAHUB_PROJECTS_FILE ]]; then
    cat "$OMAHUB_PROJECTS_FILE"
    return
  fi
  for dir in "${OMAHUB_PROJECTS_CANDIDATES[@]}"; do
    if [[ -d $HOME/$dir ]]; then
      echo "$HOME/$dir"
      return
    fi
  done
  echo "$HOME/Projects"
}

omahub_projects_state() {
  local dir
  dir=$(omahub_projects_folder)
  omahub_state "$(jq -nc --arg dir "$dir" '$dir')" "$(omahub_home_label "$dir")"
}

omahub_projects_options() {
  local current dir
  current=$(omahub_projects_folder)
  {
    printf '%s\n' "$current"
    for dir in "${OMAHUB_PROJECTS_CANDIDATES[@]}"; do
      if [[ -d $HOME/$dir ]]; then
        printf '%s\n' "$HOME/$dir"
      fi
    done
  } | awk '!seen[$0]++' | jq -Rsc --arg current "$current" \
    'split("\n") | map(select(length > 0)) | map({value: ., label: (split("/") | last), current: (. == $current)})'
}

# Create a project in the projects folder and start git there, unless the projects folder is
# itself a repository. Spaces in the name become dashes. Prints the new folder.
omahub_project_new() {
  local name="${1// /-}" root dir
  if [[ ! $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    omahub_fail "name a project with letters, numbers, dots, dashes, or underscores"
  fi
  root=$(omahub_projects_folder)
  dir="$root/$name"
  if [[ -e $dir ]]; then
    omahub_fail "$(omahub_home_label "$dir") already exists. Pick another name"
  fi
  mkdir -p "$dir"
  if omarchy-cmd-present git && ! git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$dir" init -q
  fi
  printf '%s\n' "$dir"
}

omahub_projects_set() {
  local dir
  dir=$(realpath -m -- "$1")
  mkdir -p "$dir" "$OMAHUB_STATE_DIR"
  printf '%s\n' "$dir" >"$OMAHUB_PROJECTS_FILE"
}
