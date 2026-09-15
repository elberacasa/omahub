import QtQuick
import qs.Commons
import "Pets.js" as Pets

// An agent's pet, in its project's color from the active theme's palette, or its own color in the gallery. Its pose says the state: tapping at a
// tiny keyboard while its agent works, arms out once the turn is done, asleep once idle, and wide-eyed with an
// urgent mark while it calls you. A lively pet types in a rhythm, blinks, looks toward the pointer, stretches awake
// and blinks as work arrives, shuts its eyes and settles as it falls asleep, breathes in its sleep, squishes when
// pressed, and celebrates a finished turn with a squash and stretch hop and a burst of its color. A calm pet only changes
// pose, and with Hyprland's animations off every pet holds still. Every movement stays on the pixel grid, so the
// pet is never blurred by scaling.
Item {
  id: pet

  // Which pet: `look` names one directly, as in the hub's gallery; otherwise the company behind the agent's
  // model, such as anthropic, picks it, with the dock's settings as `choices`. `mood` is the dock's activity
  // state for the agent, and an empty mood hides the pet.
  property string look: ""
  property string family: ""
  property var choices: ({})
  // The theme's named palette, from PetPalette, and on the dock the color chosen for the agent's project.
  property var hues: ({})
  property string tint: ""
  property string mood: ""
  property bool still: false
  // Lively pets move; calm ones only change pose.
  property bool lively: true
  property real pixelSize: 2
  // Where the pet looks, -1, 0, or 1 along each axis: toward the pointer, or up when the keyboard reaches it.
  property int gazeX: 0
  property int gazeY: 0
  property int step: 0
  property bool blinking: false
  // Held down by a press: the pet ducks a pixel and squeezes its eyes shut.
  property bool pressed: false
  // Eyes closing on the way to sleep, and the squash or stretch of a hop or a wake-up.
  property bool closing: false
  property string pose: ""
  // The pet last shown, so it keeps its look while it shrinks away.
  property string heldPet: ""
  property string heldMood: ""

  readonly property bool active: pet.mood !== ""
  readonly property bool moving: pet.lively && !pet.still
  readonly property string petId: Pets.petFor(pet.family, pet.look, pet.choices)
  readonly property var rows: Pets.frame(pet.heldPet, pet.heldMood, pet.moving ? pet.step : 0,
    pet.moving ? { blink: pet.blinking || pet.pressed, shut: pet.closing, gazeX: pet.gazeX, gazeY: pet.gazeY, pose: pet.pose } : null)
  readonly property int columns: pet.rows[0].length
  // The project's color, or the pet's own from the theme, or the accent when the theme has neither.
  readonly property color hue: {
    if (pet.tint !== "") return pet.tint
    var value = Pets.hueFor(pet.heldPet, pet.hues)
    return value !== "" ? value : Color.accent
  }
  // A sleeping pet fades toward the tile's background rather than showing it through, so it stays a clean color.
  readonly property color body: pet.heldMood === "idle" ? Qt.tint(pet.hue, Util.alpha(Color.menu.background, 0.28)) : pet.hue
  readonly property color mark: pet.heldMood === "waiting" || pet.heldMood === "attention" ? Color.urgent : Color.menu.text
  // The colors ease when a project's color, sleep, or a call changes them, while every pixel changes at once, so a
  // pose or a frame never smears between two shapes.
  property color shownBody: pet.body
  property color shownMark: pet.mark
  Behavior on shownBody {
    ColorAnimation { duration: 200 }
  }
  Behavior on shownMark {
    ColorAnimation { duration: 200 }
  }

  width: pet.columns * pet.pixelSize
  height: pet.rows.length * pet.pixelSize
  visible: pet.scale > 0
  scale: pet.active ? 1 : 0

  // Handlers read the mood itself: a binding such as active may not have caught up yet when they run.
  onMoodChanged: {
    if (pet.mood === "") return
    // Falling asleep shuts the eyes and settles the pet before the sleeping pose takes over.
    if (pet.mood === "idle" && pet.heldMood !== "idle" && pet.heldMood !== "" && pet.moving) {
      pet.heldPet = pet.petId
      drowse.restart()
      return
    }
    drowse.stop()
    pet.closing = false
    if (pet.heldMood === "idle" && pet.mood !== "idle" && pet.moving) wake.restart()
    // Only a turn that ends while the dock watches earns a celebration, never a pet that appears already done.
    if (pet.mood === "done" && pet.heldMood === "working" && pet.moving) {
      hop.restart()
      celebrate.restart()
    }
    pet.heldMood = pet.mood
    pet.heldPet = pet.petId
  }
  onPetIdChanged: if (pet.mood !== "") pet.heldPet = pet.petId
  Component.onCompleted: {
    pet.heldMood = pet.mood
    pet.heldPet = pet.petId
  }

  // A press ducks the pet a pixel with its eyes squeezed shut, and letting go pops it a pixel above where it
  // rests before it settles.
  function press() {
    if (!pet.moving) return
    spring.stop()
    pet.pressed = true
    duck.y = pet.pixelSize
  }

  function letGo() {
    if (!pet.pressed) return
    pet.pressed = false
    spring.restart()
  }

  function colorFor(pixel) {
    if (pixel === "a" || pixel === "u") return pet.shownMark
    if (pixel === "e") return Color.menu.background
    if (pixel === "p") return Qt.darker(pet.shownBody, 1.35)
    if (pixel === "k") return Util.alpha(Color.menu.text, 0.4)
    return pet.shownBody
  }

  transform: [
    Translate {
      id: duck
    },
    Translate {
      id: breath
    },
    Translate {
      id: lift
    }
  ]

  Behavior on scale {
    NumberAnimation { duration: pet.active ? 220 : 160; easing.type: pet.active ? Easing.OutCubic : Easing.InCubic }
  }

  // A crouch, a stretch on the way up easing out, back to shape at the top, down easing in, and a squash on landing,
  // like something light and springy.
  SequentialAnimation {
    id: hop
    PropertyAction { target: pet; property: "pose"; value: "squash" }
    PauseAnimation { duration: 90 }
    PropertyAction { target: pet; property: "pose"; value: "stretch" }
    NumberAnimation { target: lift; property: "y"; to: -pet.pixelSize * 3; duration: 190; easing.type: Easing.OutCubic }
    PropertyAction { target: pet; property: "pose"; value: "" }
    NumberAnimation { target: lift; property: "y"; to: 0; duration: 240; easing.type: Easing.InCubic }
    PropertyAction { target: pet; property: "pose"; value: "squash" }
    PauseAnimation { duration: 90 }
    PropertyAction { target: pet; property: "pose"; value: "" }
  }

  // Work arrives for a sleeping pet: it stretches as its eyes open, then blinks twice.
  SequentialAnimation {
    id: wake
    PropertyAction { target: pet; property: "pose"; value: "stretch" }
    PropertyAction { target: pet; property: "blinking"; value: true }
    PauseAnimation { duration: 150 }
    PropertyAction { target: pet; property: "pose"; value: "" }
    PropertyAction { target: pet; property: "blinking"; value: false }
    PauseAnimation { duration: 120 }
    PropertyAction { target: pet; property: "blinking"; value: true }
    PauseAnimation { duration: 90 }
    PropertyAction { target: pet; property: "blinking"; value: false }
  }

  // Falling asleep: the eyes close, the pet sinks a pixel, and then it sleeps.
  SequentialAnimation {
    id: drowse
    PropertyAction { target: pet; property: "closing"; value: true }
    PauseAnimation { duration: 320 }
    PropertyAction { target: pet; property: "pose"; value: "squash" }
    PauseAnimation { duration: 180 }
    ScriptAction {
      script: {
        pet.pose = ""
        pet.closing = false
        pet.heldMood = pet.mood
      }
    }
  }

  SequentialAnimation {
    id: spring
    PropertyAction { target: duck; property: "y"; value: -pet.pixelSize }
    PauseAnimation { duration: 90 }
    PropertyAction { target: duck; property: "y"; value: 0 }
  }

  // Paws type in a quick rhythm, and a call's mark bounces more slowly.
  Timer {
    interval: Pets.frameInterval(pet.heldMood)
    repeat: true
    running: pet.active && pet.moving && Pets.frameCount(pet.heldMood) > 1
    onTriggered: pet.step = (pet.step + 1) % Pets.frameCount(pet.heldMood)
  }

  // Awake pets blink now and then, never on a beat.
  Timer {
    id: blinkTimer
    interval: 3200
    repeat: true
    running: pet.active && pet.moving && pet.heldMood !== "idle" && pet.heldMood !== "done"
    onTriggered: {
      pet.blinking = true
      blinkEnd.restart()
      blinkTimer.interval = 2600 + Math.floor(Math.random() * 3800)
    }
  }

  Timer {
    id: blinkEnd
    interval: 130
    onTriggered: pet.blinking = false
  }

  // A sleeping pet breathes: it rises by a single pixel and settles again, slowly.
  SequentialAnimation {
    running: pet.active && pet.moving && pet.heldMood === "idle"
    loops: Animation.Infinite
    onRunningChanged: if (!running) breath.y = 0
    PropertyAction { target: breath; property: "y"; value: 0 }
    PauseAnimation { duration: 1650 }
    PropertyAction { target: breath; property: "y"; value: -Math.max(1, Math.round(pet.pixelSize / 2)) }
    PauseAnimation { duration: 1650 }
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
    }
  }

  // A finished turn bursts out in the pet's color and the accent, a few pixels flying from its head and fading.
  Item {
    id: burst
    property real spread: 0
    x: pet.width / 2
    y: pet.pixelSize * 7
    opacity: 0

    Repeater {
      model: 8

      delegate: Rectangle {
        required property int index
        readonly property real angle: index * Math.PI / 4 + Math.PI / 8
        width: pet.pixelSize
        height: width
        x: Math.round(Math.cos(angle) * burst.spread) - width / 2
        y: Math.round(Math.sin(angle) * burst.spread * 0.8) - height / 2
        color: index % 2 === 0 ? pet.hue : Color.accent
      }
    }

    ParallelAnimation {
      id: celebrate
      NumberAnimation { target: burst; property: "spread"; from: pet.pixelSize * 3; to: pet.pixelSize * 9; duration: 560; easing.type: Easing.OutCubic }
      SequentialAnimation {
        NumberAnimation { target: burst; property: "opacity"; from: 0; to: 1; duration: 80 }
        PauseAnimation { duration: 180 }
        NumberAnimation { target: burst; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InQuad }
      }
    }
  }

  // Sleep, drawn over the pet so it can move: one z at a time rises from beside its head, fading in as it leaves
  // and out before it reaches the edge of the tile, then the next. A calm or still pet keeps one faint z at rest.
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
        opacity: pet.moving ? 0 : (zee.index === 0 ? 0.7 : 0)

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

        // The two z's take turns in the same 3.3 second breath, each gone before the other rises.
        SequentialAnimation {
          running: sleep.visible && pet.moving
          loops: Animation.Infinite
          onRunningChanged: {
            if (running) return
            zee.drift = pet.pixelSize * 2
            zee.opacity = pet.moving ? 0 : (zee.index === 0 ? 0.7 : 0)
          }
          PauseAnimation { duration: zee.index * 1650 }
          ParallelAnimation {
            NumberAnimation { target: zee; property: "drift"; from: 0; to: pet.pixelSize * 3; duration: 1600; easing.type: Easing.OutSine }
            SequentialAnimation {
              NumberAnimation { target: zee; property: "opacity"; from: 0; to: 0.95; duration: 450; easing.type: Easing.OutSine }
              PauseAnimation { duration: 450 }
              NumberAnimation { target: zee; property: "opacity"; to: 0; duration: 700; easing.type: Easing.InSine }
            }
          }
          PauseAnimation { duration: 50 + (1 - zee.index) * 1650 }
        }
      }
    }
  }
}
