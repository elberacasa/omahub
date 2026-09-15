.pragma library

// Pixel pets for the agent tiles on the dock, on a 16 pixel grid in the theme's colors. Every company
// behind an agent's model has a pet of its own, and anyone can pick another in the hub: a blob wearing a
// sparkle, a boxy cat with a loop, a gem, a moon bunny, a fox, an owl, or a small robot. The pose says
// what the agent is doing.
//
// Pixels: # body, a the pet's mark, u the mark calling you, e eyes and mouth, p paws, k keyboard, and
// . nothing. Sleep is not in the sprite: the pet draws its z's over itself, so they can drift.

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

// Each pet wears a color from the active theme's named palette, with the next closest when a theme lacks it.
const PALETTE = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta"]
const HUES = {
  blob: ["orange", "yellow", "red"],
  cat: ["green", "cyan"],
  gem: ["blue", "cyan"],
  bunny: ["magenta", "red"],
  fox: ["red", "orange"],
  owl: ["yellow", "orange"],
  robot: ["cyan", "blue"]
}
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
  // Eyes shut, asleep.
  idle: () => [[10, 4, "e"], [10, 5, "e"], [10, 6, "e"], [10, 9, "e"], [10, 10, "e"], [10, 11, "e"]],
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

// The named colors in a theme's colors.toml, such as red = "#f7768e", leaving out every other key.
function parsePalette(text) {
  const colors = {}
  for (const line of String(text || "").split("\n")) {
    const match = /^\s*([a-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/.exec(line)
    if (match && PALETTE.indexOf(match[1]) >= 0) colors[match[1]] = match[2]
  }
  return colors
}

// A pet's color from the theme's palette, or "" when the theme has none of its colors.
function hueFor(pet, colors) {
  for (const name of HUES[pet] || HUES.robot) {
    if (colors && colors[name]) return colors[name]
  }
  return ""
}

// On the dock, a pet wears its project's color, so agents of one company still read apart at a glance. Red stays
// free, since red means an agent waiting on you.
const PROJECT_HUES = ["orange", "yellow", "green", "cyan", "blue", "magenta"]

// Colors for the projects on the dock, as { name: color }: each project starts from the color its name hashes
// to and takes the next free one when that is taken, so up to six projects all differ, and a project keeps
// its color while the same projects are on the dock. Names are taken in order, so the result never depends
// on the order they arrive in. Only the theme's own colors are used; with none of them, the result is empty.
function projectHues(names, colors) {
  const available = PROJECT_HUES.filter(key => colors && colors[key])
  const result = {}
  if (available.length === 0) return result
  const taken = {}
  const unique = Array.from(new Set((names || []).map(name => String(name || "")).filter(name => name !== ""))).sort()
  for (const name of unique) {
    let hash = 2166136261
    for (let i = 0; i < name.length; i++) hash = Math.imul(hash ^ name.charCodeAt(i), 16777619) >>> 0
    const start = hash % available.length
    let pick = start
    for (let step = 0; step < available.length; step++) {
      const candidate = (start + step) % available.length
      if (!taken[candidate]) {
        pick = candidate
        break
      }
    }
    taken[pick] = true
    result[name] = colors[available[pick]]
  }
  return result
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
  return mood === "working" ? 2 : 1
}

// One frame of a pet: `pet` is one of PETS, `state` the dock's activity state, and `step` counts frames
// for the moods that move. `look` holds what a lively pet is doing with its eyes: `blink`, and `gazeX` and
// `gazeY`, each -1, 0, or 1, to look toward the pointer or up at you. A sleeping pet does neither.
function frame(pet, state, step, look) {
  const mood = moodOf(state)
  const body = BODIES[pet] || BODIES.robot
  const rows = body.map(row => row.split(""))
  if (mood === "waiting") {
    for (let r = 0; r < 4; r++) rows[r] = rows[r].map(pixel => pixel === "a" ? "u" : pixel)
  }
  for (const pixel of FACES[mood](step || 0, body)) rows[pixel[0]][pixel[1]] = pixel[2]
  if (look && mood !== "idle") {
    const eyes = eyePixels(rows)
    if (look.blink && mood !== "done" && eyes.length > 0) {
      const bottom = Math.max.apply(null, eyes.map(eye => eye[0]))
      for (const eye of eyes) rows[eye[0]][eye[1]] = "#"
      for (const eye of eyes) rows[bottom][eye[1]] = "e"
    }
    const dx = Math.max(-1, Math.min(1, look.gazeX || 0))
    const dy = Math.max(-1, Math.min(0, look.gazeY || 0))
    const moved = eyePixels(rows)
    const room = moved.every(eye => rows[eye[0] + dy] && ["#", "e"].indexOf(rows[eye[0] + dy][eye[1] + dx]) >= 0)
    if ((dx !== 0 || dy !== 0) && moved.length > 0 && room) {
      for (const eye of moved) rows[eye[0]][eye[1]] = "#"
      for (const eye of moved) rows[eye[0] + dy][eye[1] + dx] = "e"
    }
  }
  return rows.map(row => row.join(""))
}

// The eyes, as [row, column] pairs: the cut-outs above the mouth.
function eyePixels(rows) {
  const eyes = []
  for (let r = 6; r <= 10; r++) {
    for (let c = 0; c < rows[r].length; c++) {
      if (rows[r][c] === "e") eyes.push([r, c])
    }
  }
  return eyes
}
