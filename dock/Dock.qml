import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "DockModel.js" as Model
import "../desktops/DesktopsModel.js" as Desktops

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
  // With no apps saved yet, the dock keeps the defaults `omahub dock pins` reports, the same list the
  // first keep or remove starts from.
  property var defaultPins: []
  readonly property var savedPins: Array.isArray(root.config.pins) ? root.config.pins : root.defaultPins
  // A new order from a drag shows at once, while it is being saved.
  property var pinsOverride: null
  readonly property var pins: root.pinsOverride !== null ? root.pinsOverride : root.savedPins
  readonly property var keptIds: root.items.filter(function(item) { return item.pinned }).map(function(item) { return item.id })

  // The Add apps panel: every installed app, with the kept ones checked. Choices show before they are saved.
  property bool pickerOpen: false
  property string pickerQuery: ""
  property int pickerIndex: 0
  property var pickerPending: ({})
  readonly property var pickerRows: root.pickerOpen
    ? Model.catalog(DesktopEntries.applications.values || [], root.savedPins, root.pickerQuery, root.pickerPending) : []

  // An icon being dragged: its index, where the pointer is along the dock in the icons' own layout, and
  // how far it has been pulled off the dock.
  property int dragIndex: -1
  // True while the left button is down on an icon, from the press, before any drag begins.
  property bool iconPressed: false
  property real dragAlong: 0
  property real dragStartAlong: 0
  property real dragAway: 0
  readonly property var dragItem: root.dragIndex >= 0 ? root.items[root.dragIndex] || null : null
  readonly property bool dragRemoving: root.dragItem !== null && root.dragItem.pinned && root.dragAway > root.iconSize * 1.2
  // The slot among the kept apps the icon would land in, counted without it, or -1 for none.
  readonly property int dragSlot: {
    var item = root.dragItem
    if (!item || root.dragRemoving || !item.launchable) return -1
    var count = root.keptIds.length
    var keptEnd = count > 0 ? root.layout.centers[count - 1] + root.cellWidth / 2 : 0
    if (!item.pinned && root.dragAlong > keptEnd + root.dividerWidth) return -1
    var slot = Model.dropSlot(root.layout.centers, root.dragAlong, count)
    return item.pinned && slot > root.dragIndex ? slot - 1 : slot
  }

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
  // Room beside the dock for what is open on it, measured from the menu or the Add apps panel itself, so
  // a menu that grows never runs past the edge of the dock's window.
  readonly property int menuSpace: {
    var card = root.pickerOpen ? pickerCard : (root.menuOpen ? menuCard : null)
    var needed = card ? (root.vertical ? card.width : card.height) + root.labelGap + Style.gapsOut : 0
    return Math.max(Style.space(300), Math.ceil(needed))
  }
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
      || root.keyboardActive || root.pickerOpen || root.dragIndex >= 0 || root.notice !== "")

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
    list.push({ label: "Add apps…", action: "apps" })
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
      menu: root.menuOpen, apps: apps, overview: place(overviewButton), pressed: root.iconPressed,
      screen: { x: screenX, y: screenY, width: screenWidth, height: screenHeight },
      window: { x: originX, y: originY, width: Math.round(dockWindow.width), height: Math.round(dockWindow.height) },
      shelf: place(dockBackground),
      menuCard: root.menuOpen ? place(menuCard) : null,
      busy: dockCommand.running || root.commandQueue.length > 0,
      menuItem: root.menuOpen && root.menuItem ? root.menuItem.id : null,
      menuEntry: root.menuOpen && root.menuIndex >= 0 && root.menuEntries[root.menuIndex] ? root.menuEntries[root.menuIndex].label || null : null,
      drag: root.dragIndex >= 0 ? { index: root.dragIndex, along: Math.round(root.dragAlong), away: Math.round(root.dragAway),
        removing: root.dragRemoving, slot: root.dragSlot } : null,
      picker: root.pickerOpen ? { query: root.pickerQuery, index: root.pickerIndex, rows: root.pickerRows.length,
        selected: root.pickerRows[root.pickerIndex] || null, card: place(pickerCard) } : null,
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

  // Click opens an app, or brings its windows forward one at a time. From a click, the pointer stays on
  // the dock instead of jumping to the window, even on another desktop; from the keyboard, focus moves
  // the way Omarchy moves it.
  function openItem(item, fromPointer) {
    var windows = item.windows || []
    if (windows.length === 0) {
      root.launch(item)
      return
    }
    var current = -1
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].activated) current = i
    }
    var next = windows[(current + 1) % windows.length]
    var address = fromPointer === true ? root.addressFor(next) : ""
    if (address !== "") {
      Quickshell.execDetached(["hyprctl", "eval", Desktops.quietFocusLua({ window: "address:" + address })])
    } else {
      next.activate()
    }
  }

  // Hyprland's address for a window the dock knows through the toplevel protocol.
  function addressFor(toplevel) {
    var list = Hyprland.toplevels.values || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].wayland === toplevel) return "0x" + String(list[i].address).replace(/^0x/, "")
    }
    return ""
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
    } else if (entry.action === "apps") {
      root.openPicker()
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

  // Close the menu, the Add apps panel, any drag, and keyboard mode at once.
  function dismiss() {
    root.dragIndex = -1
    root.iconPressed = false
    root.menuOpen = false
    root.menuIndex = -1
    root.closePicker()
    root.leaveKeyboard()
  }

  function leaveKeyboard() {
    if (root.keyboardActive) root.dispatch('hl.dsp.submap("reset")')
    root.keyboardActive = false
    root.menuOpen = false
    root.menuIndex = -1
    root.pickerOpen = false
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

  // Changes from the dock are checked, so one that fails says so above the dock. They run one at a time
  // in the order they were made, since each one reads and writes the same dock file.
  property var commandQueue: []

  function runOmahub(args, failure) {
    root.commandQueue = root.commandQueue.concat([{ args: args, failure: failure }])
    if (!dockCommand.running) root.runNextCommand()
  }

  function runNextCommand() {
    if (root.commandQueue.length === 0) return
    var next = root.commandQueue[0]
    root.commandQueue = root.commandQueue.slice(1)
    dockCommand.failure = next.failure
    dockCommand.command = [root.omahub].concat(next.args)
    dockCommand.running = true
  }

  Process {
    id: dockCommand
    property string failure: ""
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.showNotice(dockCommand.failure)
        root.pinsOverride = null
        root.pickerPending = ({})
      }
      Qt.callLater(root.runNextCommand)
    }
  }

  // Keep exactly these apps, in this order, showing the order before it is saved.
  function applyPins(next, failure) {
    root.pinsOverride = next
    pinsOverrideTimer.restart()
    root.runOmahub(["dock", "order"].concat(next), failure)
  }

  Timer {
    id: pinsOverrideTimer
    interval: 4000
    onTriggered: root.pinsOverride = null
  }

  // Saved changes replace the ones shown ahead of them.
  onConfigChanged: {
    if (root.pinsOverride !== null && JSON.stringify(root.savedPins) === JSON.stringify(root.pinsOverride)) root.pinsOverride = null
    var pending = root.pickerPending
    var left = {}
    var settled = false
    for (var id in pending) {
      var kept = root.savedPins.some(function(pin) { return Model.key(pin) === id })
      if (kept === pending[id]) settled = true
      else left[id] = pending[id]
    }
    if (settled) root.pickerPending = left
  }

  function openPicker() {
    root.menuOpen = false
    root.menuIndex = -1
    root.pickerQuery = ""
    root.pickerIndex = 0
    root.pickerPending = ({})
    root.menuCenter = root.vertical ? dockBackground.y + dockBackground.height / 2 : dockBackground.x + dockBackground.width / 2
    root.pickerOpen = true
    Qt.callLater(function() { dockKeys.forceActiveFocus() })
  }

  function closePicker() {
    root.pickerOpen = false
    root.pickerQuery = ""
  }

  function setPickerQuery(text) {
    root.pickerQuery = text
    root.pickerIndex = 0
  }

  function togglePicked(row) {
    if (!row) return
    var keep = !row.kept
    var pending = Object.assign({}, root.pickerPending)
    pending[Model.key(row.id)] = keep
    root.pickerPending = pending
    root.runOmahub(["dock", keep ? "pin" : "unpin", row.id], (keep ? "Couldn't keep " : "Couldn't remove ") + row.name)
  }

  function startIconDrag(index, along) {
    root.menuOpen = false
    root.dragIndex = index
    root.dragStartAlong = along
    root.dragAlong = along
    root.dragAway = 0
  }

  // Let go: off the dock removes a kept app, and along the kept apps puts it in its new place, keeping
  // an open app that was not kept.
  function endIconDrag() {
    var item = root.dragItem
    var removing = root.dragRemoving
    var slot = root.dragSlot
    root.dragIndex = -1
    if (!item) return
    var kept = root.keptIds
    if (removing) {
      root.applyPins(kept.filter(function(id) { return id !== item.id }), "Couldn't remove " + item.name)
    } else if (slot >= 0) {
      var next = Model.reorder(kept, item.id, slot)
      if (JSON.stringify(next) !== JSON.stringify(kept)) {
        root.applyPins(next, (item.pinned ? "Couldn't move " : "Couldn't keep ") + item.name)
      }
    }
  }

  // Shift + h or l from the keyboard moves the kept app under the cursor one place.
  function moveKept(step) {
    var item = root.items[root.keyCursor]
    if (!item || !item.pinned) return
    var kept = root.keptIds
    var to = kept.indexOf(item.id) + step
    if (to < 0 || to >= kept.length) return
    root.applyPins(Model.reorder(kept, item.id, to), "Couldn't move " + item.name)
    root.keyCursor = to
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
      if (parsed !== null && !Array.isArray(parsed.pins)) defaultPinsRead.running = true
    }
    onFileChanged: reload()
    onLoadFailed: {
      root.config = ({})
      defaultPinsRead.running = true
    }
  }

  Process {
    id: defaultPinsRead
    command: [root.omahub, "dock", "pins"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var pins = JSON.parse(text)
          if (Array.isArray(pins)) root.defaultPins = pins
        } catch (e) {}
      }
    }
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
  readonly property bool grabWanted: root.menuOpen || root.keyboardActive || root.pickerOpen
  onGrabWantedChanged: if (root.grabWanted) root.grabStartedAt = Date.now()
  // Opening or closing the menu or the Add apps panel reshapes the window and its input region, and the
  // panel takes the keyboard, any of which can end the grab too.
  onMenuOpenChanged: root.grabStartedAt = Date.now()
  onPickerOpenChanged: root.grabStartedAt = Date.now()

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
    // The Add apps panel takes it too, for its search.
    WlrLayershell.keyboardFocus: root.keyboardActive || root.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
      // A pressed icon takes the whole window too, so a drag off the dock stays with the dock.
      item: root.menuOpen || root.pickerOpen || root.iconPressed ? menuHit : (root.shown ? dockHit : edgeHit)
    }

    Item {
      id: dockKeys
      anchors.fill: parent
      focus: root.keyboardActive || root.menuOpen || root.pickerOpen

      Keys.onPressed: function(event) {
        // Keys by name, not by the text they type, so they work with SUPER still held from SUPER + D.
        var previous = event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_H || event.key === Qt.Key_K
        var next = event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_L || event.key === Qt.Key_J
        var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        var shifted = (event.modifiers & Qt.ShiftModifier) !== 0

        // The Add apps panel types into its search, so only arrows and Tab move through it.
        if (root.pickerOpen) {
          var count = root.pickerRows.length
          if (event.key === Qt.Key_Escape) {
            if (root.pickerQuery !== "") root.setPickerQuery("")
            else root.closePicker()
          } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !shifted)) {
            if (count > 0) root.pickerIndex = (root.pickerIndex + 1) % count
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            if (count > 0) root.pickerIndex = (root.pickerIndex - 1 + count) % count
          } else if (enter || (event.key === Qt.Key_Space && root.pickerQuery === "")) {
            root.togglePicked(root.pickerRows[root.pickerIndex])
          } else if (Util.editsFilter(event, root.pickerQuery)) {
            root.setPickerQuery(Util.editedFilter(event, root.pickerQuery))
          } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setPickerQuery(root.pickerQuery + event.text)
          } else {
            return
          }
          event.accepted = true
          return
        }

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
            if (!root.pickerOpen) root.leaveKeyboard()
          } else {
            return
          }
        } else if (root.keyboardActive) {
          if ((previous || next) && shifted) {
            root.moveKept(next ? 1 : -1)
          } else if (previous) {
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
      enabled: root.menuOpen || root.pickerOpen
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: {
        root.menuOpen = false
        root.menuIndex = -1
        root.closePicker()
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
          visible: (overviewButton.hovered || overviewButton.keyed) && !root.menuOpen && !root.pickerOpen && root.dragIndex < 0
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
            readonly property real scaleFactor: root.magnify && root.pointerX >= 0 && root.dragIndex < 0
              ? Model.magnification(cell.distance, root.magnifyRange, root.maxScale) : 1
            readonly property bool dragged: root.dragIndex === cell.index
            // While another icon is dragged, this one steps aside to open its landing place, or to close
            // the gap it left.
            readonly property real shift: {
              var from = root.dragIndex
              if (from < 0 || cell.dragged) return 0
              var item = root.dragItem
              var slot = root.dragSlot
              if (item.pinned) {
                if (slot < 0) return cell.index > from ? -root.cellWidth : 0
                if (cell.index > from && cell.index <= slot) return -root.cellWidth
                if (cell.index < from && cell.index >= slot) return root.cellWidth
                return 0
              }
              return slot >= 0 && cell.index >= slot && cell.index < from ? root.cellWidth : 0
            }
            z: cell.dragged ? 2 : 0

            // The dragged icon follows the pointer, fading once it is far enough off the dock to remove.
            transform: Translate {
              x: root.vertical ? (cell.dragged ? (root.edge === "left" ? root.dragAway : -root.dragAway) : 0)
                : (cell.dragged ? root.dragAlong - root.dragStartAlong : cell.shift)
              y: root.vertical ? (cell.dragged ? root.dragAlong - root.dragStartAlong : cell.shift)
                : (cell.dragged ? -root.dragAway : 0)

              Behavior on x {
                enabled: !cell.dragged
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
              Behavior on y {
                enabled: !cell.dragged
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
            }
            opacity: cell.dragged && root.dragRemoving ? 0.5 : 1

            Behavior on opacity {
              NumberAnimation { duration: 120 }
            }
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

            function open(fromPointer) {
              if (cell.windowCount === 0) cell.startLaunch()
              root.openItem(cell.modelData, fromPointer === true)
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
              visible: cell.dragged ? root.dragRemoving
                : (cell.hovered || cell.keyed) && !root.menuOpen && !root.pickerOpen && root.dragIndex < 0
              text: cell.dragged ? "Remove" : cell.modelData.name
              x: root.edge === "left" ? iconBox.x + iconBox.width + root.labelGap
                : (root.edge === "right" ? iconBox.x - width - root.labelGap : iconBox.x + (iconBox.width - width) / 2)
              y: root.vertical ? iconBox.y + (iconBox.height - height) / 2 : iconBox.y - height - root.labelGap
            }

            // Clicks count from the screen edge out past the magnified icon, not just on the icon. A press
            // that moves drags the icon: along the dock to reorder, off it to remove.
            MouseArea {
              id: cellMouse
              property point pressPoint: Qt.point(0, 0)
              property bool moved: false
              x: root.edge === "left" ? -root.reachEdge : (root.edge === "right" ? -root.reachAway : 0)
              y: root.edge === "bottom" ? -root.reachAway : 0
              width: root.vertical ? root.iconSize + root.reachAway + root.reachEdge : parent.width
              height: root.vertical ? parent.height : root.iconSize + root.reachAway + root.reachEdge
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              cursorShape: cell.dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              onPressed: function(mouse) {
                cellMouse.pressPoint = cellMouse.mapToItem(iconRow, mouse.x, mouse.y)
                cellMouse.moved = false
                if (mouse.button === Qt.LeftButton) root.iconPressed = true
              }
              onPositionChanged: function(mouse) {
                if (!(cellMouse.pressedButtons & Qt.LeftButton)) return
                var point = cellMouse.mapToItem(iconRow, mouse.x, mouse.y)
                var along = root.vertical ? point.y : point.x
                var startAlong = root.vertical ? cellMouse.pressPoint.y : cellMouse.pressPoint.x
                var away = root.edge === "bottom" ? cellMouse.pressPoint.y - point.y
                  : (root.edge === "left" ? point.x - cellMouse.pressPoint.x : cellMouse.pressPoint.x - point.x)
                if (!cellMouse.moved && Math.hypot(point.x - cellMouse.pressPoint.x, point.y - cellMouse.pressPoint.y) > Style.space(10)) {
                  cellMouse.moved = true
                  root.startIconDrag(cell.index, startAlong)
                }
                if (cell.dragged) {
                  root.dragAlong = along
                  root.dragAway = Math.max(0, away)
                }
              }
              onReleased: {
                root.iconPressed = false
                if (cell.dragged) root.endIconDrag()
              }
              onCanceled: {
                root.iconPressed = false
                if (cell.dragged) root.dragIndex = -1
              }
              onClicked: function(mouse) {
                if (cellMouse.moved) return
                if (mouse.button === Qt.RightButton) {
                  root.openMenu(cell.modelData, cell, false)
                } else if (mouse.button === Qt.MiddleButton) {
                  cell.startLaunch()
                  root.launch(cell.modelData)
                } else {
                  cell.open(true)
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

    // Add apps: every installed app with the kept ones checked, beside the dock like its menu. Typing
    // searches, and Enter, Space, or a click keeps or removes an app at once.
    BorderSurface {
      id: pickerCard
      visible: root.pickerOpen
      width: Style.space(340)
      height: pickerColumn.implicitHeight + Style.spacing.lg * 2
      x: root.edge === "left" ? root.edgeGap + root.baseHeight + root.labelGap
        : (root.edge === "right" ? dockWindow.width - root.edgeGap - root.baseHeight - width - root.labelGap
          : Math.max(Style.gapsOut, Math.min(dockWindow.width - width - Style.gapsOut, root.menuCenter - width / 2)))
      y: root.vertical ? Math.max(Style.gapsOut, Math.min(dockWindow.height - height - Style.gapsOut, root.menuCenter - height / 2))
        : dockWindow.height - root.baseHeight - root.edgeGap - height - root.labelGap
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

      // Clicks inside the panel stay in it, instead of reaching the area that closes it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      }

      Column {
        id: pickerColumn
        x: Style.spacing.lg
        y: Style.spacing.lg
        width: parent.width - Style.spacing.lg * 2
        spacing: Style.spacing.sm

        Item {
          width: parent.width
          height: pickerTitle.implicitHeight

          Text {
            id: pickerTitle
            textFormat: Text.PlainText
            text: "Add apps"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.baseline: pickerTitle.baseline
            textFormat: Text.PlainText
            text: root.keptIds.length === 1 ? "1 in the dock" : root.keptIds.length + " in the dock"
            color: Color.menu.text
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(34)
          radius: Style.cornerRadius
          color: Util.alpha(Color.menu.text, 0.06)
          border.width: Math.max(1, Style.space(1))
          border.color: Color.accent

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String.fromCodePoint(0xF0349)
              color: Color.menu.text
              opacity: 0.6
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, pickerColumn.width - Style.space(60))
              elide: Text.ElideLeft
              textFormat: Text.PlainText
              text: root.pickerQuery !== "" ? root.pickerQuery : "Search apps"
              color: Color.menu.text
              opacity: root.pickerQuery !== "" ? 1 : 0.5
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(1, Style.space(2))
              height: Style.font.body + Style.spacing.xs
              color: Color.accent

              SequentialAnimation on opacity {
                running: root.pickerOpen
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
                NumberAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 530 }
              }
            }
          }
        }

        ListView {
          id: pickerList
          readonly property int rowHeight: Style.space(40)
          width: parent.width
          height: Math.max(pickerList.rowHeight, Math.min(root.pickerRows.length * pickerList.rowHeight, Style.space(360)))
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.pickerRows
          currentIndex: root.pickerIndex
          onCurrentIndexChanged: pickerList.positionViewAtIndex(pickerList.currentIndex, ListView.Contain)

          delegate: Item {
            id: pickerRow
            required property var modelData
            required property int index
            readonly property bool highlighted: pickerRowMouse.containsMouse || root.pickerIndex === pickerRow.index
            width: pickerList.width
            height: pickerList.rowHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: pickerRow.highlighted ? Color.menu.selectedBackground : "transparent"
            }

            Image {
              id: pickerIcon
              x: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(26)
              height: width
              sourceSize.width: Style.space(52)
              sourceSize.height: Style.space(52)
              source: root.iconSource(pickerRow.modelData.icon)
              fillMode: Image.PreserveAspectFit
              smooth: true
            }

            Column {
              anchors.left: pickerIcon.right
              anchors.leftMargin: Style.spacing.sm
              anchors.right: pickerCheck.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter

              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: pickerRow.modelData.name
                color: pickerRow.highlighted ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              Text {
                visible: pickerRow.modelData.detail !== ""
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: pickerRow.modelData.detail
                color: pickerRow.highlighted ? Color.menu.selectedText : Color.menu.text
                opacity: 0.6
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }

            // A check box, filled while the app is kept.
            Rectangle {
              id: pickerCheck
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: width
              radius: Math.round(width * 0.25)
              color: pickerRow.modelData.kept ? Color.accent : "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: pickerRow.modelData.kept ? Color.accent : Util.alpha(pickerRow.highlighted ? Color.menu.selectedText : Color.menu.text, 0.4)

              Behavior on color {
                ColorAnimation { duration: 100 }
              }

              Text {
                visible: pickerRow.modelData.kept
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: String.fromCodePoint(0xF012C)
                color: Color.menu.background
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: pickerRowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.pickerIndex = pickerRow.index
                root.togglePicked(pickerRow.modelData)
              }
            }
          }

          Text {
            visible: root.pickerRows.length === 0
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width)
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: root.pickerQuery !== "" ? "No apps match “" + root.pickerQuery + "”" : "No apps found"
            color: Color.menu.text
            opacity: 0.6
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: "Drag an icon in the dock to move it, or off the dock to remove it."
          color: Color.menu.text
          opacity: 0.5
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
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
