<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/omahub-hero-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/omahub-hero-light.svg">
    <img alt="Omahub" src="assets/omahub-hero-dark.svg" width="560">
  </picture>
</p>

<p align="center">The Mac layer for Omarchy. One key for everything you want to change.</p>

# Omahub

Omahub turns SUPER + A into the place where you set up, tune, and extend Omarchy. It brings the details people love about the Mac to a system that stays pure Omarchy underneath: every change runs through Omarchy's own commands, follows your theme, and can be undone.

Every setting in Omahub is a small, readable file. People change them from the hub, agents change them from the terminal, and contributors add new ones with a single file and a test.

## Today

| | What it does |
|---|---|
| Mac keyboard layout | SUPER + SHIFT + 3, 4, and 5 for screenshots, switchable back to Omarchy's keys at any time |
| [Omahub Capture](https://github.com/elberacasa/omahub-capture) | A thumbnail after every screenshot. Click to edit, drag into any app, drag right to throw away, right-click to save it anywhere |

## Building now

- **The hub.** Search every setting, grouped by section, with live state and one-key changes.
- **`omahub`.** One command for the hub, the terminal, and agents: `omahub settings --json`, `get`, `set`, `reset`.
- **A welcome** that lets new users pick the Mac touches they want, and nothing else.
- **An agent skill,** so any coding agent on Omarchy can use Omahub the same way you do.

## Install

```bash
omarchy plugin add https://github.com/elberacasa/omahub.git --enable
omarchy restart shell
```

Add the screenshot thumbnail too:

```bash
omarchy plugin add https://github.com/elberacasa/omahub-capture.git --enable
omarchy restart shell
```

Plugins land disabled until you enable them, so you can read the code first. Omahub never uses sudo. Anything that needs your password opens in a visible terminal.

## Keyboard

Installing Omahub never changes your keybindings. Pick a layout when you want one:

```bash
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh omarchy   # SUPER + A opens Omahub
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh mac       # SUPER + A, plus Mac screenshot keys
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh off       # remove everything Omahub added
```

The Mac layout changes only these keys, and every Omarchy action it displaces keeps a key:

| Keys | Mac layout | Omarchy default |
|---|---|---|
| SUPER + SHIFT + 3 | Screenshot full screen | Move window to workspace 3 |
| SUPER + SHIFT + 4 | Screenshot region | Move window to workspace 4 |
| SUPER + SHIFT + 5 | Capture menu | Move window to workspace 5 |
| SUPER + SHIFT + CTRL + 3 or 4 | Screenshot to clipboard | Unbound |
| SUPER + SHIFT + ALT + 1 to 0 | Move window to workspace | Move window silently |
| SUPER + CTRL + ALT + 1 to 0 | Move window silently to workspace | Unbound |

With Omahub Capture installed, the screenshot keys show the floating thumbnail. Without it, they use Omarchy's own screenshot flow.

Omahub edits one marked block in `~/.config/hypr/bindings.lua`, backs the file up first, and restores it if Hyprland reports an error.

## Principles

- **Omarchy is the source of truth.** Omahub calls Omarchy's commands and reads its data. It never reimplements installs, themes, or captures.
- **Your theme, always.** Every color, radius, and font comes from the active Omarchy theme.
- **Nothing changes until you ask.** Installing never touches your config. Every change is one command to undo.
- **Motion with purpose.** Transitions are short, calm, and reviewed frame by frame before they ship.

## Development

Clone into your projects folder, then sync it into the plugins folder the shell watches:

```bash
dev/sync --restart   # copy the working tree and restart the shell
dev/sync --watch     # keep copying on every save
omarchy plugin validate .
```

Plugins with `keepLoaded: true` only pick up QML changes after a shell restart.

Record and review motion:

```bash
dev/take thumbnail 7 --quiet --run "<command that triggers the animation>"
dev/frames tmp/takes/thumbnail.mp4 0.4 1.0 --fps 60
dev/export-media tmp/takes/thumbnail.mp4 thumbnail 0.4-6.5
```

`dev/take` records the focused monitor with notifications silenced. `dev/frames` tiles every frame of a window into one image. `dev/export-media` cuts segments into an MP4 and a GIF.

## Contributing

Bug reports, ideas, and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get set up and [AGENTS.md](AGENTS.md) for the conventions this project follows, which are Omarchy's own. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).

## Remove

Run `keymap.sh off` first if you picked a layout, then:

```bash
omarchy plugin remove io.github.elberacasa.omahub
```

## Requirements

Omarchy 4.0 or newer. The development tools also use `ffmpeg` and `gpu-screen-recorder`, which ship with Omarchy.

## License

MIT
