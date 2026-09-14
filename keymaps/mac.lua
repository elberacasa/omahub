-- Mac screenshot keys. SUPER + SHIFT + 3, 4, and 5 capture like Command + Shift on a Mac.
-- The actions they displace move as one family, so every workspace follows the same rule:
--   Move window to workspace   SUPER + SHIFT + number  ->  SUPER + ALT + number
--   Switch to group window     SUPER + ALT + 1-5       ->  SUPER + CTRL + ALT + 1-5
-- Move window silently keeps Omarchy's own SUPER + SHIFT + ALT + number.

local lib = dofile((os.getenv("HOME") or "") .. "/.config/omarchy/plugins/io.github.elberacasa.omahub/keymaps/lib.lua")

for index = 1, 5 do
  local digit = "code:" .. tostring(index + 9)
  hl.unbind("SUPER + ALT + " .. digit)
  o.bind("SUPER + CTRL + ALT + " .. digit, "Switch to group window " .. index, hl.dsp.group.active({ index = index }))
end

for workspace = 1, 10 do
  local digit = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + SHIFT + " .. digit)
  o.bind("SUPER + ALT + " .. digit, "Move window to workspace " .. workspace, hl.dsp.window.move({ workspace = tostring(workspace) }))
end

o.bind("SUPER + SHIFT + code:12", "Screenshot full screen", lib.screenshot("fullscreen"))
o.bind("SUPER + SHIFT + code:13", "Screenshot region", lib.screenshot("region"))
o.bind("SUPER + SHIFT + code:14", "Capture menu", "omarchy-menu toggle capture")
-- Next to the screenshot keys, SUPER + SHIFT + 6 opens the screenshot thumbnail's menu from the keyboard.
o.bind("SUPER + SHIFT + code:15", "Screenshot thumbnail menu", "omarchy-shell shell call io.github.elberacasa.omahub captureMenu ''")
o.bind("SUPER + SHIFT + CTRL + code:12", "Screenshot full screen to clipboard", "omarchy-capture-screenshot fullscreen copy")
o.bind("SUPER + SHIFT + CTRL + code:13", "Screenshot region to clipboard", "omarchy-capture-screenshot region copy")
