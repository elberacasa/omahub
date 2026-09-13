# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Omahub overlay skeleton with section tabs. Switch sections with h and l, the arrow keys, Tab, or 1 to 5. Esc closes.
- Switchable keyboard layouts in `scripts/keymap.sh`: Omarchy defaults or Mac screenshot keys, with SUPER + A for Omahub in both.
- Mac screenshot keys use Omahub Capture when it is installed and fall back to Omarchy's screenshot flow when it is not.
- Development tools: `bin/dev-sync`, plus `bin/take`, `bin/frames`, and `bin/export-media` for recording takes and reviewing motion frame by frame.
- Keycap brand in `assets/`: mark, logo, and an animated hero for light and dark grounds, plus a block-character logo for terminals.

### Changed

- Development tools moved from `bin/` to `dev/`, leaving `bin/` for the upcoming `omahub` command.
