import QtQuick
import Quickshell
import "hub"
import "capture"
import "dock"
import "overview"

// The one entry the shell loads for Omahub. The shell summons it with a payload and each
// feature takes the payloads meant for it: a screenshot carries `capture`, the overview key
// carries `overview`, and everything else goes to the hub. SUPER + A toggles the hub, so the
// shell reads `opened` from the hub. The dock runs on its own and reloads its settings when
// `omahub` asks through `dockReload`.
Item {
  id: root

  readonly property bool opened: hub.opened

  // The overview and the dock turn SUPER shortcuts off while they have the keyboard. If the shell stopped
  // in the middle, Hyprland would stay in that key set, so a starting shell always switches back.
  Component.onCompleted: Quickshell.execDetached(["hyprctl", "eval",
    'local current = hl.get_current_submap() if current == "omahub-overview" or current == "omahub-dock" then hl.dispatch(hl.dsp.submap("reset")) end'])

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}

    if (payload.capture) {
      capture.open(JSON.stringify(payload.capture))
    } else if (payload.overview) {
      hub.close()
      overview.open(String(payload.overview), Number(payload.press) || 0)
    } else {
      overview.close()
      hub.open(payloadJson)
    }
  }

  function close() {
    hub.close()
    overview.close()
  }

  function dockReload() {
    dock.reload()
  }

  // SUPER + D: the keyboard moves to the dock, so the hub and the overview step aside.
  function dockFocus() {
    hub.close()
    overview.close()
    return dock.focusDock()
  }

  // From the keyboard: the screenshot thumbnail's menu, while a thumbnail is showing.
  function captureMenu() {
    return capture.openMenuFromKeyboard()
  }

  // SUPER came up. The number is the latest SUPER + TAB press, from keymaps/overview.lua.
  function overviewRelease(press) {
    overview.release(Number(press) || 0)
  }
  // Where the overview's and the dock's pieces are on screen, for demo scripts and agents.
  function overviewLayout() {
    return overview.layoutJson()
  }

  function dockLayout() {
    return dock.layoutJson()
  }

  Hub {
    id: hub
  }

  Capture {
    id: capture
  }

  Dock {
    id: dock
  }

  Overview {
    id: overview
  }
}
