-- Mouse buttons. Holding SUPER turns the side buttons into shortcuts, so they keep working as
-- back and forward in browsers without it.

local lib = dofile((os.getenv("HOME") or "") .. "/.config/omarchy/plugins/io.github.elberacasa.omahub/keymaps/lib.lua")

o.bind("SUPER + mouse:276", "Screenshot region", lib.screenshot("region"))

if o.cmd_present("voxtype") then
  o.bind("SUPER + mouse:275", "Toggle dictation", "voxtype record toggle")
end
