# AGENTS.md

Guidance for anyone working on this repository, human or agent.

## What this is

Omahub Capture is a plugin for the [Omarchy](https://omarchy.org) shell that shows a Mac-style thumbnail after a screenshot. It is part of the [Omahub](https://github.com/elberacasa/omahub) family and works on its own. Screenshots are always taken by Omarchy's own `omarchy-capture-screenshot`.

## Layout

| Path | Purpose |
|---|---|
| `manifest.json` | Plugin manifest. `version` follows semver |
| `Capture.qml` | The thumbnail panel: motion, click, drag, right-click menu |
| `capture.sh` | Takes a screenshot with Omarchy in `save` mode and summons the thumbnail |
| `drop-target.sh` | Tells the panel whether a drag ended over a window |
| `screenshot-dir.sh` | Gets, sets, and lists screenshot folders, and moves a screenshot |
| `settings/` | Settings the Omahub hub shows when Omahub is installed, in [Omahub's setting format](https://github.com/elberacasa/omahub/blob/main/docs/settings.md) |
| `test/` | `test/all` runs every test against a disposable home |
| `assets/` | Brand assets for the README |
| `dev/` | Development tools. Nothing at runtime uses them |

## Ground rules

- **Omarchy is the source of truth.** Capture never takes screenshots itself. The screenshot folder is Omarchy's documented `OMARCHY_SCREENSHOT_DIR`.
- **Nothing changes until the user asks.** User files are edited only inside a marked block, backed up first, and `screenshot-dir.sh reset` removes every trace.
- **Theme tokens only.** Every color, radius, spacing, and font in QML comes from `qs.Commons`.
- **The input region never moves.** `mask` follows the static `hitArea`; the card only moves visually. Animating the masked item leaves clicks behind.

## Style

Follow Omarchy's conventions, described in [Omahub's AGENTS.md](https://github.com/elberacasa/omahub/blob/main/AGENTS.md#style): `#!/bin/bash`, two spaces, `[[ ]]` and `(( ))`, full `if`/`else`, theme tokens in QML, keyboard and mouse parity, eased motion, no em dashes.

## Develop

```bash
dev/sync --restart          # copy into ~/.config/omarchy/plugins and restart the shell
omarchy plugin validate .
omarchy-shell shell summon io.github.elberacasa.omahub-capture '{"path":"/path/to/image.png"}'
```

The plugin sets `keepLoaded: true`, so QML changes only apply after a shell restart.

Run the tests. Settings run through the `omahub` command, so clone Omahub next to this repo or point `OMAHUB_PATH` at a checkout:

```bash
test/all
```

Try a script by hand against a temporary home so it never touches your own config:

```bash
env -i HOME="$(mktemp -d)" PATH="$PATH" bash screenshot-dir.sh places
```

## Verify

Check changes in a dark and a light theme. Review motion frame by frame with Omahub's `dev/take` and `dev/frames`, summoning the thumbnail through `--run`.

## Commits and releases

- One coherent change per commit. Imperative subject under 60 characters, no trailing period. The body explains why.
- Add a line under `Unreleased` in `CHANGELOG.md` for anything a user would notice.
- Releases bump `version` in `manifest.json` and are tagged `vX.Y.Z`.
