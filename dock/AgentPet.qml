import QtQuick
import qs.Commons
import "Pets.js" as Pets

// An agent's pet, in the active theme's colors. Its color says the state at a glance: the accent while its
// agent works, the text color once the turn is done, dimmed once idle, and urgent while it calls you. A lively
// pet taps at a tiny keyboard while working, hops once with its arms up when the turn is done, and dozes off
// once idle, its z's drifting away. A calm pet only changes pose, and with Hyprland's animations off every
// pet holds still.
Item {
  id: pet

  // Which pet: `look` names one directly, as in the hub's gallery; otherwise the company behind the agent's
  // model, such as anthropic, picks it, with the dock's settings as `choices`. `mood` is the dock's activity
  // state for the agent, and an empty mood hides the pet.
  property string look: ""
  property string family: ""
  property var choices: ({})
  property string mood: ""
  property bool still: false
  // Lively pets move; calm ones only change pose.
  property bool lively: true
  property real pixelSize: 2
  property int step: 0
  // The pet last shown, so it keeps its look while it shrinks away.
  property string heldPet: ""
  property string heldMood: ""

  readonly property bool active: pet.mood !== ""
  readonly property bool moving: pet.lively && !pet.still
  readonly property string petId: Pets.petFor(pet.family, pet.look, pet.choices)
  readonly property var rows: Pets.frame(pet.heldPet, pet.heldMood, pet.moving ? pet.step : 0)
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
    if (pet.mood === "done" && pet.heldMood === "working" && pet.moving) hop.restart()
    pet.heldMood = pet.mood
    pet.heldPet = pet.petId
  }
  onPetIdChanged: if (pet.mood !== "") pet.heldPet = pet.petId
  Component.onCompleted: {
    pet.heldMood = pet.mood
    pet.heldPet = pet.petId
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

  // Paws tap briskly.
  Timer {
    interval: 280
    repeat: true
    running: pet.active && pet.moving && Pets.frameCount(pet.heldMood) > 1
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

  // Sleep, drawn over the pet so it can move: z's rise one after another from beside its head, fading in as
  // they leave and out before they reach the edge of the tile. A calm or still pet keeps one faint z at rest.
  Item {
    id: sleep
    visible: pet.active && pet.heldMood === "idle"
    x: pet.pixelSize * 12
    y: pet.pixelSize * 3

    Repeater {
      model: 2

      delegate: Item {
        id: zee
        required property int index
        readonly property real cell: pet.pixelSize
        // A resting z sits a little above where a drifting one starts, clear of the pet's head.
        property real drift: pet.pixelSize * 2

        width: zee.cell * 4
        height: width
        opacity: pet.moving ? 0 : (zee.index === 0 ? 0.55 : 0)

        transform: Translate {
          x: zee.drift * 0.5
          y: -zee.drift
        }

        Repeater {
          model: ["####", "..#.", ".#..", "####"].join("").split("")

          delegate: Rectangle {
            required property string modelData
            required property int index
            visible: modelData === "#"
            x: (index % 4) * zee.cell
            y: Math.floor(index / 4) * zee.cell
            width: zee.cell
            height: zee.cell
            color: Util.alpha(Color.menu.text, 0.8)
          }
        }

        // Each z takes its turn in the same 3.3 second breath, the second a third of a breath behind.
        SequentialAnimation {
          running: sleep.visible && pet.moving
          loops: Animation.Infinite
          onRunningChanged: {
            if (running) return
            zee.drift = pet.pixelSize * 2
            zee.opacity = pet.moving ? 0 : (zee.index === 0 ? 0.55 : 0)
          }
          PauseAnimation { duration: zee.index * 1100 }
          ParallelAnimation {
            NumberAnimation { target: zee; property: "drift"; from: 0; to: pet.pixelSize * 3; duration: 2200; easing.type: Easing.OutSine }
            SequentialAnimation {
              NumberAnimation { target: zee; property: "opacity"; from: 0; to: 0.7; duration: 600; easing.type: Easing.OutSine }
              PauseAnimation { duration: 700 }
              NumberAnimation { target: zee; property: "opacity"; to: 0; duration: 900; easing.type: Easing.InSine }
            }
          }
          PauseAnimation { duration: (1 - zee.index) * 1100 }
        }
      }
    }
  }
}
