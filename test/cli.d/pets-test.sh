#!/bin/bash

# dock/Pets.js: every frame of every pet is a whole sprite on one 16 pixel grid, drawn only in pixels the
# dock knows how to color, each company's pet is its own, and each mood reads differently.

source "$(dirname "$0")/../base-test.sh"

if ! command -v node >/dev/null 2>&1; then
  pass "node is not installed, so the pet checks are skipped"
  finish
fi

results=$(node - "$OMAHUB_PATH/dock/Pets.js" <<'SCRIPT'
const fs = require("fs")
const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library\s*/, "")
const Pets = new Function(source + "\nreturn { frame, frameCount }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

const families = ["anthropic", "openai", "other", "moonshot"]
const states = ["agent", "working", "done", "idle", "waiting", "attention", "media", ""]
const frames = []
families.forEach(family => states.forEach(state => {
  for (let step = 0; step < Pets.frameCount(state); step++) frames.push(Pets.frame(family, state, step))
}))
const text = rows => rows.join("\n")

check("every frame is 16 pixels square", frames.every(rows => rows.length === 16 && rows.every(row => row.length === 16)))
check("every pixel is one the dock colors", frames.every(rows => rows.every(row => /^[.#aeupkz]+$/.test(row))))
check("Anthropic, OpenAI, and everyone else each have their own pet",
  new Set(["anthropic", "openai", "other"].map(family => text(Pets.frame(family, "agent", 0)))).size === 3)
check("a company without its own pet gets the shared one", text(Pets.frame("moonshot", "done", 0)) === text(Pets.frame("other", "done", 0)))
check("every pet wears its company's mark", families.every(family => text(Pets.frame(family, "agent", 0)).includes("a")))
check("a working pet taps at its keyboard", text(Pets.frame("anthropic", "working", 0)) !== text(Pets.frame("anthropic", "working", 1))
  && text(Pets.frame("anthropic", "working", 0)).includes("k"))
check("a pet whose turn is done holds still", Pets.frameCount("done") === 1 && Pets.frameCount("agent") === 1)
check("done, idle, and working pets look different", new Set(["done", "idle", "working"].map(state => text(Pets.frame("openai", state, 1)))).size === 3)
check("an idle pet sleeps, its z coming and going", text(Pets.frame("anthropic", "idle", 0)).includes("z") && !text(Pets.frame("anthropic", "idle", 1)).includes("z"))
check("a pet calling you turns its mark urgent", ["waiting", "attention"].every(state =>
  text(Pets.frame("openai", state, 0)).includes("u") && !text(Pets.frame("openai", state, 0)).includes("a")))

console.log(JSON.stringify(checks))
SCRIPT
)

while IFS=$'\t' read -r ok name; do
  if [[ $ok == "true" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
done < <(jq -r '.[] | "\(.ok)\t\(.name)"' <<<"$results")

finish
