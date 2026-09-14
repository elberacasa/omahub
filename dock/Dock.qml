import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as Model

// The dock: pinned apps, then open apps that are not pinned, on one edge of the focused screen.
// Its settings live in ~/.local/state/omahub/dock.json, which the hub, the terminal, and agents
// change through `omahub`, so every change shows here at once.
//
// The layout is written once for any edge: "along" runs with the edge the dock sits on, and "across"
// runs in from it. Icons grow away from the edge, and dots sit on the edge side, as on the Mac.
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
  readonly property string edge: ["left", "right"].indexOf(root.config.position) >= 0 ? root.config.position : "bottom"
  readonly property bool vertical: root.edge !== "bottom"
  readonly property bool tiles: root.config.tiles === true
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
  // How far the shelf reaches in from its edge.
  readonly property int baseHeight: root.iconSize + root.dockPadding * 2 + root.dotSpace
  // A soft shelf: rounded in proportion to its depth, edged with a hairline in the theme's text color
  // rather than a heavy border, so the icons carry the dock.
  readonly property int shelfRadius: Math.round(root.baseHeight * 0.32)
  readonly property color hairline: Util.alpha(Color.menu.text, 0.14)
  readonly property int edgeGap: Style.gapsOut
  readonly property real maxScale: root.magnification === "large" ? 1.5 : (root.magnification === "subtle" ? 1.25 : 1)
  readonly property real magnifyRange: root.cellWidth * 2.5
  // The overview button leads the dock, set off from the apps by a divider.
  readonly property int overviewButtonWidth: root.cellWidth + root.dividerWidth
  // How long the shelf runs along its edge, before magnification.
  readonly property int baseWidth: root.layout.width + root.dockPadding * 2 + root.overviewButtonWidth
  // Room in from the edge for magnified icons and the app name.
  readonly property int bandHeight: Math.ceil(root.iconSize * root.maxScale) + root.dockPadding * 2
    + root.dotSpace + root.edgeGap + Style.space(40)
  readonly property int menuSpace: Style.space(300)
  readonly property int labelGap: Style.space(10)
  // How far a click still counts from an icon: past its magnified size away from the edge, and all the
  // way to the screen edge, so the dock is easy to hit.
  readonly property real reachAway: root.iconSize * (root.maxScale - 1)
  readonly property real reachEdge: root.dockPadding + root.dotSpace + root.edgeGap

  // The pointer's position along the dock in the unscaled layout, or -1 when it is away.
  property real pointerX: -1
  property bool pointerInside: false
  property bool lingering: false
  property bool covered: false
  property bool menuOpen: false
  property var menuItem: null
  property real menuCenter: 0
  // SUPER + D puts the keyboard on the dock. The cursor is an app's index, or -1 for the Overview tile.
  property bool keyboardActive: false
  property int keyCursor: 0
  // The highlighted menu row while the menu is used from the keyboard, or -1.
  property int menuIndex: -1
  // A short message above the dock, such as an app that did not open.
  property string notice: ""

  readonly property bool shown: root.enabled
    && (!root.autohide || !root.covered || root.pointerInside || root.lingering || root.menuOpen
      || root.keyboardActive || root.notice !== "")

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
    list.push({ heading: "Magnification" })
    list.push({ label: "Off", action: "magnify", value: "off", checked: root.magnification === "off" })
    list.push({ label: "Subtle", action: "magnify", value: "subtle", checked: root.magnification === "subtle" })
    list.push({ label: "Large", action: "magnify", value: "large", checked: root.magnification === "large" })
    list.push({ heading: "Position on screen" })
    list.push({ label: "Left", action: "position", value: "left", checked: root.edge === "left" })
    list.push({ label: "Bottom", action: "position", value: "bottom", checked: root.edge === "bottom" })
    list.push({ label: "Right", action: "position", value: "right", checked: root.edge === "right" })
    list.push({ separator: true })
    list.push({ label: "Dock settings…", action: "settings" })
    return list
  }

  // The name next to a hovered icon: a small pill, like the one on the Mac.
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

  // The keyboard cursor's ring around an icon or the Overview tile.
  component FocusRing: Rectangle {
    color: "transparent"
    radius: Math.round(width * 0.26)
    border.width: Math.max(2, Style.space(2))
    border.color: Color.accent
  }

  function reload() {
    stateView.reload()
  }

  // Where the dock's pieces are on screen, in the compositor's coordinates, for demo scripts and
  // agents that drive it with a pointer. The edge point is where a hidden dock wakes up.
  function layoutJson() {
    var screen = root.focusedScreen
    var screenX = screen ? screen.x : 0
    var screenY = screen ? screen.y : 0
    var screenWidth = screen ? screen.width : dockWindow.width
    var screenHeight = screen ? screen.height : dockWindow.height
    var originX = root.edge === "right" ? screenX + screenWidth - dockWindow.width : screenX
    var originY = root.edge === "bottom" ? screenY + screenHeight - dockWindow.height : screenY
    function place(item) {
      var point = item.mapToItem(null, 0, 0)
      return {
        x: Math.round(originX + point.x), y: Math.round(originY + point.y),
        width: Math.round(item.width), height: Math.round(item.height)
      }
    }
    var apps = []
    for (var i = 0; i < iconRepeater.count; i++) {
      var cell = iconRepeater.itemAt(i)
      if (cell) apps.push(Object.assign({ id: cell.modelData.id, name: cell.modelData.name, windows: cell.modelData.windows.length }, place(cell)))
    }
    var edgePoint = root.edge === "left" ? { x: screenX, y: screenY + screenHeight / 2 }
      : (root.edge === "right" ? { x: screenX + screenWidth - 1, y: screenY + screenHeight / 2 }
        : { x: screenX + screenWidth / 2, y: screenY + screenHeight - 1 })
    return JSON.stringify({
      shown: root.shown, position: root.edge, keyboard: root.keyboardActive, cursor: root.keyCursor,
      menu: root.menuOpen, apps: apps, overview: place(overviewButton),
      edge: { x: Math.round(edgePoint.x), y: Math.round(edgePoint.y), width: 1, height: 1 }
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

  function openMenu(item, cell, fromKeyboard) {
    root.menuItem = item
    var point = cell.mapToItem(dockVisual, cell.width / 2, cell.height / 2)
    root.menuCenter = root.vertical ? point.y : point.x
    root.menuIndex = -1
    root.menuOpen = true
    if (fromKeyboard) root.stepMenu(1)
  }

  function runMenu(entry) {
    var item = root.menuItem
    root.menuOpen = false
    root.menuIndex = -1
    if (entry.action === "launch") {
      root.launch(item)
    } else if (entry.action === "pin" || entry.action === "unpin") {
      root.runOmahub(["dock", entry.action, item.id],
        (entry.action === "pin" ? "Couldn't keep " : "Couldn't remove ") + item.name)
    } else if (entry.action === "quit") {
      item.windows.forEach(function(window) { window.close() })
    } else if (entry.action === "autohide") {
      root.runOmahub(["set", "dock/autohide", root.autohide ? "off" : "on"], "Couldn't change automatic hiding")
    } else if (entry.action === "magnify") {
      root.runOmahub(["set", "dock/magnify", entry.value], "Couldn't change magnification")
    } else if (entry.action === "position") {
      root.runOmahub(["set", "dock/position", entry.value], "Couldn't move the dock")
    } else if (entry.action === "settings") {
      Quickshell.execDetached([root.omahub, "open", "dock"])
    }
  }

  // Moves the menu's keyboard highlight to the next row that does something, wrapping around.
  function stepMenu(delta) {
    var entries = root.menuEntries
    if (entries.length === 0) return
    var index = root.menuIndex
    for (var tries = 0; tries < entries.length; tries++) {
      index = (index + delta + entries.length) % entries.length
      if (!entries[index].separator && !entries[index].heading) {
        root.menuIndex = index
        return
      }
    }
  }

  // SUPER + D. The cursor starts on the app in front, or the first app.
  function focusDock() {
    if (!root.enabled) return "off"
    // SUPER + D again gives the keyboard back.
    if (root.keyboardActive) {
      root.leaveKeyboard()
      return "left"
    }
    var active = root.items.findIndex(function(item) {
      return item.windows.some(function(window) { return window.activated })
    })
    root.keyCursor = active >= 0 ? active : (root.items.length > 0 ? 0 : -1)
    root.menuOpen = false
    root.keyboardActive = true
    root.keyboardSince = Date.now()
    root.dispatch('hl.dsp.submap("omahub-dock")')
    Qt.callLater(function() { dockKeys.forceActiveFocus() })
    return "ok"
  }

  function leaveKeyboard() {
    if (root.keyboardActive) root.dispatch('hl.dsp.submap("reset")')
    root.keyboardActive = false
    root.menuOpen = false
    root.menuIndex = -1
  }

  function dispatch(command) {
    Quickshell.execDetached(["hyprctl", "dispatch", command])
  }

  // When the keyboard mode began, so the focus change it causes itself is not taken as leaving it.
  property real keyboardSince: 0

  function showNotice(text) {
    root.notice = text
    noticeTimer.restart()
  }

  // Changes from the dock's menu are checked, so one that fails says so above the dock. A second
  // change while one is being checked runs unchecked.
  function runOmahub(args, failure) {
    if (dockCommand.running) {
      Quickshell.execDetached([root.omahub].concat(args))
      return
    }
    dockCommand.failure = failure
    dockCommand.command = [root.omahub].concat(args)
    dockCommand.running = true
  }

  Process {
    id: dockCommand
    property string failure: ""
    onExited: function(exitCode) {
      if (exitCode !== 0) root.showNotice(dockCommand.failure)
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
    root.covered = Model.covered(monitor, clients, root.edge, root.baseWidth + root.edgeGap * 2, root.baseHeight + root.edgeGap)
  }

  onEnabledChanged: {
    if (!root.enabled) root.leaveKeyboard()
    root.checkCover()
  }
  onAutohideChanged: root.checkCover()
  onEdgeChanged: root.checkCover()
  onItemsChanged: {
    if (root.keyCursor >= root.items.length) root.keyCursor = root.items.length - 1
  }
  Component.onCompleted: root.checkCover()

  FileView {
    id: stateView
    path: root.stateFile
    watchChanges: true
    printErrors: false
    // A file caught half written, or edited into something that is not settings, keeps the dock as
    // it was until the file makes sense again.
    onLoaded: {
      var parsed = Model.parseConfig(text())
      if (parsed !== null) root.config = parsed
    }
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
      // A click on a window or a move to another desktop ends the dock's keyboard mode, like clicking away
      // from the Dock on a Mac. The focus change the mode causes as it starts does not count.
      if (root.keyboardActive && Date.now() - root.keyboardSince > 400
          && ["activewindowv2", "workspacev2", "focusedmon"].indexOf(name) !== -1) {
        root.leaveKeyboard()
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

  Timer {
    id: noticeTimer
    interval: 3200
    onTriggered: root.notice = ""
  }

  // A click outside the dock closes its menu, like Omarchy's own popups. Hyprland can drop a grab in
  // the moment it starts, while the click that opened the menu is still settling, so a grab dropped
  // that soon is taken again instead of closing the menu under the pointer.
  property real grabStartedAt: 0
  property bool grabArmed: true
  readonly property bool grabWanted: root.menuOpen || root.keyboardActive
  onGrabWantedChanged: if (root.grabWanted) root.grabStartedAt = Date.now()
  // Opening or closing the menu reshapes the window's input region, which can end the grab too.
  onMenuOpenChanged: root.grabStartedAt = Date.now()

  HyprlandFocusGrab {
    active: root.grabWanted && root.grabArmed
    windows: [dockWindow]
    onCleared: {
      if (Date.now() - root.grabStartedAt < 400 && root.grabWanted) {
        root.grabArmed = false
        Qt.callLater(function() { root.grabArmed = true })
        return
      }
      root.leaveKeyboard()
    }
  }

  PanelWindow {
    id: dockWindow
    visible: root.enabled && root.focusedScreen !== null
    screen: root.focusedScreen
    anchors {
      left: root.edge !== "right"
      right: root.edge !== "left"
      top: root.vertical
      bottom: true
    }
    implicitWidth: root.bandHeight + root.menuSpace
    implicitHeight: root.bandHeight + root.menuSpace
    color: "transparent"
    WlrLayershell.namespace: "omahub-dock"
    WlrLayershell.layer: WlrLayer.Top
    // The dock takes the keyboard only while it is used from the keyboard, after SUPER + D. A menu opened
    // with the mouse leaves focus alone, as Omarchy's popups do, since switching focus as the menu opens
    // can end the grab that keeps it open. Typing otherwise goes to the window in front.
    WlrLayershell.keyboardFocus: root.keyboardActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // A dock that stays on screen keeps its own room, so windows resize to make way for it, like the
    // bar. One that hides floats over them instead.
    exclusionMode: root.enabled && !root.autohide ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: root.baseHeight + root.edgeGap

    // The window's length along the edge the dock sits on.
    readonly property real alongLength: root.vertical ? dockWindow.height : dockWindow.width

    // Input lands only where the dock is: its band while shown and a thin strip at the edge while
    // hidden. While the menu is open the whole dock window takes clicks, so one outside the menu
    // closes it. Everywhere else reaches the windows below.
    mask: Region {
      item: root.menuOpen ? menuHit : (root.shown ? dockHit : edgeHit)
    }

    Item {
      id: dockKeys
      anchors.fill: parent
      focus: root.keyboardActive || root.menuOpen

      Keys.onPressed: function(event) {
        // Keys by name, not by the text they type, so they work with SUPER still held from SUPER + D.
        var previous = event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_H || event.key === Qt.Key_K
        var next = event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_L || event.key === Qt.Key_J
        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter

        if (event.key === Qt.Key_Escape) {
          if (root.menuOpen && root.keyboardActive) {
            root.menuOpen = false
            root.menuIndex = -1
          } else {
            root.leaveKeyboard()
          }
        } else if (root.menuOpen) {
          if (previous || (event.key === Qt.Key_Backtab)) {
            root.stepMenu(-1)
          } else if (next || event.key === Qt.Key_Tab) {
            root.stepMenu(1)
          } else if ((enter || event.key === Qt.Key_Space) && root.menuIndex >= 0) {
            var entry = root.menuEntries[root.menuIndex]
            root.runMenu(entry)
            root.leaveKeyboard()
          } else {
            return
          }
        } else if (root.keyboardActive) {
          if (previous) {
            root.keyCursor = Math.max(-1, root.keyCursor - 1)
          } else if (next) {
            root.keyCursor = Math.min(root.items.length - 1, root.keyCursor + 1)
          } else if (enter) {
            if (root.keyCursor < 0) {
              Quickshell.execDetached([root.omahub, "open", "overview"])
            } else {
              var cell = iconRepeater.itemAt(root.keyCursor)
              if (cell) cell.open()
            }
            root.leaveKeyboard()
          } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Menu) {
            var target = iconRepeater.itemAt(root.keyCursor)
            if (target) root.openMenu(target.modelData, target, true)
          } else {
            return
          }
        } else {
          return
        }
        event.accepted = true
      }
    }

    Item {
      id: menuHit
      anchors.fill: parent
    }

    MouseArea {
      anchors.fill: menuHit
      enabled: root.menuOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: {
        root.menuOpen = false
        root.menuIndex = -1
      }
    }

    Item {
      id: edgeHit
      readonly property int thickness: Math.max(2, Style.space(3))
      x: root.edge === "right" ? dockWindow.width - edgeHit.thickness : 0
      y: root.edge === "bottom" ? dockWindow.height - edgeHit.thickness : 0
      width: root.vertical ? edgeHit.thickness : dockWindow.width
      height: root.vertical ? dockWindow.height : edgeHit.thickness
    }

    Item {
      id: dockHit
      readonly property real length: root.baseWidth + root.cellWidth * 2
      x: root.edge === "left" ? 0 : (root.edge === "right" ? dockWindow.width - root.bandHeight : (dockWindow.width - dockHit.length) / 2)
      y: root.vertical ? (dockWindow.height - dockHit.length) / 2 : dockWindow.height - root.bandHeight
      width: root.vertical ? root.bandHeight : dockHit.length
      height: root.vertical ? dockHit.length : root.bandHeight
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
        var along = root.vertical ? dockHit.y + mouse.y : dockHit.x + mouse.x
        var origin = (dockWindow.alongLength - root.baseWidth) / 2 + root.dockPadding + root.overviewButtonWidth
        root.pointerX = along - origin
      }
    }

    Item {
      id: dockVisual
      anchors.fill: parent
      opacity: root.shown ? 1 : 0

      readonly property real away: root.shown ? 0 : root.baseHeight + root.edgeGap

      Behavior on opacity {
        NumberAnimation { duration: root.shown ? 180 : 140; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
      }

      // A hidden dock waits just past its edge and slides in from there.
      transform: Translate {
        x: root.edge === "left" ? -dockVisual.away : (root.edge === "right" ? dockVisual.away : 0)
        y: root.edge === "bottom" ? dockVisual.away : 0

        Behavior on x {
          NumberAnimation { duration: root.shown ? 240 : 170; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
        }
        Behavior on y {
          NumberAnimation { duration: root.shown ? 240 : 170; easing.type: root.shown ? Easing.OutCubic : Easing.InCubic }
        }
      }

      BorderSurface {
        id: dockBackground
        // With no apps kept or open, the shelf still holds the Overview tile.
        readonly property real length: (root.items.length > 0 ? (root.vertical ? iconRow.height : iconRow.width) : -root.dividerWidth)
          + root.dockPadding * 2 + root.overviewButtonWidth
        x: root.edge === "left" ? root.edgeGap
          : (root.edge === "right" ? parent.width - width - root.edgeGap : (parent.width - width) / 2)
        y: root.vertical ? (parent.height - height) / 2 : parent.height - height - root.edgeGap
        width: root.vertical ? root.baseHeight : dockBackground.length
        height: root.vertical ? dockBackground.length : root.baseHeight
        radius: root.shelfRadius
        color: Util.alpha(Color.menu.background, 0.8)
        borderSpec: Border.flat(root.hairline, Math.max(1, Style.space(1)))
      }

      Item {
        id: overviewButton
        readonly property bool hovered: root.pointerX > -root.overviewButtonWidth && root.pointerX < -root.dividerWidth
        readonly property bool keyed: root.keyboardActive && !root.menuOpen && root.keyCursor === -1
        // Icons start after the dots on the edge side: below them at the bottom, beside them on a side.
        x: dockBackground.x + root.dockPadding + (root.edge === "left" ? root.dotSpace : 0)
        y: dockBackground.y + root.dockPadding
        width: root.vertical ? root.iconSize : root.overviewButtonWidth
        height: root.vertical ? root.overviewButtonWidth : root.iconSize

        // A tile of four squares, drawn from theme colors, so it sits among the app icons in any theme.
        Rectangle {
          id: overviewTile
          width: Math.round(root.iconSize * 0.88)
          height: width
          x: root.vertical ? (root.edge === "left" ? 0 : root.iconSize - width) : root.cellPadding + (root.iconSize - width) / 2
          y: root.vertical ? root.cellPadding + (root.iconSize - height) / 2 : root.iconSize - height
          radius: Math.round(width * 0.24)
          color: Util.alpha(overviewButton.hovered || overviewButton.keyed ? Color.accent : Color.menu.text,
            overviewButton.hovered || overviewButton.keyed ? 0.22 : 0.1)

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
                color: overviewButton.hovered || overviewButton.keyed ? Color.accent : Util.alpha(Color.menu.text, 0.8)
              }
            }
          }
        }

        FocusRing {
          visible: overviewButton.keyed
          x: overviewTile.x - Style.space(4)
          y: overviewTile.y - Style.space(4)
          width: overviewTile.width + Style.space(8)
          height: overviewTile.height + Style.space(8)
        }

        Rectangle {
          visible: root.items.length > 0
          x: root.vertical ? overviewTile.x + (overviewTile.width - width) / 2 : root.cellWidth + root.dividerWidth / 2
          y: root.vertical ? root.cellWidth + root.dividerWidth / 2 : overviewTile.y + (overviewTile.height - height) / 2
          width: root.vertical ? Math.round(root.iconSize * 0.7) : Math.max(1, Style.space(1))
          height: root.vertical ? Math.max(1, Style.space(1)) : Math.round(root.iconSize * 0.7)
          color: root.hairline
        }

        DockLabel {
          visible: (overviewButton.hovered || overviewButton.keyed) && !root.menuOpen
          text: "Overview"
          x: root.edge === "left" ? overviewTile.x + overviewTile.width + root.labelGap
            : (root.edge === "right" ? overviewTile.x - width - root.labelGap : overviewTile.x + (overviewTile.width - width) / 2)
          y: root.vertical ? overviewTile.y + (overviewTile.height - height) / 2 : overviewTile.y - height - root.labelGap
        }

        MouseArea {
          x: root.edge === "left" ? -root.reachEdge : 0
          y: root.edge === "bottom" ? 0 : 0
          width: root.vertical ? parent.width + root.reachEdge : root.cellWidth
          height: root.vertical ? root.cellWidth : parent.height + root.reachEdge
          cursorShape: Qt.PointingHandCursor
          onClicked: Quickshell.execDetached([root.omahub, "open", "overview"])
        }
      }

      Grid {
        id: iconRow
        columns: root.vertical ? 1 : Math.max(1, iconRepeater.count)
        x: root.vertical ? dockBackground.x + root.dockPadding + (root.edge === "left" ? root.dotSpace : 0)
          : dockBackground.x + dockBackground.width - root.dockPadding - width
        y: root.vertical ? dockBackground.y + dockBackground.height - root.dockPadding - height : dockBackground.y + root.dockPadding

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
            readonly property bool keyed: root.keyboardActive && !root.menuOpen && root.keyCursor === cell.index
            readonly property int windowCount: cell.modelData.windows.length
            readonly property bool active: {
              for (var i = 0; i < cell.modelData.windows.length; i++) {
                if (cell.modelData.windows[i].activated) return true
              }
              return false
            }
            readonly property int dividerSpace: cell.modelData.divider ? root.dividerWidth : 0
            readonly property real length: cell.dividerSpace + root.iconSize * cell.scaleFactor + root.cellPadding * 2
            // While an app is starting, the number of windows it had, so the icon bounces until one more
            // appears. -1 when nothing is starting.
            property int launchBaseline: -1
            readonly property bool launching: cell.launchBaseline >= 0 && cell.windowCount <= cell.launchBaseline

            width: root.vertical ? root.iconSize : cell.length
            height: root.vertical ? cell.length : root.iconSize

            onLaunchingChanged: if (!cell.launching) cell.launchBaseline = -1

            function open() {
              if (cell.windowCount === 0) cell.startLaunch()
              root.openItem(cell.modelData)
            }

            function startLaunch() {
              if (!cell.modelData.launchable) return
              cell.launchBaseline = cell.windowCount
            }

            Behavior on width {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }
            Behavior on height {
              NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
            }

            // An app that opens no window within a few seconds says so, instead of bouncing forever.
            Timer {
              interval: 6000
              running: cell.launching
              onTriggered: {
                cell.launchBaseline = -1
                root.showNotice(cell.modelData.name + " didn't open a window")
              }
            }

            Rectangle {
              visible: cell.modelData.divider
              x: root.vertical ? Math.round(root.iconSize * 0.15) : root.dividerWidth / 2
              y: root.vertical ? root.dividerWidth / 2 : Math.round(root.iconSize * 0.15)
              width: root.vertical ? Math.round(root.iconSize * 0.7) : Math.max(1, Style.space(1))
              height: root.vertical ? Math.max(1, Style.space(1)) : Math.round(root.iconSize * 0.7)
              color: root.hairline
            }

            // The icon, and its tile when tiles are on. It grows away from the edge and lifts the
            // same way while its app opens.
            Item {
              id: iconBox
              property real hop: 0
              width: root.iconSize * cell.scaleFactor
              height: width
              x: root.edge === "left" ? iconBox.hop
                : (root.edge === "right" ? root.iconSize - width - iconBox.hop : cell.dividerSpace + root.cellPadding)
              y: root.vertical ? cell.dividerSpace + root.cellPadding : root.iconSize - height - iconBox.hop

              Behavior on width {
                NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
              }

              Rectangle {
                visible: root.tiles || iconImage.status !== Image.Ready
                anchors.fill: parent
                radius: Math.round(width * 0.23)
                color: Util.alpha(Color.menu.text, 0.1)
                border.width: Math.max(1, Style.space(1))
                border.color: root.hairline
              }

              Image {
                id: iconImage
                anchors.centerIn: parent
                width: iconBox.width * (root.tiles ? 0.72 : 1)
                height: width
                // Rendered for the largest magnified size, so icons stay crisp under the pointer.
                sourceSize.width: Math.ceil(root.iconSize * root.maxScale * 2)
                sourceSize.height: Math.ceil(root.iconSize * root.maxScale * 2)
                source: root.iconSource(cell.modelData.icon)
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
              }

              // An app whose icon cannot be found shows its first letter on the tile, never a blank.
              Text {
                visible: iconImage.status !== Image.Ready
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String(cell.modelData.name || "?").charAt(0).toUpperCase()
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Math.round(iconBox.width * 0.46)
                font.bold: true
              }

              SequentialAnimation {
                id: hopAnimation
                loops: cell.launching ? Animation.Infinite : 1
                alwaysRunToEnd: true
                running: root.bounce && cell.launching
                NumberAnimation { target: iconBox; property: "hop"; to: Style.space(14); duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: iconBox; property: "hop"; to: 0; duration: 220; easing.type: Easing.InOutCubic }
              }
            }

            FocusRing {
              visible: cell.keyed
              x: iconBox.x - Style.space(4)
              y: iconBox.y - Style.space(4)
              width: iconBox.width + Style.space(8)
              height: iconBox.height + Style.space(8)
            }

            Rectangle {
              visible: root.indicators && cell.windowCount > 0
              width: Style.space(4)
              height: width
              radius: width / 2
              x: root.edge === "left" ? -root.dotSpace + (root.dotSpace - width) / 2
                : (root.edge === "right" ? root.iconSize + (root.dotSpace - width) / 2 : iconBox.x + (iconBox.width - width) / 2)
              y: root.vertical ? iconBox.y + (iconBox.height - height) / 2 : root.iconSize + (root.dotSpace - height) / 2
              color: cell.active ? Color.accent : Util.alpha(Color.menu.text, 0.55)
            }

            DockLabel {
              visible: (cell.hovered || cell.keyed) && !root.menuOpen
              text: cell.modelData.name
              x: root.edge === "left" ? iconBox.x + iconBox.width + root.labelGap
                : (root.edge === "right" ? iconBox.x - width - root.labelGap : iconBox.x + (iconBox.width - width) / 2)
              y: root.vertical ? iconBox.y + (iconBox.height - height) / 2 : iconBox.y - height - root.labelGap
            }

            // Clicks count from the screen edge out past the magnified icon, not just on the icon.
            MouseArea {
              x: root.edge === "left" ? -root.reachEdge : (root.edge === "right" ? -root.reachAway : 0)
              y: root.edge === "bottom" ? -root.reachAway : 0
              width: root.vertical ? root.iconSize + root.reachAway + root.reachEdge : parent.width
              height: root.vertical ? parent.height : root.iconSize + root.reachAway + root.reachEdge
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  root.openMenu(cell.modelData, cell, false)
                } else if (mouse.button === Qt.MiddleButton) {
                  cell.startLaunch()
                  root.launch(cell.modelData)
                } else {
                  cell.open()
                }
              }
            }
          }
        }
      }

      DockLabel {
        visible: root.notice !== ""
        text: root.notice
        x: root.edge === "left" ? dockBackground.x + dockBackground.width + root.labelGap
          : (root.edge === "right" ? dockBackground.x - width - root.labelGap : dockBackground.x + (dockBackground.width - width) / 2)
        y: root.vertical ? dockBackground.y - height - root.labelGap : dockBackground.y - height - root.labelGap * 5
      }
    }

    // The menu opens beside the dock: above it at the bottom, next to it on a side.
    BorderSurface {
      id: menuCard
      visible: root.menuOpen
      width: Style.space(230)
      height: menuColumn.implicitHeight + Style.spacing.sm * 2
      x: root.edge === "left" ? root.edgeGap + root.baseHeight + root.labelGap
        : (root.edge === "right" ? dockWindow.width - root.edgeGap - root.baseHeight - width - root.labelGap
          : Math.max(Style.gapsOut, Math.min(dockWindow.width - width - Style.gapsOut, root.menuCenter - width / 2)))
      y: root.vertical ? Math.max(Style.gapsOut, Math.min(dockWindow.height - height - Style.gapsOut, root.menuCenter - height / 2))
        : dockWindow.height - root.baseHeight - root.edgeGap - height - root.labelGap
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
            required property int index
            readonly property bool actionable: !menuRow.modelData.separator && !menuRow.modelData.heading
            readonly property bool highlighted: rowMouse.containsMouse || root.menuIndex === menuRow.index
            width: menuColumn.width
            height: menuRow.modelData.separator ? Style.space(9) : (menuRow.modelData.heading ? Style.space(24) : Style.space(30))

            Rectangle {
              visible: !!menuRow.modelData.separator
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Math.max(1, Style.space(1))
              color: Util.alpha(Color.menu.text, 0.12)
            }

            Text {
              visible: !!menuRow.modelData.heading
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.spacing.xs
              x: Style.spacing.sm
              textFormat: Text.PlainText
              text: menuRow.modelData.heading || ""
              color: Color.menu.text
              opacity: 0.6
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              visible: menuRow.actionable
              anchors.fill: parent
              radius: Style.cornerRadius
              color: menuRow.highlighted ? Color.menu.selectedBackground : "transparent"
            }

            Text {
              visible: menuRow.actionable
              anchors.verticalCenter: parent.verticalCenter
              x: Style.spacing.sm
              width: parent.width - Style.spacing.sm * 2 - checkMark.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: menuRow.modelData.label || ""
              color: menuRow.highlighted ? Color.menu.selectedText : Color.menu.text
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
              text: String.fromCodePoint(0xF012C)
              color: menuRow.highlighted ? Color.menu.selectedText : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              enabled: menuRow.actionable
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
