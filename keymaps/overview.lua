-- Overview. SUPER + TAB is a window switcher from the first press: tap it to flip to the window used
-- before, keep SUPER held and tap TAB to walk every window, let go of SUPER to jump. Omarchy's Next
-- workspace moves to SUPER + CTRL + ALT + TAB; Previous and Former keep SUPER + SHIFT + TAB and
-- SUPER + CTRL + TAB.

local plugin = "io.github.elberacasa.omahub"

-- Each SUPER + TAB press gets the next number, and letting go of SUPER carries the latest one. Hyprland
-- runs the two as separate commands that can reach Omahub in either order, so the number lets the
-- overview pair a quick tap with its release whichever arrives first.
local press = 0
local watching = false

local function release()
  hl.exec_cmd(string.format("omarchy-shell shell call %s overviewRelease '%d'", plugin, press))
end

-- Hyprland's release binding does not fire when TAB and SUPER come up together, as they do in a quick
-- rolling tap, so SUPER itself is also checked every few milliseconds until it comes up.
local function watch_super()
  if hl.is_key_down("Super_L") or hl.is_key_down("Super_R") then
    hl.timer(watch_super, { timeout = 30, type = "oneshot" })
  else
    watching = false
    release()
  end
end

local function summon()
  press = press + 1
  hl.exec_cmd(string.format("omarchy-shell shell summon %s '{\"overview\":\"next\",\"press\":%d}'", plugin, press))
  if not watching then
    watching = true
    hl.timer(watch_super, { timeout = 30, type = "oneshot" })
  end
end

hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Overview", summon)
o.bind("SUPER + CTRL + ALT + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))

-- Letting go of SUPER jumps to the chosen window. Hyprland sees the key come up even when a quick tap
-- ends before the overview has the keyboard; the overview ignores it when it is not switching, and a
-- second release for the same press.
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
