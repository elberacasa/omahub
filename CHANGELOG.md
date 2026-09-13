# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Switchable keyboard layouts in `scripts/keymap.sh`: Omarchy defaults or Mac screenshot keys, with SUPER + A for Omahub in both.
- Mac screenshot keys use Omahub Capture when it is installed and fall back to Omarchy's screenshot flow when it is not.
- Development tools: `bin/dev-sync`, plus `bin/take`, `bin/frames`, and `bin/export-media` for recording takes and reviewing motion frame by frame.
- Keycap brand in `assets/`: mark, logo, and an animated hero for light and dark grounds, plus a block-character logo for terminals.
- `AGENTS.md`, `CONTRIBUTING.md`, a code of conduct, a security policy, and issue and pull request templates.
- The `omahub` command: `settings`, `get`, `set`, `options`, `reset`, `open`, and `version`, shared by the hub, the terminal, and agents.
- Settings as files. Each setting is one executable with `# omahub:` headers, found across Omahub, its sibling plugins, and `~/.config/omahub/settings`, where a file with the same name replaces the shipped one. Documented in `docs/settings.md`.
- `test/all`, which runs every test against a disposable home.
- Keyboard settings compare the actions Omarchy has keys for before and after every change, and undo the change if any action would lose its key.
- `keyboard/vim-focus`: H, J, K, and L focus, swap, and group windows wherever Omarchy uses arrows. Keybindings join a help family on `/`.
- `keyboard/agent-keys`: Agent on SUPER + SHIFT + A, browser on SUPER + B, and dictation on SUPER + R.
- `keyboard/mouse-buttons`: hold SUPER and press a mouse side button to take a screenshot or toggle dictation.
- `keyboard/size`: detects the keyboard from known models and its name, and recommends the keyboard settings that fit it. Contributors add a keyboard with one file in `keyboards/`.
- The hub. SUPER + A opens a search-first overlay of every setting, grouped by section, with live state, a keyboard card that shows the detected keyboard and turns on its recommended settings, and full keyboard control: j and k move, h and l switch sections, Space changes, / searches, Esc closes. Settings are read when the shell starts, so the hub opens on real state with nothing shifting into place.
- An agent skill in `agents/skills/omahub`, and an Agents section: "Let agents use Omahub" links the skill into `~/.agents/skills`, and "Omahub command" puts `omahub` on the PATH. Both are off until turned on, and neither ever replaces a file already there.
- `agents/setup.md`, a guide any coding agent can follow to install Omahub and set it up with the person, asking before every change.
- `agents/claude-usage`, `agents/codex-usage`, and `agents/fireworks-usage` choose which subscriptions show in Omarchy's Agents bar panel, through `omarchy bar set`. They follow a clone of the widget made with `omarchy plugin clone`.
- `agents/bar-limits` shows every subscription's limit on the bar when the Agents widget offers a Limits mode.
- `agents/default-agent`, `agents/editor`, and `agents/projects-folder`, built on Omarchy's own `omarchy default` commands, so agents and editors Omarchy adds appear on their own. Reset restores what was chosen before.
- `omahub agent [agent] [--pick]` starts a coding agent in your projects folder or a folder you pick, and `omahub edit [--pick]` opens it in your editor.
- Folder settings in the hub: the current folder and quick places as chips, plus Choose… for any folder. Omahub Capture's screenshot folder is the first.
- The screenshot thumbnail, which began as Omahub Capture, now ships inside Omahub. Turn on `capture/thumbnail` and PRINT, the Mac screenshot keys, and the mouse shortcut show a floating thumbnail: click to edit, drag into any app, drag right to dismiss, or right-click to copy, show in Files, trash, or save to another folder.
- The welcome. The first time Omahub loads, it opens once with the detected keyboard and the settings recommended for it. `omahub open welcome` brings it back.

### Changed

- Development tools moved from `bin/` to `dev/`, leaving `bin/` for the upcoming `omahub` command.
- Keyboard layouts are now two independent settings, `keyboard/omahub-key` and `keyboard/mac-screenshot-keys`, replacing `scripts/keymap.sh`. Existing setups keep working unchanged.
- The Mac screenshot keys move windows to a workspace with SUPER + ALT + number, and group windows move to SUPER + CTRL + ALT + 1 to 5. Silent moves keep Omarchy's own SUPER + SHIFT + ALT + number.

### Fixed

- The Mac layout no longer drops Omarchy's "move window silently to workspace". It now lives on SUPER + CTRL + ALT + number.
