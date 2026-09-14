.pragma library

// Pure shaping for the dock: pinned apps first, then open apps that are not pinned, and the
// magnification curve.

function key(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "")
}

// The dock's settings, or null when the file holds something that is not a settings object, so the
// dock keeps the last good settings instead of vanishing. An empty file means no settings.
function parseConfig(text) {
  if (String(text || "").trim() === "") return {}
  try {
    const value = JSON.parse(text)
    return value && typeof value === "object" && !Array.isArray(value) ? value : null
  } catch (e) {
    return null
  }
}

function makeItem(id, entry, windows, pinned, fallback) {
  const first = windows.length > 0 ? windows[0] : null
  return {
    id: entry ? String(entry.id) : id,
    name: entry ? String(entry.name || entry.id) : String((first && first.title) || id),
    icon: entry ? String(entry.icon || "") : (fallback ? String(fallback.icon || "") : id),
    launchable: !!entry,
    pinned: pinned,
    windows: windows,
    divider: false
  }
}

// Chromium names an app window after its address: https://x.com/ opens as chrome-x.com__-Default.
function webHost(appId) {
  const match = /^chrome-([^_]+)__/.exec(appId)
  return match ? match[1] : ""
}

// Pinned apps in their order, then apps with open windows, unless showOpen is false. A window finds
// its app by the entry's startup class or id, compared without case, so "Cursor" and "cursor" meet.
// A web app window finds the Omarchy web app that opens its site.
function items(pins, entries, toplevels, showOpen) {
  const byId = {}
  const byClass = {}
  const byHost = {}
  for (const entry of entries) {
    if (!entry || !entry.id) continue
    byId[key(entry.id)] = entry
    const startupClass = key(entry.startupClass)
    if (startupClass && !byClass[startupClass]) byClass[startupClass] = entry
    const site = /omarchy-launch-webapp\s+\S*?:\/\/([^\/\s]+)/.exec(String(entry.execString || ""))
    if (site && !byHost[site[1].toLowerCase()]) byHost[site[1].toLowerCase()] = entry
  }
  const browser = byId["chromium"] || byId["google-chrome"] || byId["brave-browser"] || null

  const windows = {}
  const order = []
  for (const toplevel of toplevels) {
    if (!toplevel) continue
    const app = key(toplevel.appId)
    if (!app) continue
    const host = webHost(app)
    const entry = byClass[app] || byId[app] || (host ? byHost[host] : null)
    const id = entry ? key(entry.id) : app
    if (!windows[id]) {
      windows[id] = { entry: entry || null, fallback: app.indexOf("chrome-") === 0 ? browser : null, list: [] }
      order.push(id)
    }
    windows[id].list.push(toplevel)
  }

  const result = []
  const seen = {}
  for (const pin of pins) {
    const id = key(pin)
    const entry = byId[id]
    if (!entry || seen[id]) continue
    seen[id] = true
    result.push(makeItem(id, entry, windows[id] ? windows[id].list : [], true))
  }

  const pinnedCount = result.length
  if (showOpen === false) return result
  for (const id of order) {
    if (seen[id]) continue
    seen[id] = true
    const item = makeItem(id, windows[id].entry, windows[id].list, false, windows[id].fallback)
    item.divider = pinnedCount > 0 && result.length === pinnedCount
    result.push(item)
  }
  return result
}

// Where each icon's center sits in the unscaled dock, so magnification never chases its own layout.
function layout(items, cellWidth, dividerWidth) {
  const centers = []
  let x = 0
  for (const item of items) {
    if (item.divider) x += dividerWidth
    centers.push(x + cellWidth / 2)
    x += cellWidth
  }
  return { centers: centers, width: x }
}

// QML hands Hyprland's lists over as array-like wrappers, not arrays.
function listValue(value) {
  const out = []
  const length = value && value.length ? value.length : 0
  for (let i = 0; i < length; i++) out.push(value[i])
  return out
}

// The band a dock uses on one edge of the monitor, in logical pixels: `length` along the edge,
// centered, and `depth` in from it.
function band(monitor, edge, length, depth) {
  const width = monitor.width / monitor.scale
  const height = monitor.height / monitor.scale
  if (edge === "left" || edge === "right") {
    const top = monitor.y + (height - length) / 2
    const left = edge === "left" ? monitor.x : monitor.x + width - depth
    return { left: left, right: left + depth, top: top, bottom: top + length }
  }
  const left = monitor.x + (width - length) / 2
  return { left: left, right: left + length, top: monitor.y + height - depth, bottom: monitor.y + height }
}

// True when a window on the monitor's visible desktop, or on its open special workspace, reaches
// into the band the dock uses on its edge. `monitor` and `clients` are Hyprland's own records, the
// ones `hyprctl monitors -j` and `hyprctl clients -j` print.
function covered(monitor, clients, edge, length, depth) {
  if (!monitor || !(monitor.scale > 0)) return false
  const area = band(monitor, edge, length, depth)
  const active = monitor.activeWorkspace ? monitor.activeWorkspace.id : null
  const special = monitor.specialWorkspace ? monitor.specialWorkspace.id || 0 : 0
  return listValue(clients).some(client => {
    if (!client || client.mapped !== true || client.hidden === true) return false
    const workspace = client.workspace ? client.workspace.id : null
    if (workspace !== active && !(special !== 0 && workspace === special)) return false
    const at = listValue(client.at)
    const size = listValue(client.size)
    if (at.length < 2 || size.length < 2) return false
    return at[0] < area.right && at[0] + size[0] > area.left && at[1] < area.bottom && at[1] + size[1] > area.top
  })
}

function magnification(distance, range, maxScale) {
  const t = Math.min(1, Math.abs(distance) / range)
  return 1 + (maxScale - 1) * Math.cos(t * Math.PI / 2)
}
