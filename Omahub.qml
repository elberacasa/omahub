import QtQuick
import "hub"
import "capture"

// The one entry the shell loads for Omahub. The shell summons it with a payload and each
// feature takes the payloads meant for it: a screenshot carries `capture`, everything else
// goes to the hub. SUPER + A toggles the hub, so the shell reads `opened` from the hub.
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

  Hub {
    id: hub
  }

  Capture {
    id: capture
  }
}
