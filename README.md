# Omahub Capture

Mac-style screenshots for Omarchy. Take a shot and a thumbnail slides into the corner.

- Click it to open the editor
- Swipe it right to dismiss
- Hover to copy, show in Files, or move to trash
- Leave it and it slides away on its own

Screenshots come from Omarchy's own capture tool and follow your theme.

## Install

```bash
omarchy plugin add https://github.com/elberacasa/omahub-capture.git --enable
omarchy restart shell
```

## Use

Bind the capture script to any key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + CTRL + code:13", "Screenshot region", "~/.config/omarchy/plugins/io.github.elberacasa.omahub-capture/capture.sh region")
```

Modes: `region`, `windows`, `fullscreen`.

Or use [Omahub](https://github.com/elberacasa/omahub)'s Mac keyboard layout, which puts it on SUPER + SHIFT + 3 and 4 for you.

## Remove

```bash
omarchy plugin remove io.github.elberacasa.omahub-capture
```

## Requirements

Omarchy 4.0 or newer. No external dependencies beyond what ships with Omarchy.

## License

MIT
