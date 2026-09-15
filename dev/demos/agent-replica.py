#!/usr/bin/python3
# A stand-in for Claude Code or Codex in demo recordings: a full terminal screen drawn the way each one
# looks, driven by a file of events a scene appends to. It never talks to any model or account. Typing
# into it shows in its input, and Enter moves the text into the transcript and notes it for the scene.
#
#   REPLICA_AGENT=claude|codex REPLICA_EVENTS=<file> [REPLICA_SUBMITTED=<file>] [REPLICA_MODEL=<name>]
#
# Launch it through a script named claude or codex, so the process table shows that name and Omahub
# finds it like the real agent. Events are JSON lines:
#   {"type": "user", "text": ...}                      a prompt already sent
#   {"type": "say", "text": ...}                       the agent writes
#   {"type": "tool", "name": ..., "arg": ..., "result": ...}
#   {"type": "diff", "rows": [["+", 12, "code"], ...]}
#   {"type": "spin", "label": ..., "elapsed": seconds} and {"type": "spin_off"}
#   {"type": "ask", "tool": ..., "command": ..., "note": ...} and {"type": "ask_off"}
#   {"type": "done", "text": ..., "worked": "2m 14s"}

import json
import os
import select
import signal
import sys
import termios
import textwrap
import time
import tty

AGENT = os.environ.get("REPLICA_AGENT", "claude")
EVENTS = os.environ.get("REPLICA_EVENTS", "")
SUBMITTED = os.environ.get("REPLICA_SUBMITTED", "")
MODEL = os.environ.get("REPLICA_MODEL", "")
FOLDER = "~/Code/" + os.path.basename(os.getcwd())

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
ITALIC = "\033[3m"
GREEN = "\033[32m"
RED = "\033[31m"
CYAN = "\033[36m"
ACCENT = "\033[38;2;215;119;87m" if AGENT == "claude" else "\033[38;2;130;170;255m"
ADDED = "\033[48;2;30;62;42m"
REMOVED = "\033[48;2;74;34;40m"
PROMPT = "\033[48;2;46;48;60m"

transcript = []
state = {"input": "", "spin": None, "since": 0.0, "ask": None}


def line(*segments):
    return [(style, str(text)) for style, text in segments]


def render(segments, width):
    out, used = [], 0
    for style, text in segments:
        room = width - used
        if room <= 0:
            break
        text = text[:room]
        out.append(style + text + RESET if style else text)
        used += len(text)
    return "".join(out), used


def filled(segments, width, background):
    text, used = render(segments, width)
    return background + text.replace(RESET, RESET + background) + " " * max(0, width - used) + RESET


def wrapped(first, rest, style, text, width):
    rows = textwrap.wrap(text, max(10, width - len(first))) or [""]
    return [line(first_style, lead, (style, row)) for (first_style, lead), row in
            zip([(ACCENT if AGENT == "claude" and first.strip() == "⏺" else "", first)] + [("", rest)] * len(rows), rows)]


def transcript_rows(width):
    rows = []
    for entry in transcript:
        kind = entry["type"]
        if kind == "user":
            if AGENT == "claude":
                for row in textwrap.wrap(entry["text"], max(10, width - 4)) or [""]:
                    rows.append(("fill", line((DIM, "> "), ("", row)), PROMPT))
            else:
                for index, row in enumerate(textwrap.wrap(entry["text"], max(10, width - 4)) or [""]):
                    rows.append(("fill", line((BOLD + CYAN, "› " if index == 0 else "  "), (BOLD, row)), PROMPT))
            rows.append(line())
        elif kind == "say":
            mark = "⏺ " if AGENT == "claude" else "• "
            for index, row in enumerate(textwrap.wrap(entry["text"], max(10, width - 3)) or [""]):
                rows.append(line(("", mark if index == 0 else "  "), ("", row)))
            rows.append(line())
        elif kind == "tool":
            if AGENT == "claude":
                rows.append(line((GREEN, "⏺ "), (BOLD, entry["name"]), ("", "(" + entry.get("arg", "") + ")")))
                if entry.get("result"):
                    rows.append(line((DIM, "  ⎿  "), (DIM, entry["result"])))
                rows.append(line())
            else:
                rows.append(line((GREEN, "• "), (BOLD, entry["name"]), ("", " " + entry.get("arg", ""))))
                if entry.get("result"):
                    rows.append(line((DIM, "  └ "), (DIM, entry["result"])))
        elif kind == "diff":
            for sign, number, code in entry["rows"]:
                background = ADDED if sign == "+" else (REMOVED if sign == "-" else "")
                segments = line((DIM, "      %4s " % number), ("", sign + " "), ("", code))
                rows.append(("fill", segments, background) if background else segments)
        elif kind == "worked":
            rows.append(line((DIM, "✻ Worked for " + entry["text"])))
            rows.append(line())
        elif kind == "gap":
            rows.append(line())
    return rows


def header(width):
    box = min(60, width - 2)
    if AGENT == "claude":
        body = [line((ACCENT, "✻ "), (BOLD, "Welcome to Claude Code!")), line(),
                line((DIM, "  /help for help, /status for your current setup")), line(),
                line((DIM, "  cwd: " + FOLDER))]
    else:
        body = [line((BOLD, ">_ OpenAI Codex")), line(),
                line((DIM, " model:     "), ("", MODEL), (DIM, "   /model to change")),
                line((DIM, " directory: "), ("", FOLDER))]
    rows = [line((DIM, "╭" + "─" * (box - 2) + "╮"))]
    for segments in body:
        text, used = render(segments, box - 4)
        rows.append(("raw", DIM + "│ " + RESET + text + " " * (box - 4 - used) + DIM + " │" + RESET))
    rows.append(line((DIM, "╰" + "─" * (box - 2) + "╯")))
    rows.append(line())
    return rows


