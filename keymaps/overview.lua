-- Overview. SUPER + TAB is a window switcher from the first press: tap it to flip to the window used
-- before, keep SUPER held and tap TAB to walk every window, let go of SUPER to jump. Omarchy's Next
-- workspace moves to SUPER + CTRL + ALT + TAB; Previous and Former keep SUPER + SHIFT + TAB and
-- SUPER + CTRL + TAB.

local summon = "omarchy-shell shell summon io.github.elberacasa.omahub '{\"overview\":\"next\"}'"
local release = "omarchy-shell shell call io.github.elberacasa.omahub overviewRelease ''"

hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Overview", summon)
o.bind("SUPER + CTRL + ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))

-- Letting go of SUPER jumps to the chosen window. Hyprland sees the key come up even when a quick tap
-- ends before the overview has the keyboard; the overview ignores it when it is not switching.
o.bind("SUPER + SUPER_L", nil, release, { release = true })

-- While the overview is open, Hyprland uses this key set instead of the usual one. SUPER is often
-- still held from SUPER + TAB, and Omarchy's SUPER shortcuts would otherwise act on the windows behind
-- the overview: SUPER + drag would move a window while a card is dragged, and SUPER + SHIFT + a
-- number would move a window as the overview moves it too. Here only walking and letting go of SUPER
-- stay with Hyprland, and every other key and click reaches the overview. The overview leaves this key
-- set whenever it closes.
hl.define_submap("omahub-overview", function()
  o.bind("SUPER + TAB", nil, summon)
  o.bind("SUPER + SUPER_L", nil, release, { release = true })
end)
