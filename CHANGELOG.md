# Changelog

Notable changes to Omahub. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Agents in the dock, a switch in the dock's menu and settings: every agent at work gets its own tile between your apps and desktops, with a pixel pet in your theme's colors. The pet taps at a tiny keyboard while its agent works, hops with its arms up when the turn is done, and falls asleep once the agent has been idle for five minutes, all read from Claude Code's and Codex's own session records. Every Claude model shares a blob with a sparkle, every GPT model a boxy cat with a loop, and other models a small robot. Click a tile to go to that agent's window, even inside Cursor, and hover for a card with its project and branch, how long it has worked or how long ago it finished, the tool it is running and its model, and the first line it said when its turn ended. Agent cards in settings choose which of these the card shows, one chip each. Every company has its own pet, and a gallery in settings picks another for any company you use: a blob, a cat, a gem, a moon bunny, a fox, an owl, or a robot. Gemini models start with the gem and Kimi models with the bunny. A sleeping pet's z's drift up from its head and fade, Pet motion makes pets calm when you would rather they only change pose, and Naps after picks how long an agent stays quiet before its pet falls asleep: 5 minutes, 15 minutes, an hour, or never. Every agent's pet wears its project's color from your theme's palette, so agents of one company read apart at a glance and a project keeps its color, and the gallery shows each pet in its own color. Lively pets blink, look toward your pointer and up when SUPER + D reaches them, breathe in their sleep, squish when you press their tile, and celebrate a finished turn with a burst of their color. A waiting agent's tile is ringed in red. Right-click an agent's tile, or press Space on it after SUPER + D, to answer it without leaving your desktop: send Codex a message, which it reads when its turn ends, or, with Answer agents from the dock on, allow or deny what Claude asks to run, seeing exactly what it is. Claude still asks in its terminal too, and whichever you answer first counts. Turn on Waiting agents and Omahub adds one hook each to Claude Code and Codex, so when either asks for your answer its pet raises an exclamation mark, its card says it is waiting on you, and a hidden dock comes out until you answer. Codex asks you to trust its hook once in /hooks, and turning it off removes only those hooks. An agent that finishes while you are on another window brings a hidden dock out for a moment and keeps a dot under its tile until you look at it, and SUPER + D starts on the agent that needs you: one waiting on you first, then one that finished. The overview's badge shows Done and Idle too.
- The overview always shows desktops 1 to 5, each numbered with the key that reaches it, so an empty desktop is one key or one drop away. The New tile appears once they are all in use.
- A window moved with Shift + a number moves the moment the key is pressed and flies into its desktop's thumbnail, and u or Undo puts it back. The other windows slide into the room it leaves.
- Holding SUPER from SUPER + TAB is one gesture: pick a desktop with a number, a window with h j k l, the arrows, or the pointer, and letting go of SUPER goes there. Moving windows while holding it keeps the overview open to keep organizing.
- Holding Shift in the overview lights the desktop numbers and shows the keys that move windows. Dragging a window lights them too, and the desktop under it reads "Move here".
- Each desktop in the overview is named after what is on it: the project its terminals and editor are in, with the git branch and its apps' icons. Press r or right-click a desktop to give it your own name, which stays even when the desktop empties, and `omahub desktop name` does the same from a terminal.
- A badge on each desktop shows the agent running in its project, whether it runs in a terminal, in Cursor's terminal, or in a terminal inside Neovim, and a window asking for attention or media playing. It only shows what Omahub can read for certain.
- Search in the overview also finds desktops by their name, project, or branch.
- Press p in the overview, or click Projects, to open a project: your projects folder, newest first with each branch. Enter opens the project on a free desktop with your editor and agent, goes to the desktop it is already open on, or creates a project from a new name. `omahub project list` and `omahub project open` do the same from a terminal.
- Add apps in the dock's menu lists every installed app with the ones in the dock checked. Type to search, and click or press Enter to keep or remove an app.
- Drag an icon along the dock to move it, drag an open app among the kept ones to keep it there, or drag an icon off the dock to remove it. Shift + h and l move the app under the cursor after SUPER + D.
- `omahub dock order <app>...` keeps exactly those apps, in that order.
- Desktops in the dock, a switch in the dock's menu and settings: your desktops sit at the end of the dock, named like in the overview and showing the app used last. Click one to go there, drop an app on one to open it there, or reach them with SUPER + D.
- For contributors and their agents: `dev/live` runs live checks of the overview and the dock on a real desktop, and `dev/agent` reads what Omahub shows and types on a virtual keyboard with the real keymap. Both work inside a sandbox of test windows that puts every setting back when it ends. The live checks cover the overview, the dock and its agent tiles, cards, and waiting agents, the hub, the screenshot thumbnail, and turning Omahub off, on, and restarting it.
- `dev/privacy-check` reads every half second of a video with OCR and fails when a user name, host name, home folder, or git identity is on screen, and `dev/export-media` runs it on everything it exports.

### Fixed

- An agent started in a new terminal gets its tile right away when desktops in the dock and autohide are both off, instead of only after the shell restarts.
- Right-clicking an agent's tile or an app in the dock no longer crashes the shell now and then as the panel or menu opens.
- An agent working in a folder that is not a git project, such as Codex in one of several Cursor windows, gets its tile on that window's desktop and goes by the folder's name, instead of landing on another window of the same editor.
- Dock icons magnify and show their names only once the pointer is over the dock, not as it comes near, and settle as soon as it leaves them. The empty space above a resting dock no longer opens apps.
- Walking windows with SUPER + TAB and back with SHIFT + TAB, then letting go, jumps to the window chosen instead of leaving the overview open.
- A desktop's thumbnail in the overview shows a window that just moved or resized as it looks once it settles, not a frame from halfway through.
- A dock with no apps saved shows the default apps, so keeping one more adds just that one.
- A desktop where only an editor has a project open shows the project's branch too, when the project is in your projects folder.
- A desktop's branch in the overview no longer runs past its thumbnail when it has more apps than icons shown.
- A desktop of terminals in the dock is named by the project or tool running in them, like the overview names it, instead of by the terminal app.
- A dock notice about an app with a long name shortens the name instead of running off the screen beside a side dock.
- A dock with more apps than fit along its edge makes its icons smaller, like the Mac, instead of running past the screen and under the bar.

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
- Clicking an app in the dock, or a window or desktop in the overview, leaves the pointer where you clicked, even when the window is on another desktop, instead of jumping it to the middle of the screen. Switching from the keyboard still moves the pointer the way Omarchy does.
- The dock's right-click menu stays open instead of closing the moment it appears.
- The dock's menu and Add apps are never cut off at any dock position or magnification: the room beside the dock grows to fit what is open.
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
