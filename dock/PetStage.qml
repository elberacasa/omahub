import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "../hub"

// Pets on a stage of their own, for recording them: a row drawn large on the theme's background, or on nothing, in
// any look, color, and mood, switched on cue by dev/pet-stage. A pet changing mood moves exactly as it does on the
// dock, so a working pet set to done hops and bursts. The stage takes no clicks or keys and reads nothing about
// agents.
Item {
  id: root

  property bool opened: false
  // Each pet as { look, mood, tint, gazeX, gazeY }: tint names a color of the theme's palette, such as cyan.
  property var pets: []
  // The size of one pet pixel on screen, and the room between pets, in pet pixels.
  property int pixel: 10
  property int gap: 6
  property bool clear: false
  // An end card: the keycap and the omahub wordmark in pixels above the pets, with a line saying what they are.
  property bool title: false
  property string caption: ""

  readonly property var focusedScreen: {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  // Merges what the payload names into the stage: pets, pixel, gap, background ("theme" or "clear"), and open.
  function show(payload) {
    if (Array.isArray(payload.pets)) root.pets = payload.pets
    if (payload.pixel !== undefined) root.pixel = Math.max(1, Math.round(Number(payload.pixel) || 1))
    if (payload.gap !== undefined) root.gap = Math.max(0, Math.round(Number(payload.gap) || 0))
    if (payload.background !== undefined) root.clear = payload.background === "clear"
    if (payload.title !== undefined) root.title = payload.title === true
    if (payload.caption !== undefined) root.caption = String(payload.caption)
    root.opened = payload.open !== false
  }

  function close() {
    root.opened = false
  }

  // What the stage shows, with each pet's box in the compositor's layout, so a recording can zoom to it.
  function stateJson() {
    var list = []
    for (var i = 0; i < petRepeater.count; i++) {
      var item = petRepeater.itemAt(i)
      var spec = root.pets[i] || {}
      var entry = { look: String(spec.look || "blob"), mood: String(spec.mood === undefined ? "agent" : spec.mood),
        tint: String(spec.tint || ""), gazeX: Number(spec.gazeX) || 0, gazeY: Number(spec.gazeY) || 0 }
      if (item && root.opened && root.focusedScreen) {
        var point = item.mapToItem(null, 0, 0)
        entry.x = Math.round(root.focusedScreen.x + point.x)
        entry.y = Math.round(root.focusedScreen.y + point.y)
        entry.width = Math.round(item.width)
        entry.height = Math.round(item.height)
      }
      list.push(entry)
    }
    return JSON.stringify({ opened: root.opened, pixel: root.pixel, gap: root.gap, clear: root.clear, title: root.title, caption: root.caption, pets: list })
  }

  // Not named palette: every Item already has a palette property, which would shadow it.
  PetPalette {
    id: petPalette
  }

  // The stage fades in and out, so a recording never cuts to it or away from it in a single frame.
  property real shown: root.opened ? 1 : 0
  Behavior on shown {
    NumberAnimation { duration: root.opened ? 280 : 220; easing.type: root.opened ? Easing.OutCubic : Easing.InCubic }
  }

  PanelWindow {
    visible: (root.opened || root.shown > 0) && root.focusedScreen !== null
    screen: root.focusedScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub-stage"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Rectangle {
      anchors.fill: parent
      visible: !root.clear
      opacity: root.shown
      color: Color.menu.background
    }

    Column {
      anchors.centerIn: parent
      opacity: root.shown
      spacing: root.pixel * 8

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.title
        spacing: root.pixel * 4

        Keycap {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.pixel * 2
          cell: root.pixel
        }

        Wordmark {
          anchors.bottom: parent.bottom
          word: "omahub"
          cell: root.pixel
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.title && root.caption !== ""
        textFormat: Text.PlainText
        text: root.caption
        color: Color.accent
        font.family: Style.font.menuFamily
        font.pixelSize: root.pixel * 4
        font.bold: true
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.pixel * root.gap

        Repeater {
          id: petRepeater
          model: root.pets.length

          delegate: AgentPet {
            required property int index
            readonly property var spec: root.pets[index] || ({})

            look: String(spec.look || "blob")
            hues: petPalette.colors
            tint: spec.tint ? (petPalette.colors[spec.tint] || "") : ""
            mood: String(spec.mood === undefined ? "agent" : spec.mood)
            gazeX: Number(spec.gazeX) || 0
            gazeY: Number(spec.gazeY) || 0
            pixelSize: root.pixel
          }
        }
      }
    }
  }
}
