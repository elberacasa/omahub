import QtQuick
import "hub"
import "capture"
import "dock"

// The one entry the shell loads for Omahub. The shell summons it with a payload and each
// feature takes the payloads meant for it: a screenshot carries `capture`, everything else
// goes to the hub. SUPER + A toggles the hub, so the shell reads `opened` from the hub. The dock
// runs on its own and reloads its settings when `omahub` asks through `dockReload`.
Item {
  id: root

  readonly property bool opened: hub.opened

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}

    if (payload.capture) {
      capture.open(JSON.stringify(payload.capture))
    } else {
      hub.open(payloadJson)
    }
  }

  function close() {
    hub.close()
  }

  function dockReload() {
    dock.reload()
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
}
