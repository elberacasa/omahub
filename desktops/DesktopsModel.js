.pragma library

// Desktops as contexts, for the overview and the dock: which project a window belongs to, what its
// terminals are doing, and how a whole desktop reads, from its name down to the apps on it.

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

// Lua for Hyprland that focuses a window or a desktop without moving the pointer, for actions started with
// the pointer. Omarchy moves the pointer to the window that gets focus when the desktop changes, which
// suits the keyboard but makes a click jump across the screen. The person's settings come back a moment
// later from a timer inside Hyprland, so they return even if the shell stops, and only the latest of
// several quick clicks restores them, so a click never saves the settings another click turned off.
// `target` is { window: "address:0x..." } or { workspace: "3" }.
function quietFocusLua(target) {
  const spec = target && target.window
    ? "window = " + JSON.stringify(String(target.window))
    : "workspace = " + JSON.stringify(String(target && target.workspace))
  return [
    "omahub_quiet_focus = omahub_quiet_focus or { count = 0 }",
    "local quiet = omahub_quiet_focus",
    "if quiet.saved == nil then",
    "  quiet.saved = { warp = hl.get_config(\"cursor.warp_on_change_workspace\"), no_warps = hl.get_config(\"cursor.no_warps\") }",
    "end",
    "quiet.count = quiet.count + 1",
    "local mine = quiet.count",
    "hl.config({ cursor = { warp_on_change_workspace = 0, no_warps = true } })",
    "hl.dispatch(hl.dsp.focus({ " + spec + " }))",
    "hl.timer(function()",
    "  if quiet.count ~= mine or quiet.saved == nil then return end",
    "  hl.config({ cursor = { warp_on_change_workspace = quiet.saved.warp, no_warps = quiet.saved.no_warps } })",
    "  quiet.saved = nil",
    "end, { timeout = 400, type = \"oneshot\" })"
  ].join("\n")
}

// Editors name the open project in the window title: "file - project - Cursor" or "project - Cursor".
function projectFromTitle(appId, title) {
  if (EDITORS.indexOf(lower(appId)) < 0) return ""
  const parts = String(title || "").replace(/^[●•*]\s*/, "").split(" - ").map(part => part.trim()).filter(part => part !== "")
  if (parts.length >= 3) return parts[parts.length - 2]
  if (parts.length === 2) return parts[0]
  return ""
}

function kindOf(command) {
  const name = lower(command)
  if (AGENTS.indexOf(name) >= 0) return "agent"
  if (BUILDS.indexOf(name) >= 0) return "build"
  if (EDITING.indexOf(name) >= 0) return "editor"
  return ""
}

// The name an agent goes by on a badge.
function agentLabel(command) {
  const names = { claude: "Claude", codex: "Codex", opencode: "opencode", gemini: "Gemini", pi: "Pi", crush: "Crush",
    "cursor-agent": "Cursor Agent", copilot: "Copilot", amp: "Amp", aider: "Aider", goose: "Goose", qwen: "Qwen" }
  return names[lower(command)] || String(command || "")
}

// What one window is running, from facts only. `info` is the window's entry from context.sh. A session's
// `state` is "working" or "waiting" only when the agent itself reported it; without that, an agent shows
// as present, never as working or waiting. An app that shows several windows from one process, such as an
// editor, owns the terminals in the project its title names, so each of its windows shows its own agents.
function windowContext(window, info) {
  const titleProject = projectFromTitle(window.appId, window.title)
  let sessions = (info && info.sessions) || []
  if (titleProject && sessions.some(session => session.project)) {
    sessions = sessions.filter(session => session.project === titleProject)
  }
  const kinds = sessions.map(session => ({ session: session, kind: kindOf(session.command) }))
  const primary = kinds.find(item => item.kind === "agent") || kinds.find(item => item.kind === "build")
    || kinds.find(item => item.kind === "editor") || kinds.find(item => item.session.command) || null
  const withProject = sessions.find(session => session.project) || null
  const source = primary && primary.session.project ? primary.session : withProject
  const project = (source && source.project) || titleProject || ""
  const editorApp = EDITORS.indexOf(lower(window.appId)) >= 0
  const agent = kinds.find(item => item.kind === "agent") || null
  return {
    project: project,
    branch: source && source.project === project ? source.branch || "" : "",
    command: primary ? lower(primary.session.command) : "",
    kind: primary && primary.kind ? primary.kind : (editorApp ? "editor" : ""),
    agent: agent ? lower(agent.session.command) : "",
    agentWorking: kinds.some(item => item.kind === "agent" && item.session.state === "working"),
    agentWaiting: kinds.some(item => item.kind === "agent" && item.session.state === "waiting")
  }
}

// How a desktop reads. Windows carry {address, appId, appName, focus, media, attention}; contexts map
// addresses to windowContext results; `name` is a name the person gave it.
function summary(desktop, contexts, name) {
  const windows = (desktop.windows || []).slice().sort((a, b) => (a.focus || 0) - (b.focus || 0))
  const scores = {}
  const branches = {}
  const apps = []
  const activity = { agent: "", agentWorking: false, agentWaiting: false, media: false, attention: false }

  windows.forEach((window, rank) => {
    const context = contexts[window.address] || {}
    if (context.project) {
      // Recently used windows count most, and an agent or an editor says the most about a project.
      const weight = windows.length - rank + (context.kind === "agent" || context.kind === "editor" ? 2 : 0)
      scores[context.project] = (scores[context.project] || 0) + weight
      if (context.branch && !branches[context.project]) branches[context.project] = context.branch
    }
    if (context.agent && !activity.agent) activity.agent = context.agent
    if (context.agentWorking) activity.agentWorking = true
    if (context.agentWaiting) activity.agentWaiting = true
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
