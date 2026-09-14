-- Dock. SUPER + D moves the keyboard to the dock, the way Control + F3 does on a Mac: arrows or
-- h, j, k, and l move, Enter opens, Space shows the app's menu, and Esc or SUPER + D again goes back.
-- Loaded while the dock is on.

local focus = "omarchy-shell shell call io.github.elberacasa.omahub dockFocus ''"

o.bind("SUPER + D", "Dock", focus)

-- While the dock has the keyboard, Hyprland uses this key set instead of the usual one. SUPER is
-- usually still held from SUPER + D, so the next arrow would be SUPER + an arrow and Omarchy would move
-- focus instead of the dock's cursor. Here only SUPER + D stays with Hyprland, and every other key
-- reaches the dock. The dock leaves this key set as soon as it lets go of the keyboard.
hl.define_submap("omahub-dock", function()
  o.bind("SUPER + D", nil, focus)
end)
