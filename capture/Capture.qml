import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string path: ""
  property string imageUrl: ""
  property bool mounted: false
  property bool dismissing: false
  property bool launching: false
  property bool dragging: false
  property bool probing: false
  property bool saving: false
  property bool hovered: false
  property bool pressedVisual: false
  property string gesture: ""
  property real pressX: 0
  property real pressY: 0
  property bool menuOpen: false
  property int menuIndex: 0
  property real menuX: 0
  property real menuY: 0
  property real swipe: 0
  property string flash: ""
  property bool flashDismisses: true
  property var places: []
  property var dragGrab: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string fileUrl: root.path ? Util.fileUrl(root.path) : ""
  readonly property string editor: Quickshell.env("OMARCHY_SCREENSHOT_EDITOR") || "tensaku-edit"
  readonly property string dropTargetScript: Qt.resolvedUrl("drop-target.sh").toString().replace("file://", "")
  readonly property string folderScript: Qt.resolvedUrl("screenshot-dir.sh").toString().replace("file://", "")
  readonly property int margin: Style.gapsOut + Style.spacing.panelPadding
  readonly property int frame: Style.spacing.sm
  readonly property int thumbWidth: Style.space(240)
  readonly property int maxThumbHeight: Style.space(180)
  readonly property int gestureThreshold: Style.space(8)
  readonly property int menuWidth: Style.space(200)
  readonly property int menuRowHeight: Math.max(Style.spacing.popupRowHeight, Style.font.body + Style.spacing.controlPaddingY * 2)
  readonly property int menuHeaderHeight: Style.font.caption + Style.spacing.md * 2
  readonly property int displayMs: 5000
  readonly property int lingerMs: 2500
  readonly property bool held: root.hovered || root.dragging || root.probing || root.saving
    || root.menuOpen || root.flash !== "" || root.gesture === "swipe"

  readonly property var menuItems: {
    var items = [
      { label: "Copy", action: "copy" },
      { label: "Open in Editor", action: "edit" },
      { label: "Show in Files", action: "reveal" },
      { separator: true },
      { header: "Save to" }
    ]
    for (var i = 0; i < root.places.length; i++) {
      var place = root.places[i]
      items.push({ label: place.name, action: "saveTo", arg: place.path, checked: place.current === true })
    }
    items.push({ label: "Choose Folder…", action: "saveTo", arg: "" })
    items.push({ separator: true })
    items.push({ label: "Move to Trash", action: "trash" })
    items.push({ label: "Close", action: "dismiss" })
    return items
  }

  onHeldChanged: root.updateTimer()

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { return }
    if (!payload.path || root.dragging || root.probing || root.saving) return

    root.stopMotion()
    root.closeMenu()
    root.path = payload.path
    root.imageUrl = Util.fileUrl(payload.path)
    root.flash = ""
    root.swipe = 0
    root.gesture = ""
    root.dismissing = false
    root.launching = false
    root.mounted = true
    placesProbe.running = false
    placesProbe.running = true
    enter.restart()
    dismissTimer.interval = root.displayMs
    if (!root.held) dismissTimer.restart()
  }

  function close() {
    root.dismiss()
  }

  function updateTimer() {
    if (!root.mounted || root.dismissing || root.launching) return
    if (root.held) {
      dismissTimer.stop()
    } else {
      dismissTimer.interval = root.lingerMs
      dismissTimer.restart()
    }
  }

  function stopMotion() {
    enter.stop()
    exit.stop()
    launch.stop()
    snapBack.stop()
    dragFade.stop()
    dragReturn.stop()
    swipeEnd.stop()
  }

  function unmount() {
    root.mounted = false
    root.dismissing = false
    root.launching = false
    root.dragging = false
    root.probing = false
    root.saving = false
    root.pressedVisual = false
    root.gesture = ""
    root.menuOpen = false
    root.swipe = 0
    root.flash = ""
    root.dragGrab = null
    shift.x = 0
  }

  function dismiss() {
    if (!root.mounted || root.dismissing || root.launching) return
    root.closeMenu()
    dismissTimer.stop()
    root.stopMotion()
    root.dismissing = true
    exit.restart()
  }

  function run(command) {
    Quickshell.execDetached(command)
    root.dismiss()
  }

  function showFlash(text, dismissAfter, ms) {
    root.flashDismisses = dismissAfter
    root.flash = text
    flashTimer.interval = ms
    flashTimer.restart()
  }

  function edit() {
    if (!root.mounted || root.dismissing || root.launching) return
    root.closeMenu()
    dismissTimer.stop()
    Quickshell.execDetached([root.editor, root.path])
    root.stopMotion()
    root.launching = true
    launch.restart()
  }

  function copy() {
    Quickshell.execDetached(["bash", "-c", "wl-copy --type image/png < \"$1\"", "copy", root.path])
    root.showFlash("Copied", true, 700)
  }

  function reveal() {
    root.run(["uwsm-app", "--", "nautilus", "--select", root.path])
  }

  function trash() {
    root.run(["gio", "trash", root.path])
  }

  // Moves the screenshot into a folder and makes that folder the default, like Save to on
  // a Mac. An empty folder opens the desktop folder chooser.
  function saveTo(folder) {
    if (!root.mounted || root.dismissing || root.launching || root.saving) return
    root.saving = true
    mover.command = folder
      ? ["bash", root.folderScript, "move", root.path, folder]
      : ["bash", root.folderScript, "move", root.path]
    mover.running = true
  }

  function finishSave(output) {
    if (!root.saving) return
    root.saving = false
    var saved = String(output || "").trim()
    if (!saved) {
      root.updateTimer()
      return
    }
    root.path = saved
    var folder = saved.substring(0, saved.lastIndexOf("/"))
    var name = folder === root.home ? "Home" : folder.substring(folder.lastIndexOf("/") + 1)
    root.showFlash("Saved to " + name, true, 900)
  }

  function beginDrag() {
    root.closeMenu()
    root.stopMotion()
    root.dragging = true
    root.pressedVisual = false
    root.hovered = false
    dragFade.restart()
  }

  function endDrag(dropAction) {
    dragProxy.Drag.active = false
    root.gesture = ""
    if (dropAction !== Qt.IgnoreAction) {
      root.unmount()
      return
    }
    // Qt on Wayland reports many accepted drops as ignored, so ask Hyprland where the pointer
    // landed. Probing keeps the card held until the answer arrives.
    root.probing = true
    root.dragging = false
    dropProbe.running = true
  }

  function finishDrop(output) {
    var landed = {}
    try { landed = JSON.parse(output) } catch (e) {}
    root.probing = false

    var onCard = landed.x >= hitArea.x && landed.x < hitArea.x + hitArea.width
      && landed.y >= hitArea.y && landed.y < hitArea.y + hitArea.height

    if (landed.window === true && !onCard) {
      root.unmount()
      return
    }
    root.stopMotion()
    dragReturn.restart()
    root.updateTimer()
  }

  function selectable(item) {
    return item && !item.separator && !item.header
  }

  function openMenu(x, y) {
    root.menuX = x
    root.menuY = y
    root.menuIndex = 0
    root.menuOpen = true
    Qt.callLater(function() { menuKeys.forceActiveFocus() })
  }

  function closeMenu() {
    root.menuOpen = false
  }

  function moveMenu(delta) {
    var count = root.menuItems.length
    var next = root.menuIndex
    for (var i = 0; i < count; i++) {
      next = (next + delta + count) % count
      if (root.selectable(root.menuItems[next])) break
    }
    root.menuIndex = next
  }

  function activateMenu(index) {
    var item = root.menuItems[index]
    if (!root.selectable(item)) return
    root.closeMenu()
    root[item.action](item.arg)
  }

  Process {
    id: dropProbe
    command: ["bash", root.dropTargetScript]
    stdout: StdioCollector {
      onStreamFinished: root.finishDrop(text)
    }
  }

  Process {
    id: placesProbe
    command: ["bash", root.folderScript, "places"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.places = JSON.parse(text) } catch (e) { root.places = [] }
      }
    }
  }

  Process {
    id: mover
    stdout: StdioCollector {
      id: moverOutput
      onStreamFinished: root.finishSave(text)
    }
    onExited: Qt.callLater(function() { root.finishSave(moverOutput.text) })
  }

  Timer {
    id: dismissTimer
    onTriggered: root.dismiss()
  }

  Timer {
    id: flashTimer
    onTriggered: {
      root.flash = ""
      if (root.flashDismisses) root.dismiss()
    }
  }

  Timer {
    id: swipeEnd
    interval: 140
    onTriggered: {
      if (root.swipe > card.width * 0.3) {
        root.dismiss()
      } else {
        root.swipe = 0
        snapBack.restart()
      }
    }
  }

  // Reviewed frame by frame at 60 fps. OutQuint arrived in one visible jump, so the glide
  // uses OutCubic over a longer span. On exit the fade finishes before the card reaches
  // the screen edge, otherwise a faint strip lingers there.
  ParallelAnimation {
    id: enter
    NumberAnimation { target: shift; property: "x"; from: card.width + root.margin; to: 0; duration: 340; easing.type: Easing.OutCubic }
    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: exit
    ParallelAnimation {
      NumberAnimation { target: shift; property: "x"; to: card.width + root.margin; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: card; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InQuad }
    }
    ScriptAction { script: root.unmount() }
  }

  SequentialAnimation {
    id: launch
    NumberAnimation { target: card; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
    ScriptAction { script: root.unmount() }
  }

  ParallelAnimation {
    id: snapBack
    NumberAnimation { target: shift; property: "x"; to: 0; duration: 240; easing.type: Easing.OutCubic }
    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
  }

  NumberAnimation {
    id: dragFade
    target: card
    property: "opacity"
    to: 0
    duration: 100
    easing.type: Easing.OutCubic
  }

  ParallelAnimation {
    id: dragReturn
    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
    NumberAnimation { target: shift; property: "x"; from: Style.space(16); to: 0; duration: 260; easing.type: Easing.OutQuint }
  }

  PanelWindow {
    id: panel
    visible: root.mounted
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub-capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.menuOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    // The input region follows a static item at the card's resting place. The card itself
    // only moves visually, so a transform never leaves the clickable area behind.
    mask: Region { item: root.menuOpen ? menuLayer : hitArea }

    BorderSurface {
      id: card
      width: image.width + card.borderLeft + card.borderRight + root.frame * 2
      height: image.height + card.borderTop + card.borderBottom + root.frame * 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.margin
      anchors.bottomMargin: root.margin
      color: Util.alpha(Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: 0
      transformOrigin: Item.Center
      scale: root.launching ? 1.06
        : root.pressedVisual ? 0.97
        : root.hovered && !root.menuOpen && root.gesture === "" ? 1.02
        : 1

      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      transform: Translate { id: shift }

      // The whole screenshot always shows, like a Mac thumbnail. Wide shots use the full
      // width, tall shots use the full height and a narrower card. The source is set once
      // per screenshot, so moving the file never reloads or resizes the card.
      Image {
        id: image

        readonly property real aspect: implicitHeight > 0 ? implicitWidth / implicitHeight : 16 / 9
        readonly property bool tall: aspect < root.thumbWidth / root.maxThumbHeight

        x: card.borderLeft + root.frame
        y: card.borderTop + root.frame
        width: tall ? Math.max(Style.space(96), Math.round(root.maxThumbHeight * aspect)) : root.thumbWidth
        height: tall ? root.maxThumbHeight : Math.round(root.thumbWidth / aspect)
        source: root.imageUrl
        sourceSize: Qt.size(root.thumbWidth * 2, root.maxThumbHeight * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
      }

      Rectangle {
        x: image.x + Math.round((image.width - width) / 2)
        y: image.y + Math.round((image.height - height) / 2)
        width: Math.min(flashLabel.implicitWidth + Style.spacing.controlPaddingX * 2, image.width - Style.spacing.sm * 2)
        height: flashLabel.implicitHeight + Style.spacing.controlPaddingY * 2
        radius: Style.cornerRadius
        color: Util.alpha(Color.background, 0.9)
        opacity: root.flash ? 1 : 0
        visible: opacity > 0

        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Text {
          id: flashLabel
          anchors.centerIn: parent
          width: parent.width - Style.spacing.controlPaddingX * 2
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: root.flash
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
      }
    }

    Item {
      id: hitArea
      width: card.width
      height: card.height
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: root.margin
      anchors.bottomMargin: root.margin

      Item {
        id: dragProxy
        width: hitArea.width
        height: hitArea.height

        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.proposedAction: Qt.CopyAction
        Drag.mimeData: ({ "text/uri-list": root.fileUrl + "\r\n", "text/plain": root.path })
        Drag.onDragStarted: root.beginDrag()
        Drag.onDragFinished: function(dropAction) { root.endDrag(dropAction) }
      }

      // A press decides its gesture once it moves past the threshold: mostly rightward
      // throws the card away and it follows the pointer, anything else starts a file drag.
      // A press that never moves is a click and opens the editor.
      MouseArea {
        id: pointer
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        enabled: root.mounted && !root.dismissing && !root.launching && !root.probing && !root.saving
        cursorShape: root.dragging || root.gesture === "swipe" ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            var point = mapToItem(panel.contentItem, mouse.x, mouse.y)
            root.openMenu(point.x, point.y)
            return
          }
          var start = mapToItem(panel.contentItem, mouse.x, mouse.y)
          root.pressX = start.x
          root.pressY = start.y
          root.gesture = ""
          root.pressedVisual = true
          snapBack.stop()
          dragProxy.Drag.hotSpot.x = mouse.x
          dragProxy.Drag.hotSpot.y = mouse.y
          card.grabToImage(function(result) {
            root.dragGrab = result
            dragProxy.Drag.imageSource = result.url
          })
        }

        onPositionChanged: function(mouse) {
          if (!(pressedButtons & Qt.LeftButton) || root.menuOpen || root.gesture === "drag") return
          var now = mapToItem(panel.contentItem, mouse.x, mouse.y)
          var dx = now.x - root.pressX
          var dy = now.y - root.pressY

          if (root.gesture === "") {
            if (Math.abs(dx) < root.gestureThreshold && Math.abs(dy) < root.gestureThreshold) return
            root.pressedVisual = false
            if (dx > 0 && dx > Math.abs(dy) * 1.2) {
              root.gesture = "swipe"
            } else {
              root.gesture = "drag"
              dragProxy.Drag.active = true
              return
            }
          }

          shift.x = Math.max(0, dx)
          card.opacity = Math.max(0.35, 1 - shift.x / (card.width * 1.4))
        }

        onReleased: function(mouse) {
          root.pressedVisual = false
          if (mouse.button !== Qt.LeftButton) return
          if (root.gesture === "swipe") {
            root.gesture = ""
            if (shift.x > card.width * 0.25) root.dismiss()
            else snapBack.restart()
          } else if (root.gesture === "") {
            root.edit()
          }
        }

        onCanceled: {
          root.pressedVisual = false
          if (root.gesture === "swipe") {
            root.gesture = ""
            snapBack.restart()
          }
        }

        onWheel: function(wheel) {
          var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 4
          if (dx === 0 || root.dismissing || root.launching) return
          snapBack.stop()
          root.swipe += Math.abs(dx)
          shift.x = root.swipe
          card.opacity = Math.max(0.35, 1 - shift.x / (card.width * 1.4))
          swipeEnd.restart()
        }
      }
    }

    Item {
      id: menuLayer
      anchors.fill: parent
      visible: root.menuOpen || menu.opacity > 0

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        enabled: root.menuOpen
        onPressed: root.closeMenu()
      }

      BorderSurface {
        id: menu

        readonly property bool flipUp: root.menuY + menu.height > panel.height - Style.gapsOut

        x: Math.max(Style.gapsOut, Math.min(root.menuX, panel.width - menu.width - Style.gapsOut))
        y: Math.max(Style.gapsOut, flipUp ? root.menuY - menu.height : root.menuY)
        width: root.menuWidth
        height: menuColumn.implicitHeight + menu.borderTop + menu.borderBottom + Style.spacing.sm * 2
        color: Color.menu.background
        borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        opacity: root.menuOpen ? 1 : 0
        scale: root.menuOpen ? 1 : 0.96
        transformOrigin: flipUp ? Item.BottomLeft : Item.TopLeft

        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Item {
          id: menuKeys
          anchors.fill: parent
          focus: root.menuOpen

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.closeMenu()
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
              root.moveMenu(1)
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab) {
              root.moveMenu(-1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              root.activateMenu(root.menuIndex)
            } else {
              return
            }
            event.accepted = true
          }
        }

        Column {
          id: menuColumn
          x: menu.borderLeft + Style.spacing.sm
          y: menu.borderTop + Style.spacing.sm
          width: menu.width - menu.borderLeft - menu.borderRight - Style.spacing.sm * 2

          Repeater {
            model: root.menuItems

            delegate: Item {
              id: row
              required property int index
              required property var modelData

              readonly property bool isSeparator: !!modelData.separator
              readonly property bool isHeader: !!modelData.header
              readonly property bool selected: root.selectable(modelData) && root.menuIndex === index

              width: menuColumn.width
              height: isSeparator ? Style.spacing.md * 2 + Style.normalBorderWidth
                : isHeader ? root.menuHeaderHeight
                : root.menuRowHeight

              Rectangle {
                visible: row.isSeparator
                anchors.verticalCenter: parent.verticalCenter
                x: Style.spacing.rowPaddingX
                width: parent.width - Style.spacing.rowPaddingX * 2
                height: Style.normalBorderWidth
                color: Util.alpha(Color.menu.text, 0.16)
              }

              Text {
                visible: row.isHeader
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.spacing.xs
                textFormat: Text.PlainText
                text: row.modelData.header || ""
                color: Util.alpha(Color.menu.text, 0.55)
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                visible: !row.isSeparator && !row.isHeader
                anchors.fill: parent
                radius: Style.cornerRadius
                color: row.selected ? Color.menu.selectedBackground : "transparent"

                Behavior on color { ColorAnimation { duration: 90 } }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.right: check.left
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: row.modelData.label || ""
                  elide: Text.ElideRight
                  color: row.selected ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  id: check
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: row.modelData.checked ? "󰄬" : ""
                  color: row.selected ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.menuIndex = row.index
                  onClicked: root.activateMenu(row.index)
                }
              }
            }
          }
        }
      }
    }
  }
}
