# Omahub

Browse, install, and manage everything Omarchy offers from one place.

Omahub is a native Omarchy shell plugin. It opens instantly, follows your theme, and works entirely from the keyboard. Apps, themes, plugins, services, and dev environments all live behind one search box.

> Status: early development. Not ready for daily use yet.

## Install

```bash
omarchy plugin add https://github.com/elberacasa/omahub.git --enable
```

Plugins land disabled by default so you can review the code first. Omahub runs Omarchy's own commands and never uses sudo itself. Anything that needs your password opens in a visible terminal.

## Keyboard

Omahub never changes your keybindings on install. Pick a layout when you want one:

```bash
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh omarchy   # SUPER + A opens Omahub
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh mac       # SUPER + A, plus Mac screenshot keys
~/.config/omarchy/plugins/io.github.elberacasa.omahub/scripts/keymap.sh off       # remove everything Omahub added
```

The Mac layout changes only these keys:

| Keys | Mac layout |
|---|---|
| SUPER + SHIFT + 3 | Screenshot full screen |
| SUPER + SHIFT + 4 | Screenshot region |
| SUPER + SHIFT + 5 | Capture menu |
| SUPER + SHIFT + CTRL + 3 or 4 | Screenshot to clipboard |
| SUPER + SHIFT + ALT + 1 to 0 | Move window to workspace |

Omahub edits one marked block in `~/.config/hypr/bindings.lua`, backs the file up first, and restores it if Hyprland reports an error.

Without a layout, open Omahub with `omarchy-shell shell toggle io.github.elberacasa.omahub`.

## Remove

Run `keymap.sh off` first if you picked a layout, then:

```bash
omarchy plugin remove io.github.elberacasa.omahub
```

## Requirements

- Omarchy 4.0 or newer
- No external dependencies beyond what ships with Omarchy

## License

MIT
