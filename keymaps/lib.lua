-- Shared helpers for Omahub keyboard layers.

local M = {}

-- Screenshot keys show Omahub's thumbnail while the thumbnail layer is on. The check reads the
-- bindings block at key press, so turning the layer off never leaves a stale choice behind.
function M.screenshot(mode)
  local capture = "$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub/capture/capture.sh"
  return "if grep -qs '\"thumbnail\"' \"$HOME/.config/hypr/bindings.lua\"; then \"" .. capture .. "\" " .. mode .. "; else omarchy-capture-screenshot " .. mode .. "; fi"
end

return M
