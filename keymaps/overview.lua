-- Overview. SUPER + TAB is a window switcher from the first press: tap it to flip to the window used
-- before, keep SUPER held and tap TAB to walk every window, let go of SUPER to jump. Omarchy's Next
-- workspace moves to SUPER + CTRL + ALT + TAB; Previous and Former keep SUPER + SHIFT + TAB and
-- SUPER + CTRL + TAB.

hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Overview", "omarchy-shell shell summon io.github.elberacasa.omahub '{\"overview\":\"next\"}'")
o.bind("SUPER + CTRL + ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))

-- Letting go of SUPER jumps to the chosen window. Hyprland sees the key come up even when a quick tap
-- ends before the overview has the keyboard; the overview ignores it when it is not switching.
o.bind("SUPER + SUPER_L", nil, "omarchy-shell shell call io.github.elberacasa.omahub overviewRelease ''", { release = true })
