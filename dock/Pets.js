.pragma library

// Pixel pets for the agent tiles on the dock, on a 16 pixel grid in the theme's colors. Every company
// behind an agent's model has a pet of its own, and anyone can pick another in the hub: a blob wearing a
// sparkle, a boxy cat with a loop, a gem, a moon bunny, a fox, an owl, or a small robot. The pose says
// what the agent is doing.
//
// Pixels: # body, a the pet's mark, u the mark calling you, e eyes and mouth, p paws, k keyboard,
// z sleep, and . nothing.

const BODIES = {
  blob: [
    ".......a........",
    "......aaa.......",
    ".......a........",
    ".......#........",
    ".....######.....",
    "...##########...",
    "..############..",
    ".##############.",
    ".##############.",
    ".##############.",
    ".##############.",
    "..############..",
    "...##########...",
    ".....######.....",
    "....pp....pp....",
    "................"
  ],
  cat: [
    "......aaa.......",
    "......a.a.......",
    "......aaa.......",
    ".......#........",
    "..##...#....##..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "...##########...",
    "...pp......pp...",
    "................"
  ],
  gem: [
    "......a.a.......",
    ".......a........",
    "......a.a.......",
    ".......#........",
    "......####......",
    ".....######.....",
    "....########....",
    "...##########...",
    "..############..",
    ".##############.",
    ".##############.",
    "..############..",
    "...##########...",
    "....########....",
    "....pp....pp....",
    "................"
  ],
  bunny: [
    ".aa..##..##.....",
    "a....##..##.....",
    ".aa..##..##.....",
    ".....##..##.....",
    ".....######.....",
    "...##########...",
    "..############..",
    ".##############.",
    ".##############.",
    ".##############.",
    ".##############.",
    "..############..",
    "...##########...",
    ".....######.....",
    "....pp....pp....",
    "................"
  ],
  fox: [
    "................",
    "...a........a...",
    "...##......##...",
    "...###....###...",
    "...##########...",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "...##########...",
    "....########....",
    ".....######.....",
    "....pp....pp....",
    "................"
  ],
  owl: [
    "................",
    "................",
    "...a........a...",
    "...##......##...",
    "...##########...",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "...##########...",
    "....########....",
    "...pp......pp...",
    "................"
  ],
  robot: [
    "................",
    ".......a........",
    ".......#........",
    ".......#........",
    "...##########...",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "..############..",
    "...##########...",
    "...pp......pp...",
    "................"
  ]
}

// The pets in the order the hub offers them, and the one each company starts with.
const PETS = ["blob", "cat", "gem", "bunny", "fox", "owl", "robot"]
const DEFAULTS = { anthropic: "blob", openai: "cat", google: "gem", moonshot: "bunny" }

// Each mood draws its face and paws over the body: [row, column, pixel].
const FACES = {
  present: () => [[8, 5, "e"], [9, 5, "e"], [8, 10, "e"], [9, 10, "e"]],
  // Eyes down on a tiny keyboard, paws tapping.
  working: step => [[10, 5, "e"], [10, 10, "e"]]
    .concat(clearRow(14))
    .concat(step % 2 === 0 ? [[14, 4, "p"], [14, 9, "p"]] : [[14, 6, "p"], [14, 11, "p"]])
    .concat(range(2, 13).map(column => [15, column, "k"])),
  // Happy eyes and an open mouth, arms out against its sides.
  done: (step, body) => [[9, 4, "e"], [8, 5, "e"], [9, 6, "e"], [9, 9, "e"], [8, 10, "e"], [9, 11, "e"], [11, 7, "e"], [11, 8, "e"]]
    .concat(arms(body, 9)).concat(arms(body, 10)),
  // Eyes shut, a z coming and going behind its ears.
  idle: step => [[10, 4, "e"], [10, 5, "e"], [10, 6, "e"], [10, 9, "e"], [10, 10, "e"], [10, 11, "e"]]
    .concat(step % 2 === 0 ? [[0, 11, "z"], [0, 12, "z"], [0, 13, "z"], [0, 14, "z"], [1, 13, "z"], [2, 12, "z"],
      [3, 11, "z"], [3, 12, "z"], [3, 13, "z"], [3, 14, "z"]] : []),
  // Wide eyes and an exclamation mark, on the outer edge where no ears or tufts reach.
  waiting: () => [[8, 5, "e"], [8, 6, "e"], [9, 5, "e"], [9, 6, "e"], [8, 9, "e"], [8, 10, "e"], [9, 9, "e"], [9, 10, "e"],
    [0, 15, "u"], [1, 15, "u"], [3, 15, "u"]]
}

function range(from, to) {
  const list = []
  for (let value = from; value <= to; value++) list.push(value)
  return list
}

// Paws just outside the body's edges on a row, whatever the pet's shape.
function arms(body, row) {
  const line = body[row]
  return [[row, line.indexOf("#") - 1, "p"], [row, line.lastIndexOf("#") + 1, "p"]]
}

function clearRow(row) {
  return range(0, 15).map(column => [row, column, "."])
}

// The pet to draw: `look` when it names one, as in the hub's gallery, or else the pet chosen for the
// company in the dock's settings (`pet-anthropic` and so on), the company's own, or the one chosen for
// everyone else.
function petFor(family, look, choices) {
  if (BODIES[look]) return look
  const chosen = choices ? choices["pet-" + family] : ""
  if (BODIES[chosen]) return chosen
  if (DEFAULTS[family]) return DEFAULTS[family]
  const other = choices ? choices["pet-other"] : ""
  return BODIES[other] ? other : "robot"
}

// The look a dock state gives a pet.
function moodOf(state) {
  if (state === "attention") return "waiting"
  return FACES[state] ? state : "present"
}

function frameCount(state) {
  const mood = moodOf(state)
  return mood === "working" || mood === "idle" ? 2 : 1
}

// One frame of a pet: `pet` is one of PETS, `state` the dock's activity state, and `step` counts frames
// for the moods that move.
function frame(pet, state, step) {
  const mood = moodOf(state)
  const body = BODIES[pet] || BODIES.robot
  const rows = body.map(row => row.split(""))
  if (mood === "waiting") {
    for (let r = 0; r < 4; r++) rows[r] = rows[r].map(pixel => pixel === "a" ? "u" : pixel)
  }
  for (const pixel of FACES[mood](step || 0, body)) {
    // Sleep drifts behind the pet, never over it.
    if (pixel[2] === "z" && rows[pixel[0]][pixel[1]] !== ".") continue
    rows[pixel[0]][pixel[1]] = pixel[2]
  }
  return rows.map(row => row.join(""))
}
