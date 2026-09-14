import QtQuick
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

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}

    if (payload.capture) {
      capture.open(JSON.stringify(payload.capture))
    } else if (payload.overview) {
      hub.close()
      overview.open(String(payload.overview))
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

  // From the keyboard: the screenshot thumbnail's menu, while a thumbnail is showing.
  function captureMenu() {
    return capture.openMenuFromKeyboard()
  }

  function overviewRelease() {
    overview.release()
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
