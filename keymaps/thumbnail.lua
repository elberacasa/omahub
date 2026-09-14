-- Screenshot thumbnail. Omarchy's PRINT key takes the same screenshot and then shows Omahub's
-- floating thumbnail, and Omahub's own screenshot keys do the same while this layer is on.

local capture = (os.getenv("HOME") or "") .. "/.config/omarchy/plugins/io.github.elberacasa.omahub/capture/capture.sh"

hl.unbind("PRINT")
o.bind("PRINT", "Screenshot", capture .. " smart")

-- SHIFT + PRINT opens the thumbnail's menu from the keyboard while a thumbnail is showing.
o.bind("SHIFT + PRINT", "Screenshot thumbnail menu", "omarchy-shell shell call io.github.elberacasa.omahub captureMenu ''")
