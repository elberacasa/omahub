#!/bin/bash

# Retitle the terminal ten times a second, the way a coding agent's spinner does.

while :; do
  printf '\033]0;agent working %s\007' "$RANDOM"
  sleep 0.1
done
