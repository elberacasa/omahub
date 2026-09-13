-- Omahub Mac layout. Screenshots take the macOS keys, and every Omarchy action they displace
-- gets a new home, the same for all ten workspaces:
--   Move window to workspace           SUPER + SHIFT + number  ->  SUPER + SHIFT + ALT + number
--   Move window silently to workspace  SUPER + SHIFT + ALT + number  ->  SUPER + CTRL + ALT + number

for workspace = 1, 10 do
  local digit = "code:" .. tostring(workspace + 9)
  local follow = "SUPER + SHIFT + ALT + " .. digit
  local silent = "SUPER + CTRL + ALT + " .. digit

  hl.unbind(follow)
  o.bind(follow, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
  o.bind(silent, "Move window silently to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace), follow = false }))
end

-- Omahub Capture shows a Mac-style thumbnail when installed. Checked at key press, so
-- the keys keep working with Omarchy's own screenshot flow without it.
local function screenshot(mode)
  local capture = "$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub-capture/capture.sh"
  return "if [[ -x \"" .. capture .. "\" ]]; then \"" .. capture .. "\" " .. mode .. "; else omarchy-capture-screenshot " .. mode .. "; fi"
end

hl.unbind("SUPER + SHIFT + code:12")
hl.unbind("SUPER + SHIFT + code:13")
hl.unbind("SUPER + SHIFT + code:14")

o.bind("SUPER + SHIFT + code:12", "Screenshot full screen", screenshot("fullscreen"))
o.bind("SUPER + SHIFT + code:13", "Screenshot region", screenshot("region"))
o.bind("SUPER + SHIFT + code:14", "Capture menu", "omarchy-menu toggle capture")
o.bind("SUPER + SHIFT + CTRL + code:12", "Screenshot full screen to clipboard", "omarchy-capture-screenshot fullscreen copy")
o.bind("SUPER + SHIFT + CTRL + code:13", "Screenshot region to clipboard", "omarchy-capture-screenshot region copy")
