#!/bin/bash

# What the terminals in each window are running, for the overview and the dock.
#
#   context.sh <address>=<pid>...
#
# Give it every window. Every terminal under a window's process counts, however deep: a terminal
# window's own, the terminals inside an editor such as Cursor, and a terminal inside Neovim. For each
# one it reports facts read from the system, never guesses: the command in front, recognizing an agent
# started through a runtime or a version manager by what it runs, that command's process, the git
# project and branch of its folder, and for an agent that keeps a session record, what it is doing.
#
# Prints a JSON array, [{address, sessions: [{terminal, command, pid, project, branch, state, tool, quiet, model, since, message}]}],
# leaving out windows without terminals. Folders and projects are names only, never paths, so nothing it
# prints shows where they live. It reads the process table once and then only /proc, .git files, and the
# ends of agents' session records, so it is cheap enough to run every second.

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

# What an agent is doing, from its own session record for the folder it works in: "working" and the tool
# it is running, or "done" once its turn ends. Only Claude Code and Codex keep records Omahub can read. A
# record older than the agent's process belongs to an earlier session, so it says nothing. Prints
# state<TAB>tool<TAB>quiet<TAB>model<TAB>since<TAB>message: quiet is how many seconds ago the record last
# changed, model the one the agent last answered with, since when its latest turn began, in epoch seconds,
# and message the first line of what it last said, kept short.
agent_state() {
  local command="$1" pid="$2" folder="$3" log="" file started said model since message
  case "$command" in
    claude)
      log=$(ls -t "$HOME/.claude/projects/${folder//[^a-zA-Z0-9]/-}"/*.jsonl 2>/dev/null | head -n 1)
      ;;
    codex)
      while read -r file; do
        if [[ $(head -n 1 "$file" | jq -r '.payload.cwd // empty' 2>/dev/null) == "$folder" ]]; then
          log=$file
          break
        fi
      done < <(find "$HOME/.codex/sessions" -name '*.jsonl' -mmin -4320 -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
      ;;
  esac
  [[ -n $log && -f $log ]] || return 1
  started=$(( $(awk '/^btime/ { print $2 }' /proc/stat) + $(awk '{ print $22 }' "/proc/$pid/stat" 2>/dev/null || echo 0) / $(getconf CLK_TCK) ))
  (( $(stat -c %Y "$log") >= started )) || return 1

  if [[ $command == "claude" ]]; then
    said=$(tail -n 80 "$log" | jq -Rrn '[inputs | fromjson? // empty | select(.isSidechain != true)
        | select(.type == "assistant" or .type == "user" or (.type == "system" and .subtype == "turn_duration"))]
      | last // empty
      | if .type == "system" then ["done", ""]
        elif .type == "assistant" then
          (if .message.stop_reason == "end_turn" then ["done", ""]
           else ["working", ([.message.content[]? | select(.type == "tool_use") | .name] | last // "")] end)
        elif (.message.content | tostring | test("\\[Request interrupted")) then ["done", ""]
        else ["working", ""] end
      | @tsv')
  else
    # Codex records tool output inline, so lines can be large: only the last few event lines are parsed.
    said=$(tail -n 400 "$log" \
      | grep -E '"payload":\{"type":"(task_started|task_complete|turn_aborted|custom_tool_call|function_call|custom_tool_call_output|function_call_output)"' \
      | tail -n 3 | jq -Rrn '[inputs | fromjson? // empty | .payload? // empty | objects
        | select(.type == "task_started" or .type == "task_complete" or .type == "turn_aborted"
          or .type == "custom_tool_call" or .type == "function_call" or .type == "custom_tool_call_output" or .type == "function_call_output")]
      | last // empty
      | if .type == "task_complete" or .type == "turn_aborted" then ["done", ""]
        elif .type == "custom_tool_call" or .type == "function_call" then ["working", (.name // "")]
        else ["working", ""] end
      | @tsv')
  fi
  [[ -n $said ]] || return 1
  if [[ $command == "claude" ]]; then
    IFS=$'\t' read -r model since message < <(tail -n 160 "$log" | jq -Rrn '
      [inputs | fromjson? // empty | select(.isSidechain != true)] as $all
      | ([$all[] | select(.type == "assistant") | .message.model // empty | select(. != "<synthetic>")] | last // "") as $model
      | ([$all[] | select(.type == "user" and .isMeta != true
          and ((.message.content | type) == "string" or any(.message.content[]?; .type == "text")))] | last) as $prompt
      | ([$all[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // "") as $text
      | [$model,
         (($prompt.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0) | floor | tostring),
         ($text | gsub("\t"; " ") | split("\n") | map(select(test("\\S"))) | first // "" | sub("^\\s+"; "") | .[0:140])]
      | @tsv')
  else
    model=$(grep '"type":"turn_context"' "$log" | tail -n 1 | jq -r '.payload.model // ""' 2>/dev/null)
    since=$(grep '"type":"task_started"' "$log" | tail -n 1 | jq -r '.payload.started_at // 0 | floor' 2>/dev/null)
    message=$(grep '"type":"task_complete"' "$log" | tail -n 1 \
      | jq -r '.payload.last_agent_message // "" | gsub("\t"; " ") | split("\n") | map(select(test("\\S"))) | first // "" | sub("^\\s+"; "") | .[0:140]' 2>/dev/null)
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$said" "$(( EPOCHSECONDS - $(stat -c %Y "$log") ))" "$model" "${since:-0}" "$message"
}

# What each agent's record said this run, by agent and folder.
declare -A states

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
    state=""
    tool=""
    quiet=0
    model=""
    since=0
    message=""
    if [[ ($command == "claude" || $command == "codex") && -n $process && -n $folder ]]; then
      # Agents working in one folder write one record, so it is read once.
      key="$command:$folder"
      [[ -n ${states[$key]+set} ]] || states[$key]=$(agent_state "$command" "$process" "$folder")
      found=${states[$key]}
      if [[ -n $found ]]; then
        state=${found%%$'\t'*}
        rest=${found#*$'\t'}
        tool=${rest%%$'\t'*}
        rest=${rest#*$'\t'}
        quiet=${rest%%$'\t'*}
        rest=${rest#*$'\t'}
        model=${rest%%$'\t'*}
        rest=${rest#*$'\t'}
        since=${rest%%$'\t'*}
        message=${rest#*$'\t'}
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$address" "$terminal" "$command" "${process:-0}" "$project" "$branch" \
      "$state" "$tool" "$quiet" "$model" "$since" "$message"
  done
done | jq -Rcn '[inputs | split("\t") | {address: .[0], terminal: .[1], command: .[2], pid: (.[3] | tonumber), project: .[4], branch: .[5],
    state: (.[6] // ""), tool: (.[7] // ""), quiet: ((.[8] // "0") | tonumber? // 0), model: (.[9] // ""),
    since: ((.[10] // "0") | tonumber? // 0), message: (.[11:] | join(" "))}]
  | group_by(.address) | map({address: .[0].address, sessions: map(del(.address))})'
