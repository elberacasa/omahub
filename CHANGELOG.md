# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- The overview always shows desktops 1 to 5, each numbered with the key that reaches it, so an empty desktop is one key or one drop away. The New tile appears once they are all in use.
- A window moved with Shift + a number moves the moment the key is pressed and flies into its desktop's thumbnail, and u or Undo puts it back. The other windows slide into the room it leaves.
- Holding SUPER from SUPER + TAB is one gesture: pick a desktop with a number, a window with h j k l, the arrows, or the pointer, and letting go of SUPER goes there. Moving windows while holding it keeps the overview open to keep organizing.
- Holding Shift in the overview lights the desktop numbers and shows the keys that move windows. Dragging a window lights them too, and the desktop under it reads "Move here".
- Each desktop's label says how many windows are on it.
- Add apps in the dock's menu lists every installed app with the ones in the dock checked. Type to search, and click or press Enter to keep or remove an app.
- Drag an icon along the dock to move it, drag an open app among the kept ones to keep it there, or drag an icon off the dock to remove it. Shift + h and l move the app under the cursor after SUPER + D.
- `omahub dock order <app>...` keeps exactly those apps, in that order.
- For contributors and their agents: `dev/live` runs live checks of the overview and the dock on a real desktop, and `dev/agent` reads what Omahub shows and types on a virtual keyboard with the real keymap. Both work inside a sandbox of test windows that puts every setting back when it ends.

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
- Error messages say what went wrong and how to fix it, and name a value that was not understood.
- Setting summaries say one thing each, and the README, the agent guide, and the skill match what ships, including how to remove Omahub.
- Menu items and hints use sentence case, such as "Open in editor" and "Press Enter to go there".
- In the overview, h, j, k, and l move like the arrows, Shift + h and l jump desktops, and Shift + n moves the window to a new desktop. A middle click closes a window.
- Shift + a number moves a window on every keyboard layout, not only US ones.
- Esc during a drag in the overview cancels it, instead of leaving the dragged card stuck.
- While the overview is open, Omarchy's SUPER shortcuts step aside, so dragging a card with SUPER still held from SUPER + TAB no longer moves a window behind it, and SUPER + SHIFT + a number moves a window once.
- A quick SUPER + TAB where TAB and SUPER come up together flips to the last window, instead of leaving the overview open waiting for SUPER.
- Opening the hub on a setting lands on it in whatever section it lives, instead of staying on the section already open.
- The dock's right-click menu stays open instead of closing the moment it appears.
- After SUPER + D, the arrows, Enter, and Space reach the dock even with SUPER still held, instead of Omarchy's own shortcuts. Clicking a window, changing desktop, or SUPER + D again gives the keyboard back.
- Many desktops fit in the overview's strip, long names and searches are shortened instead of spilling, and a window with no title reads "Untitled window".
- The screenshot thumbnail slides in at its real size, instead of resizing after it appears, and shows the file's name when the image can't be shown.
- The thumbnail says Copied only after the copy worked, and says so when copying, opening the editor or Files, moving to trash, or saving fails, instead of disappearing.
- A screenshot taken while the thumbnail is saving or being dragged shows as soon as it is free, instead of being lost.
- The thumbnail's menu opens from the keyboard: SHIFT + PRINT with the thumbnail on, and SUPER + SHIFT + 6 with the Mac screenshot keys.

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
