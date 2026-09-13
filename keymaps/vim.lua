-- Vim focus. H, J, K, and L work wherever Omarchy uses the arrow keys:
--   SUPER            focus
--   SUPER + SHIFT    swap
--   SUPER + ALT      move into a group
-- The actions on those keys move, keeping their letters or joining the help family on /:
--   Toggle window split       SUPER + J          ->  SUPER + SHIFT + ALT + J
--   Toggle workspace layout   SUPER + L          ->  SUPER + SHIFT + ALT + L
--   Keybindings               SUPER + K          ->  SUPER + /
--   Tmux keybindings          SUPER + ALT + K    ->  SUPER + ALT + /
--   Herdr keybindings         SUPER + CTRL + K   ->  SUPER + CTRL + /
--   Monitor scaling up        SUPER + /          ->  SUPER + CTRL + ALT + =
--   Monitor scaling down      SUPER + ALT + /    ->  SUPER + CTRL + ALT + -

for _, key in ipairs({ "SUPER + J", "SUPER + K", "SUPER + L", "SUPER + ALT + K", "SUPER + CTRL + K", "SUPER + SLASH", "SUPER + ALT + SLASH" }) do
  hl.unbind(key)
end

o.bind("SUPER + H", "Focus left", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + J", "Focus down", hl.dsp.focus({ direction = "d" }))
o.bind("SUPER + K", "Focus up", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + L", "Focus right", hl.dsp.focus({ direction = "r" }))

o.bind("SUPER + SHIFT + H", "Swap window left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + SHIFT + J", "Swap window down", hl.dsp.window.swap({ direction = "d" }))
o.bind("SUPER + SHIFT + K", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + SHIFT + L", "Swap window right", hl.dsp.window.swap({ direction = "r" }))

o.bind("SUPER + ALT + H", "Move window into group left", hl.dsp.window.move({ into_group = "l" }))
o.bind("SUPER + ALT + J", "Move window into group below", hl.dsp.window.move({ into_group = "d" }))
o.bind("SUPER + ALT + K", "Move window into group above", hl.dsp.window.move({ into_group = "u" }))
o.bind("SUPER + ALT + L", "Move window into group right", hl.dsp.window.move({ into_group = "r" }))

o.bind("SUPER + SHIFT + ALT + J", "Toggle window split", hl.dsp.layout("togglesplit"))
o.bind("SUPER + SHIFT + ALT + L", "Toggle workspace layout", "omarchy-hyprland-workspace-layout-toggle")
o.bind("SUPER + SLASH", "Keybindings", "omarchy-menu-keybindings")
o.bind("SUPER + ALT + SLASH", "Tmux keybindings", "omarchy-menu-tmux-keybindings")
o.bind("SUPER + CTRL + SLASH", "Herdr keybindings", "omarchy-menu-herdr-keybindings")
o.bind("SUPER + CTRL + ALT + code:21", "Monitor scaling up", "omarchy-hyprland-monitor-scaling up")
o.bind("SUPER + CTRL + ALT + code:20", "Monitor scaling down", "omarchy-hyprland-monitor-scaling down")
