.pragma library

// Pure data shaping for the hub: sections, search, row order, and state parsing.

const SECTION_ORDER = ["keyboard", "capture", "dock", "projects", "agents", "appearance", "plugins", "system"]
const SECTION_LABELS = { keyboard: "Keyboard", capture: "Capture", dock: "Dock", projects: "Projects", agents: "Agents", appearance: "Appearance", plugins: "Plugins", system: "System" }
const SECTION_ICONS = { keyboard: "󰌌", capture: "󰄄", dock: "󰀻", projects: "󰉋", agents: "󰚩", appearance: "󰏘", plugins: "󰐱", system: "󰒓" }
const KIND_ORDER = { choice: 0, toggle: 1, folder: 2, keys: 3, action: 4 }

function sectionLabel(id) {
  return SECTION_LABELS[id] || id.charAt(0).toUpperCase() + id.slice(1)
}

function sectionIcon(id) {
  return SECTION_ICONS[id] || "󰒓"
}

function parseCatalog(text) {
  try {
    const list = JSON.parse(text)
    return Array.isArray(list) ? list.filter(setting => !setting.hidden) : null
  } catch (e) {
    return null
  }
}

function sections(catalog) {
  const counts = {}
  for (const setting of catalog) counts[setting.section] = (counts[setting.section] || 0) + 1
  const rank = id => {
    const index = SECTION_ORDER.indexOf(id)
    return index < 0 ? SECTION_ORDER.length : index
  }
  return Object.keys(counts)
    .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
    .map(id => ({ id: id, label: sectionLabel(id), icon: sectionIcon(id), count: counts[id] }))
}

function hasSection(catalog, id) {
  return catalog.some(setting => setting.section === id)
}

// Every word of the query must appear in the title, summary, keywords, or section.
function matches(setting, query) {
  const words = query.trim().toLowerCase().split(/\s+/).filter(word => word.length > 0)
  const haystack = [setting.title, setting.summary, setting.keywords, sectionLabel(setting.section)].join(" ").toLowerCase()
  return words.every(word => haystack.indexOf(word) >= 0)
}

function rows(catalog, section, query) {
  const searching = (query || "").trim().length > 0
  return catalog
    .filter(setting => searching ? matches(setting, query) : setting.section === section)
    .sort((a, b) => (a.order ?? 100) - (b.order ?? 100)
      || (KIND_ORDER[a.kind] ?? 9) - (KIND_ORDER[b.kind] ?? 9) || a.title.localeCompare(b.title))
}

function parseJson(text) {
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

// A state line is "id<TAB>state json<TAB>options json".
function parseStateLine(line) {
  const parts = String(line).split("\t")
  if (parts.length < 3 || !parts[0]) return null
  return { id: parts[0], state: parseJson(parts[1]), options: parseJson(parts[2]) }
}

function errorText(stderr) {
  const lines = String(stderr || "").trim().split("\n").filter(line => line.length > 0)
  const last = lines.length ? lines[lines.length - 1] : "Omahub didn't respond. Try again"
  const message = last.replace(/^omahub: /, "")
  // Commands write their messages mid-sentence, after "omahub: ". On their own row they start a sentence.
  return message.charAt(0).toUpperCase() + message.slice(1)
}

// Choices with the given value marked current, compared as text since values arrive as either.
function markCurrent(options, value) {
  if (!Array.isArray(options)) return options
  // A setting holding several choices has a list for its value, and every option in it is current.
  const chosen = Array.isArray(value) ? value.map(String) : [String(value)]
  return options.map(option => Object.assign({}, option, { current: chosen.indexOf(String(option.value)) >= 0 }))
}

// What to send when one chip of a setting holding several choices is switched: the options that stay or
// become on, in the order the options come, or "none".
function toggleMulti(options, value) {
  const on = (options || [])
    .filter(option => (String(option.value) === String(value)) !== (option.current === true))
    .map(option => String(option.value))
  return on.length > 0 ? on.join(",") : "none"
}

// How a setting holding several choices reads: every chip on is "Everything", none is "Nothing".
function multiLabel(options) {
  const on = options.filter(option => option.current)
  if (on.length === 0) return "Nothing"
  if (on.length === options.length) return "Everything"
  return on.map(option => option.label).join(", ")
}

// What a switch or a choice will show once a change goes through, so the row can show it at once.
// Everything else in the state stays, such as the keyboard's recommendations. Other kinds wait for
// the real answer, so this returns null for them.
function optimistic(setting, state, options, value) {
  if (!setting) return null
  if (setting.kind === "toggle") {
    if (value !== "on" && value !== "off") return null
    const on = value === "on"
    return { state: Object.assign({}, state || {}, { value: on, label: on ? "On" : "Off" }), options: null }
  }
  if (setting.kind === "choice" && Array.isArray(options)) {
    const chosen = options.find(option => String(option.value) === String(value))
    if (!chosen) return null
    return {
      state: Object.assign({}, state || {}, { value: chosen.value, label: chosen.label }),
      options: markCurrent(options, chosen.value)
    }
  }
  if (setting.kind === "multi" && Array.isArray(options)) {
    const values = String(value) === "none" ? [] : String(value).split(",")
    if (values.some(item => !options.some(option => String(option.value) === item))) return null
    const next = markCurrent(options, values)
    return { state: Object.assign({}, state || {}, { value: values, label: multiLabel(next) }), options: next }
  }
  return null
}

// Beyond the keyboard, the welcome offers the few choices that change a first day the most.
const WELCOME_EXTRAS = ["capture/thumbnail", "dock/show", "projects/default-agent", "projects/editor"]

// The welcome shows the keyboard's size and the settings recommended for it, in recommended order,
// then the extras. A keyboard Omahub does not recognize sees every keyboard setting instead.
function welcomeRows(catalog, states) {
  const byId = {}
  for (const setting of catalog) byId[setting.id] = setting
  const extras = WELCOME_EXTRAS.map(id => byId[id]).filter(Boolean)

  const size = states["keyboard/size"]
  if (!size || size.value === null || !Array.isArray(size.recommended)) return rows(catalog, "keyboard", "").concat(extras)

  return ["keyboard/size"].concat(size.recommended).map(id => byId[id]).filter(Boolean).concat(extras)
}

function pendingRecommended(states) {
  const size = states["keyboard/size"]
  if (!size || !Array.isArray(size.recommended)) return []
  return size.recommended.filter(id => states[id] && states[id].value !== true)
}

function keyboardSummary(states) {
  const size = states["keyboard/size"]
  if (!size) return null

  const recommended = Array.isArray(size.recommended) ? size.recommended : []
  const on = recommended.filter(id => states[id] && states[id].value === true).length
  const recognized = size.value !== null && recommended.length > 0

  let detail
  if (size.value === null) detail = "Not recognized yet. Pick its size below and Omahub will recommend keys for it."
  else if (size.source === "chosen") detail = size.label + " keyboard, chosen by you"
  else detail = size.label + " keyboard, detected"

  // With nothing recommended yet, there is no progress to report, only the next step.
  let progress = "Pick a size to get recommendations"
  if (recognized) {
    progress = on === recommended.length
      ? "All " + recommended.length + " recommended settings are on"
      : on + " of " + recommended.length + " recommended settings are on"
  }

  return {
    name: size.keyboard || "Your keyboard",
    detail: detail,
    progress: progress,
    complete: recognized && on === recommended.length
  }
}
