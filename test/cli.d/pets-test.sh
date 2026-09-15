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
const Pets = new Function(source + "\nreturn { frame, frameCount, petFor, PETS }")()
const checks = []
const check = (name, ok) => checks.push({ name, ok: !!ok })

const pets = Pets.PETS
const states = ["agent", "working", "done", "idle", "waiting", "attention", "media", ""]
const frames = []
pets.forEach(pet => states.forEach(state => {
  for (let step = 0; step < Pets.frameCount(state); step++) frames.push(Pets.frame(pet, state, step))
}))
const text = rows => rows.join("\n")

check("the gallery has seven pets", pets.join(",") === "blob,cat,gem,bunny,fox,owl,robot")
check("every frame is 16 pixels square", frames.every(rows => rows.length === 16 && rows.every(row => row.length === 16)))
check("every pixel is one the dock colors", frames.every(rows => rows.every(row => /^[.#aeupkz]+$/.test(row))))
check("every pet looks different", new Set(pets.map(pet => text(Pets.frame(pet, "agent", 0)))).size === pets.length)
check("every pet wears its mark", pets.every(pet => text(Pets.frame(pet, "agent", 0)).includes("a")))
check("paws, eyes, and mouths land on every pet's body", pets.every(pet =>
  ["agent", "working", "done", "idle", "waiting"].every(state => (text(Pets.frame(pet, state, 0)).match(/e/g) || []).length >= 2)))
check("sleep drifts behind a pet, never over it", pets.every(pet => {
  const awake = Pets.frame(pet, "idle", 1)
  const asleep = Pets.frame(pet, "idle", 0)
  return asleep.every((row, r) => row.split("").every((pixel, c) => pixel !== "z" || awake[r][c] === "."))
}))
check("a working pet taps at its keyboard", pets.every(pet => text(Pets.frame(pet, "working", 0)) !== text(Pets.frame(pet, "working", 1))
  && text(Pets.frame(pet, "working", 0)).includes("k")))
check("a pet whose turn is done holds still", Pets.frameCount("done") === 1 && Pets.frameCount("agent") === 1)
check("a pet calling you turns its mark urgent", pets.every(pet => ["waiting", "attention"].every(state =>
  text(Pets.frame(pet, state, 0)).includes("u") && !text(Pets.frame(pet, state, 0)).includes("a"))))

check("every company starts with its own pet", Pets.petFor("anthropic") === "blob" && Pets.petFor("openai") === "cat"
  && Pets.petFor("google") === "gem" && Pets.petFor("moonshot") === "bunny" && Pets.petFor("other") === "robot")
check("a pet chosen for a company wins", Pets.petFor("anthropic", "", { "pet-anthropic": "fox" }) === "fox")
check("a choice that is not a pet is ignored", Pets.petFor("openai", "", { "pet-openai": "dragon" }) === "cat")
check("a company without a pet of its own takes the one chosen for everyone else",
  Pets.petFor("deepseek", "", { "pet-other": "owl" }) === "owl" && Pets.petFor("deepseek", "", {}) === "robot")
check("the gallery names a pet directly", Pets.petFor("anthropic", "gem", { "pet-anthropic": "fox" }) === "gem")

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
