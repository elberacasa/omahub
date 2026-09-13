# Set up Omarchy with Omahub

You are a coding agent on an [Omarchy](https://omarchy.org) machine. The person asked you to set it up with Omahub, usually because they come from a Mac. Follow these steps in order. Talk to them like a friend who knows Linux: short, concrete, no jargon.

## Rules

- Nothing changes without a yes. Ask before installing anything and before turning on each setting group.
- Installs run in a terminal the person can see. Never pass `--yes` to `omarchy plugin add`, never use `sudo`.
- Change settings only through the `omahub` command. Never edit Omahub's marked blocks in config files by hand.
- If a command fails, show the person its message and stop that step. Every Omahub setting can be undone with `omahub reset <setting>`.

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

Offer Omahub Capture next: a Mac-style thumbnail after every screenshot. If they want it, install it the same way with `https://github.com/elberacasa/omahub-capture.git` and wait for `io.github.elberacasa.omahub-capture`.

Then load the new plugins:

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

- Mac screenshot keys: SUPER + SHIFT + 3, 4, and 5 take screenshots, like Command + Shift on a Mac
- Vim focus: H, J, K, and L move between windows, which suits small keyboards without arrow keys

If `value` is `null`, the keyboard was not recognized. Ask its size and set it with a value from `"$omahub" options keyboard/size`, then read the recommendations again.

Turn on what they choose, one setting at a time:

```bash
"$omahub" set keyboard/mac-screenshot-keys on
```

Keyboard settings make sure every Omarchy action still has a key, and undo themselves when one would be lost. If that happens, pass the message on rather than working around it. Tell them where anything that moved now lives; `omarchy menu keybindings --print` lists every key.

## 5. Screenshots

If Omahub Capture is installed, ask where screenshots should be saved:

```bash
"$omahub" options capture/screenshot-folder
"$omahub" set capture/screenshot-folder ~/Pictures/Screenshots
```

## 6. Show them

```bash
"$omahub" open
```

Finish with a short summary: what is on, the keys worth remembering, SUPER + A to open Omahub if "Omahub key" is on, and that anything can be changed back from the hub or by asking you.
