.pragma library

// Desktops as contexts, for the overview and the dock: which project a window belongs to, what its
// terminals are doing, and how a whole desktop reads, from its name down to the apps on it.

const EDITORS = ["cursor", "code", "code-oss", "codium", "vscodium", "windsurf", "zed", "dev.zed.zed"]
const AGENTS = ["claude", "codex", "opencode", "gemini", "pi", "crush", "cursor-agent", "copilot", "amp", "aider", "goose", "qwen"]
const BUILDS = ["cargo", "npm", "pnpm", "yarn", "bun", "deno", "node", "make", "cmake", "ninja", "go", "pytest", "python", "python3",
  "rails", "bundle", "rake", "mix", "gradle", "mvn", "docker", "podman", "vitest", "jest", "zig", "swift", "dotnet", "just"]
const EDITING = ["nvim", "vim", "hx", "helix", "emacs", "nano", "micro", "kak"]
// An agent whose turn ended this many seconds ago, with nothing since, is idle.
const IDLE_SECONDS = 300

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

// A tool by its own short name: an MCP tool such as mcp__browser__navigate is "navigate".
function toolLabel(tool) {
  return String(tool || "").split("__").pop()
}

// The company behind an agent's model, which picks its pet: every Claude model shares one, every OpenAI model
// another. Without a model, the agent's own name decides, and anything else is "other".
function family(model, agent) {
  const name = lower(model)
  const companies = [[/^claude|anthropic/, "anthropic"], [/^(gpt|o\d|codex|chatgpt|openai)/, "openai"], [/^(gemini|gemma)/, "google"],
    [/^kimi|moonshot/, "moonshot"], [/^qwen/, "alibaba"], [/^deepseek/, "deepseek"], [/^grok/, "xai"], [/^(mistral|codestral|devstral)/, "mistral"]]
  for (const company of companies) {
    if (company[0].test(name)) return company[1]
  }
  const agents = { claude: "anthropic", codex: "openai", gemini: "google", qwen: "alibaba" }
  return agents[lower(agent)] || "other"
}

// Every agent session running in a window, once each, for the dock's agent tiles. `windows` carry {address,
// appId, title, workspace}; `info` maps addresses to context.sh entries. The windows of one process list the
// same terminals, so a session sits on the window whose title names its project, or else the first that has
// it. Sessions come in desktop order, then by project.
function sessions(windows, info) {
  const found = {}
  const order = []
  for (const window of windows || []) {
    const read = info ? info[window.address] : null
    if (!read || !read.sessions) continue
    const titleProject = projectFromTitle(window.appId, window.title)
    for (const session of read.sessions) {
      if (kindOf(session.command) !== "agent") continue
      const id = String(session.pid || window.address + session.terminal)
      const fits = titleProject !== "" && session.project === titleProject
      if (found[id] && (found[id].fits || !fits)) continue
      if (!found[id]) order.push(id)
      const state = session.state || ""
      found[id] = {
        fits: fits,
        entry: {
          id: id,
          agent: lower(session.command),
          model: String(session.model || ""),
          family: family(session.model, session.command),
          project: String(session.project || ""),
          branch: String(session.branch || ""),
          address: window.address,
          workspace: Number(window.workspace) || 0,
          // When its latest turn began, in epoch seconds, and the first line of what it last said.
          since: Number(session.since) || 0,
          message: String(session.message || ""),
          activity: {
            agent: lower(session.command),
            agentWorking: state === "working",
            agentWaiting: state === "waiting",
            agentDone: state === "done",
            agentTool: state === "working" ? toolLabel(session.tool) : "",
            agentQuiet: state === "done" ? Number(session.quiet) || 0 : 0
          }
        }
      }
    }
  }
  return order.map(id => found[id].entry)
    .sort((a, b) => a.workspace - b.workspace || a.project.localeCompare(b.project) || a.id.localeCompare(b.id))
}

// How long ago something was, said the short way: "less than a minute", "4 min", "2 h 5 min".
function duration(seconds) {
  const minutes = Math.floor(Math.max(0, Number(seconds) || 0) / 60)
  if (minutes < 1) return "less than a minute"
  if (minutes < 60) return minutes + " min"
  const hours = Math.floor(minutes / 60)
  return minutes % 60 === 0 ? hours + " h" : hours + " h " + (minutes % 60) + " min"
}

// The state line on an agent's card, at `now` in epoch seconds: "Working for 4 min", "Done 2 min ago",
// "Idle for 1 h". Without a turn start, working says only that.
function stateLine(session, now, napAfter) {
  const state = activityState(session.activity, napAfter)
  if (state === "working") return session.since > 0 ? "Working for " + duration(now - session.since) : "Working"
  if (state === "done") return "Done " + duration(session.activity.agentQuiet) + " ago"
  if (state === "idle") return "Idle for " + duration(session.activity.agentQuiet)
  if (state === "waiting") return "Waiting on you"
  return "Running"
}

