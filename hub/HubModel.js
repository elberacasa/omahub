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
    .sort((a, b) => (KIND_ORDER[a.kind] ?? 9) - (KIND_ORDER[b.kind] ?? 9) || a.title.localeCompare(b.title))
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
  const last = lines.length ? lines[lines.length - 1] : "Something went wrong."
  return last.replace(/^omahub: /, "")
}

// Beyond the keyboard, the welcome offers the few choices that change a first day the most.
const WELCOME_EXTRAS = ["capture/thumbnail", "projects/default-agent", "projects/editor"]

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

  let detail
  if (size.value === null) detail = "Not recognized yet. Pick its size below and Omahub will recommend keys for it."
  else if (size.source === "chosen") detail = size.label + " keyboard, chosen by you"
  else detail = size.label + " keyboard, detected"

  return {
    name: size.keyboard || "Your keyboard",
    detail: detail,
    progress: on === recommended.length
      ? "All " + recommended.length + " recommended settings are on"
      : on + " of " + recommended.length + " recommended settings are on",
    complete: on === recommended.length
  }
}
