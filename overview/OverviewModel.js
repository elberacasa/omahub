.pragma library

// Pure shaping for the overview: desktops on a screen, their windows in reading order, Exposé
// packing, search across every desktop, and moving a selection around the grid.

function selector(address) {
  const value = String(address || "")
  return "address:" + (value.indexOf("0x") === 0 ? value : "0x" + value)
}

// Hyprland's JSON reaches QML as list wrappers that are not JavaScript arrays, so read pairs by index.
function pair(value) {
  return value && value.length >= 2 ? [Number(value[0]) || 0, Number(value[1]) || 0] : [0, 0]
}

function windowInfo(toplevel) {
  const data = (toplevel && toplevel.lastIpcObject) || {}
  const at = pair(data.at)
  const size = pair(data.size)
  const workspace = toplevel && toplevel.workspace ? toplevel.workspace.id : (data.workspace ? data.workspace.id : 0)
  return {
    toplevel: toplevel,
    address: String(data.address || (toplevel && toplevel.address) || ""),
    title: String((toplevel && toplevel.title) || data.title || ""),
    appId: String(data.class || ""),
    workspace: workspace,
    x: Number(at[0]) || 0,
    y: Number(at[1]) || 0,
    width: Number(size[0]) || 0,
    height: Number(size[1]) || 0,
    // Hyprland counts focus history from 0 for the window focused last.
    focus: data.focusHistoryID !== undefined ? Number(data.focusHistoryID) : 1000
  }
}

function bareAddress(address) {
  return String(address || "").replace(/^0x/, "")
}

// Every window on every desktop, most recently focused first, the order a window switcher walks.
// `order` is the overview's own list of focused addresses, newest first, which stays current
// between Hyprland refreshes; Hyprland's focus history decides for windows it does not cover.
function recent(desktopList, order) {
  const rank = {}
  const list = order || []
  for (let index = 0; index < list.length; index++) {
    const address = bareAddress(list[index])
    if (rank[address] === undefined) rank[address] = index
  }
  const all = []
  for (const desktop of desktopList) {
    for (const window of desktop.windows) all.push(window)
  }
  const position = window => {
    const known = rank[bareAddress(window.address)]
    return known !== undefined ? known : list.length + window.focus
  }
  return all.sort((a, b) => position(a) - position(b))
}

function readingOrder(a, b) {
  return a.y - b.y || a.x - b.x
}

// Regular desktops on the named screen, in id order, each with its windows in reading order.
function desktops(workspaces, toplevels, monitorName) {
  const list = []
  for (const workspace of workspaces) {
    if (!workspace || workspace.id <= 0) continue
    if (monitorName && workspace.monitor && workspace.monitor.name !== monitorName) continue
    list.push({ id: workspace.id, name: String(workspace.name || workspace.id), windows: [] })
  }
  list.sort((a, b) => a.id - b.id)

  const windows = toplevels.map(windowInfo).filter(window => window.width > 0 && window.height > 0)
  for (const desktop of list) {
    desktop.windows = windows.filter(window => window.workspace === desktop.id).sort(readingOrder)
  }
  return list
}

// Every word must appear in a window's title or app.
function search(desktopList, query) {
  const words = String(query || "").toLowerCase().split(/\s+/).filter(word => word.length > 0)
  const found = []
  for (const desktop of desktopList) {
    for (const window of desktop.windows) {
      const haystack = (window.title + " " + window.appId).toLowerCase()
      if (words.every(word => haystack.indexOf(word) >= 0)) found.push(window)
    }
  }
  return found
}

// Lay windows out in rows that keep each window's shape, as large as the area allows and never
// larger than the window really is. Tries every row count and keeps the one with the biggest scale.
function pack(windows, areaWidth, areaHeight, gap) {
  const count = windows.length
  if (count === 0 || areaWidth <= 0 || areaHeight <= 0) return []

  let best = null
  for (let rows = 1; rows <= count; rows++) {
    const perRow = Math.ceil(count / rows)
    const rowHeight = (areaHeight - gap * (rows - 1)) / rows
    if (rowHeight <= 0) break
    let scale = 1
    for (let row = 0; row < rows; row++) {
      const items = windows.slice(row * perRow, (row + 1) * perRow)
      if (items.length === 0) continue
      const width = items.reduce((sum, window) => sum + window.width, 0)
      const height = Math.max.apply(null, items.map(window => window.height))
      scale = Math.min(scale, rowHeight / height, (areaWidth - gap * (items.length - 1)) / width)
    }
    if (!best || scale > best.scale) best = { rows: rows, perRow: perRow, scale: scale }
  }

  const rects = []
  const rowsData = []
  let totalHeight = 0
  for (let row = 0; row < best.rows; row++) {
    const start = row * best.perRow
    const items = windows.slice(start, start + best.perRow)
    if (items.length === 0) continue
    const width = items.reduce((sum, window) => sum + window.width * best.scale, 0) + gap * (items.length - 1)
    const height = Math.max.apply(null, items.map(window => window.height * best.scale))
    rowsData.push({ start: start, items: items, width: width, height: height })
    totalHeight += height
  }
  totalHeight += gap * (rowsData.length - 1)

  let y = (areaHeight - totalHeight) / 2
  for (const row of rowsData) {
    let x = (areaWidth - row.width) / 2
    row.items.forEach((window, offset) => {
      const width = window.width * best.scale
      const height = window.height * best.scale
      // Whole pixels keep previews crisp and every edge inside the area.
      rects[row.start + offset] = {
        x: Math.round(x),
        y: Math.max(0, Math.round(y + (row.height - height) / 2)),
        width: Math.floor(width),
        height: Math.floor(height)
      }
      x += width + gap
    })
    y += row.height + gap
  }
  return rects
}

// The closest rect in a direction, preferring ones in line with the current selection.
function neighbor(rects, index, dx, dy) {
  const from = rects[index]
  if (!from) return index
  const cx = from.x + from.width / 2
  const cy = from.y + from.height / 2
  let best = -1
  let bestScore = Infinity
  rects.forEach((rect, candidate) => {
    if (candidate === index || !rect) return
    const x = rect.x + rect.width / 2 - cx
    const y = rect.y + rect.height / 2 - cy
    const along = dx !== 0 ? x * dx : y * dy
    if (along <= 1) return
    const across = dx !== 0 ? Math.abs(y) : Math.abs(x)
    const score = along + across * 2
    if (score < bestScore) {
      bestScore = score
      best = candidate
    }
  })
  return best < 0 ? index : best
}
