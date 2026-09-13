import QtQuick
import "hub"

// The one entry the shell loads for Omahub. The shell summons it with a payload and each
// feature takes the payloads meant for it. SUPER + A toggles the hub, so the shell reads
// `opened` from the hub.
Item {
  id: root

  readonly property bool opened: hub.opened

  function open(payloadJson) {
    hub.open(payloadJson)
  }

  function close() {
    hub.close()
  }

  Hub {
    id: hub
  }
}
