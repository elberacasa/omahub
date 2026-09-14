# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Fixed

- Switches and choices in the hub change the moment you pick them. If a change fails or takes too long, the row goes back to how it was and says why.
- A setting that could not be read says so, instead of looking switched off.
- New project keeps the name you typed until the project exists, and asks for a name when there is none.
- An unrecognized keyboard no longer reads "All 0 recommended settings are on".
- `omahub open` lands on a setting even when the hub had not loaded it yet.
- A click between two choices, or inside a name field, no longer changes the setting.
- The same change is never sent twice, and changes waiting their turn look it.
- Chips and buttons in the hub are taller and easier to hit, and a choice with many chips gives them their own line when they would crowd the title.
- Everything in the hub works from the keyboard: Shift + Space steps a choice back, Shift + Enter opens More… or Choose…, k from the first row reaches Turn on recommended, and Enter tries again after an error.
- Search has a button to clear it, a click away from a name field cancels it, and the hub opens scrolled to the top.
- The hub says what to do when Omarchy's folder chooser is missing, and its loading rows leave room for the keyboard card so nothing jumps.

## 0.1.0 - 2026-09-13

The first release: the Mac layer for Omarchy, one plugin with a hub for every setting. Nothing changes until you turn it on, and `omahub uninstall` puts everything back.

### Added

#### Hub

- SUPER + A opens a search-first hub of every setting, grouped by section, with the real state of your system in every row. j and k move, h and l switch sections, Space changes, / searches, and Esc closes.
- A welcome opens once on first load with your detected keyboard, the settings recommended for it, the screenshot thumbnail, the dock, and your default agent and editor. `omahub open welcome` brings it back.
- Settings are files. Each one is a small executable with `# omahub:` headers, and a file with the same name in `~/.config/omahub/settings` replaces the shipped one. See `docs/settings.md`.
- The `omahub` command runs the same settings from a terminal or an agent: `settings`, `get`, `set`, `options`, `reset`, `open`, `agent`, `edit`, `project new`, `dock`, `uninstall`, and `version`.

#### Keyboard

- Detects your keyboard and recommends the settings that fit it. Contributors add a keyboard with one file in `keyboards/`.
- The Omahub key (SUPER + A), Mac screenshot keys, Vim focus, agent keys, mouse side buttons, and SUPER + TAB, each a setting you can turn off.
- No Omarchy action loses its key. Every change compares the actions before and after, and undoes itself if one would lose its key. The README lists where moved actions now live.
- Each layer loads on its own, so a layer broken by an Omarchy update is skipped and named instead of stopping the rest of your bindings.

#### Overview

- SUPER + TAB flips to your last window with a tap. Held, it walks every window on every desktop, most recently used first, with live previews, and letting go jumps. A slow press stays open so you can look around and click any window.
- Every desktop as a live thumbnail: click one to go there, drag a window onto it to move it, and type to search every window. h, j, k, and l, Enter, x, Shift + a number, and n work from the keyboard.

#### Dock

- Your kept and open apps on a soft rounded shelf that follows your theme, starting from Omarchy's default terminal, browser, file manager, and editor.
- The Mac's dock settings: position on the left, bottom, or right, size, magnification, automatic hiding that steps aside only when a window reaches the dock, open app dots, open apps after a divider, the bounce when an app opens, and optional icon tiles.
- Kept on screen, the dock reserves its room so windows sit beside it. A right-click opens, keeps, or quits apps and changes the dock, and `omahub dock pin <app>` does the same from a terminal.

#### Screenshots

- A floating thumbnail after every screenshot: click to edit, drag into any app, drag right to dismiss, or right-click to copy, show in Files, trash, or save somewhere else.
- Pick the screenshot folder from the hub.

#### Projects and agents

- New project: type a name, and Omahub creates the folder, starts git, and opens your agent or editor there.
- Your default agent, editor, and projects folder, built on Omarchy's own `omarchy default` commands, so agents and editors Omarchy adds appear on their own.
- Choose which subscriptions show in Omarchy's Agents panel, put their limits on the bar, and pick for each plan which limit shows. Hovering a percentage names the limit and when it resets.
- An agent skill and a setup guide in `agents/`, so any coding agent can set up Omahub with you, asking before every change.

#### Development

- `test/all` runs every test against a disposable home, and `dev/` has tools to sync the plugin, record takes, script demos, and review motion frame by frame.
- `AGENTS.md`, `CONTRIBUTING.md`, a code of conduct, a security policy, and issue and pull request templates.
