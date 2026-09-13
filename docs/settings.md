# Settings

Every setting in Omahub is one executable file. Its header describes it to the hub, and its verbs do the work. The hub, the `omahub` command, and agents all use the same files, so a setting added here shows up everywhere at once.

The format mirrors Omarchy's own commands, which describe themselves with `# omarchy:` headers.

## Example

```bash
#!/bin/bash

# omahub:title=Mac screenshot keys
# omahub:summary=SUPER + SHIFT + 3, 4, and 5 take screenshots, like Command + Shift on a Mac
# omahub:section=keyboard
# omahub:kind=toggle
# omahub:icon=󰹑
# omahub:keywords=screenshot capture keyboard mac layout workspace

set -euo pipefail
source "${OMAHUB_PATH:?run this through omahub}/lib/settings.sh"

case "${1:-}" in
  get) ... ;;
  set) ... ;;
  reset) ... ;;
  *) omahub_fail "usage: omahub get|set|reset keyboard/mac-screenshot-keys" ;;
esac
```

## Where settings live

| Location | Id |
|---|---|
| `settings/<section>/<name>` in Omahub | `<section>/<name>` |
| `settings/<section>/<name>` in a plugin whose id starts with Omahub's, such as `io.github.elberacasa.omahub-extra` | `<section>/<name>` |
| `omahub/settings/<section>/<name>` in any other Omarchy plugin | `<section>/<name>` |
| `~/.config/omahub/settings/<section>/<name>` | `<section>/<name>` |

Later rows win. A file in `~/.config/omahub/settings/` with the same id replaces the shipped setting, so anyone can adjust a setting without forking.

Only executable files are read. `chmod +x` a new setting.

## Headers

| Header | Required | Meaning |
|---|---|---|
| `title` | yes | Row title in sentence case |
| `summary` | yes | One line under the title. Also searched |
| `section` | yes | The hub section the row belongs to |
| `kind` | yes | `toggle`, `choice`, `folder`, `keys`, or `action`. Decides how the hub draws it |
| `icon` | no | A Nerd Font glyph |
| `keywords` | no | Extra words people might search for |
| `requires` | no | A plugin id (contains a dot) or a command. The setting is hidden when it is missing |
| `privileged` | no | `true` makes the hub run `set` in Omarchy's floating terminal |
| `hidden` | no | `true` keeps it out of the hub but available to `omahub` |
| `action` | no | Button label for an `action` setting, such as `Create`. Its `set` runs the action |
| `prompt` | no | For an `action`: the hub asks for a value inline, with this placeholder, then runs `set <value>` |
| `closes` | no | `true` closes the hub after `set` succeeds, for actions that open a window |
| `more` | no | For a `choice`: an Omarchy menu route opened from a More… chip, such as `setup.default.agent` |

## Verbs

| Verb | Prints | Rules |
|---|---|---|
| `get` | `{"value": ..., "label": "..."}` | Reads the real system every time. Never cached |
| `set <value>` | The new state, same shape as `get` | Idempotent. Rejects values it doesn't understand |
| `options` | `[{"value": ..., "label": "...", "current": true}]` | Only for `choice` and `folder` |
| `reset` | The state after resetting | Undoes everything the setting ever changed |

Exit with `1` and a short message on stderr when something fails. `omahub_fail` does both.

## Helpers

Source `lib/settings.sh` through `$OMAHUB_PATH`:

| Helper | Use |
|---|---|
| `omahub_state <json value> <label>` | Print a state, for example `omahub_state true "On"` |
| `omahub_block_write <file> <id> <comment>` | Replace the setting's marked block with standard input |
| `omahub_block_read <file> <id> <comment>` | Print what is inside the block |
| `omahub_block_remove <file> <id> <comment>` | Remove the block, and the file if nothing else is left |
| `omahub_backup <file> <comment>` | Back up a user file before changing it |
| `omahub_link_toggle_setting <link> <target> <id> <verb> [value]` | Every verb of a toggle that owns one symlink. Never removes a file it did not create |
| `omahub_fail <message>` | Print an error and exit |

`<comment>` is the file's comment prefix, such as `#` for shell files or `--` for Lua.

## Rules

- Prefer Omarchy's commands and documented settings over writing files at all.
- When a setting must change a user file, change only its own marked block, and call `omahub_backup` first.
- `reset` leaves no trace.
- Follow Omarchy's bash style, described in [AGENTS.md](../AGENTS.md#style).

## Try it

```bash
bin/omahub settings
bin/omahub get keyboard/mac-screenshot-keys
bin/omahub set keyboard/mac-screenshot-keys on
```

## Test it

Add `test/settings.d/<name>-test.sh`. Source `test/base-test.sh`, which gives you a disposable `HOME`, a stubbed `hyprctl`, and assertions, then run the setting through `omahub` and check that `get`, `set`, and `reset` round trip. Run everything with `test/all`.
