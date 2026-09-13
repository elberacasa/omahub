-- Shared helpers for Omahub keyboard layers.

local M = {}

-- Omahub Capture shows a thumbnail when it is installed. The check runs at key press, so the
-- screenshot keys keep working with Omarchy's own flow without it.
function M.screenshot(mode)
  local capture = "$HOME/.config/omarchy/plugins/io.github.elberacasa.omahub-capture/capture.sh"
  return "if [[ -x \"" .. capture .. "\" ]]; then \"" .. capture .. "\" " .. mode .. "; else omarchy-capture-screenshot " .. mode .. "; fi"
end

return M
