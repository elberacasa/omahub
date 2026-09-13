<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/omahub-capture-mark-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="assets/omahub-capture-mark-light.svg">
    <img alt="Omahub Capture" src="assets/omahub-capture-mark-dark.svg" width="96">
  </picture>
</p>

# Omahub Capture

Mac-style screenshots for Omarchy. Take a shot and a thumbnail slides into the corner.

Part of [Omahub](https://github.com/elberacasa/omahub).

- Click it to open the editor
- Drag it into any app to drop the file: a terminal, a browser, Files
- Drag it to the right to throw it away
- Right-click to copy it, show it in Files, move it to trash, or save it to another folder
- Save to moves the screenshot and sends every future one to the same folder
- With [Omahub](https://github.com/elberacasa/omahub) installed, pick the screenshot folder from its Capture section too
- Hover to keep it around, or leave it and it slides away on its own

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

## Contributing

Bug reports, ideas, and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get set up and [AGENTS.md](AGENTS.md) for the conventions this project follows. Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).

## Remove

```bash
omarchy plugin remove io.github.elberacasa.omahub-capture
```

## Requirements

Omarchy 4.0 or newer. No external dependencies beyond what ships with Omarchy.

## License

MIT
