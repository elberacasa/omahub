#!/bin/bash

# What each terminal window is working on, for the overview and the dock: the git project and branch
# of its folder, the command in front of its shell, and the processor time that command has used.
# It reads only /proc and .git files, so it is cheap enough to run every second.
#
#   context.sh <address>=<pid>...
#
# Give it every window. A window is a terminal when the program it started runs on a terminal device,
# whatever the terminal or its app id, so terminals launched under another name, such as an agent's,
# are read too, and apps without one are left out.
#
# Prints a JSON array with one object per terminal window. Folders and projects are names only, never
# paths, so nothing it prints shows where they live.

set -uo pipefail

# The shells a terminal starts. When one of these is in front, the terminal is at its prompt.
shells=" bash zsh fish sh dash nu xonsh elvish "

# Prints the project folder's name and its branch, when the folder is inside a git work tree.
git_project() {
  local dir="$1" git="" head
  while [[ -n $dir && $dir != "/" ]]; do
    if [[ -d $dir/.git ]]; then
      git="$dir/.git"
      break
    fi
    if [[ -f $dir/.git ]]; then
      git=$(sed -n 's/^gitdir: //p' "$dir/.git")
      [[ $git == /* ]] || git="$dir/$git"
      break
    fi
    dir=${dir%/*}
  done
  [[ -n $git && -f $git/HEAD ]] || return 1
  head=$(<"$git/HEAD")
  if [[ $head == "ref: refs/heads/"* ]]; then
    printf '%s\t%s\n' "${dir##*/}" "${head#ref: refs/heads/}"
  else
    printf '%s\t%s\n' "${dir##*/}" "${head:0:7}"
  fi
}

# Fields of /proc/<pid>/stat after the command name, which can itself contain spaces.
stat_fields() {
  local line
  line=$(<"/proc/$1/stat") 2>/dev/null || return 1
  printf '%s\n' "${line##*) }"
}

for pair in "$@"; do
  address=${pair%%=*}
  pid=${pair#*=}
  [[ $pid =~ ^[0-9]+$ && -d /proc/$pid ]] || continue

  # The terminal's first child is its shell, or the program it was started with.
  shell=$(pgrep -o -P "$pid" 2>/dev/null) || shell=$pid
  read -r -a fields <<<"$(stat_fields "$shell")" || continue
  # No terminal device: an app, not a terminal.
  [[ ${fields[4]:-0} != "0" ]] || continue
  shell_group=${fields[2]:-0}
  front_group=${fields[5]:-0}
  shell_name=$(<"/proc/$shell/comm")

  command=""
  front=$shell
  cpu=0
  if (( front_group > 0 )) && [[ $front_group != "$shell_group" && -d /proc/$front_group ]]; then
    front=$front_group
    command=$(<"/proc/$front_group/comm")
  elif [[ $shells != *" $shell_name "* ]]; then
    # Started without a shell, such as a terminal that runs an agent or btop directly.
    command=$shell_name
  fi
  if [[ -n $command ]]; then
    for member in $(pgrep -g "$front" 2>/dev/null); do
      read -r -a usage <<<"$(stat_fields "$member")" || continue
      cpu=$((cpu + ${usage[11]:-0} + ${usage[12]:-0}))
    done
  fi

  folder=$(readlink "/proc/$front/cwd" 2>/dev/null) || folder=""
  project=""
  branch=""
  if [[ -n $folder ]] && found=$(git_project "$folder"); then
    project=${found%%$'\t'*}
    branch=${found#*$'\t'}
  fi
  if [[ $folder == "$HOME" ]]; then
    folder="~"
  else
    folder=${folder##*/}
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$address" "$folder" "$project" "$branch" "$command" "$cpu"
done | jq -Rcn '[inputs | split("\t") | {address: .[0], folder: .[1], project: .[2], branch: .[3], command: .[4], cpu: (.[5] | tonumber)}]'
