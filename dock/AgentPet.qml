import QtQuick
import qs.Commons
import "Pets.js" as Pets

// An agent's pet, in the active theme's colors. Its color says the state at a glance: the accent while its
// agent works, the text color once the turn is done, dimmed once idle, and urgent while it calls you. It taps
// at a tiny keyboard while working, hops once with its arms up when the turn is done, and falls asleep once
// idle. With Hyprland's animations off it holds still.
Item {
  id: pet

  // The company behind the agent's model, such as anthropic, and the dock's activity state for the agent.
  // An empty mood hides the pet.
  property string family: ""
  property string mood: ""
  property bool still: false
  property real pixelSize: 2
  property int step: 0
  // The pet last shown, so it keeps its look while it shrinks away.
  property string heldFamily: ""
  property string heldMood: ""

  readonly property bool active: pet.mood !== ""
  readonly property var rows: Pets.frame(pet.heldFamily, pet.heldMood, pet.still ? 0 : pet.step)
  readonly property int columns: pet.rows[0].length
  readonly property color body: pet.heldMood === "working" ? Color.accent
    : (pet.heldMood === "waiting" || pet.heldMood === "attention" ? Color.urgent
      : (pet.heldMood === "idle" ? Util.alpha(Color.menu.text, 0.5) : Color.menu.text))
  // On a body already in the accent or urgent color, the company's mark stands out in the text color.
  readonly property color mark: pet.heldMood === "working" || pet.heldMood === "waiting" || pet.heldMood === "attention"
    ? Color.menu.text : Color.accent

  width: pet.columns * pet.pixelSize
  height: pet.rows.length * pet.pixelSize
  visible: pet.scale > 0
  scale: pet.active ? 1 : 0

  // Handlers read the mood itself: a binding such as active may not have caught up yet when they run.
  onMoodChanged: {
    if (pet.mood === "") return
    // Only a turn that ends while the dock watches earns a hop, never a pet that appears already done.
    if (pet.mood === "done" && pet.heldMood === "working" && !pet.still) hop.restart()
    pet.heldMood = pet.mood
    pet.heldFamily = pet.family
  }
  onFamilyChanged: if (pet.mood !== "") pet.heldFamily = pet.family
  Component.onCompleted: {
    pet.heldMood = pet.mood
    pet.heldFamily = pet.family
  }

  function colorFor(pixel) {
    if (pixel === "a" || pixel === "u") return pet.mark
    if (pixel === "e") return Color.menu.background
    if (pixel === "p") return Util.alpha(Color.menu.text, 0.75)
    if (pixel === "k" || pixel === "z") return Util.alpha(Color.menu.text, 0.4)
    return pet.body
  }

  transform: Translate {
    id: lift
  }

  Behavior on scale {
    NumberAnimation { duration: pet.active ? 220 : 160; easing.type: pet.active ? Easing.OutCubic : Easing.InCubic }
  }

  // Up easing out, down easing in, like something light landing.
  SequentialAnimation {
    id: hop
    NumberAnimation { target: lift; property: "y"; to: -pet.pixelSize * 2; duration: 200; easing.type: Easing.OutCubic }
    NumberAnimation { target: lift; property: "y"; to: 0; duration: 260; easing.type: Easing.InCubic }
  }

  // Paws tap briskly; sleep comes and goes slowly.
  Timer {
    interval: pet.heldMood === "idle" ? 1200 : 280
    repeat: true
    running: pet.active && !pet.still && Pets.frameCount(pet.heldMood) > 1
    onTriggered: pet.step = (pet.step + 1) % 2
  }

  Repeater {
    model: pet.rows.length * pet.columns

    delegate: Rectangle {
      required property int index

      readonly property string pixel: pet.rows[Math.floor(index / pet.columns)].charAt(index % pet.columns)

      visible: pixel !== "."
      x: (index % pet.columns) * pet.pixelSize
      y: Math.floor(index / pet.columns) * pet.pixelSize
      width: pet.pixelSize
      height: pet.pixelSize
      color: pet.colorFor(pixel)

      Behavior on color {
        ColorAnimation { duration: 200 }
      }
    }
  }
}
