# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Omahub overlay skeleton with section tabs. Switch sections with h and l, the arrow keys, Tab, or 1 to 5. Esc closes.
- Switchable keyboard layouts in `scripts/keymap.sh`: Omarchy defaults or Mac screenshot keys, with SUPER + A for Omahub in both.
- Mac screenshot keys use Omahub Capture when it is installed and fall back to Omarchy's screenshot flow when it is not.
- Development tools: `bin/dev-sync`, plus `bin/take`, `bin/frames`, and `bin/export-media` for recording takes and reviewing motion frame by frame.
- Keycap brand in `assets/`: mark, logo, and an animated hero for light and dark grounds, plus a block-character logo for terminals.
- `AGENTS.md`, `CONTRIBUTING.md`, a code of conduct, a security policy, and issue and pull request templates.
- The `omahub` command: `settings`, `get`, `set`, `options`, `reset`, `open`, and `version`, shared by the hub, the terminal, and agents.
- Settings as files. Each setting is one executable with `# omahub:` headers, found across Omahub, its sibling plugins, and `~/.config/omahub/settings`, where a file with the same name replaces the shipped one. Documented in `docs/settings.md`.
- `test/all`, which runs every test against a disposable home.
- Keyboard settings compare the actions Omarchy has keys for before and after every change, and undo the change if any action would lose its key.

### Changed

- Development tools moved from `bin/` to `dev/`, leaving `bin/` for the upcoming `omahub` command.
- Keyboard layouts are now two independent settings, `keyboard/omahub-key` and `keyboard/mac-screenshot-keys`, replacing `scripts/keymap.sh`. Existing setups keep working unchanged.

### Fixed

- The Mac layout no longer drops Omarchy's "move window silently to workspace". It now lives on SUPER + CTRL + ALT + number.
