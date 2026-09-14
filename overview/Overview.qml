import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "OverviewModel.js" as Model

// Every desktop on the focused screen as a live thumbnail, and the selected desktop's windows laid
// out large with live previews. Keyboard first: h, j, k, and l move between windows like the arrows,
// and past the end of a row to the next desktop. Shift + h and l jump desktops, Tab walks windows,
// Enter goes, x closes, a number shows that desktop, Shift + a number moves a window there, Shift + n
// moves it to a new desktop, u undoes a move, and typing searches. Desktops 1 to 5 are always there.
// Opened again while SUPER is held, it walks windows and letting go of SUPER jumps to the choice.
Item {
  id: root

  property bool opened: false
  property bool mounted: false
  property var desktops: []
  property int desktopIndex: 0
  property int windowIndex: 0
  property string query: ""
  property bool searching: false
  property bool cycling: false
  property bool userMoved: false
  // Focused window addresses, newest first, kept from Hyprland's events even while closed, so the
  // switcher knows the window used before the instant SUPER + TAB is pressed.
  property var focusOrder: []
  // False from opening until the first rebuild on fresh data from Hyprland, so a desktop never reads
  // "Empty desktop" while its windows are still being reported.
  property bool settled: false
  // While switching, the choice is how many windows back, not a particular window, so it survives
  // Hyprland's fresher window list arriving a moment after the key press.
  property int cycleSteps: 0
  property real switchStartedAt: 0
  // A quick tap can let go of SUPER before the overview even opens; that release is remembered.
  property real releasedAt: 0
  property var dragWindow: null
  property point dragPoint: Qt.point(0, 0)
  property var dropTarget: null

  readonly property var monitor: Hyprland.focusedMonitor
  readonly property real monitorX: root.monitor ? root.monitor.x : 0
  readonly property real monitorY: root.monitor ? root.monitor.y : 0
  readonly property real monitorWidth: root.monitor && root.monitor.scale > 0 ? root.monitor.width / root.monitor.scale : 1920
  readonly property real monitorHeight: root.monitor && root.monitor.scale > 0 ? root.monitor.height / root.monitor.scale : 1080
  readonly property var focusedScreen: {
    var name = root.monitor ? root.monitor.name : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  readonly property var selectedDesktop: root.desktops.length > 0
    ? root.desktops[Math.max(0, Math.min(root.desktopIndex, root.desktops.length - 1))] : null
  readonly property bool searchActive: root.searching && root.query !== ""
  readonly property var shownWindows: {
    if (root.cycling) return Model.recent(root.desktops, root.focusOrder)
    var list = root.searchActive
      ? Model.search(root.desktops, root.query)
      : (root.selectedDesktop ? root.selectedDesktop.windows : [])
    var leaving = root.leaving
    return list.filter(function(item) { return leaving[item.address] !== item.workspace })
  }
  // Holding Shift, or dragging a window, lights the desktop numbers that move a window there.
  property bool shiftHeld: false
  // The Shift layer shows once Shift is held a moment, so a quick Shift + a number never flashes it.
  property bool shiftShown: false
  onShiftHeldChanged: {
    if (root.shiftHeld) {
      shiftRevealTimer.restart()
    } else {
      shiftRevealTimer.stop()
      root.shiftShown = false
    }
  }
  readonly property bool numbersLit: (root.shiftShown && !root.searching || root.dragWindow !== null) && !root.cycling
  // SUPER is still held from SUPER + TAB. Holding it is one session: a choice made during it, by
  // walking with TAB, a number, h j k l, the arrows, or the pointer, is where letting go of SUPER goes.
  property bool superHeld: false
  property bool heldChoice: false

  Timer {
    id: shiftRevealTimer
    interval: 220
    onTriggered: root.shiftShown = root.shiftHeld
  }
  readonly property bool hasUnopened: root.desktops.some(function(item) { return item.unopened })
  readonly property var rects: Model.pack(root.shownWindows, mainArea.width, mainArea.height, root.cardGap)
  readonly property var selectedWindow: root.shownWindows.length > 0 ? root.shownWindows[root.windowIndex] || null : null

  readonly property int cardGap: Style.space(32)
  readonly property int stripGap: Style.space(14)
  // Many desktops shrink their thumbnails before the strip would run off the screen.
  readonly property int thumbWidth: Math.max(Style.space(56), Math.min(Style.space(210),
    (overviewWindow.width - Style.space(160) - root.stripGap * root.desktops.length) / Math.max(1, root.desktops.length + (root.hasUnopened ? 0 : 1))))
  readonly property int thumbHeight: Math.round(root.thumbWidth * root.monitorHeight / root.monitorWidth)
  readonly property int labelSpace: Style.space(28)

  // Where the overview's pieces are on screen, in the compositor's coordinates, for demo scripts
  // and agents that drive it with a pointer.
  function layoutJson() {
    function place(item) {
      var point = item.mapToItem(scene, 0, 0)
      return {
        x: Math.round(point.x + root.monitorX), y: Math.round(point.y + root.monitorY),
        width: Math.round(item.width), height: Math.round(item.height)
      }
    }
    var cards = []
    for (var i = 0; i < cardRepeater.count; i++) {
      var card = cardRepeater.itemAt(i)
      if (card) cards.push(Object.assign({ address: card.modelData.address, workspace: card.modelData.workspace, title: card.modelData.title }, place(card)))
    }
    var desktops = []
    for (var j = 0; j < thumbRepeater.count; j++) {
      var thumb = thumbRepeater.itemAt(j)
      if (thumb) desktops.push(Object.assign({ id: thumb.modelData.id, unopened: thumb.modelData.unopened }, place(thumb.frame)))
    }
    var selected = root.selectedWindow
    return JSON.stringify({
      opened: root.opened, cycling: root.cycling, numbersLit: root.numbersLit, held: root.superHeld, choice: root.heldChoice,
      undo: root.lastMove ? root.lastMove.to : null, flying: flight.running,
      selected: selected ? { address: selected.address, workspace: selected.workspace, title: selected.title } : null,
      cards: cards, desktops: desktops, newDesktop: place(newTile)
    })
  }

  function dispatch(command) {
    Quickshell.execDetached(["hyprctl", "dispatch", command])
  }

  function iconFor(appId) {
    var name = String(appId || "").toLowerCase()
    var themed = name !== "" ? Quickshell.iconPath(name, true) : ""
    return themed !== "" ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  function rebuild() {
    var keepAddress = root.selectedWindow ? root.selectedWindow.address : ""
    var keepDesktop = root.selectedDesktop ? root.selectedDesktop.id : -1
    // Desktops 1 to 5 always show, so there is always somewhere to move a window and its number to press.
    root.desktops = Model.desktops(Hyprland.workspaces.values || [], Hyprland.toplevels.values || [],
      root.monitor ? root.monitor.name : "", 5)

    var desktop = root.desktops.findIndex(function(item) { return item.id === keepDesktop })
    root.desktopIndex = desktop >= 0 ? desktop : Math.max(0, Math.min(root.desktopIndex, root.desktops.length - 1))
    var count = root.shownWindows.length
    if (root.cycling && count > 0) {
      root.windowIndex = ((root.cycleSteps % count) + count) % count
      return
    }
    var window = root.shownWindows.findIndex(function(item) { return item.address === keepAddress })
    root.windowIndex = window >= 0 ? window : Math.max(0, Math.min(root.windowIndex, count - 1))
  }

  function selectCurrent() {
    var current = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    root.desktopIndex = Math.max(0, root.desktops.findIndex(function(item) { return item.id === current }))
    root.windowIndex = Math.max(0, root.shownWindows.findIndex(function(item) {
      return item.toplevel && item.toplevel.activated
    }))
  }

  function open(mode) {
    if (root.opened) {
      if (mode === "next") {
        root.superHeld = true
        root.cycle(1)
      }
      return
    }
    var switching = mode === "next"
    root.superHeld = switching
    root.heldChoice = false

    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.settled = false
    root.query = ""
    root.searching = false
    root.cycling = false
    root.userMoved = false
    root.shiftHeld = false
    root.leaving = ({})
    root.lastMove = null
    root.rebuild()
    root.selectCurrent()
    // SUPER + TAB is a switcher from the first press: it already points at the window used before,
    // so a quick tap flips between the last two windows.
    if (switching) root.cycle(1)

    // SUPER already came up: this was the quickest tap, so flip without showing anything.
    if (switching && Date.now() - root.releasedAt < 250) {
      var target = root.selectedWindow
      root.cycling = false
      if (target) root.dispatch('hl.dsp.focus({ window = "' + Model.selector(target.address) + '" })')
      return
    }

    exitAnimation.stop()
    root.mounted = true
    root.opened = true
    root.enterKeySet()
    enterAnimation.restart()
    pointerGate.reset()
    settleTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // While open, Hyprland switches to the overview's own key set from keymaps/overview.lua, so SUPER
  // shortcuts held over from SUPER + TAB never move windows behind it. Without that keyboard layer the
  // key set does not exist and Hyprland ignores the switch.
  property bool inKeySet: false

  function enterKeySet() {
    if (root.inKeySet) return
    root.inKeySet = true
    root.dispatch('hl.dsp.submap("omahub-overview")')
  }

  function leaveKeySet() {
    if (!root.inKeySet) return
    root.inKeySet = false
    root.dispatch('hl.dsp.submap("reset")')
  }

  // Walking windows covers every desktop, most recent first. It starts from the window focused now,
  // so the first step lands on the one used before it.
  function cycle(step) {
    if (!root.cycling) {
      root.searching = false
      root.query = ""
      root.cycling = true
      root.cycleSteps = 0
      root.switchStartedAt = Date.now()
    }
    root.cycleSteps += step
    root.selectWindow(root.cycleSteps)
  }

  // SUPER came up. Hyprland reports it even when a quick tap ends before the overview has the keyboard.
  function release() {
    if (!root.opened) {
      root.releasedAt = Date.now()
      return
    }
    if (!root.superHeld) return
    root.superHeld = false
    // Letting go in the middle of a drag leaves the drag to finish.
    if (root.dragWindow !== null) return
    if (root.heldChoice) {
      root.goToSelected()
    } else if (root.cycling) {
      // A slow press with nothing else means looking around, so the overview stays open on the choice.
      // A quick tap, or walking with TAB, jumps.
      if (root.cycleSteps === 1 && Date.now() - root.switchStartedAt >= 350) {
        root.browseSelection()
      } else {
        root.goToSelected()
      }
    }
  }

  // Leave switching for browsing, keeping the chosen window selected on its own desktop.
  function browseSelection() {
    var chosen = root.selectedWindow
    root.cycling = false
    root.userMoved = true
    if (!chosen) return
    var desktop = root.desktops.findIndex(function(item) { return item.id === chosen.workspace })
    if (desktop >= 0) root.desktopIndex = desktop
    root.windowIndex = Math.max(0, root.shownWindows.findIndex(function(item) { return item.address === chosen.address }))
  }

  function close() {
    if (!root.mounted) return
    root.cancelDrag()
    root.leaveKeySet()
    root.opened = false
    root.cycling = false
    root.shiftHeld = false
    root.superHeld = false
    root.heldChoice = false
    root.lastMove = null
    enterAnimation.stop()
    exitAnimation.restart()
  }

  function selectWindow(index, fromPointer) {
    var count = root.shownWindows.length
    if (count === 0) return
    root.windowIndex = ((index % count) + count) % count
    // Each TAB is already a step to jump to. Anything else picked while SUPER is held is a choice.
    if (root.superHeld && (fromPointer || !root.cycling)) root.heldChoice = true
    // While walking, the strip follows the chosen window's desktop, and a window picked with the
    // pointer becomes the step to keep.
    if (root.cycling) {
      if (fromPointer) root.cycleSteps = root.windowIndex
      var chosen = root.shownWindows[root.windowIndex]
      var desktop = chosen ? root.desktops.findIndex(function(item) { return item.id === chosen.workspace }) : -1
      if (desktop >= 0) root.desktopIndex = desktop
    }
    if (!fromPointer) {
      root.userMoved = true
      pointerGate.reset()
    }
  }

  function selectDesktop(index) {
    if (root.desktops.length === 0) return
    var next = Math.max(0, Math.min(root.desktops.length - 1, index))
    root.cycling = false
    root.searching = false
    root.query = ""
    root.userMoved = true
    if (root.superHeld) root.heldChoice = true
    if (next === root.desktopIndex) return
    root.desktopIndex = next
    root.windowIndex = Math.max(0, root.shownWindows.findIndex(function(item) {
      return item.toplevel && item.toplevel.activated
    }))
    desktopFade.restart()
  }

  // Arrows follow the grid. Past the first or last window in a row, left and right change desktop.
  function moveSelection(dx, dy) {
    if (root.superHeld) root.heldChoice = true
    var next = Model.neighbor(root.rects, root.windowIndex, dx, dy)
    if (next === root.windowIndex && dx !== 0 && !root.searchActive) {
      root.selectDesktop(root.desktopIndex + dx)
    } else {
      root.selectWindow(next)
    }
  }

  function setQuery(text) {
    root.query = text
    root.windowIndex = 0
  }

  function goToSelected() {
    var window = root.selectedWindow
    if (window) {
      root.focusAfterClose('hl.dsp.focus({ window = "' + Model.selector(window.address) + '" })')
    } else if (root.selectedDesktop && !root.searchActive) {
      root.focusAfterClose('hl.dsp.focus({ workspace = "' + root.selectedDesktop.id + '" })')
    } else {
      root.close()
    }
  }

  function goToDesktop(id) {
    root.focusAfterClose('hl.dsp.focus({ workspace = "' + id + '" })')
  }

  // The overview gives the keyboard back as it closes, then focuses. Focusing first would lose to
  // Hyprland handing focus back to the window that had it when the overview's surface lets go, which
  // looks like nothing happened when the choice is on the same desktop.
  function focusAfterClose(command) {
    root.close()
    focusTimer.command = command
    focusTimer.restart()
  }

  Timer {
    id: focusTimer
    property string command: ""
    interval: 30
    onTriggered: root.dispatch(focusTimer.command)
  }

  function goToDesktopNumber(number) {
    var index = root.desktops.findIndex(function(item) { return item.id === number })
    if (index >= 0) {
      root.selectDesktop(index)
    } else {
      root.dispatch('hl.dsp.focus({ workspace = "' + number + '" })')
      root.close()
    }
  }

  function closeSelected() {
    var window = root.selectedWindow
    if (!window) return
    root.dispatchChecked('hl.dsp.window.close({ window = "' + Model.selector(window.address) + '" })',
      "Couldn't close " + (window.title || "the window"))
    settleTimer.restart()
  }

  // Moves a window to a desktop by number, or to a new one with "empty", the moment it is asked. Its card
  // leaves the layout at once and flies into the desktop's thumbnail, and u puts it back. A drop lands
  // where it already is, so the thumbnail only answers.
  function moveWindow(window, workspace, dropPoint) {
    if (!window) return
    var target = String(workspace)
    if (target === String(window.workspace)) return
    var card = root.cardFor(window.address)
    var landing = root.landingFor(target)
    var title = window.title || window.appId || "the window"

    // Moving windows while SUPER is held is organizing, so letting go afterwards stays in the overview.
    if (root.superHeld) {
      if (root.cycling) root.browseSelection()
      root.heldChoice = false
    }

    root.dispatchChecked('hl.dsp.window.move({ workspace = "' + target + '", window = "' + Model.selector(window.address) + '", follow = false })',
      "Couldn't move " + title)

    if (landing && !dropPoint && card && card.width > 0 && card.height > 0) {
      var corner = card.mapToItem(scene, 0, 0)
      root.fly(window, { x: corner.x, y: corner.y, width: card.width, height: card.height }, landing.item)
    } else if (landing) {
      root.ringAt(landing.item)
    }

    var marked = Object.assign({}, root.leaving)
    marked[window.address] = window.workspace
    root.leaving = marked
    leavingTimer.restart()
    root.windowIndex = Math.max(0, Math.min(root.windowIndex, root.shownWindows.length - 1))
    root.lastMove = { address: window.address, from: window.workspace, title: title,
      to: target === "empty" ? "a new desktop" : "desktop " + target }
    undoTimer.restart()
    settleTimer.restart()
  }

  // Cards are kept by window, not rebuilt with every change, so when a window leaves or arrives the
  // others slide to their new places and their live previews never blink.
  ListModel {
    id: cardModel
  }

  property var windowByAddress: ({})
  onShownWindowsChanged: root.syncCards()

  function syncCards() {
    var list = root.shownWindows
    var byAddress = {}
    for (var i = 0; i < list.length; i++) byAddress[list[i].address] = list[i]
    root.windowByAddress = byAddress
    for (var j = cardModel.count - 1; j >= 0; j--) {
      if (!byAddress[cardModel.get(j).address]) cardModel.remove(j)
    }
    for (var k = 0; k < list.length; k++) {
      var found = -1
      for (var m = k; m < cardModel.count; m++) {
        if (cardModel.get(m).address === list[k].address) {
          found = m
          break
        }
      }
      if (found < 0) cardModel.insert(k, { address: list[k].address })
      else if (found !== k) cardModel.move(found, k, 1)
    }
  }

  function cardFor(address) {
    for (var i = 0; i < cardRepeater.count; i++) {
      var card = cardRepeater.itemAt(i)
      if (card && card.modelData.address === address) return card
    }
    return null
  }

  // Where a moved window lands: the thumbnail of its desktop, and for a new desktop the first one not
  // opened yet, which is the one Hyprland picks, or the New tile.
  function landingFor(target) {
    for (var i = 0; i < thumbRepeater.count; i++) {
      var thumb = thumbRepeater.itemAt(i)
      if (!thumb) continue
      if (target === "empty" ? thumb.modelData.unopened : String(thumb.modelData.id) === target) {
        return { item: thumb.frame, id: thumb.modelData.id }
      }
    }
    return target === "empty" && newTile.visible ? { item: newFrame, id: "empty" } : null
  }

  // The card shrinks into the middle of the thumbnail, keeping its shape, starting fast so the move
  // answers the key at once, and the thumbnail rings as it lands. The flyer already shows the selected
  // window live, so it has a picture from its first frame.
  function fly(window, from, target) {
    var corner = target.mapToItem(scene, 0, 0)
    var fit = Math.min(target.width * 0.7 / from.width, target.height * 0.7 / from.height)
    var width = from.width * fit
    var height = from.height * fit
    flyer.toplevel = window.toplevel || null
    flyer.x = from.x
    flyer.y = from.y
    flyer.width = from.width
    flyer.height = from.height
    flyer.opacity = 1
    flyer.landing = { x: corner.x, y: corner.y, width: target.width, height: target.height }
    flyX.to = corner.x + (target.width - width) / 2
    flyY.to = corner.y + (target.height - height) / 2
    flyWidth.to = width
    flyHeight.to = height
    flight.restart()
  }

  // An accent ring that swells and fades over a thumbnail, drawn above the strip so a rebuild of the
  // thumbnails never cuts it short.
  function ringAt(target) {
    var corner = target.mapToItem(scene, 0, 0)
    root.ringOn({ x: corner.x, y: corner.y, width: target.width, height: target.height })
  }

  function ringOn(rect) {
    landingRing.x = rect.x
    landingRing.y = rect.y
    landingRing.width = rect.width
    landingRing.height = rect.height
    ringAnimation.restart()
  }

  function undoMove() {
    var move = root.lastMove
    if (!move) return
    root.lastMove = null
    var marked = Object.assign({}, root.leaving)
    delete marked[move.address]
    root.leaving = marked
    root.dispatchChecked('hl.dsp.window.move({ workspace = "' + move.from + '", window = "' + Model.selector(move.address) + '", follow = false })',
      "Couldn't move " + move.title + " back")
    settleTimer.restart()
  }

  // Windows on their way to another desktop, by address, with the desktop they left. Hyprland reports a
  // move a moment after it happens, so until then their cards stay out of the old desktop.
  property var leaving: ({})
  property var lastMove: null

  Timer {
    id: leavingTimer
    interval: 2500
    onTriggered: root.leaving = ({})
  }

  Timer {
    id: undoTimer
    interval: 6000
    onTriggered: root.lastMove = null
  }

  SequentialAnimation {
    id: flight
    ParallelAnimation {
      NumberAnimation { id: flyX; target: flyer; property: "x"; duration: 220; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyY; target: flyer; property: "y"; duration: 220; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyWidth; target: flyer; property: "width"; duration: 220; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyHeight; target: flyer; property: "height"; duration: 220; easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: 150 }
        NumberAnimation { target: flyer; property: "opacity"; to: 0; duration: 70; easing.type: Easing.InCubic }
      }
    }
    ScriptAction {
      script: {
        root.ringOn(flyer.landing)
        flyer.toplevel = null
      }
    }
  }

  ParallelAnimation {
    id: ringAnimation
    NumberAnimation { target: landingRing; property: "scale"; from: 1; to: 1.08; duration: 240; easing.type: Easing.OutCubic }
    NumberAnimation { target: landingRing; property: "opacity"; from: 1; to: 0; duration: 240; easing.type: Easing.InCubic }
  }

  // Closing and moving windows are checked, so a window Hyprland refuses to close or move says so
  // instead of nothing happening. A second action while one is being checked runs unchecked.
  function dispatchChecked(command, failure) {
    if (checkedDispatch.running) {
      root.dispatch(command)
      return
    }
    checkedDispatch.failure = failure
    checkedDispatch.reported = false
    checkedDispatch.command = ["hyprctl", "dispatch", command]
    checkedDispatch.running = true
  }

  function showNotice(text) {
    root.notice = text
    noticeTimer.restart()
  }

  property string notice: ""

  Timer {
    id: noticeTimer
    interval: 3000
    onTriggered: root.notice = ""
  }

  Process {
    id: checkedDispatch
    property string failure: ""
    property bool reported: false
    stdout: StdioCollector {
      onStreamFinished: {
        var answer = String(text || "").toLowerCase()
        if (!checkedDispatch.reported && (answer.indexOf("error") >= 0 || answer.indexOf("invalid") >= 0 || answer.indexOf("no such") >= 0)) {
          checkedDispatch.reported = true
          root.showNotice(checkedDispatch.failure)
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !checkedDispatch.reported) {
        checkedDispatch.reported = true
        root.showNotice(checkedDispatch.failure)
      }
    }
  }

  // A refused move or close leaves every card where Hyprland has it, and nothing to undo.
  onNoticeChanged: {
    if (root.notice === "") return
    root.leaving = ({})
    root.lastMove = null
  }

  function moveSelectedTo(number) {
    root.moveWindow(root.selectedWindow, String(number))
  }

  // The desktop thumbnail, or the new desktop tile, under a point in the scene.
  function desktopAt(point) {
    var local = stripRow.mapFromItem(scene, point.x, point.y)
    var target = stripRow.childAt(local.x, local.y)
    if (!target) return null
    if (target.isNewDesktop) return { id: "empty" }
    return target.modelData && target.modelData.id !== undefined ? { id: target.modelData.id } : null
  }

  function dragTo(window, point) {
    root.dragWindow = window
    root.dragPoint = point
    root.dropTarget = root.desktopAt(point)
  }

  function dropAt(point) {
    var window = root.dragWindow
    var target = root.desktopAt(point)
    root.dragWindow = null
    root.dropTarget = null
    if (!window || !target || target.id === window.workspace) return
    root.moveWindow(window, String(target.id), point)
  }

  // A drag that ends without a drop, from Esc, closing the overview, or the pointer being taken
  // away, leaves nothing behind: no floating card, and no rebuild left waiting for it.
  function cancelDrag() {
    root.dragWindow = null
    root.dropTarget = null
  }

  function newDesktop() {
    root.dispatch('hl.dsp.focus({ workspace = "empty" })')
    root.close()
  }

  ParallelAnimation {
    id: enterAnimation
    NumberAnimation { target: scene; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
    NumberAnimation { target: stripRise; property: "y"; from: -Style.space(12); to: 0; duration: 220; easing.type: Easing.OutCubic }
    NumberAnimation { target: mainArea; property: "scale"; from: 0.95; to: 1; duration: 220; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: exitAnimation
    NumberAnimation { target: scene; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
    ScriptAction { script: root.mounted = false }
  }

  NumberAnimation {
    id: desktopFade
    target: mainArea
    property: "opacity"
    from: 0.35
    to: 1
    duration: 160
    easing.type: Easing.OutCubic
  }

  // Hyprland answers refreshes a moment later, so the overview settles once they land.
  Timer {
    id: settleTimer
    interval: 140
    onTriggered: {
      // Rebuilding replaces the cards, so it waits for a drag to finish.
      if (root.dragWindow !== null) {
        settleTimer.restart()
        return
      }
      root.rebuild()
      root.settled = true
      // While switching, rebuild already keeps the step count, and the current window must not win.
      if (!root.userMoved && !root.cycling) root.selectCurrent()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event && event.name ? String(event.name) : ""
      if (name === "activewindowv2") {
        var address = String(event.data || "").replace(/^0x/, "")
        if (address !== "" && address !== "," && !root.cycling) {
          root.focusOrder = [address].concat(root.focusOrder.filter(function(item) { return item !== address })).slice(0, 64)
        }
        return
      }
      if (!root.opened) return
      // Titles are left out on purpose: agents in terminals retitle many times a second, and
      // cards read titles live, so a title never needs a rebuild.
      if (["openwindow", "closewindow", "movewindow", "movewindowv2", "createworkspace", "createworkspacev2",
           "destroyworkspace", "destroyworkspacev2"].indexOf(name) !== -1) {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        settleTimer.restart()
      }
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: scene
  }

  PanelWindow {
    id: overviewWindow
    visible: root.mounted
    screen: root.focusedScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    // The keyboard goes back the moment the overview closes, not when its fade ends, so the window
    // chosen gets focus at once.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: scene
      anchors.fill: parent
      opacity: 0

      // The desktop recedes behind a deep, theme colored veil so the previews are the only bright
      // things on screen.
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.97)
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          var shifted = (event.modifiers & Qt.ShiftModifier) !== 0
          var printable = event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127
          // The number row by its physical keys, 1 to 9 and then 0 for 10, so every keyboard layout
          // moves and jumps the same way.
          var digit = event.nativeScanCode >= 10 && event.nativeScanCode <= 19 ? ((event.nativeScanCode - 9) % 10 || 10) : -1

          if (event.key === Qt.Key_Shift) {
            root.shiftHeld = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.dragWindow !== null) {
              root.cancelDrag()
            } else if (root.searching) {
              root.setQuery("")
              root.searching = false
            } else {
              root.close()
            }
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.goToSelected()
          } else if (root.searching) {
            if (Util.editsFilter(event, root.query)) {
              root.setQuery(Util.editedFilter(event, root.query))
            } else if (event.key === Qt.Key_Backspace) {
              root.searching = false
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
              root.selectWindow(root.windowIndex + 1)
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
              root.selectWindow(root.windowIndex - 1)
            } else if (event.key === Qt.Key_Left) {
              root.moveSelection(-1, 0)
            } else if (event.key === Qt.Key_Right) {
              root.moveSelection(1, 0)
            } else if (plain && (printable || event.key === Qt.Key_Space)) {
              root.setQuery(root.query + event.text)
            } else {
              return
            }
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            var back = event.key === Qt.Key_Backtab || shifted
            if (event.modifiers & Qt.MetaModifier) {
              root.cycle(back ? -1 : 1)
            } else {
              root.selectWindow(root.windowIndex + (back ? -1 : 1))
            }
          } else if (event.key === Qt.Key_Left) {
            root.moveSelection(-1, 0)
          } else if (event.key === Qt.Key_Right) {
            root.moveSelection(1, 0)
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(0, -1)
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(0, 1)
          } else if (event.key === Qt.Key_Space) {
            root.goToSelected()
          } else if (digit > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            // SUPER may still be held from SUPER + TAB, and the overview's key set leaves numbers to it.
            if (shifted) root.moveSelectedTo(digit)
            else root.goToDesktopNumber(digit)
          } else if (!plain) {
            return
          } else if (event.text === "h") {
            root.moveSelection(-1, 0)
          } else if (event.text === "l") {
            root.moveSelection(1, 0)
          } else if (event.text === "k") {
            root.moveSelection(0, -1)
          } else if (event.text === "j") {
            root.moveSelection(0, 1)
          } else if (event.text === "H") {
            root.selectDesktop(root.desktopIndex - 1)
          } else if (event.text === "L") {
            root.selectDesktop(root.desktopIndex + 1)
          } else if (event.text === "x") {
            root.closeSelected()
          } else if (event.text === "n") {
            root.newDesktop()
          } else if (event.text === "N") {
            root.moveWindow(root.selectedWindow, "empty")
          } else if (event.text === "u" && root.lastMove !== null) {
            root.undoMove()
          } else if (event.text === "/") {
            root.searching = true
          } else if (printable) {
            root.searching = true
            root.setQuery(event.text)
          } else {
            return
          }
          event.accepted = true
        }

        // Walking windows with SUPER held ends when SUPER comes up.
        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Shift) root.shiftHeld = false
          if (!root.superHeld) return
          if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
            root.release()
          }
        }
      }

      Item {
        id: strip
        anchors.top: parent.top
        anchors.topMargin: Style.space(36)
        anchors.horizontalCenter: parent.horizontalCenter
        width: stripRow.width
        height: root.thumbHeight + root.labelSpace
        transform: Translate { id: stripRise }

        Row {
          id: stripRow
          spacing: root.stripGap

          Repeater {
            id: thumbRepeater
            model: root.desktops

            delegate: Item {
              id: thumb
              required property var modelData
              required property int index

              readonly property bool current: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === thumb.modelData.id
              readonly property bool dropping: root.dropTarget !== null && root.dropTarget.id === thumb.modelData.id
              readonly property bool selected: (!root.searchActive && thumb.index === root.desktopIndex) || thumb.dropping
              readonly property real ratio: root.thumbWidth / root.monitorWidth
              readonly property Item frame: thumbFrame

              width: root.thumbWidth
              height: root.thumbHeight + root.labelSpace

              Rectangle {
                id: thumbFrame
                width: root.thumbWidth
                height: root.thumbHeight
                radius: Style.cornerRadius
                clip: true
                scale: thumb.dropping ? 1.06 : 1

                Behavior on scale {
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }

                // A desktop not opened yet is an outline, like the New tile, until something is on it.
                color: thumb.modelData.unopened && !thumb.dropping ? "transparent" : Util.alpha(Color.menu.background, 0.92)

                // The outline is drawn over the miniatures, so their square corners stay inside it.
                Rectangle {
                  z: 1
                  anchors.fill: parent
                  radius: parent.radius
                  color: "transparent"
                  border.width: thumb.selected ? Style.space(3) : Math.max(1, Style.space(1))
                  border.color: thumb.selected ? Color.accent
                    : (thumb.current ? Util.alpha(Color.accent, 0.55) : Util.alpha(Color.menu.text, thumb.modelData.unopened ? 0.22 : 0.18))

                  Behavior on border.color {
                    ColorAnimation { duration: 120 }
                  }
                }

                Repeater {
                  model: thumb.modelData.windows

                  delegate: Item {
                    id: miniature
                    required property var modelData
                    x: (miniature.modelData.x - root.monitorX) * thumb.ratio
                    y: (miniature.modelData.y - root.monitorY) * thumb.ratio
                    width: miniature.modelData.width * thumb.ratio
                    height: miniature.modelData.height * thumb.ratio

                    Rectangle {
                      anchors.fill: parent
                      radius: Math.max(1, Style.space(2))
                      color: Util.alpha(Color.menu.text, 0.1)
                    }

                    ScreencopyView {
                      anchors.fill: parent
                      captureSource: root.mounted && miniature.modelData.toplevel ? miniature.modelData.toplevel.wayland : null
                      live: false
                    }
                  }
                }

                // The number key that reaches this desktop, and with Shift moves a window to it.
                Rectangle {
                  visible: thumb.modelData.id <= 10
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.margins: Style.space(6)
                  width: Math.max(height, badgeText.implicitWidth + Style.spacing.sm * 2)
                  height: badgeText.implicitHeight + Style.spacing.xxs * 2
                  radius: Style.cornerRadius
                  color: root.numbersLit ? Color.accent : Util.alpha(Color.menu.background, 0.85)
                  border.width: Style.normalBorderWidth
                  border.color: root.numbersLit ? Color.accent : Util.alpha(Color.menu.text, 0.28)
                  scale: root.numbersLit ? 1.12 : 1

                  Behavior on color {
                    ColorAnimation { duration: 120 }
                  }
                  Behavior on scale {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                  }

                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: thumb.modelData.id === 10 ? "0" : String(thumb.modelData.id)
                    color: root.numbersLit ? Color.menu.background : Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }

              Text {
                anchors.top: thumbFrame.bottom
                anchors.topMargin: Style.space(6)
                anchors.horizontalCenter: thumbFrame.horizontalCenter
                textFormat: Text.PlainText
                // The number is on the thumbnail, so the label says what is on the desktop.
                text: {
                  var count = thumb.modelData.windows.length
                  if (thumb.dropping) return "Move here"
                  if (thumb.modelData.name !== String(thumb.modelData.id)) return thumb.modelData.name
                  return count === 0 ? "Empty" : count === 1 ? "1 window" : count + " windows"
                }
                width: Math.min(implicitWidth, root.thumbWidth)
                elide: Text.ElideRight
                color: thumb.selected ? Color.accent : Color.menu.text
                opacity: thumb.selected || thumb.current ? 1 : 0.6
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                font.bold: thumb.selected
              }

              // A click goes to the desktop at once, like clicking a window. h and l still browse
              // desktops without leaving.
              // The desktop's name under its thumbnail is part of what can be clicked.
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.goToDesktop(thumb.modelData.id)
              }
            }
          }

          // Desktops not opened yet already stand for new ones, so the New tile shows once they are all in use.
          Item {
            id: newTile
            visible: !root.hasUnopened
            readonly property bool isNewDesktop: true
            readonly property bool dropping: root.dropTarget !== null && root.dropTarget.id === "empty"
            width: root.thumbWidth
            height: root.thumbHeight + root.labelSpace

            Rectangle {
              id: newFrame
              width: root.thumbWidth
              height: root.thumbHeight
              radius: Style.cornerRadius
              scale: parent.dropping ? 1.06 : 1
              color: newMouse.containsMouse || parent.dropping ? Util.alpha(Color.menu.background, 0.92) : "transparent"
              border.width: parent.dropping ? Style.space(3) : Math.max(1, Style.space(1))
              border.color: parent.dropping ? Color.accent : Util.alpha(Color.menu.text, newMouse.containsMouse ? 0.4 : 0.22)

              Behavior on scale {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
              }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "+"
                color: Color.menu.text
                opacity: 0.6
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.heading * 1.4
              }
            }

            Text {
              anchors.top: newFrame.bottom
              anchors.topMargin: Style.space(6)
              anchors.horizontalCenter: newFrame.horizontalCenter
              textFormat: Text.PlainText
              text: parent.dropping ? "Move here" : "New"
              color: Color.menu.text
              opacity: 0.6
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: newMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.newDesktop()
            }
          }
        }
      }

      // A moved window's card on its way into the desktop's thumbnail. Between flights it quietly
      // follows the selected window, so the next move flies with a picture from its first frame.
      Item {
        id: flyer
        property var toplevel: null
        property var landing: ({ x: 0, y: 0, width: 0, height: 0 })
        z: 3
        visible: flight.running

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Color.menu.background
        }

        ScreencopyView {
          anchors.fill: parent
          captureSource: !root.mounted ? null
            : flight.running ? (flyer.toplevel ? flyer.toplevel.wayland : null)
            : (root.selectedWindow && root.selectedWindow.toplevel ? root.selectedWindow.toplevel.wayland : null)
          live: root.mounted
        }

        // The selected card's outline travels with it, so a dark window still reads as a card in flight.
        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: "transparent"
          border.width: Style.space(2)
          border.color: Color.accent
        }
      }

      Rectangle {
        id: landingRing
        z: 3
        visible: ringAnimation.running
        radius: Style.cornerRadius
        color: "transparent"
        border.width: Style.space(3)
        border.color: Color.accent
      }

      // After a move, what happened and how to take it back.
      Rectangle {
        id: undoToast
        z: 2
        visible: opacity > 0
        opacity: root.lastMove !== null && root.notice === "" ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(72)
        width: undoRow.implicitWidth + Style.spacing.lg * 2
        height: undoRow.implicitHeight + Style.spacing.sm * 2
        radius: height / 2
        color: Util.alpha(Color.menu.background, 0.94)
        border.width: Math.max(1, Style.space(1))
        border.color: undoMouse.containsMouse ? Color.accent : Util.alpha(Color.menu.text, 0.28)

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        property string text: root.lastMove ? "Moved " + root.lastMove.title + " to " + root.lastMove.to : ""

        Row {
          id: undoRow
          anchors.centerIn: parent
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Style.space(420))
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: undoToast.text
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, undoKey.implicitWidth + Style.spacing.md * 2)
            height: undoKey.implicitHeight + Style.spacing.xxs * 2
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Style.normalBorderWidth
            border.color: Util.alpha(Color.menu.text, 0.28)

            Text {
              id: undoKey
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "u"
              color: Color.menu.text
              opacity: 0.8
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Undo"
            color: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        MouseArea {
          id: undoMouse
          anchors.fill: parent
          enabled: root.lastMove !== null
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // Hovering keeps the offer open while the pointer is on its way to it.
          onContainsMouseChanged: if (containsMouse) undoTimer.restart()
          onClicked: root.undoMove()
        }
      }

      // A short message when closing or moving a window did not work.
      Rectangle {
        z: 2
        visible: opacity > 0
        opacity: root.notice !== "" ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(72)
        width: Math.min(noticeText.implicitWidth + Style.spacing.lg * 2, parent.width * 0.6)
        height: noticeText.implicitHeight + Style.spacing.sm * 2
        radius: height / 2
        color: Util.alpha(Color.menu.background, 0.94)
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Color.urgent, 0.6)

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
          id: noticeText
          anchors.centerIn: parent
          width: parent.width - Style.spacing.lg * 2
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: root.notice
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }

      BorderSurface {
        id: searchField
        visible: root.searching
        anchors.top: strip.bottom
        anchors.topMargin: Style.space(10)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(420)
        height: Style.space(40)
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.controlSpec("focus", Color.menu.text, Color.accent)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰍉"
            color: Color.menu.text
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.query !== "" ? root.query : "Search windows"
            // A long search keeps its end in view, where the typing is.
            width: Math.min(implicitWidth, Style.space(520))
            elide: Text.ElideLeft
            color: Color.menu.text
            opacity: root.query !== "" ? 1 : 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1, Style.space(2))
            height: Style.font.body + Style.spacing.xs
            color: Color.accent

            SequentialAnimation on opacity {
              running: root.searching
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 530 }
              NumberAnimation { to: 0; duration: 0 }
              PauseAnimation { duration: 530 }
            }
          }
        }
      }

      Item {
        id: mainArea
        anchors.top: strip.bottom
        anchors.topMargin: Style.space(72)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(32)
        anchors.left: parent.left
        anchors.leftMargin: Style.space(96)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(96)

        Repeater {
          id: cardRepeater
          model: cardModel

          delegate: Item {
            id: card
            required property string address
            required property int index
            readonly property var modelData: root.windowByAddress[card.address]
              || ({ address: card.address, title: "", appId: "", workspace: 0, toplevel: null })

            readonly property var rect: root.rects[card.index] || ({ x: 0, y: 0, width: 0, height: 0 })
            readonly property bool selected: card.index === root.windowIndex

            x: card.rect.x
            y: card.rect.y - (card.selected ? Style.space(4) : 0)
            width: card.rect.width
            height: card.rect.height

            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Rectangle {
              anchors.fill: parent
              anchors.margins: -Style.space(5)
              radius: Style.cornerRadius + Style.space(4)
              color: "transparent"
              border.width: Style.space(3)
              border.color: Color.accent
              opacity: card.selected ? 1 : 0

              Behavior on opacity {
                NumberAnimation { duration: 120 }
              }
            }

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: Color.menu.background
            }

            // Until the first frame arrives the card shows the app's icon, never a black box.
            Image {
              anchors.centerIn: parent
              visible: !preview.hasContent
              width: Math.min(Style.space(64), parent.width / 3)
              height: width
              sourceSize.width: Style.space(128)
              sourceSize.height: Style.space(128)
              source: root.iconFor(card.modelData.appId)
              fillMode: Image.PreserveAspectFit
              smooth: true
            }

            ScreencopyView {
              id: preview
              anchors.fill: parent
              // Previews stay through the closing fade, so the cards never flash empty on the way out.
              captureSource: root.mounted && card.modelData.toplevel ? card.modelData.toplevel.wayland : null
              live: root.mounted
            }

            BorderSurface {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(10)
              width: Math.min(titleRow.implicitWidth + Style.spacing.md * 2, parent.width - Style.space(20))
              height: titleRow.implicitHeight + Style.spacing.xs * 2
              radius: Style.cornerRadius
              color: Util.alpha(Color.menu.background, 0.92)
              borderSpec: Border.controlSpec(card.selected ? "focus" : "normal", Color.menu.text, Color.accent)

              Row {
                id: titleRow
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - Style.spacing.md * 2)
                spacing: Style.spacing.sm

                Text {
                  visible: root.searchActive || root.cycling
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(card.modelData.workspace)
                  color: Color.accent
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.font.body
                  height: width
                  sourceSize.width: Style.space(32)
                  sourceSize.height: Style.space(32)
                  source: root.iconFor(card.modelData.appId)
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, card.width - Style.space(90))
                  textFormat: Text.PlainText
                  text: {
                    var title = card.modelData.toplevel && card.modelData.toplevel.title ? card.modelData.toplevel.title : card.modelData.title
                    return title !== "" ? title : (card.modelData.appId || "Untitled window")
                  }
                  color: Color.menu.text
                  elide: Text.ElideRight
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // A click goes to the window, a middle click closes it, and a drag carries it to a desktop
            // thumbnail.
            MouseArea {
              id: cardMouse
              property point pressPoint: Qt.point(0, 0)
              property bool dragging: false
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              cursorShape: cardMouse.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              onPressed: function(mouse) {
                cardMouse.pressPoint = Qt.point(mouse.x, mouse.y)
                cardMouse.dragging = false
              }
              onCanceled: {
                cardMouse.dragging = false
                root.cancelDrag()
              }
              onPositionChanged: function(mouse) {
                if (!cardMouse.pressed || !(cardMouse.pressedButtons & Qt.LeftButton)) {
                  // Cards zoom in under a resting pointer as the overview opens, so only a pointer
                  // that really moves after that picks a window.
                  if (enterAnimation.running) return
                  if (pointerGate.moved(card, mouse)) root.selectWindow(card.index, true)
                  return
                }
                if (!cardMouse.dragging && Math.hypot(mouse.x - cardMouse.pressPoint.x, mouse.y - cardMouse.pressPoint.y) > Style.space(8)) {
                  cardMouse.dragging = true
                  root.windowIndex = card.index
                }
                if (cardMouse.dragging) root.dragTo(card.modelData, cardMouse.mapToItem(scene, mouse.x, mouse.y))
              }
              onReleased: function(mouse) {
                if (mouse.button === Qt.MiddleButton) {
                  if (cardMouse.containsMouse) {
                    root.windowIndex = card.index
                    root.closeSelected()
                  }
                } else if (cardMouse.dragging) {
                  cardMouse.dragging = false
                  root.dropAt(cardMouse.mapToItem(scene, mouse.x, mouse.y))
                } else if (cardMouse.containsMouse) {
                  root.windowIndex = card.index
                  root.goToSelected()
                }
              }
            }
          }
        }

        Column {
          visible: root.shownWindows.length === 0 && (root.settled || root.searchActive) && !root.cycling
          anchors.centerIn: parent
          spacing: Style.spacing.md

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: root.searchActive ? "No windows match “" + root.query + "”" : "Empty desktop"
            width: Math.min(implicitWidth, root.monitorWidth * 0.6)
            elide: Text.ElideMiddle
            color: Color.menu.text
            opacity: 0.8
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !root.searchActive
            textFormat: Text.PlainText
            text: "Press Enter to go there"
            color: Color.menu.text
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      // The window being dragged, as a small card under the pointer.
      BorderSurface {
        visible: root.dragWindow !== null
        x: root.dragPoint.x - width / 2
        y: root.dragPoint.y - height / 2
        width: dragRow.implicitWidth + Style.spacing.md * 2
        height: dragRow.implicitHeight + Style.spacing.sm * 2
        radius: Style.cornerRadius
        color: Color.menu.background
        borderSpec: Border.controlSpec("focus", Color.menu.text, Color.accent)

        Row {
          id: dragRow
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          Image {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.body
            height: width
            sourceSize.width: Style.space(32)
            sourceSize.height: Style.space(32)
            source: root.dragWindow ? root.iconFor(root.dragWindow.appId) : ""
            fillMode: Image.PreserveAspectFit
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Style.space(260))
            textFormat: Text.PlainText
            text: root.dragWindow ? (root.dragWindow.title || root.dragWindow.appId) : ""
            color: Color.menu.text
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Row {
        id: footer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(28)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.spacing.xxl

        Repeater {
          // The keys for what is on screen now. Holding Shift shows the keys that move windows.
          model: root.cycling
            ? [{ keys: ["tab"], label: "Next window" }, { keys: ["shift", "tab"], label: "Previous" },
               { keys: ["super"], label: "Let go to jump" }, { keys: ["click"], label: "Go" }, { keys: ["esc"], label: "Cancel" }]
            : root.dragWindow !== null
            ? [{ keys: [], label: "Drop on a desktop to move the window there" }, { keys: ["esc"], label: "Cancel" }]
            : root.searching
            ? [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["enter"], label: "Go" }, { keys: ["esc"], label: "Clear" }]
            : root.shiftShown
            ? [{ keys: ["shift", "1-9"], label: "Move the window to that desktop" }, { keys: ["shift", "n"], label: "Move it to a new desktop" },
               { keys: ["shift", "h", "l"], label: "Previous or next desktop" }]
            : [{ keys: ["h", "j", "k", "l"], label: "Move" }, { keys: ["1-9"], label: "Desktop" }, { keys: ["shift"], label: "Hold to move windows" },
               { keys: ["enter"], label: "Go" }, { keys: ["x"], label: "Close" }, { keys: ["n"], label: "New desktop" },
               { keys: ["/"], label: "Search" }, { keys: ["esc"], label: "Back" }]

          delegate: Row {
            id: hint
            required property var modelData
            spacing: Style.spacing.sm

            Repeater {
              model: hint.modelData.keys

              delegate: Rectangle {
                required property string modelData
                width: Math.max(height, keyText.implicitWidth + Style.spacing.md * 2)
                height: keyText.implicitHeight + Style.spacing.xxs * 2
                radius: Style.cornerRadius
                color: Util.alpha(Color.menu.background, 0.8)
                border.width: Style.normalBorderWidth
                border.color: Util.alpha(Color.menu.text, 0.28)

                Text {
                  id: keyText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: parent.modelData
                  color: Color.menu.text
                  opacity: 0.8
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.xs
              textFormat: Text.PlainText
              text: hint.modelData.label
              color: Color.menu.text
              opacity: 0.7
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
