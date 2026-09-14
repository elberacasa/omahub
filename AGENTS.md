# AGENTS.md

Guidance for anyone working on this repository, human or agent.

## What this is

Omahub is a plugin for the [Omarchy](https://omarchy.org) shell, written in QML on Quickshell with small bash helpers. It brings Mac conveniences to Omarchy without replacing any of Omarchy's own tools. SUPER + A opens it.

## Layout

| Path | Purpose |
|---|---|
| `manifest.json` | Plugin manifest. `version` follows semver |
| `Omahub.qml` | The entry the shell loads. Routes each summon to the feature it is for |
| `hub/` | The hub window: search, sections, and rows read from `omahub settings --json`, plus pure data shaping in `HubModel.js` |
| `overview/` | The overview: `Overview.qml` with live previews, and desktops, Exposé packing, search, and grid moves in `OverviewModel.js` |
| `dock/` | The dock: `Dock.qml`, layout and magnification in `DockModel.js`, and `covered.sh`, which tells an auto-hiding dock when a window reaches it |
| `capture/` | The screenshot thumbnail: `Capture.qml` and the scripts it runs. `capture/thumbnail` turns it on as a keyboard layer |
| `bin/omahub` | The command the hub, people, and agents use to list and change settings |
| `settings/` | One executable file per setting, described by `# omahub:` headers. See [docs/settings.md](docs/settings.md) |
| `lib/` | Shared bash for settings: discovery, marked blocks, backups, keyboard layers |
| `keymaps/` | Hyprland bindings loaded by the keyboard settings, one layer per file |
| `agents/skills/` | The skill coding agents read, in Omarchy's `SKILL.md` format. `agents/skill` links it into `~/.agents/skills` |
| `keyboards/` | Known keyboard models, one file per vendor and product id, used to detect keyboard size |
| `docs/` | Reference for contributors |
| `test/` | `test/all` runs every test against a disposable home |
| `assets/` | Brand assets for READMEs |
| `dev/` | Development tools. Nothing at runtime uses them |

## Ground rules

- **Omarchy is the source of truth.** Call Omarchy's commands and read its data. Never reimplement what Omarchy already does, and never edit `/usr/share/omarchy/`.
- **Nothing changes until the user asks.** User files are edited only inside a marked block, backed up first, and every change can be undone.
- **No sudo in the plugin.** Privileged or interactive work runs in Omarchy's floating terminal (`omarchy-launch-floating-terminal-with-presentation`) so the user sees and confirms it.
- **Theme tokens only.** Every color, radius, spacing, and font in QML comes from `qs.Commons` (`Color`, `Style`, `Border`). No hex values, no fixed pixel sizes.
- **Honest state.** The UI reads the real system every time instead of caching a guess.

## Style

Bash follows Omarchy's conventions:

- `#!/bin/bash` shebangs, two-space indentation, no tabs.
- `[[ ]]` for string and file tests, without quoting variables but quoting string literals. `(( ))` for numbers.
- A full `if`/`else` for two-path control flow instead of relying on `exit` in one branch.
- Quote paths with spaces rather than escaping them.
- Use Omarchy helpers such as `omarchy-notification-send` instead of raw tools.

QML:

- Size with `Style.space()` and `Style.spacing.*`, type with `Style.font.*`, surfaces with `Color.menu.*` or `Color.popups.*`.
- Every action works with the keyboard (`h` `j` `k` `l` wherever arrows work) and with the mouse.
- Motion is short and eased: ease out on enter, ease in on exit, no single-frame jumps.

Writing: sentence case, short and specific. No em dashes anywhere.

## Develop

```bash
dev/sync --restart          # copy the working tree into ~/.config/omarchy/plugins and restart the shell
omarchy plugin validate .   # must pass
test/all                    # must pass
omarchy-shell shell toggle io.github.elberacasa.omahub '{}'
```

The plugin sets `keepLoaded: true`, so QML changes only apply after `omarchy restart shell`. `dev/sync --restart` does that for you.

## Verify

- Screenshot the change in a dark and a light theme: `omarchy capture screenshot fullscreen save`, then `omarchy theme set <name>`.
- Anything that animates gets a frame review:

```bash
dev/take <name> 7 --quiet --run "<command that triggers the animation>"
dev/frames tmp/takes/<name>.mp4 <start> <end> --fps 60
```

Look for pops, flicker, jumps, and states that skip.

- Anything you click, drag, or hover gets a scripted demo. `dev/demo` runs a script from `dev/demos/` that moves a virtual pointer, clicks, drags, and types while it records, then tiles the frames and puts the pointer and workspace back:

```bash
dev/demo dev/demos/overview-drag.sh 12   # review tmp/demos/overview-drag.png and its .log
```

Demo scripts source `dev/demo-lib.sh` for `move`, `click`, `drag`, `key`, `summon`, `layout`, and throwaway windows. Omahub reports where its pieces are on screen with `omarchy-shell shell call io.github.elberacasa.omahub overviewLayout ""` and `dockLayout`, so scripts never guess pixels. Never send SUPER combinations with wtype: its keys reach Hyprland as other keys. Drive what a keybind does through `summon` instead.

## Commits and releases

- One coherent change per commit. Imperative subject under 60 characters, no trailing period. The body explains why.
- Add a line under `Unreleased` in `CHANGELOG.md` for anything a user would notice.
- Releases bump `version` in `manifest.json`, move `Unreleased` into a version section, and are tagged `vX.Y.Z`.
