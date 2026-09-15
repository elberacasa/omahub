.pragma library

// Pixel pets for the agent tiles on the dock, one for each company behind an agent's model, on a 16 pixel
// grid in the theme's colors: a round blob wearing a sparkle for Anthropic, a boxy cat with a loop for
// OpenAI, and a small robot for everyone else. The pose says what the agent is doing.
//
// Pixels: # body, a the company's mark, u the mark calling you, e eyes and mouth, p paws, k keyboard,
// z sleep, and . nothing.

const BODIES = {
  anthropic: [
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
  openai: [
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
  other: [
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
  // Eyes shut, a z coming and going.
  idle: step => [[10, 4, "e"], [10, 5, "e"], [10, 6, "e"], [10, 9, "e"], [10, 10, "e"], [10, 11, "e"]]
    .concat(step % 2 === 0 ? [[0, 11, "z"], [0, 12, "z"], [0, 13, "z"], [0, 14, "z"], [1, 13, "z"], [2, 12, "z"],
      [3, 11, "z"], [3, 12, "z"], [3, 13, "z"], [3, 14, "z"]] : []),
  // Wide eyes and an exclamation mark.
  waiting: () => [[8, 5, "e"], [8, 6, "e"], [9, 5, "e"], [9, 6, "e"], [8, 9, "e"], [8, 10, "e"], [9, 9, "e"], [9, 10, "e"],
    [0, 14, "u"], [1, 14, "u"], [3, 14, "u"]]
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

// The look a dock state gives a pet.
function moodOf(state) {
  if (state === "attention") return "waiting"
  return FACES[state] ? state : "present"
}

function frameCount(state) {
  const mood = moodOf(state)
  return mood === "working" || mood === "idle" ? 2 : 1
}

// One frame of a pet: `family` is the company behind the agent's model, `state` the dock's activity state,
// and `step` counts frames for the moods that move.
function frame(family, state, step) {
  const mood = moodOf(state)
  const rows = (BODIES[family] || BODIES.other).map(row => row.split(""))
  if (mood === "waiting") {
    for (let r = 0; r < 4; r++) rows[r] = rows[r].map(pixel => pixel === "a" ? "u" : pixel)
  }
  for (const pixel of FACES[mood](step || 0, BODIES[family] || BODIES.other)) rows[pixel[0]][pixel[1]] = pixel[2]
  return rows.map(row => row.join(""))
}
