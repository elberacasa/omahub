# Omahub

Mac comforts for Omarchy, built the Omarchy way.

Omahub is a small family of [Omarchy](https://omarchy.org) shell plugins for people who came from macOS and still want the details right: screenshot keys that feel familiar, a thumbnail you can drag straight into your coding agent, and one place to browse and manage everything Omarchy offers. Every piece follows your theme, runs Omarchy's own commands, and works from the keyboard.

## What's inside

| Piece | What it does | Status |
|---|---|---|
| Mac keyboard layout | SUPER + SHIFT + 3, 4, and 5 for screenshots. Switch back to Omarchy's keys any time | Ready |
| [Omahub Capture](https://github.com/elberacasa/omahub-capture) | A floating thumbnail after every screenshot. Click to edit, drag the file into any app, right-click for more | Ready |
| Omahub | Browse, install, and remove apps, themes, plugins, and services from one overlay | In progress |

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

The Mac layout changes only these keys:

| Keys | Mac layout | Omarchy default |
|---|---|---|
| SUPER + SHIFT + 3 | Screenshot full screen | Move window to workspace 3 |
| SUPER + SHIFT + 4 | Screenshot region | Move window to workspace 4 |
| SUPER + SHIFT + 5 | Capture menu | Move window to workspace 5 |
| SUPER + SHIFT + CTRL + 3 or 4 | Screenshot to clipboard | Unbound |
| SUPER + SHIFT + ALT + 1 to 0 | Move window to workspace | Move window silently |

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
bin/dev-sync --restart   # copy the working tree and restart the shell
bin/dev-sync --watch     # keep copying on every save
omarchy plugin validate .
```

Plugins with `keepLoaded: true` only pick up QML changes after a shell restart.

Record and review motion:

```bash
bin/take thumbnail 7 --quiet --run "<command that triggers the animation>"
bin/frames tmp/takes/thumbnail.mp4 0.4 1.0 --fps 60
bin/export-media tmp/takes/thumbnail.mp4 thumbnail 0.4-6.5
```

`bin/take` records the focused monitor with notifications silenced. `bin/frames` tiles every frame of a window into one image. `bin/export-media` cuts segments into an MP4 and a GIF.

## Remove

Run `keymap.sh off` first if you picked a layout, then:

```bash
omarchy plugin remove io.github.elberacasa.omahub
```

## Requirements

Omarchy 4.0 or newer. The development tools also use `ffmpeg` and `gpu-screen-recorder`, which ship with Omarchy.

## License

MIT
