#!/bin/bash

# Shared helpers for the omahub command and for setting files: discovery, marked blocks,
# backups, and JSON state. Setting files source this through $OMAHUB_PATH.

OMAHUB_PLUGIN_ID="io.github.elberacasa.omahub"
OMAHUB_PLUGINS_DIR="$HOME/.config/omarchy/plugins"
OMAHUB_STATE_DIR="$HOME/.local/state/omahub"
OMAHUB_USER_SETTINGS="$HOME/.config/omahub/settings"

omahub_fail() {
  echo "omahub: $*" >&2
  exit 1
}

# Print setting roots in override order: Omahub, family plugins, opted-in plugins, the user.
omahub_setting_roots() {
  local plugin name

  printf '%s\n' "$OMAHUB_PATH/settings"

  for plugin in "$OMAHUB_PLUGINS_DIR"/*/; do
    plugin=${plugin%/}
    name=$(basename -- "$plugin")
    if [[ $name == "$OMAHUB_PLUGIN_ID" ]]; then
      continue
    elif [[ $name == "$OMAHUB_PLUGIN_ID"-* && -d $plugin/settings ]]; then
      printf '%s\n' "$plugin/settings"
    elif [[ -d $plugin/omahub/settings ]]; then
      printf '%s\n' "$plugin/omahub/settings"
    fi
  done

  printf '%s\n' "$OMAHUB_USER_SETTINGS"
}

# A requirement is a plugin id (contains a dot) that must be installed, or a command.
omahub_requirement_met() {
  local requirement="$1"
  if [[ $requirement == *.* ]]; then
    [[ -d $OMAHUB_PLUGINS_DIR/$requirement ]]
  else
    command -v "$requirement" >/dev/null 2>&1
  fi
}

# Print one setting as JSON from its "# omahub:" headers. Prints nothing when a required
# header is missing.
omahub_setting_json() {
  local root="$1" file="$2"

  jq -nc --arg id "${file#"$root"/}" --arg path "$file" --rawfile source "$file" '
    ($source
      | split("\n")
      | map(select(startswith("# omahub:")) | ltrimstr("# omahub:"))
      | map(select(test("^[a-z]+=")) | capture("^(?<key>[a-z]+)=(?<value>.*)$"))
      | map({(.key): .value})
      | add // {}) as $h
    | if ($h.title and $h.summary and $h.section and $h.kind) then
        {
          id: $id,
          path: $path,
          title: $h.title,
          summary: $h.summary,
          section: $h.section,
          kind: $h.kind,
          icon: ($h.icon // ""),
          keywords: ($h.keywords // ""),
          requires: ($h.requires // ""),
          privileged: ($h.privileged == "true"),
          action: ($h.action // ""),
          prompt: ($h.prompt // ""),
          closes: ($h.closes == "true"),
          more: ($h.more // ""),
          preview: ($h.preview // ""),
          hidden: ($h.hidden == "true"),
          order: (try ($h.order | tonumber) catch 100)
        }
      else
        empty
      end'
}

# Print the catalog of every available setting as one JSON array. Later roots replace
# earlier settings with the same id.
omahub_catalog() {
  local root file json requirement

  while IFS= read -r root; do
    [[ -d $root ]] || continue
    while IFS= read -r -d '' file; do
      json=$(omahub_setting_json "$root" "$file")
      if [[ -z $json ]]; then
        echo "omahub: skipping $file: it needs title, summary, section, and kind headers" >&2
        continue
      fi
      requirement=$(jq -r .requires <<<"$json")
      if [[ -z $requirement ]] || omahub_requirement_met "$requirement"; then
        printf '%s\n' "$json"
      fi
    done < <(find "$root" -type f -perm -u+x -print0 | sort -z)
  done < <(omahub_setting_roots) | jq -s 'reduce .[] as $s ({}; .[$s.id] = $s) | [.[]] | sort_by(.section, .title)'
}

# Find one setting's file without building the whole catalog, following the same rules: later
# roots win, and a file needs its headers and its requirement to count.
omahub_setting_path() {
  local id="$1" root file requirement found=""
  if [[ ! $id =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)*$ ]]; then
    return 0
  fi
  while IFS= read -r root; do
    file="$root/$id"
    if [[ -f $file && -x $file ]] && grep -q '^# omahub:title=' "$file"; then
      requirement=$(sed -n 's/^# omahub:requires=//p' "$file" | head -1)
      if [[ -z $requirement ]] || omahub_requirement_met "$requirement"; then
        found=$file
      fi
    fi
  done < <(omahub_setting_roots)
  printf '%s\n' "$found"
}

# Print a setting state: omahub_state <json value> <label>.
omahub_state() {
  jq -nc --argjson value "$1" --arg label "$2" '{value: $value, label: $label}'
}

# Marked blocks let a setting own a few lines inside a user file and nothing else.
# The comment argument is the file's comment prefix, for example "#" or "--".
omahub_block_start() {
  printf '%s omahub:%s:start' "$2" "$1"
}

omahub_block_end() {
  printf '%s omahub:%s:end' "$2" "$1"
}

omahub_block_has() {
  local file="$1" id="$2" comment="$3"
  [[ -f $file ]] && grep -qxF -e "$(omahub_block_start "$id" "$comment")" "$file"
}

omahub_block_read() {
  local file="$1" id="$2" comment="$3" start end
  [[ -f $file ]] || return 0
  start=$(omahub_block_start "$id" "$comment")
  end=$(omahub_block_end "$id" "$comment")
  awk -v start="$start" -v end="$end" '$0 == end { inside = 0 } inside { print } $0 == start { inside = 1 }' "$file"
}

# Remove the block. A file that ends up empty is deleted, so reset leaves no trace.
omahub_block_remove() {
  local file="$1" id="$2" comment="$3" start end
  [[ -f $file ]] || return 0
  start=$(omahub_block_start "$id" "$comment")
  end=$(omahub_block_end "$id" "$comment")
  awk -v start="$start" -v end="$end" '$0 == start { skip = 1 } !skip { print } $0 == end { skip = 0 }' "$file" >"$file.omahub.tmp"
  mv "$file.omahub.tmp" "$file"
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$file"
  if ! grep -q '[^[:space:]]' "$file"; then
    rm -f "$file"
  fi
}

# Replace the block with standard input, appended at the end of the file.
omahub_block_write() {
  local file="$1" id="$2" comment="$3" body
  body=$(cat)
  mkdir -p "$(dirname "$file")"
  omahub_block_remove "$file" "$id" "$comment"
  if [[ -s $file ]]; then
    printf '\n' >>"$file"
  fi
  {
    omahub_block_start "$id" "$comment"
    printf '\n%s\n' "$body"
    omahub_block_end "$id" "$comment"
    printf '\n'
  } >>"$file"
}

# Links let a setting own one symlink, such as a skill in ~/.agents/skills. A link is only
# removed when it points at the setting's own target, so a file the user put there is never
# touched.
omahub_link_has() {
  local link="$1" target="$2"
  [[ -L $link && $(readlink -- "$link") == "$target" ]]
}

omahub_link_on() {
  local link="$1" target="$2"
  if omahub_link_has "$link" "$target"; then
    return 0
  elif [[ -e $link || -L $link ]]; then
    omahub_fail "$link already exists. Move it away, then try again."
  fi
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link"
}

omahub_link_off() {
  local link="$1" target="$2"
  if omahub_link_has "$link" "$target"; then
    rm -f -- "$link"
  fi
}

# The get, set, and reset verbs of a toggle that owns one link.
omahub_link_toggle_setting() {
  local link="$1" target="$2" id="$3" verb="${4:-}" value="${5:-}"

  case "$verb" in
    get) ;;
    set)
      case "$value" in
        on | true) omahub_link_on "$link" "$target" ;;
        off | false) omahub_link_off "$link" "$target" ;;
        *) omahub_fail "'$value' is not on or off. Use: omahub set $id on|off" ;;
      esac
      ;;
    reset) omahub_link_off "$link" "$target" ;;
    *) omahub_fail "usage: omahub get|set|reset $id" ;;
  esac

  if omahub_link_has "$link" "$target"; then
    omahub_state true "On"
  else
    omahub_state false "Off"
  fi
}

# Back up a user file before changing it. Skips files that hold only Omahub blocks, and
# skips when the newest backup is already identical.
omahub_backup() {
  local file="$1" comment="$2" latest
  [[ -s $file ]] || return 0

  if ! awk -v prefix="$comment omahub:" '
      index($0, prefix) == 1 && $0 ~ /:start$/ { skip = 1; next }
      index($0, prefix) == 1 && $0 ~ /:end$/ { skip = 0; next }
      !skip && /[^[:space:]]/ { found = 1 }
      END { exit !found }' "$file"; then
    return 0
  fi

  latest=$(ls -t "$file".bak.* 2>/dev/null | head -1 || true)
  if [[ -z $latest ]] || ! cmp -s "$file" "$latest"; then
    cp "$file" "$file.bak.$(date +%s)"
  fi
}