def spinner(width):
    if state["spin"] is None:
        return []
    seconds = int(time.time() - state["since"])
    if AGENT == "claude":
        glyphs = "·✢✳✶✻✽✻✶✳✢"
        glyph = glyphs[int(time.time() * 8) % len(glyphs)]
        return [line((ACCENT, glyph + " " + state["spin"] + "… "), (DIM, "(%ds · esc to interrupt)" % seconds)), line()]
    shimmer = BOLD if int(time.time() * 3) % 2 == 0 else ""
    return [line((shimmer, "• " + state["spin"] + " "), (DIM, "(%ds • esc to interrupt)" % seconds)), line()]


def ask_box(width):
    ask = state["ask"]
    if ask is None:
        return []
    box = min(86, width - 2)
    if AGENT == "claude":
        body = [line((BOLD, ask.get("tool", "Bash") + " command")), line(),
                line(("", "  " + ask.get("command", ""))), line((DIM, "  " + ask.get("note", ""))), line(),
                line(("", "Do you want to proceed?")),
                line((ACCENT, "❯ "), (ACCENT, "1. Yes")),
                line(("", "  2. Yes, and don't ask again for this command in " + FOLDER)),
                line(("", "  3. No, and tell Claude what to do differently "), (DIM, "(esc)"))]
    else:
        body = [line((BOLD, "Allow command?")), line(), line((DIM, "$ "), ("", ask.get("command", ""))), line(),
                line((ACCENT, "❯ Yes (y)"), ("", "   Always for this session (a)   No (n)"))]
    rows = [line((ACCENT, "╭" + "─" * (box - 2) + "╮"))]
    for segments in body:
        text, used = render(segments, box - 4)
        rows.append(("raw", ACCENT + "│ " + RESET + text + " " * (box - 4 - used) + ACCENT + " │" + RESET))
    rows.append(line((ACCENT, "╰" + "─" * (box - 2) + "╯")))
    return rows


def input_rows(width):
    if state["ask"] is not None:
        return []
    caret = "\033[7m \033[27m"
    if AGENT == "claude":
        text, used = render(line(("", state["input"][-(width - 8):])), width - 8)
        return [line((DIM, "╭" + "─" * (width - 2) + "╮")),
                ("raw", DIM + "│" + RESET + " > " + text + caret + " " * max(0, width - 6 - used) + DIM + "│" + RESET),
                line((DIM, "╰" + "─" * (width - 2) + "╯")),
                line((DIM, "  ? for shortcuts"))]
    if state["input"]:
        typed = ("raw", BOLD + "› " + RESET + state["input"][-(width - 4):] + caret)
    else:
        typed = ("raw", BOLD + "› " + RESET + caret + DIM + "Ask Codex to do anything" + RESET)
    return [typed, line(), line((DIM, "  ⏎ send   ⌃J newline   ⌃T transcript   ⌃C quit"))]


def draw():
    columns, lines = os.get_terminal_size()
    width = max(20, columns - 2)
    rows = header(width) + transcript_rows(width) + spinner(width) + ask_box(width) + input_rows(width)
    rows = rows[-(lines - 1):]
    out = ["\033[H"]
    for row in rows:
        if isinstance(row, tuple) and row[0] == "raw":
            text = row[1]
        elif isinstance(row, tuple) and row[0] == "fill":
            text = filled(row[1], width, row[2])
        else:
            text = render(row, width)[0]
        out.append(" " + text + "\033[K\r\n")
    out.append("\033[J")
    sys.stdout.write("".join(out))
    sys.stdout.flush()


def apply(event):
    kind = event.get("type")
    if kind in ("user", "say", "tool", "diff", "gap"):
        transcript.append(event)
    elif kind == "spin":
        state["spin"] = event.get("label", "Thinking")
        state["since"] = time.time() - float(event.get("elapsed", 0))
    elif kind == "spin_off":
        state["spin"] = None
    elif kind == "ask":
        state["ask"] = event
    elif kind == "ask_off":
        state["ask"] = None
    elif kind == "done":
        state["spin"] = None
        transcript.append({"type": "say", "text": event.get("text", "")})
        if event.get("worked") and AGENT == "claude":
            transcript.append({"type": "worked", "text": event["worked"]})


def read_events(offset):
    if not EVENTS or not os.path.exists(EVENTS):
        return offset
    with open(EVENTS, encoding="utf-8") as handle:
        handle.seek(offset)
        while True:
            start = handle.tell()
            text = handle.readline()
            if not text.endswith("\n"):
                return start
            try:
                apply(json.loads(text))
            except ValueError:
                pass


def typed(keys):
    for key in keys:
        if key in ("\r", "\n"):
            text = state["input"].strip()
            state["input"] = ""
            if text:
                transcript.append({"type": "user", "text": text})
                if SUBMITTED:
                    with open(SUBMITTED, "a", encoding="utf-8") as handle:
                        handle.write(text + "\n")
        elif key == "\x7f":
            state["input"] = state["input"][:-1]
        elif key.isprintable():
            state["input"] += key


def main():
    descriptor = sys.stdin.fileno()
    saved = termios.tcgetattr(descriptor)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(0))
    tty.setcbreak(descriptor)
    sys.stdout.write("\033[?25l\033[2J")
    offset = 0
    try:
        while True:
            offset = read_events(offset)
            ready, _, _ = select.select([descriptor], [], [], 0.06)
            if ready:
                data = os.read(descriptor, 256).decode("utf-8", "ignore")
                if not data.startswith("\x1b"):
                    typed(data)
            draw()
    finally:
        termios.tcsetattr(descriptor, termios.TCSADRAIN, saved)
        sys.stdout.write("\033[?25h" + RESET)


if __name__ == "__main__":
    main()
