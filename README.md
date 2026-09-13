# Omahub

Browse, install, and manage everything Omarchy offers from one place.

Omahub is a native Omarchy shell plugin. It opens instantly, follows your theme, and works entirely from the keyboard. Apps, themes, plugins, services, and dev environments all live behind one search box.

> Status: early development. Not ready for daily use yet.

## Install

```bash
omarchy plugin add https://github.com/elberacasa/omahub.git --enable
```

Plugins land disabled by default so you can review the code first. Omahub runs Omarchy's own commands and never uses sudo itself. Anything that needs your password opens in a visible terminal.

## Remove

```bash
omarchy plugin remove io.github.elberacasa.omahub
```

## Requirements

- Omarchy 4.0 or newer
- No external dependencies beyond what ships with Omarchy

## License

MIT