// What most needs a look, from facts only: a window asking for attention, an agent waiting on you, working,
// done, or idle after a while done, the agent running there, or media playing. Empty when nothing does.
// `napAfter` is how many quiet seconds after its turn an agent counts as idle, five minutes unless given,
// and 0 for never.
function activityState(activity, napAfter) {
  if (!activity) return ""
  if (activity.attention) return "attention"
  if (activity.agentWaiting) return "waiting"
  if (activity.agentWorking) return "working"
  if (activity.agentDone) {
    const nap = napAfter === undefined || napAfter === null ? IDLE_SECONDS : Number(napAfter)
    return nap > 0 && (activity.agentQuiet || 0) >= nap ? "idle" : "done"
  }
  if (activity.agent) return "agent"
  return activity.media ? "media" : ""
}

// The same, said in a few words for a label: "Claude is running Bash", "Codex is done".
function activityLabel(activity, napAfter) {
  const state = activityState(activity, napAfter)
  const name = activity ? agentLabel(activity.agent) : ""
  if (state === "attention") return "Needs you"
  if (state === "media") return "Playing"
  if (state === "waiting") return name + " is waiting on you"
  if (state === "working") return activity.agentTool ? name + " is running " + activity.agentTool : name + " is working"
  if (state === "done") return name + " is done"
  if (state === "idle") return name + " is idle"
  return state === "agent" ? name : ""
}

// What one window is running, from facts only. `info` is the window's entry from context.sh. A session's
// `state` is "working", "waiting", or "done" only when the agent's own record says so; without that, an
// agent shows as present and nothing more. An app that shows several windows from one process, such as an
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
  const agents = kinds.filter(item => item.kind === "agent")
  const working = agents.find(item => item.session.state === "working") || null
  const finished = agents.filter(item => item.session.state === "done")
  const agent = working || agents[0] || null
  return {
    project: project,
    branch: source && source.project === project ? source.branch || "" : "",
    command: primary ? lower(primary.session.command) : "",
    kind: primary && primary.kind ? primary.kind : (editorApp ? "editor" : ""),
    agent: agent ? lower(agent.session.command) : "",
    agentWorking: working !== null,
    agentWaiting: agents.some(item => item.session.state === "waiting"),
    agentDone: working === null && agents.some(item => item.session.state === "done"),
    // How long the most recently finished agent has been quiet.
    agentQuiet: finished.length > 0 ? Math.min.apply(null, finished.map(item => Number(item.session.quiet) || 0)) : 0,
    agentTool: working ? toolLabel(working.session.tool) : ""
  }
}

// How a desktop reads. Windows carry {address, appId, appName, focus, media, attention}; contexts map
// addresses to windowContext results; `name` is a name the person gave it. `knownBranches` maps the projects
// in the projects folder to their branches, for a project that only an editor's title names.
function summary(desktop, contexts, name, knownBranches) {
  const windows = (desktop.windows || []).slice().sort((a, b) => (a.focus || 0) - (b.focus || 0))
  const scores = {}
  const branches = {}
  const apps = []
  const activity = { agent: "", agentWorking: false, agentWaiting: false, agentDone: false, agentTool: "", agentQuiet: 0, media: false,
    attention: false }

  windows.forEach((window, rank) => {
    const context = contexts[window.address] || {}
    if (context.project) {
      // Recently used windows count most, and an agent or an editor says the most about a project.
      const weight = windows.length - rank + (context.kind === "agent" || context.kind === "editor" ? 2 : 0)
      scores[context.project] = (scores[context.project] || 0) + weight
      if (context.branch && !branches[context.project]) branches[context.project] = context.branch
    }
    // A working agent names the desktop's activity over one that is only present or done.
    if (context.agent && (!activity.agent || (context.agentWorking && !activity.agentWorking))) activity.agent = context.agent
    if (context.agentWorking && !activity.agentWorking) {
      activity.agentWorking = true
      activity.agentTool = context.agentTool || ""
    }
    if (context.agentWaiting) activity.agentWaiting = true
    if (context.agentDone) {
      activity.agentQuiet = activity.agentDone ? Math.min(activity.agentQuiet, context.agentQuiet || 0) : context.agentQuiet || 0
      activity.agentDone = true
    }
    if (window.media) activity.media = true
    if (window.attention) activity.attention = true
    const app = { appId: window.appId, name: window.appName || window.appId }
    if (!apps.some(item => item.appId === app.appId)) apps.push(app)
  })
  // A waiting or finished agent only matters while no agent on the desktop is still working.
  if (activity.agentWorking) {
    activity.agentWaiting = false
    activity.agentDone = false
  }

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
    branch: project ? branches[project] || (knownBranches && knownBranches[project]) || "" : "",
    apps: apps.slice(0, 4),
    moreApps: Math.max(0, apps.length - 4),
    windows: windows.length,
    activity: activity
  }
}
