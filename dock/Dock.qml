import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as Model

// The dock: pinned apps, then open apps that are not pinned, at the bottom of the focused screen.
// Its settings live in ~/.local/state/omahub/dock.json, which the hub, the terminal, and agents
// change through `omahub`, so every change shows here at once.
Item {
  id: root

  readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/omahub/dock.json"
  readonly property string omahub: Qt.resolvedUrl("../bin/omahub").toString().replace("file://", "")

  property var config: ({})
  readonly property bool enabled: root.config.show === true
  readonly property bool autohide: root.config.autohide !== false
  // Magnification was a switch before it had strengths: on reads as large, off as off.
  readonly property string magnification: root.config.magnify === false || root.config.magnify === "off" ? "off"
    : (root.config.magnify === "subtle" ? "subtle" : "large")
  readonly property bool magnify: root.magnification !== "off"
  readonly property string size: ["small", "medium", "large"].indexOf(root.config.size) >= 0 ? root.config.size : "medium"
  readonly property bool indicators: root.config.indicators !== false
  readonly property bool showOpen: root.config.recents !== false
  readonly property bool bounce: root.config.bounce !== false
  readonly property var pins: Array.isArray(root.config.pins) ? root.config.pins : []

  readonly property var items: Model.items(root.pins,
    DesktopEntries.applications.values || [], ToplevelManager.toplevels.values || [], root.showOpen)
  readonly property var layout: Model.layout(root.items, root.cellWidth, root.dividerWidth)

  readonly property int iconSize: Style.space(root.size === "small" ? 40 : (root.size === "large" ? 62 : 50))
  readonly property int cellPadding: Style.space(5)
  readonly property int cellWidth: root.iconSize + root.cellPadding * 2
  readonly property int dividerWidth: Style.space(17)
  readonly property int dockPadding: Style.space(9)
  readonly property int dotSpace: Style.space(7)
  readonly property int baseHeight: root.iconSize + root.dockPadding * 2 + root.dotSpace
  // A soft shelf: rounded in proportion to its height, edged with a hairline in the theme's text
  // color rather than a heavy border, so the icons carry the dock.
  readonly property int shelfRadius: Math.round(root.baseHeight * 0.32)
  readonly property color hairline: Util.alpha(Color.menu.text, 0.14)
  readonly property int edgeGap: Style.gapsOut
  readonly property real maxScale: root.magnification === "large" ? 1.5 : (root.magnification === "subtle" ? 1.25 : 1)
  readonly property real magnifyRange: root.cellWidth * 2.5
  // The overview button leads the dock, set off from the apps by a divider.
  readonly property int overviewButtonWidth: root.cellWidth + root.dividerWidth
  readonly property int baseWidth: root.layout.width + root.dockPadding * 2 + root.overviewButtonWidth
  // Room above the dock for magnified icons and the app name.
  readonly property int bandHeight: Math.ceil(root.iconSize * root.maxScale) + root.dockPadding * 2
    + root.dotSpace + root.edgeGap + Style.space(40)
  readonly property int menuSpace: Style.space(300)

  // The pointer's position in the unscaled layout, or -1 when it is away from the dock.
  property real pointerX: -1
  property bool pointerInside: false
  property bool lingering: false
  property bool covered: false
  property bool menuOpen: false
  property var menuItem: null
  property real menuCenter: 0

  readonly property bool shown: root.enabled && root.items.length > 0
    && (!root.autohide || !root.covered || root.pointerInside || root.lingering || root.menuOpen)

  readonly property var focusedScreen: {
    var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  readonly property var menuEntries: {
    var item = root.menuItem
    if (!item) return []
    var list = []
    if (item.launchable) {
      list.push({ label: item.windows.length > 0 ? "New window" : "Open", action: "launch" })
      list.push({ label: item.pinned ? "Remove from dock" : "Keep in dock", action: item.pinned ? "unpin" : "pin" })
    }
    if (item.windows.length > 0) list.push({ label: item.windows.length > 1 ? "Quit all windows" : "Quit", action: "quit" })
    list.push({ separator: true })
    list.push({ label: "Automatically hide", action: "autohide", checked: root.autohide })
    list.push({ label: "Magnification", action: "magnify", checked: root.magnify })
    list.push({ label: "Dock settings…", action: "settings" })
    return list
  }

  // The name above a hovered icon: a small pill, like the one on the Mac.
  component DockLabel: Rectangle {
    property string text: ""
    width: labelText.implicitWidth + Style.spacing.lg * 2
    height: labelText.implicitHeight + Style.spacing.xs * 2
    radius: height / 2
    color: Util.alpha(Color.menu.background, 0.92)
    border.width: Math.max(1, Style.space(1))
    border.color: root.hairline

    Text {
      id: labelText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.text
      color: Color.menu.text
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.caption
    }
  }

  function reload() {
    stateView.reload()
  }

  // Where the dock's pieces are on screen, in the compositor's coordinates, for demo scripts and
  // agents that drive it with a pointer. The bottom edge is where a hidden dock wakes up.
  function layoutJson() {
    var screen = root.focusedScreen
    var screenX = screen ? screen.x : 0
    var screenY = screen ? screen.y : 0
    var screenHeight = screen ? screen.height : dockWindow.height
    function place(item) {
      var point = item.mapToItem(null, 0, 0)
      return {
        x: Math.round(screenX + point.x), y: Math.round(screenY + screenHeight - dockWindow.height + point.y),
        width: Math.round(item.width), height: Math.round(item.height)
      }
    }
    var apps = []
    for (var i = 0; i < iconRepeater.count; i++) {
      var cell = iconRepeater.itemAt(i)
      if (cell) apps.push(Object.assign({ id: cell.modelData.id, name: cell.modelData.name, windows: cell.modelData.windows.length }, place(cell)))
    }
    return JSON.stringify({
      shown: root.shown, apps: apps, overview: place(overviewButton),
      edge: { x: Math.round(screenX + (screen ? screen.width : 0) / 2), y: Math.round(screenY + screenHeight - 1), width: 1, height: 1 }
    })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.charAt(0) === "/") return "file://" + value
    var themed = value !== "" ? Quickshell.iconPath(value, true) : ""
    return themed !== "" ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function launch(item) {
    if (!item || !item.launchable) return
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", item.id + ".desktop"])
  }

  // Click opens an app, or brings its windows forward one at a time.
  function openItem(item) {
    var windows = item.windows || []
    if (windows.length === 0) {
      root.launch(item)
      return
    }
    var current = -1
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].activated) current = i
    }
    windows[(current + 1) % windows.length].activate()
  }

  function openMenu(item, cell) {
    root.menuItem = item
    root.menuCenter = cell.mapToItem(dockVisual, cell.width / 2, 0).x
    root.menuOpen = true
  }

  function runMenu(entry) {
    var item = root.menuItem
    root.menuOpen = false
    if (entry.action === "launch") {
      root.launch(item)
    } else if (entry.action === "pin" || entry.action === "unpin") {
      Quickshell.execDetached([root.omahub, "dock", entry.action, item.id])
    } else if (entry.action === "quit") {
      item.windows.forEach(function(window) { window.close() })
    } else if (entry.action === "autohide") {
      Quickshell.execDetached([root.omahub, "set", "dock/autohide", root.autohide ? "off" : "on"])
    } else if (entry.action === "magnify") {
      Quickshell.execDetached([root.omahub, "set", "dock/magnify", root.magnify ? "off" : "large"])
    } else if (entry.action === "settings") {
      Quickshell.execDetached([root.omahub, "open", "dock"])
    }
  }

  // Whether a window reaches the dock's band, read from Hyprland's own records. Refreshing them is a
  // request over Hyprland's socket, so checking often starts no processes. The answers arrive a
  // moment later, so the check is read again a few times.
  function checkCover() {
    if (!root.enabled || !root.autohide) {
      coverRead.stop()
      root.covered = false
      return
    }
    Hyprland.refreshMonitors()
    Hyprland.refreshToplevels()
    coverRead.passes = 0
    coverRead.restart()
  }

  function readCover() {
    var monitor = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.lastIpcObject : null
    var clients = (Hyprland.toplevels.values || []).map(function(toplevel) { return toplevel.lastIpcObject })
    root.covered = Model.covered(monitor, clients, root.baseWidth + root.edgeGap * 2, root.baseHeight + root.edgeGap)
  }

  onEnabledChanged: root.checkCover()
  onAutohideChanged: root.checkCover()
  Component.onCompleted: root.checkCover()

  FileView {
    id: stateView
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onLoaded: root.config = Model.parseConfig(text())
    onFileChanged: reload()
    onLoadFailed: root.config = ({})
  }

  Timer {
    id: coverRead
    property int passes: 0
    interval: 70
    repeat: true
    onTriggered: {
      root.readCover()
      coverRead.passes += 1
      if (coverRead.passes >= 3) coverRead.stop()
    }
  }

  // Window changes arrive as Hyprland events. A slow poll catches floating windows resized by hand.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event && event.name ? String(event.name) : ""
      if (["openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode", "fullscreen",
           "workspace", "workspacev2", "focusedmon", "activespecial"].indexOf(name) !== -1) {
        coverDelay.restart()
      }
    }
  }

  Timer {
    id: coverDelay
    interval: 80
    onTriggered: root.checkCover()
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.enabled && root.autohide
    onTriggered: root.checkCover()
  }

  Timer {
    id: lingerTimer
    interval: 450
    onTriggered: root.lingering = false
  }

  HyprlandFocusGrab {
    active: root.menuOpen
    windows: [dockWindow]
    onCleared: root.menuOpen = false
  }

  PanelWindow {
    id: dockWindow
    visible: root.enabled && root.focusedScreen !== null
    screen: root.focusedScreen
    anchors { bottom: true; left: true; right: true }
    implicitHeight: root.bandHeight + root.menuSpace
    color: "transparent"
    WlrLayershell.namespace: "omahub-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // A dock that stays on screen keeps its own room, so windows resize to sit above it, like the
    // bar. One that hides floats over them instead.
    exclusionMode: root.enabled && !root.autohide && root.items.length > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: root.baseHeight + root.edgeGap

    // Input lands only where the dock is: its band while shown and a thin strip at the edge while
    // hidden. While the menu is open the whole dock window takes clicks, so one outside the menu
    // closes it. Everywhere else reaches the windows below.
    mask: Region {
      item: root.menuOpen ? menuHit : (root.shown ? dockHit : edgeHit)
    }

    Item {
      id: menuHit
      anchors.fill: parent
    }

    MouseArea {
      anchors.fill: menuHit
      enabled: root.menuOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: root.menuOpen = false
    }

    Item {
      id: edgeHit
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(2, Style.space(3))
    }

    Item {
      id: dockHit
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: root.baseWidth + root.cellWidth * 2
      height: root.bandHeight
    }

    MouseArea {
      anchors.fill: edgeHit
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: {
        root.pointerInside = true
        lingerTimer.stop()
      }
      onExited: {
        if (!root.shown) root.pointerInside = false
      }
    }

    MouseArea {
      anchors.fill: dockHit
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: {
        root.pointerInside = true
        lingerTimer.stop()
      }
      onExited: {
        root.pointerInside = false
        root.pointerX = -1
        root.lingering = true
        lingerTimer.restart()
      }
      onPositionChanged: function(mouse) {
        root.pointerInside = true
        var origin = (dockWindow.width - root.baseWidth) / 2 + root.dockPadding + root.overviewButtonWidth
        root.pointerX = dockHit.x + mouse.x - origin
      }
    }

    Item {
      id: dockVisual
      anchors.fill: parent
      opacity: root.shown ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: root.shown ? 180 : 140; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
      }

      transform: Translate {
        y: root.shown ? 0 : root.baseHeight + root.edgeGap

        Behavior on y {
          NumberAnimation { duration: root.shown ? 240 : 170; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
        }
      }

      BorderSurface {
        id: dockBackground
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.edgeGap
        width: iconRow.width + root.dockPadding * 2 + root.overviewButtonWidth
        height: root.baseHeight
        radius: root.shelfRadius
        color: Util.alpha(Color.menu.background, 0.8)
        borderSpec: Border.flat(root.hairline, Math.max(1, Style.space(1)))
      }

      Item {
        id: overviewButton
        readonly property bool hovered: root.pointerX > -root.overviewButtonWidth && root.pointerX < -root.dividerWidth
        anchors.left: dockBackground.left
        anchors.leftMargin: root.dockPadding
        anchors.bottom: dockBackground.bottom
        anchors.bottomMargin: root.dockPadding + root.dotSpace
        width: root.overviewButtonWidth
        height: root.iconSize

        // A tile of four squares, drawn from theme colors, so it sits among the app icons in any theme.
        Rectangle {
          id: overviewTile
          x: root.cellPadding + (root.iconSize - width) / 2
          anchors.bottom: parent.bottom
          width: Math.round(root.iconSize * 0.88)
          height: width
          radius: Math.round(width * 0.24)
          color: Util.alpha(overviewButton.hovered ? Color.accent : Color.menu.text, overviewButton.hovered ? 0.22 : 0.1)

          Behavior on color {
            ColorAnimation { duration: 120 }
          }

          Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: Math.round(overviewTile.width * 0.1)

            Repeater {
              model: 4

              Rectangle {
                width: Math.round(overviewTile.width * 0.24)
                height: width
                radius: Math.round(width * 0.28)
                color: overviewButton.hovered ? Color.accent : Util.alpha(Color.menu.text, 0.8)
              }
            }
          }
        }

        Rectangle {
          x: root.cellWidth + root.dividerWidth / 2
          anchors.verticalCenter: overviewTile.verticalCenter
          width: Math.max(1, Style.space(1))
          height: Math.round(root.iconSize * 0.7)
          color: root.hairline
        }

        DockLabel {
          visible: overviewButton.hovered && !root.menuOpen
          anchors.horizontalCenter: overviewTile.horizontalCenter
          anchors.bottom: parent.top
          anchors.bottomMargin: Style.space(10)
          text: "Overview"
        }

        MouseArea {
          width: root.cellWidth
          height: parent.height
          cursorShape: Qt.PointingHandCursor
          onClicked: Quickshell.execDetached([root.omahub, "open", "overview"])
        }
      }

      Row {
        id: iconRow
        anchors.right: dockBackground.right
        anchors.rightMargin: root.dockPadding
        anchors.bottom: dockBackground.bottom
        anchors.bottomMargin: root.dockPadding + root.dotSpace

        Repeater {
          id: iconRepeater
          model: root.items

          delegate: Item {
            id: cell
            required property var modelData
            required property int index

            readonly property real distance: root.pointerX < 0 ? 1e9 : root.pointerX - root.layout.centers[cell.index]
            readonly property real scaleFactor: root.magnify && root.pointerX >= 0
              ? Model.magnification(cell.distance, root.magnifyRange, root.maxScale) : 1
            readonly property bool hovered: root.pointerX >= 0 && Math.abs(cell.distance) <= root.cellWidth / 2
            readonly property int windowCount: cell.modelData.windows.length
            readonly property bool active: {
              for (var i = 0; i < cell.modelData.windows.length; i++) {
                if (cell.modelData.windows[i].activated) return true
              }
              return false
            }
            readonly property int dividerSpace: cell.modelData.divider ? root.dividerWidth : 0

            width: cell.dividerSpace + root.iconSize * cell.scaleFactor + root.cellPadding * 2
            height: root.iconSize

            Behavior on width {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }

            Rectangle {
              visible: cell.modelData.divider
              x: root.dividerWidth / 2
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Math.round(root.iconSize * 0.15)
              width: Math.max(1, Style.space(1))
              height: Math.round(root.iconSize * 0.7)
              color: root.hairline
            }

            Image {
              id: icon
              property real hop: 0
              x: cell.dividerSpace + root.cellPadding
              anchors.bottom: parent.bottom
              anchors.bottomMargin: icon.hop
              width: root.iconSize * cell.scaleFactor
              height: width
              // Rendered for the largest magnified size, so icons stay crisp under the pointer.
              sourceSize.width: Math.ceil(root.iconSize * root.maxScale * 2)
              sourceSize.height: Math.ceil(root.iconSize * root.maxScale * 2)
              source: root.iconSource(cell.modelData.icon)
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true

              Behavior on width {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
              }

              // Launching lifts the icon once, the dock's version of a bounce.
              SequentialAnimation {
                id: hopAnimation
                NumberAnimation { target: icon; property: "hop"; to: Style.space(14); duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: icon; property: "hop"; to: 0; duration: 220; easing.type: Easing.InOutCubic }
              }
            }

            Rectangle {
              visible: root.indicators && cell.windowCount > 0
              width: Style.space(4)
              height: width
              radius: width / 2
              anchors.horizontalCenter: icon.horizontalCenter
              y: cell.height + (root.dotSpace - height) / 2
              color: cell.active ? Color.accent : Util.alpha(Color.menu.text, 0.55)
            }

            DockLabel {
              visible: cell.hovered && !root.menuOpen
              anchors.horizontalCenter: icon.horizontalCenter
              anchors.bottom: icon.top
              anchors.bottomMargin: Style.space(10)
              text: cell.modelData.name
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.openMenu(cell.modelData, cell)
                } else if (mouse.button === Qt.MiddleButton) {
                  if (root.bounce) hopAnimation.restart()
                  root.launch(cell.modelData)
                } else {
                  if (root.bounce && cell.windowCount === 0) hopAnimation.restart()
                  root.openItem(cell.modelData)
                }
              }
            }
          }
        }
      }
    }

    BorderSurface {
      id: menuCard
      visible: root.menuOpen
      width: Style.space(230)
      height: menuColumn.implicitHeight + Style.spacing.sm * 2
      x: Math.max(Style.gapsOut, Math.min(dockWindow.width - width - Style.gapsOut, root.menuCenter - width / 2))
      y: dockWindow.height - root.baseHeight - root.edgeGap - height - Style.space(10)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

      Column {
        id: menuColumn
        x: Style.spacing.sm
        y: Style.spacing.sm
        width: parent.width - Style.spacing.sm * 2

        Text {
          width: parent.width
          leftPadding: Style.spacing.sm
          bottomPadding: Style.spacing.xs
          textFormat: Text.PlainText
          text: root.menuItem ? root.menuItem.name : ""
          color: Color.menu.text
          opacity: 0.6
          elide: Text.ElideRight
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Repeater {
          model: root.menuEntries

          delegate: Item {
            id: menuRow
            required property var modelData
            width: menuColumn.width
            height: menuRow.modelData.separator ? Style.space(9) : Style.space(30)

            Rectangle {
              visible: !!menuRow.modelData.separator
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Math.max(1, Style.space(1))
              color: Util.alpha(Color.menu.text, 0.12)
            }

            Rectangle {
              visible: !menuRow.modelData.separator
              anchors.fill: parent
              radius: Style.cornerRadius
              color: rowMouse.containsMouse ? Color.menu.selectedBackground : "transparent"
            }

            Text {
              visible: !menuRow.modelData.separator
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.sm
              width: parent.width - Style.spacing.sm * 2 - checkMark.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: menuRow.modelData.label || ""
              color: rowMouse.containsMouse ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            Text {
              id: checkMark
              visible: menuRow.modelData.checked === true
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "󰄬"
              color: rowMouse.containsMouse ? Color.menu.selectedText : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              enabled: !menuRow.modelData.separator
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runMenu(menuRow.modelData)
            }
          }
        }
      }
    }
  }
}
