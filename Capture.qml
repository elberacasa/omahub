import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string path: ""
  property bool mounted: false
  property bool dismissing: false
  property string flash: ""

  readonly property string editor: Quickshell.env("OMARCHY_SCREENSHOT_EDITOR") || "tensaku-edit"
  readonly property int margin: Style.gapsOut + Style.spacing.panelPadding
  readonly property int frame: Style.spacing.sm
  readonly property int thumbWidth: Style.space(240)
  readonly property int maxThumbHeight: Style.space(180)
  readonly property int buttonSize: Math.max(Style.spacing.controlHeight, Style.font.icon + Style.spacing.md * 2)
  readonly property int displayMs: 5000
  readonly property int lingerMs: 2500

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { return }
    if (!payload.path) return

    exit.stop()
    snapBack.stop()
    root.path = payload.path
    root.flash = ""
    root.dismissing = false
    root.mounted = true
    enter.restart()
    dismissTimer.interval = root.displayMs
    dismissTimer.restart()
  }

  function close() {
    root.dismiss()
  }

  function dismiss() {
    if (!root.mounted || root.dismissing) return
    root.dismissing = true
    dismissTimer.stop()
    enter.stop()
    snapBack.stop()
    exit.restart()
  }

  function run(command) {
    Quickshell.execDetached(command)
    root.dismiss()
  }

  function edit() {
    root.run([root.editor, root.path])
  }

  function copy() {
    Quickshell.execDetached(["bash", "-c", "wl-copy --type image/png < \"$1\"", "copy", root.path])
    root.flash = "Copied"
    dismissTimer.stop()
    flashTimer.restart()
  }

  function reveal() {
    root.run(["uwsm-app", "--", "nautilus", "--select", root.path])
  }

  function trash() {
    root.run(["gio", "trash", root.path])
  }

  Timer {
    id: dismissTimer
    onTriggered: root.dismiss()
  }

  Timer {
    id: flashTimer
    interval: 700
    onTriggered: root.dismiss()
  }

  ParallelAnimation {
    id: enter
    NumberAnimation { target: shift; property: "x"; from: root.thumbWidth; to: 0; duration: 280; easing.type: Easing.OutQuint }
    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: exit
    ParallelAnimation {
      NumberAnimation { target: shift; property: "x"; to: card.width + root.margin; duration: 220; easing.type: Easing.InCubic }
      NumberAnimation { target: card; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
    }
    ScriptAction {
      script: {
        root.mounted = false
        root.dismissing = false
      }
    }
  }

  NumberAnimation {
    id: snapBack
    target: shift
    property: "x"
    to: 0
    duration: 200
    easing.type: Easing.OutCubic
  }

  PanelWindow {
    id: panel
    visible: root.mounted
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }

    BorderSurface {
      id: card
      width: root.thumbWidth + card.borderLeft + card.borderRight + root.frame * 2
      height: image.height + card.borderTop + card.borderBottom + root.frame * 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.margin
      anchors.bottomMargin: root.margin
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: 0

      transform: Translate { id: shift }

      Image {
        id: image
        x: card.borderLeft + root.frame
        y: card.borderTop + root.frame
        width: root.thumbWidth
        height: implicitWidth > 0
          ? Math.min(root.maxThumbHeight, Math.round(root.thumbWidth * implicitHeight / implicitWidth))
          : Math.round(root.thumbWidth * 9 / 16)
        source: root.path ? Util.fileUrl(root.path) : ""
        sourceSize.width: root.thumbWidth * 2
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
      }

      MouseArea {
        id: pointer

        property real pressX: 0
        property bool dragged: false

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        onContainsMouseChanged: {
          if (root.dismissing || root.flash) return
          if (containsMouse) {
            dismissTimer.stop()
          } else {
            dismissTimer.interval = root.lingerMs
            dismissTimer.restart()
          }
        }

        onPressed: function(mouse) {
          pressX = mapToItem(panel.contentItem, mouse.x, mouse.y).x
          dragged = false
          snapBack.stop()
        }

        onPositionChanged: function(mouse) {
          if (!pressed) return
          var delta = mapToItem(panel.contentItem, mouse.x, mouse.y).x - pressX
          if (!dragged && Math.abs(delta) > Style.space(6)) dragged = true
          if (dragged) shift.x = Math.max(0, delta)
        }

        onReleased: {
          if (!dragged) {
            root.edit()
          } else if (shift.x > card.width * 0.3) {
            root.dismiss()
          } else {
            snapBack.restart()
          }
          dragged = false
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: card.borderBottom + root.frame + Style.spacing.md
          spacing: Style.spacing.sm
          opacity: pointer.containsMouse && !pointer.dragged && !root.flash ? 1 : 0
          visible: opacity > 0

          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

          Repeater {
            model: [
              { glyph: "󰆏", action: "copy" },
              { glyph: "󰉋", action: "reveal" },
              { glyph: "󰩹", action: "trash" }
            ]

            delegate: Rectangle {
              id: button
              required property var modelData

              width: root.buttonSize
              height: root.buttonSize
              radius: Style.cornerRadius
              color: buttonArea.containsMouse ? Util.alpha(Color.background, 0.97) : Util.alpha(Color.background, 0.82)
              border.width: Style.normalBorderWidth
              border.color: Util.alpha(Color.popups.text, buttonArea.containsMouse ? 0.4 : 0.18)

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: button.modelData.glyph
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                id: buttonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root[button.modelData.action]()
              }
            }
          }
        }

        Rectangle {
          x: image.x + Math.round((image.width - width) / 2)
          y: image.y + Math.round((image.height - height) / 2)
          width: flashLabel.implicitWidth + Style.spacing.controlPaddingX * 2
          height: flashLabel.implicitHeight + Style.spacing.controlPaddingY * 2
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.9)
          opacity: root.flash ? 1 : 0
          visible: opacity > 0

          Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

          Text {
            id: flashLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.flash
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }
      }
    }
  }
}
