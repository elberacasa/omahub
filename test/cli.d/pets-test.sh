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
const Pets = new Function(source + "\nreturn { frame, frameCount, petFor, PETS, parsePalette, hueFor, projectHues }")()
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
check("every pixel is one the dock colors", frames.every(rows => rows.every(row => /^[.#aeupk]+$/.test(row))))
check("every pet looks different", new Set(pets.map(pet => text(Pets.frame(pet, "agent", 0)))).size === pets.length)
check("every pet wears its mark", pets.every(pet => text(Pets.frame(pet, "agent", 0)).includes("a")))
check("paws, eyes, and mouths land on every pet's body", pets.every(pet =>
  ["agent", "working", "done", "idle", "waiting"].every(state => (text(Pets.frame(pet, state, 0)).match(/e/g) || []).length >= 2)))
check("an idle pet shuts its eyes and holds its pose, its sleep drawn over it", pets.every(pet =>
  Pets.frame(pet, "idle", 0)[10].includes("eee") && Pets.frameCount("idle") === 1))
check("a working pet taps at its keyboard", pets.every(pet => text(Pets.frame(pet, "working", 0)) !== text(Pets.frame(pet, "working", 1))
  && text(Pets.frame(pet, "working", 0)).includes("k")))
check("a pet whose turn is done holds still", Pets.frameCount("done") === 1 && Pets.frameCount("agent") === 1)
check("a pet calling you turns its mark urgent", pets.every(pet => ["waiting", "attention"].every(state =>
  text(Pets.frame(pet, state, 0)).includes("u") && !text(Pets.frame(pet, state, 0)).includes("a"))))

const palette = Pets.parsePalette('red = "#dd3344"\norange="#ee8833" # warm\nyellow = "#eecc22"\ngreen = "#44bb55"\ncyan = "#33bbcc"\nblue = "#3377ee"\nmagenta = "#cc55bb"\nforeground = "#ffffff"\nbroken = "#12"')
check("a theme's palette is read by name, and nothing else", Object.keys(palette).join(",") === "red,orange,yellow,green,cyan,blue,magenta")
check("every pet wears its own color", new Set(pets.map(pet => Pets.hueFor(pet, palette))).size === pets.length)
check("a theme without orange gives the blob its next color", Pets.hueFor("blob", { yellow: "#eecc22", red: "#dd3344" }) === "#eecc22")
check("with no palette a pet has no color of its own", Pets.hueFor("cat", {}) === "")
const projects = ["omahub", "omalink", "omavant", "omarchy-logitech", "experiment", "lumen"]
const tints = Pets.projectHues(projects, palette)
check("up to six projects on the dock each get a different color", new Set(projects.map(name => tints[name])).size === 6)
check("none of them is red, which means waiting", projects.every(name => tints[name] && tints[name] !== palette.red))
check("a project keeps its color whatever order the projects arrive in",
  JSON.stringify(Pets.projectHues(projects.slice().reverse(), palette)) === JSON.stringify(tints))
check("a seventh project shares a color rather than going without",
  Object.keys(Pets.projectHues(projects.concat(["tidewater"]), palette)).length === 7)
check("a theme with fewer colors spreads projects over the ones it has",
  new Set(Object.values(Pets.projectHues(["a", "b"], { yellow: "#eecc22", green: "#44bb55", red: "#dd3344" }))).size === 2)
check("a theme with none of them leaves projects without a color, so pets wear their own", Object.keys(Pets.projectHues(projects, {})).length === 0)
const eyeRow = (rows, r) => rows[r].split("").map((pixel, c) => pixel === "e" ? c : -1).filter(c => c >= 0).join(",")
check("a blinking pet shuts its eyes for a moment", pets.every(pet => {
  const shut = Pets.frame(pet, "agent", 0, { blink: true })
  return eyeRow(shut, 8) === "" && eyeRow(shut, 9) !== ""
}))
check("a pet looks toward the pointer", eyeRow(Pets.frame("blob", "agent", 0, { gazeX: 1 }), 8) === "6,11"
  && eyeRow(Pets.frame("blob", "agent", 0, { gazeX: -1 }), 8) === "4,9")
check("and up from its keyboard when the keyboard reaches it", eyeRow(Pets.frame("blob", "working", 0, { gazeY: -1 }), 9) === "5,10"
  && eyeRow(Pets.frame("blob", "working", 0, { gazeY: -1 }), 10) === "")
check("a sleeping pet neither blinks nor looks around", pets.every(pet =>
  text(Pets.frame(pet, "idle", 0, { blink: true, gazeX: 1, gazeY: -1 })) === text(Pets.frame(pet, "idle", 0))))
check("a pet never looks out past its own body", pets.every(pet => [-1, 1].every(dx =>
  (text(Pets.frame(pet, "waiting", 0, { gazeX: dx })).match(/e/g) || []).length === (text(Pets.frame(pet, "waiting", 0)).match(/e/g) || []).length)))

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
