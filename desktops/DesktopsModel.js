.pragma library

// Desktops as contexts, for the overview and the dock: which project a window belongs to, what it is
// doing, and how a whole desktop reads, from its name down to the apps on it.

const EDITORS = ["cursor", "code", "code-oss", "codium", "vscodium", "windsurf", "zed", "dev.zed.zed"]
const AGENTS = ["claude", "codex", "opencode", "gemini", "pi", "crush", "cursor-agent", "copilot", "amp", "aider", "goose", "qwen"]
const BUILDS = ["cargo", "npm", "pnpm", "yarn", "bun", "deno", "node", "make", "cmake", "ninja", "go", "pytest", "python", "python3",
  "rails", "bundle", "rake", "mix", "gradle", "mvn", "docker", "podman", "vitest", "jest", "zig", "swift", "dotnet", "just"]
const EDITING = ["nvim", "vim", "hx", "helix", "emacs", "nano", "micro", "kak"]

function lower(value) {
  return String(value || "").toLowerCase()
}

// Desktop entries by id, by startup class, and by the site a web app opens, built once so every window
// can find the app it belongs to.
function appIndex(entries) {
  const index = { byId: {}, byClass: {}, byHost: {} }
  for (const entry of entries || []) {
    if (!entry || !entry.id) continue
    const id = lower(String(entry.id).replace(/\.desktop$/, ""))
    if (!index.byId[id]) index.byId[id] = entry
    const startupClass = lower(entry.startupClass)
    if (startupClass && !index.byClass[startupClass]) index.byClass[startupClass] = entry
    const site = /omarchy-launch-webapp\s+\S*?:\/\/([^\/\s'"]+)/.exec(String(entry.execString || ""))
    if (site && !index.byHost[lower(site[1])]) index.byHost[lower(site[1])] = entry
  }
  return index
}

// The app a window belongs to. Chromium names a web app's window after its address, so
// https://web.whatsapp.com/ opens as chrome-web.whatsapp.com__-Default and finds the web app for that site.
function entryFor(appId, index) {
  const app = lower(appId)
  if (!app || !index) return null
  const host = /^chrome-([^_]+)__/.exec(app)
  return index.byClass[app] || index.byId[app] || (host ? index.byHost[host[1]] || null : null)
}

// Editors name the open project in the window title: "file - project - Cursor" or "project - Cursor".
function projectFromTitle(appId, title) {
  if (EDITORS.indexOf(lower(appId)) < 0) return ""
  const parts = String(title || "").replace(/^[●•*]\s*/, "").split(" - ").map(part => part.trim()).filter(part => part !== "")
  if (parts.length >= 3) return parts[parts.length - 2]
  if (parts.length === 2) return parts[0]
  return ""
}

// What one window is working on. `info` comes from desktops/context.sh for terminals.
function windowContext(window, info) {
  const command = lower(info && info.command)
  const project = (info && info.project) || projectFromTitle(window.appId, window.title)
  let kind = ""
  if (AGENTS.indexOf(command) >= 0) kind = "agent"
  else if (BUILDS.indexOf(command) >= 0) kind = "build"
  else if (EDITING.indexOf(command) >= 0 || EDITORS.indexOf(lower(window.appId)) >= 0) kind = "editor"
  return {
    project: project || "",
    branch: (info && info.project && info.branch) || "",
    command: command,
    kind: kind
  }
}

// Whether a command used more than a sliver of one processor between two looks. Processor time is in
// clock ticks, a hundredth of a second each.
function busy(previousCpu, cpu, elapsedMs) {
  if (!(elapsedMs > 0) || typeof previousCpu !== "number" || typeof cpu !== "number") return false
  return (cpu - previousCpu) * 10 / elapsedMs > 0.03
}

// How a desktop reads. Windows carry {address, appId, appName, focus, media, attention}; contexts map
// addresses to windowContext results with `busy` added; `name` is a name the person gave it.
function summary(desktop, contexts, name) {
  const windows = (desktop.windows || []).slice().sort((a, b) => (a.focus || 0) - (b.focus || 0))
  const scores = {}
  const branches = {}
  const apps = []
  const activity = { agentWorking: false, agentWaiting: false, building: false, media: false, attention: false }

  windows.forEach((window, rank) => {
    const context = contexts[window.address] || {}
    if (context.project) {
      // Recently used windows count most, and an agent or an editor says the most about a project.
      const weight = windows.length - rank + (context.kind === "agent" || context.kind === "editor" ? 2 : 0)
      scores[context.project] = (scores[context.project] || 0) + weight
      if (context.branch && !branches[context.project]) branches[context.project] = context.branch
    }
    // Busy is unknown until the command has been looked at twice, and unknown shows nothing.
    if (context.kind === "agent") {
      if (context.busy === true) activity.agentWorking = true
      else if (context.busy === false) activity.agentWaiting = true
    }
    if (context.kind === "build" && context.busy === true) activity.building = true
    if (window.media) activity.media = true
    if (window.attention) activity.attention = true
    const app = { appId: window.appId, name: window.appName || window.appId }
    if (!apps.some(item => item.appId === app.appId)) apps.push(app)
  })
  // A waiting agent only matters while no agent on the desktop is still working.
  if (activity.agentWorking) activity.agentWaiting = false

  let project = ""
  Object.keys(scores).forEach(candidate => {
    if (!project || scores[candidate] > scores[project]) project = candidate
  })

  // Without a project, the most recently used window says what the desktop is for: the tool running in
  // its terminal, such as btop, or else its app.
  let command = ""
  for (const window of windows) {
    const context = contexts[window.address] || {}
    if (context.command) {
      command = context.command
      break
    }
  }
  const given = String(name || "").trim()
  const title = given || project || command || (apps.length > 0 ? apps[0].name : "")
  return {
    title: title,
    named: given !== "",
    project: project,
    branch: project ? branches[project] || "" : "",
    apps: apps.slice(0, 4),
    moreApps: Math.max(0, apps.length - 4),
    windows: windows.length,
    activity: activity
  }
}
