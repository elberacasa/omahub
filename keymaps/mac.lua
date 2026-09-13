-- Omahub Mac layout. Screenshots move to the macOS keys, and "move window to workspace"
-- moves to SUPER + SHIFT + ALT for every workspace so the rule stays the same for all ten.
-- Omarchy's "move window silently" is the binding given up to make room.

for workspace = 1, 10 do
  local key = "SUPER + SHIFT + ALT + code:" .. tostring(workspace + 9)
  hl.unbind(key)
  o.bind(key, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
end

hl.unbind("SUPER + SHIFT + code:12")
hl.unbind("SUPER + SHIFT + code:13")
hl.unbind("SUPER + SHIFT + code:14")

o.bind("SUPER + SHIFT + code:12", "Screenshot full screen", "omarchy-capture-screenshot fullscreen")
o.bind("SUPER + SHIFT + code:13", "Screenshot region", "omarchy-capture-screenshot region")
o.bind("SUPER + SHIFT + code:14", "Capture menu", "omarchy-menu toggle capture")
o.bind("SUPER + SHIFT + CTRL + code:12", "Screenshot full screen to clipboard", "omarchy-capture-screenshot fullscreen copy")
o.bind("SUPER + SHIFT + CTRL + code:13", "Screenshot region to clipboard", "omarchy-capture-screenshot region copy")
