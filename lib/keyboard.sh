#!/bin/bash

# Keyboard and mouse detection, and the keyboard layers Omahub recommends for them.
# Requires lib/settings.sh.

OMAHUB_INPUT_DEVICES="${OMAHUB_INPUT_DEVICES:-/proc/bus/input/devices}"
OMAHUB_KEYBOARD_SIZE_FILE="$OMAHUB_STATE_DIR/keyboard-size"
OMAHUB_KEYBOARD_SIZES=(60 65 75 tkl full laptop)

# Print "vendor:product<TAB>bus<TAB>name" for each physical keyboard: devices with a keyboard
# handler and lock lights, without virtual keyboards or extra control interfaces.
# Key capability bitmaps are not used, because compact keyboards advertise keys they don't have.
omahub_keyboards() {
  awk 'BEGIN { RS = ""; FS = "\n" }
    {
      bus = vendor = product = name = ""
      kbd = 0
      ev = 0
      for (i = 1; i <= NF; i++) {
        line = $i
        if (line ~ /^I:/) {
          if (match(line, /Bus=[0-9a-fA-F]+/)) bus = substr(line, RSTART + 4, RLENGTH - 4)
          if (match(line, /Vendor=[0-9a-fA-F]+/)) vendor = substr(line, RSTART + 7, RLENGTH - 7)
          if (match(line, /Product=[0-9a-fA-F]+/)) product = substr(line, RSTART + 8, RLENGTH - 8)
        } else if (line ~ /^N: Name=/) {
          name = line
          sub(/^N: Name="/, "", name)
          sub(/"$/, "", name)
        } else if (line ~ /^H:/ && line ~ /kbd/) {
          kbd = 1
        } else if (line ~ /^B: EV=/) {
          ev = strtonum("0x" substr(line, 7))
        }
      }
      if (!kbd || !and(ev, 131072)) next
      if (tolower(name) ~ /virtual|keyd|fcitx|consumer control|system control|power button|sleep button|hotkeys|wmi/) next
      id = tolower(vendor) ":" tolower(product)
      if (id in seen) next
      seen[id] = 1
      print id "\t" bus "\t" name
    }' "$OMAHUB_INPUT_DEVICES" 2>/dev/null
}

omahub_keyboard_size_from_name() {
  local name="${1,,}" bus="$2"

  if [[ $bus == "0011" || $name == *"at translated set"* ]]; then
    echo laptop
  elif [[ $name =~ (^|[^0-9])(60|61)([^0-9]|$) ]]; then
    echo 60
  elif [[ $name =~ (^|[^0-9])(65|66|68)([^0-9]|$) ]]; then
    echo 65
  elif [[ $name =~ (^|[^0-9])(75|84)([^0-9]|$) ]]; then
    echo 75
  elif [[ $name =~ tkl|tenkeyless|(^|[^0-9])(80|87)([^0-9]|$) ]]; then
    echo tkl
  elif [[ $name =~ full|(^|[^0-9])(96|98|100|104|105|108)([^0-9]|$) ]]; then
    echo full
  fi
}

# Print "size<US>source<US>name" for the first keyboard, where source is known, name, or unknown.
omahub_keyboard_detect() {
  local id="" bus="" name="" size="" source="unknown" data

  IFS=$'\t' read -r id bus name < <(omahub_keyboards | head -n 1) || true

  if [[ -n $id ]]; then
    data="$OMAHUB_PATH/keyboards/${id/:/-}"
    if [[ -f $data ]]; then
      size=$(sed -n 's/^size=//p' "$data")
      source="known"
    else
      size=$(omahub_keyboard_size_from_name "$name" "$bus")
      if [[ -n $size ]]; then
        source="name"
      fi
    fi
  fi

  printf '%s\x1f%s\x1f%s\n' "$size" "$source" "$name"
}

# Mouse button capabilities are accurate, unlike keyboard keys. BTN_SIDE is bit 275, which is
# bit 19 of the fifth 64-bit word, counted from the last word printed.
omahub_mouse_has_side_buttons() {
  awk 'BEGIN { RS = ""; FS = "\n"; found = 0 }
    {
      mouse = 0
      key = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^H:/ && $i ~ /mouse/) mouse = 1
        else if ($i ~ /^B: KEY=/) key = substr($i, 8)
      }
      if (!mouse || key == "") next
      count = split(key, words, " ")
      if (count < 5) next
      word = words[count - 4]
      low = length(word) > 5 ? substr(word, length(word) - 4) : word
      if (and(strtonum("0x" low), 524288)) found = 1
    }
    END { exit !found }' "$OMAHUB_INPUT_DEVICES" 2>/dev/null
}

omahub_keyboard_valid_size() {
  local size
  for size in "${OMAHUB_KEYBOARD_SIZES[@]}"; do
    if [[ $1 == "$size" ]]; then
      return 0
    fi
  done
  return 1
}

omahub_keyboard_label() {
  case "$1" in
    60) echo "60%" ;;
    65) echo "65%" ;;
    75) echo "75%" ;;
    tkl) echo "Tenkeyless" ;;
    full) echo "Full size" ;;
    laptop) echo "Laptop" ;;
    *) echo "Unknown" ;;
  esac
}

# Compact boards lack arrows and function keys, so they also get Vim focus. Mouse buttons are
# recommended only when a mouse really has side buttons.
omahub_keyboard_recommended() {
  local ids=(keyboard/omahub-key)

  case "$1" in
    60 | 65) ids+=(keyboard/mac-screenshot-keys keyboard/vim-focus keyboard/agent-keys) ;;
    75 | tkl | full | laptop) ids+=(keyboard/mac-screenshot-keys keyboard/agent-keys) ;;
  esac

  if omahub_mouse_has_side_buttons; then
    ids+=(keyboard/mouse-buttons)
  fi

  printf '%s\n' "${ids[@]}" | jq -R . | jq -sc .
}

omahub_keyboard_state() {
  local size="" source="unknown" name=""

  IFS=$'\x1f' read -r size source name < <(omahub_keyboard_detect) || true

  if [[ -f $OMAHUB_KEYBOARD_SIZE_FILE ]]; then
    size=$(<"$OMAHUB_KEYBOARD_SIZE_FILE")
    source="chosen"
  fi

  jq -nc \
    --arg size "$size" \
    --arg source "$source" \
    --arg keyboard "$name" \
    --arg label "$(omahub_keyboard_label "$size")" \
    --argjson recommended "$(omahub_keyboard_recommended "$size")" \
    '{value: (if $size == "" then null else $size end), label: $label, source: $source, keyboard: $keyboard, recommended: $recommended}'
}

omahub_keyboard_options() {
  local current size
  current=$(omahub_keyboard_state | jq -r '.value // ""')

  for size in "${OMAHUB_KEYBOARD_SIZES[@]}"; do
    jq -nc --arg value "$size" --arg label "$(omahub_keyboard_label "$size")" --arg current "$current" \
      '{value: $value, label: $label, current: ($value == $current)}'
  done | jq -sc .
}
