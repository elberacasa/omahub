#!/bin/bash

# Shared setup for Omahub tests: a disposable HOME, stubbed hyprctl and omarchy, and small
# assertions. Tests source this, run their checks, and end with `finish`.

set -euo pipefail

OMAHUB_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export OMAHUB_PATH

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
mkdir -p "$HOME" "$TEST_ROOT/bin"

# Hyprland is not available in tests. The stub reloads nothing and reports no config errors.
cat >"$TEST_ROOT/bin/hyprctl" <<'EOF'
#!/bin/bash
exit 0
EOF

# Omarchy's binding list is empty in tests unless a test replaces this stub.
cat >"$TEST_ROOT/bin/omarchy" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$TEST_ROOT/bin/hyprctl" "$TEST_ROOT/bin/omarchy"
export PATH="$TEST_ROOT/bin:$PATH"

failures=0

pass() {
  printf '  ok    %s\n' "$1"
}

fail() {
  printf '  FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

assert_eq() {
  local name="$1" actual="$2" expected="$3"
  if [[ $actual == "$expected" ]]; then
    pass "$name"
  else
    fail "$name: expected [$expected], got [$actual]"
  fi
}

assert_true() {
  local name="$1"
  shift
  if "$@" >/dev/null; then
    pass "$name"
  else
    fail "$name"
  fi
}

omahub() {
  "$OMAHUB_PATH/bin/omahub" "$@"
}

finish() {
  if (( failures > 0 )); then
    exit 1
  fi
}
