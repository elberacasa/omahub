---
name: omahub
description: >
  Read and change Omahub settings on an Omarchy machine: keyboard layers such as Mac
  screenshot keys, Vim focus, and agent keys, the detected keyboard size, the screenshot
  folder, and anything else the Omahub hub shows. Use when asked to change a keybinding
  Omahub manages, turn a Mac touch on or off, find where screenshots are saved, or explain
  what SUPER + A shows. Triggers: omahub, SUPER + A hub, Mac keys, screenshot keys, vim
  focus, agent keys, keyboard size, screenshot folder.
---

# Omahub

Omahub is the settings hub for Omarchy that opens on SUPER + A. Every row in it is one
setting file, and the `omahub` command runs the same files. Change settings through the
command so the hub, the person at the keyboard, and you always agree.

## Find the command

Use `omahub` when it is on the PATH. Otherwise run it from the plugin:

```bash
~/.config/omarchy/plugins/io.github.elberacasa.omahub/bin/omahub
```

## Read before you change

```bash
omahub settings                 # every setting, grouped by section
omahub settings --json          # the same, with kind, summary, and keywords
omahub get keyboard/vim-focus   # {"value": true, "label": "On"}
omahub options keyboard/size    # choices for choice and folder settings
```

`get` reads the real system every time. Trust it over any file you inspect by hand.

## Change a setting

```bash
omahub set keyboard/mac-screenshot-keys on
omahub set keyboard/size 65
omahub set capture/screenshot-folder ~/Pictures/Screenshots
omahub reset keyboard/agent-keys   # undo everything that setting changed
```

- Toggles take `on` or `off`. Choices take a `value` from `options`. Folders take a path.
- `set` prints the new state. A non-zero exit means nothing changed, and stderr says why.
- Keyboard settings check that every Omarchy action still has a key afterwards, and undo
  themselves if one would be lost. Report that message to the person rather than working
  around it.

## Start work

```bash
omahub agent                # the default agent, in the projects folder
omahub agent codex --pick   # Codex, in a folder the person picks or creates
omahub edit                 # the projects folder, in the default editor
```

The default agent, editor, and projects folder are the settings `agents/default-agent`, `agents/editor`, and `agents/projects-folder`.

## Rules

- Never edit the marked blocks Omahub writes, such as `-- omahub:keymap:start` in
  `~/.config/hypr/bindings.lua` or `# omahub:screenshot-dir:start` in
  `~/.config/uwsm/default`. Use `set` and `reset`.
- Ask before turning on a setting the person did not mention. Every setting is opt in.
- To show the person the result, run `omahub open <section>` to open the hub there.
- `omahub settings` lists only what is installed. A missing setting usually means its
  plugin, such as Omahub Capture, is not installed.
