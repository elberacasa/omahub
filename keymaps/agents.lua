-- Agent keys. The actions of an agent workday under the left hand:
--   Agent             SUPER + SHIFT + CTRL + A  ->  SUPER + SHIFT + A
--   ChatGPT           SUPER + SHIFT + A         ->  SUPER + SHIFT + CTRL + A
--   Browser           SUPER + B, alongside Omarchy's SUPER + SHIFT + B
--   Toggle dictation  SUPER + R, alongside Omarchy's SUPER + CTRL + X

hl.unbind("SUPER + SHIFT + A")
hl.unbind("SUPER + SHIFT + CTRL + A")

o.bind("SUPER + SHIFT + A", "Agent", "omarchy-agent --pick")

if o.preinstalled_bindings_enabled() then
  o.bind("SUPER + SHIFT + CTRL + A", "ChatGPT", { webapp = "https://chatgpt.com" })
end

o.bind("SUPER + B", "Browser", { omarchy = "browser" })

if o.cmd_present("voxtype") then
  o.bind("SUPER + R", "Toggle dictation", "voxtype record toggle")
end
