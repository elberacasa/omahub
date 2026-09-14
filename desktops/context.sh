#!/bin/bash

# What the terminals in each window are running, for the overview and the dock.
#
#   context.sh <address>=<pid>...
#
# Give it every window. Every terminal under a window's process counts, however deep: a terminal
# window's own, the terminals inside an editor such as Cursor, and a terminal inside Neovim. For each
# one it reports facts read from the system, never guesses: the command in front, recognizing an agent
# started through a runtime or a version manager by what it runs, that command's process, and the git
# project and branch of its folder.
#
# Prints a JSON array, [{address, sessions: [{terminal, command, pid, project, branch}]}], leaving out
# windows without terminals. Folders and projects are names only, never paths, so nothing it prints shows
# where they live. It reads the process table once and then only /proc and .git files, so it is cheap
# enough to run every second.

set -uo pipefail

AGENTS="claude codex opencode gemini pi crush cursor-agent copilot amp aider goose qwen"
SHELLS=" bash zsh fish sh dash nu xonsh elvish "
# Programs that run an agent rather than being one: a runtime or a version manager.
RUNNERS=" node bun deno python python3 mise npx bunx uv uvx "

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

# The agent a process is, by its own name, or by a path segment of what a runtime runs, such as
# node .../@google/gemini-cli/dist/index.js or mise x opencode -- opencode.
agent_name() {
  local pid="$1" comm="$2" word segment name
  local -a segments
  if [[ " $AGENTS " == *" $comm "* ]]; then
    echo "$comm"
    return 0
  fi
  [[ $RUNNERS == *" $comm "* ]] || return 1
  for word in $(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null); do
    IFS=/ read -r -a segments <<<"$word"
    for segment in "${segments[@]}"; do
      for name in $AGENTS; do
        case "$segment" in
          "$name" | "$name-cli" | "$name-code" | "$name-agent")
            echo "$name"
            return 0
            ;;
        esac
      done
    done
  done
  return 1
}

# Every process: pid, parent, group, the terminal's foreground group, terminal, name.
snapshot=$(ps -eo pid=,ppid=,pgid=,tpgid=,tty=,comm= 2>/dev/null)

# The processes under a pid, itself included, as snapshot lines.
under() {
  awk -v root="$1" '
    { parent[$1] = $2; line[$1] = $0; order[NR] = $1 }
    END {
      for (i = 1; i <= NR; i++) {
        p = order[i]; q = p; depth = 0
        while (q != root && q > 1 && depth < 64) { q = parent[q]; depth++ }
        if (q == root) print line[p]
      }
    }' <<<"$snapshot"
}

for pair in "$@"; do
  address=${pair%%=*}
  root=${pair#*=}
  [[ $root =~ ^[0-9]+$ && -d /proc/$root ]] || continue

  members=$(under "$root")
  for terminal in $(awk '$5 != "?" { print $5 }' <<<"$members" | sort -u); do
    group=$(awk -v t="$terminal" '$5 == t' <<<"$members")
    # The top of the terminal is its process whose parent is not on the same terminal: the shell, or
    # the program a terminal was started with.
    read -r top top_comm front < <(awk '
      NR == FNR { on[$1] = 1; next }
      !($2 in on) { print $1, $6, $4; exit }' <(echo "$group") <(echo "$group"))
    [[ -n ${top:-} ]] || continue

    command=""
    process=""
    while read -r pid _ pgid _ _ comm; do
      [[ $pgid == "$front" ]] || continue
      if name=$(agent_name "$pid" "$comm"); then
        command=$name
        process=$pid
        break
      fi
    done <<<"$group"
    if [[ -z $command ]]; then
      leader=$(awk -v f="$front" '$1 == f { print $6 }' <<<"$group")
      if [[ $front != "$top" && -n $leader ]]; then
        command=$leader
        process=$front
      elif [[ $SHELLS != *" $top_comm "* ]]; then
        command=$top_comm
        process=$top
      fi
    fi

    folder=$(readlink "/proc/${process:-$top}/cwd" 2>/dev/null || readlink "/proc/$top/cwd" 2>/dev/null) || folder=""
    project=""
    branch=""
    if [[ -n $folder ]] && found=$(git_project "$folder"); then
      project=${found%%$'\t'*}
      branch=${found#*$'\t'}
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$address" "$terminal" "$command" "${process:-0}" "$project" "$branch"
  done
done | jq -Rcn '[inputs | split("\t") | {address: .[0], terminal: .[1], command: .[2], pid: (.[3] | tonumber), project: .[4], branch: .[5]}]
  | group_by(.address) | map({address: .[0].address, sessions: map(del(.address))})'
