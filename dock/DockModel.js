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

// The desktops the dock shows for a screen: each one with a window, and the one in front even when it is
// empty, in number order. Their windows come most recently used first. `workspaces` and `toplevels` are
// Hyprland's.
function desktops(workspaces, toplevels, monitorName, activeId) {
  const windows = listValue(toplevels).map(toplevel => {
    const data = (toplevel && toplevel.lastIpcObject) || {}
    return {
      address: String(data.address || (toplevel && toplevel.address) || ""),
      appId: String(data.class || ""),
      title: String((toplevel && toplevel.title) || data.title || ""),
      workspace: toplevel && toplevel.workspace ? toplevel.workspace.id : (data.workspace ? data.workspace.id : 0),
      focus: data.focusHistoryID !== undefined ? Number(data.focusHistoryID) : 1000,
      pid: Number(data.pid) || 0
    }
  }).filter(window => window.appId !== "")
  const result = []
  for (const workspace of listValue(workspaces)) {
    if (!workspace || workspace.id <= 0) continue
    if (monitorName && workspace.monitor && workspace.monitor.name !== monitorName) continue
    const own = windows.filter(window => window.workspace === workspace.id).sort((a, b) => a.focus - b.focus)
    if (own.length > 0 || workspace.id === activeId) result.push({ id: workspace.id, active: workspace.id === activeId, windows: own })
  }
  return result.sort((a, b) => a.id - b.id)
}

// The icon size that lets the dock fit in `available` along its edge: the chosen size, or a smaller one,
// down to `minimum`, when the `cells` would run past it. Each cell pads its icon by `paddingRatio` of the
// icon on both sides, so padding shrinks with it. `fixed` is the length that does not scale: dividers and
// the shelf's padding. At the largest scale, magnified icons around the pointer add about 3.24 icons of
// length (1 + 2 cos 0.2π + 2 cos 0.4π), so that growth fits too.
function fittedIconSize(chosen, minimum, available, cells, fixed, paddingRatio, maxScale) {
  const perIcon = cells * (1 + 2 * paddingRatio) + 3.24 * Math.max(0, maxScale - 1)
  const fit = Math.floor((available - fixed) / perIcon)
  return Math.max(minimum, Math.min(chosen, fit))
}

// The desktop tile a point along the dock is over, or -1. `along` counts from the first app, and the
// tiles start `gap` past the apps.
function desktopAt(along, appsLength, gap, cellWidth, count) {
  const offset = along - appsLength - gap
  if (count <= 0 || offset < 0) return -1
  const index = Math.floor(offset / cellWidth)
  return index < count ? index : -1
}

// Every app that can be kept, by name, for the Add apps panel: one row per desktop entry, leaving out
// entries hidden from launchers. `pending` holds keep or remove choices not yet saved, by app id. Every
// search word must appear in the name, generic name, id, or keywords.
function catalog(entries, pins, query, pending) {
  const kept = {}
  for (const pin of pins) kept[key(pin)] = true
  const words = String(query || "").toLowerCase().split(/\s+/).filter(word => word.length > 0)
  const seen = {}
  const rows = []
  for (const entry of entries) {
    if (!entry || !entry.id || entry.noDisplay) continue
    const id = key(entry.id)
    if (seen[id]) continue
    seen[id] = true
    const keywords = entry.keywords && entry.keywords.length ? listValue(entry.keywords).join(" ") : ""
    const haystack = [entry.name, entry.genericName, entry.id, keywords].join(" ").toLowerCase()
    if (!words.every(word => haystack.indexOf(word) >= 0)) continue
    const choice = pending ? pending[id] : undefined
    rows.push({
      id: String(entry.id),
      name: String(entry.name || entry.id),
      detail: String(entry.genericName || ""),
      icon: String(entry.icon || ""),
      kept: choice !== undefined ? choice : !!kept[id]
    })
  }
  return rows.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
}

// The slot among the first `limit` icons that a point along the dock falls in, from their centers.
function dropSlot(centers, along, limit) {
  let slot = 0
  const count = Math.min(limit, centers.length)
  for (let i = 0; i < count; i++) {
    if (along > centers[i]) slot = i + 1
  }
  return slot
}

// The kept apps with one of them, or a newly kept app, placed at a slot. Slots count the list without
// the app being moved.
function reorder(pins, id, slot) {
  const rest = pins.filter(pin => key(pin) !== key(id))
  const at = Math.max(0, Math.min(rest.length, slot))
  return rest.slice(0, at).concat([id], rest.slice(at))
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

// Whether the pointer is on the dock, as on the Mac: along the shelf, and no further out from the screen
// edge than `reach`. Callers pass the shelf's depth to start and the magnified icons' depth to stay, so
// the icons grow only once the pointer is over the dock and settle only once it leaves them.
function onDock(across, along, start, end, reach) {
  return across >= 0 && across <= reach && along >= start && along <= end
}

function magnification(distance, range, maxScale) {
  const t = Math.min(1, Math.abs(distance) / range)
  return 1 + (maxScale - 1) * Math.cos(t * Math.PI / 2)
}
