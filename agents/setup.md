# Set up Omarchy with Omahub

You are a coding agent on an [Omarchy](https://omarchy.org) machine. The person asked you to set it up with Omahub, usually because they come from a Mac. Follow these steps in order. Talk to them like a friend who knows Linux: short, concrete, no jargon.

## Rules

- Nothing changes without a yes. Ask before installing anything and before turning on each setting group.
- Installs run in a terminal the person can see. Never pass `--yes` to `omarchy plugin add`, never use `sudo`.
- Change settings only through the `omahub` command. Never edit Omahub's marked blocks in config files by hand.
- If a command fails, show the person its message and stop that step. Every Omahub setting can be undone with `omahub reset <setting>`.
- Offer, do not push. A Mac user usually wants the dock and SUPER + TAB, but ask each time.

## 1. Check the machine

```bash
omarchy version
omarchy plugin list --json | jq -r '.[] | "\(.id) enabled=\(.enabled)"'
```

Omahub needs Omarchy 4.0 or newer. If `io.github.elberacasa.omahub` is already listed and enabled, skip to step 3.

## 2. Install Omahub

Tell the person a terminal will open and ask them to confirm there. Then run:

```bash
omarchy-launch-floating-terminal-with-presentation "omarchy plugin add https://github.com/elberacasa/omahub.git --enable"
```

Check every few seconds, for up to three minutes, until it is enabled:

```bash
omarchy plugin list --json | jq -e '.[] | select(.id == "io.github.elberacasa.omahub" and .enabled)'
```

Then load it:

```bash
omarchy restart shell
```

Omahub opens a welcome window once. Let the person know they can close it; you will set things up with them here.

## 3. Find the command

```bash
omahub=~/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub
"$omahub" version
```

Ask if you may turn on "Let agents use Omahub" and "Omahub command", so you and future agents can use Omahub without this guide:

```bash
"$omahub" set agents/skill on
"$omahub" set agents/command on
```

After that, `omahub` works in any new terminal, and the skill in `~/.agents/skills/omahub` covers everyday changes.

## 4. Match their keyboard

```bash
"$omahub" get keyboard/size
"$omahub" settings --json
```

`keyboard/size` names the keyboard, its size, and a `recommended` list of setting ids. Explain each recommended setting in one line, using its `summary` from the catalog. For example:

- Mac screenshot keys: SUPER + SHIFT + 3, 4, and 5 take screenshots, like a Mac
- Vim focus: H, J, K, and L focus, swap, and group windows, which suits small keyboards without arrow keys

If `value` is `null`, the keyboard was not recognized. Ask its size and set it with a value from `"$omahub" options keyboard/size`, then read the recommendations again.

Turn on what they choose, one setting at a time:

```bash
"$omahub" set keyboard/mac-screenshot-keys on
```

Keyboard settings make sure every Omarchy action still has a key, and undo themselves when one would be lost. If that happens, pass the message on rather than working around it. Tell them where anything that moved now lives; `omarchy menu keybindings --print` lists every key.

## 5. Screenshots

Offer the Mac-style thumbnail after every screenshot: click to edit, drag into any app, drag right to dismiss.

```bash
"$omahub" set capture/thumbnail on
```

Then ask where screenshots should be saved:

```bash
"$omahub" options capture/screenshot-folder
"$omahub" set capture/screenshot-folder ~/Pictures/Screenshots
```

## 6. The dock

Offer a dock for their pinned and open apps. It starts from Omarchy's own terminal, browser, file manager, and editor:

```bash
"$omahub" set dock/show on
```

Then ask how they had it on the Mac, one question at a time, and set only what they answer:

```bash
"$omahub" options dock/position   # left, bottom, or right
"$omahub" options dock/size       # small, medium, or large
"$omahub" options dock/magnify    # off, subtle, or large
"$omahub" set dock/autohide off   # keep it on screen, with windows sized around it
"$omahub" dock pin <app>          # keep another app, by its .desktop name
"$omahub" dock order <app>...     # keep exactly these apps, in this order
"$omahub" desktop name <n> <name> # name a desktop, shown in the overview; no name clears it
"$omahub" desktop names           # the names given so far, as JSON
```

## 7. Switching windows

If "Overview" was not among the keyboard settings they turned on, offer it: SUPER + TAB flips to the last window, and held, walks every window on every desktop with live previews.

```bash
"$omahub" set keyboard/overview on
```

## 8. Projects and agents

Ask which coding agent and editor they use, and where their projects live:

```bash
"$omahub" options projects/default-agent
"$omahub" set projects/default-agent <agent>
"$omahub" options projects/editor
"$omahub" set projects/editor <editor>
"$omahub" set projects/folder ~/Projects
```

If they use Claude or Codex, ask whether they want each plan's limit on the bar, and which limit it shows:

```bash
"$omahub" set agents/bar-limits on
"$omahub" options agents/claude-bar-limit
"$omahub" options agents/codex-bar-limit
```

## 9. Show them

```bash
"$omahub" open
```

Finish with a short summary: what is on, the keys worth remembering, SUPER + A to open Omahub if "Omahub key" is on, and that anything can be changed back from the hub or by asking you.

If they ever want Omahub gone, everything it changed goes back with one command run in a terminal they can see, before the plugin is removed:

```bash
"$omahub" uninstall
omarchy plugin remove io.github.elberacasa.omahub
```
