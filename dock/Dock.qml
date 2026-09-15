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
  readonly property bool showDesktops: root.config.desktops === true
  readonly property bool showAgents: root.config.agents === true
  // What an agent's card shows on hover, from the dock's settings: any of project, state, step, and message.
  readonly property var cardFields: Array.isArray(root.config.card) ? root.config.card : ["project", "state", "step", "message"]

  onShowDesktopsChanged: {
    if (!root.showDesktops) return
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
  }
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
    if (root.dragDesktop >= 0) return -1
    var count = root.keptIds.length
    var keptEnd = count > 0 ? root.layout.centers[count - 1] + root.cellWidth / 2 : 0
    if (!item.pinned && root.dragAlong > keptEnd + root.dividerWidth) return -1
    var slot = Model.dropSlot(root.layout.centers, root.dragAlong, count)
    return item.pinned && slot > root.dragIndex ? slot - 1 : slot
  }

  readonly property var items: Model.items(root.pins,
    DesktopEntries.applications.values || [], ToplevelManager.toplevels.values || [], root.showOpen)
  readonly property var layout: Model.layout(root.items, root.cellWidth, root.dividerWidth)

  // Desktops at the end of the dock, when that setting is on: each one with a window, and the one in front.
  readonly property var desktopTiles: root.showDesktops && root.focusedScreen
    ? Model.desktops(Hyprland.workspaces.values || [], Hyprland.toplevels.values || [], root.focusedScreen.name,
      Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)
    : []
  readonly property int desktopsGap: root.items.length > 0 || root.agentSessions.length > 0 ? root.dividerWidth : 0
  readonly property int desktopsLength: root.desktopTiles.length > 0 ? root.desktopsGap + root.desktopTiles.length * root.cellWidth : 0
  // The desktop tile an icon is dragged over, where letting go opens its app, or -1.
  readonly property int dragDesktop: root.dragItem !== null && root.dragItem.launchable && !root.dragRemoving
    ? Model.desktopAt(root.dragAlong, root.layout.width + root.agentsLength, root.desktopsGap, root.cellWidth, root.desktopTiles.length) : -1
  // The tile under the pointer, measured from where the tiles are drawn, since magnified apps move them.
  readonly property int hoveredDesktop: root.dragIndex < 0 && root.pointerAlong >= 0
    ? Model.desktopAt(root.pointerAlong - (root.vertical ? desktopRow.y : desktopRow.x), 0, root.desktopsGap, root.cellWidth,
      root.desktopTiles.length) : -1
  // Past the apps, icons stop magnifying, so the tiles hold still under the pointer.
  readonly property bool pointerPastApps: (root.desktopTiles.length > 0 || root.agentSessions.length > 0)
    && root.pointerX > root.layout.width + (root.agentsLength > 0 ? root.agentsGap : root.desktopsGap) / 2

  // Agents between the apps and the desktops, when that setting is on: one tile for each agent session.
  readonly property var agentSessions: root.showAgents
    ? Desktops.sessions(Model.windowList(Hyprland.toplevels.values || []), root.terminalInfo) : []
  // An agent waiting for your answer brings a hidden dock out until you answer.
  readonly property bool agentCalling: root.agentSessions.some(function(session) { return session.activity.agentWaiting })
  // The window with focus, as Hyprland's address, so a turn that ends in front of you counts as seen.
  property string focusedFromEvent: ""
  readonly property string focusedAddress: Hyprland.activeToplevel && Hyprland.activeToplevel.address
    ? "0x" + String(Hyprland.activeToplevel.address).replace(/^0x/, "") : root.focusedFromEvent
  // Each session's state from the last read, and the finished agents you have not looked at yet.
  property var agentStates: ({})
  property var unseen: ({})
  // A turn that ends out of sight brings a hidden dock out for a moment, so its pet's hop is seen.
  property bool peeking: false
  onAgentSessionsChanged: root.followAgents()
  onFocusedAddressChanged: root.followAgents()
  readonly property int agentsGap: root.agentSessions.length > 0 && root.items.length > 0 ? root.dividerWidth : 0
  readonly property int agentsLength: root.agentSessions.length > 0 ? root.agentsGap + root.agentSessions.length * root.cellWidth : 0
  // The agent tile under the pointer, measured from where the tiles are drawn.
  // The time agent cards measure from, in epoch seconds, read again whenever a card may open.
  property real now: Date.now() / 1000
  onHoveredAgentChanged: root.now = Date.now() / 1000
  onKeyCursorChanged: root.now = Date.now() / 1000
  readonly property int hoveredAgent: root.dragIndex < 0 && root.pointerAlong >= 0
    ? Model.desktopAt(root.pointerAlong - (root.vertical ? agentRow.y : agentRow.x), 0, root.agentsGap, root.cellWidth,
      root.agentSessions.length) : -1

  // Names people gave desktops, shared with the overview.
  readonly property string desktopsFile: Quickshell.env("HOME") + "/.local/state/omahub/desktops.json"
  property var desktopNames: ({})
  // What runs in each window's terminals, so a desktop of terminals is named by its project or tool, not
  // "Foot", and every agent shows what it is doing. Read a moment after windows change, as the pointer
  // reaches the dock, and every two seconds while it shows, since agents change without any window changing.
  readonly property string contextScript: Qt.resolvedUrl("../desktops/context.sh").toString().replace("file://", "")
  property var terminalInfo: ({})
  // Pets hold still when animations are turned off in Hyprland.
  property bool stillPets: false
  onDesktopTilesChanged: contextDelay.restart()
  onPointerInsideChanged: if (root.pointerInside) contextDelay.restart()
  // Each window's context by Hyprland address: its project, and what its agents are doing.
  readonly property var windowContexts: {
    var info = root.terminalInfo
    var map = {}
    Model.windowList(Hyprland.toplevels.values || []).forEach(function(window) {
      map[window.address] = Desktops.windowContext(window, info[window.address] || null)
    })
    return map
  }
  readonly property var appIndex: Desktops.appIndex(DesktopEntries.applications.values || [])

  // The size chosen in settings, made smaller when the apps and desktops would not fit along the edge.
  readonly property int chosenIconSize: Style.space(root.size === "small" ? 40 : (root.size === "large" ? 62 : 50))
  readonly property int iconSize: Model.fittedIconSize(root.chosenIconSize, Style.space(12), root.alongRoom,
    root.items.length + root.agentSessions.length + root.desktopTiles.length + 1,
    root.items.filter(function(item) { return item.divider }).length * root.dividerWidth + root.dividerWidth
      + root.agentsGap + root.desktopsGap + root.dockPadding * 2,
    Style.space(5) / root.chosenIconSize, root.maxScale)
  // The bar's and other panels' room at each side of the screen, from Hyprland: left, top, right, bottom.
  readonly property var reserved: {
    var data = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.lastIpcObject : null
    var list = data ? Model.listValue(data.reserved) : []
    return [0, 1, 2, 3].map(function(side) { return Number(list[side]) || 0 })
  }
  // Room along the dock's edge. The dock sits centered, so the larger reserved end counts at both ends.
  readonly property real alongRoom: {
    var screen = root.focusedScreen
    if (!screen) return 1e9
    var end = root.vertical ? Math.max(root.reserved[1], root.reserved[3]) : Math.max(root.reserved[0], root.reserved[2])
    return (root.vertical ? screen.height : screen.width) - 2 * end - 2 * root.edgeGap
  }
  // The same share of the icon at every size, so a dock shrunk to fit keeps its proportions.
  readonly property int cellPadding: Math.floor(Style.space(5) * root.iconSize / root.chosenIconSize)
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
  readonly property int baseWidth: root.layout.width + root.dockPadding * 2 + root.overviewButtonWidth + root.agentsLength
    + root.desktopsLength
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
  // How wide a label beside a side dock can be: the dock's window past the shelf and a magnified icon.
  // Above a dock at the bottom the window spans the screen, so labels there are not held back.
  readonly property real labelRoom: root.vertical
    ? Math.max(Style.space(80), dockWindow.width - root.edgeGap - root.baseHeight - root.reachAway - root.labelGap - Style.space(8))
    : 1e9
  // How far a click still counts from an icon: past its magnified size away from the edge, and all the
  // way to the screen edge, so the dock is easy to hit.
  readonly property real reachAway: root.iconSize * (root.maxScale - 1)
  readonly property real reachEdge: root.dockPadding + root.dotSpace + root.edgeGap
  // Above the icons, clicks only count while they are magnified, so the empty space above a resting dock
  // opens nothing.
  readonly property real clickAway: root.pointerOnDock ? root.reachAway : 0

  // The pointer's position along the dock in the unscaled layout, or -1 when it is away.
  property real pointerX: -1
  // The pointer along the dock window, where the icons really are, magnified or not. -1 when outside.
  property real pointerAlong: -1
  // True once the pointer is over the shelf, until it leaves the shelf and its magnified icons. Hover,
  // names, and magnification follow it; the wider band around the dock only keeps a hidden dock shown.
  property bool pointerOnDock: false
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
    && (!root.autohide || !root.covered || root.pointerInside || root.lingering || root.menuOpen || root.agentCalling || root.peeking
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
    list.push({ label: "Show desktops", action: "desktops", checked: root.showDesktops })
    list.push({ label: "Show agents", action: "agents", checked: root.showAgents })
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
    // A long name shortens in the middle instead of running past the dock's window.
    property real maxWidth: root.labelRoom
    width: Math.min(labelText.implicitWidth + Style.spacing.lg * 2, maxWidth)
    height: labelText.implicitHeight + Style.spacing.xs * 2
    radius: height / 2
    color: Util.alpha(Color.menu.background, 0.92)
    border.width: Math.max(1, Style.space(1))
    border.color: root.hairline

    Text {
      id: labelText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, parent.width - Style.spacing.lg * 2)
      elide: Text.ElideMiddle
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

  // What an agent is up to, beside its tile while the pointer or the keyboard is on it: the project and
  // branch, how long it has worked or since it finished, the step it is on and its model, and the first line
  // it said when its turn ended. The dock's settings choose which of these it shows.
  component AgentCard: BorderSurface {
    id: card
    property var session: ({})
    property string agentState: ""
    property bool open: false
    readonly property bool showProject: root.cardFields.indexOf("project") >= 0
    readonly property bool showState: root.cardFields.indexOf("state") >= 0
    readonly property bool showStep: root.cardFields.indexOf("step") >= 0
    readonly property string tool: card.agentState === "working" && card.session.activity ? String(card.session.activity.agentTool || "") : ""
    readonly property string message: card.agentState !== "working" && root.cardFields.indexOf("message") >= 0 ? String(card.session.message || "") : ""

    // As wide as its lines, up to a limit, and at the limit when a message wraps.
    readonly property real widest: Math.max(cardTitle.implicitWidth + (cardBranch.visible ? cardBranch.implicitWidth + Style.spacing.md : 0),
      cardState.visible ? cardState.implicitWidth : 0, cardModel.visible ? cardModel.implicitWidth : 0)
    width: card.message !== "" ? Style.space(260) : Math.min(Style.space(260), Math.ceil(card.widest) + Style.spacing.lg * 2)
    height: cardColumn.implicitHeight + Style.spacing.lg * 2
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
    opacity: card.open ? 1 : 0
    visible: card.opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: card.open ? 160 : 120; easing.type: card.open ? Easing.OutCubic : Easing.InCubic }
    }

    // It rises out of the dock, and sinks back toward it.
    transform: Translate {
      x: card.open || !root.vertical ? 0 : (root.edge === "left" ? -Style.space(4) : Style.space(4))
      y: card.open || root.vertical ? 0 : Style.space(4)

      Behavior on x {
        NumberAnimation { duration: card.open ? 160 : 120; easing.type: card.open ? Easing.OutCubic : Easing.InCubic }
      }
      Behavior on y {
        NumberAnimation { duration: card.open ? 160 : 120; easing.type: card.open ? Easing.OutCubic : Easing.InCubic }
      }
    }

    Column {
      id: cardColumn
      x: Style.spacing.lg
      y: Style.spacing.lg
      width: parent.width - Style.spacing.lg * 2
      spacing: Style.spacing.xs

      Item {
        width: parent.width
        height: cardTitle.implicitHeight

        Text {
          id: cardTitle
          width: Math.min(implicitWidth, parent.width - (cardBranch.visible ? Math.min(cardBranch.implicitWidth, parent.width / 2) + Style.spacing.md : 0))
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: card.showProject && card.session.project ? card.session.project : Desktops.agentLabel(card.session.agent)
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          id: cardBranch
          visible: card.showProject && String(card.session.branch || "") !== ""
          anchors.left: cardTitle.right
          anchors.leftMargin: Style.spacing.md
          anchors.baseline: cardTitle.baseline
          width: Math.min(implicitWidth, parent.width - cardTitle.width - Style.spacing.md)
          elide: Text.ElideMiddle
          textFormat: Text.PlainText
          text: String(card.session.branch || "")
          color: Color.menu.text
          opacity: 0.55
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: cardState
        visible: card.showState
        spacing: Style.spacing.sm

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(6)
          height: width
          radius: width / 2
          color: card.agentState === "working" ? Color.accent
            : (card.agentState === "waiting" ? Color.urgent : Util.alpha(Color.menu.text, card.agentState === "idle" ? 0.4 : 0.8))
        }

        Text {
          textFormat: Text.PlainText
          text: Desktops.stateLine(card.session, root.now) + (card.showStep && card.tool !== "" ? " · " + card.tool : "")
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        id: cardModel
        visible: card.showStep
        width: parent.width
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: Desktops.agentLabel(card.session.agent) + (card.session.model ? " · " + card.session.model : "")
        color: Color.menu.text
        opacity: 0.55
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: card.message !== ""
        width: parent.width
        topPadding: Style.spacing.xs
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: card.message
        color: Color.menu.text
        opacity: 0.8
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
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
    // A dock that keeps its own room is laid out beside the bar, so its window starts past the bar's band.
    var originX = root.edge === "right" ? screenX + screenWidth - dockWindow.width
      : screenX + (root.edge === "bottom" && dockWindow.width < screenWidth ? root.reserved[0] : 0)
    var originY = root.edge === "bottom" ? screenY + screenHeight - dockWindow.height
      : screenY + (dockWindow.height < screenHeight ? root.reserved[1] : 0)
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
      if (cell) apps.push(Object.assign({ id: cell.modelData.id, name: cell.modelData.name, windows: cell.modelData.windows.length,
        agent: cell.agentState }, place(cell)))
    }
    var agents = []
    for (var g = 0; g < agentRepeater.count; g++) {
      var agentTile = agentRepeater.itemAt(g)
      if (agentTile) agents.push(Object.assign({ id: agentTile.modelData.id, family: agentTile.modelData.family,
        project: agentTile.modelData.project, agent: agentTile.agentState, unseen: root.unseen[agentTile.modelData.id] === true },
        place(agentTile)))
    }
    var desktops = []
    for (var d = 0; d < desktopRepeater.count; d++) {
      var tile = desktopRepeater.itemAt(d)
      if (tile) desktops.push(Object.assign({ id: tile.modelData.id, title: tile.title, active: tile.modelData.active, agent: tile.agentState,
        windows: tile.modelData.windows.length }, place(tile)))
    }
    var edgePoint = root.edge === "left" ? { x: screenX, y: screenY + screenHeight / 2 }
      : (root.edge === "right" ? { x: screenX + screenWidth - 1, y: screenY + screenHeight / 2 }
        : { x: screenX + screenWidth / 2, y: screenY + screenHeight - 1 })
    return JSON.stringify({
      shown: root.shown, position: root.edge, keyboard: root.keyboardActive, cursor: root.keyCursor,
      menu: root.menuOpen, apps: apps, agents: agents, desktops: desktops, peeking: root.peeking, overview: place(overviewButton), pressed: root.iconPressed,
      screen: { x: screenX, y: screenY, width: screenWidth, height: screenHeight },
      usable: { x: screenX + root.reserved[0], y: screenY + root.reserved[1],
        width: screenWidth - root.reserved[0] - root.reserved[2], height: screenHeight - root.reserved[1] - root.reserved[3] },
      iconSize: root.iconSize, chosenIconSize: root.chosenIconSize,
      hoveredDesktop: root.hoveredDesktop >= 0 ? root.desktopTiles[root.hoveredDesktop].id : null,
      notice: root.notice !== "" ? Object.assign({ text: root.notice }, place(noticeLabel)) : null,
      window: { x: originX, y: originY, width: Math.round(dockWindow.width), height: Math.round(dockWindow.height) },
      shelf: place(dockBackground),
      menuCard: root.menuOpen ? place(menuCard) : null,
      busy: dockCommand.running || root.commandQueue.length > 0,
      menuItem: root.menuOpen && root.menuItem ? root.menuItem.id : null,
      menuEntry: root.menuOpen && root.menuIndex >= 0 && root.menuEntries[root.menuIndex] ? root.menuEntries[root.menuIndex].label || null : null,
      drag: root.dragIndex >= 0 ? { index: root.dragIndex, along: Math.round(root.dragAlong), away: Math.round(root.dragAway),
        removing: root.dragRemoving, slot: root.dragSlot,
        desktop: root.dragDesktop >= 0 ? root.desktopTiles[root.dragDesktop].id : null } : null,
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

  // From a click, the pointer stays on the dock.
  function goToDesktop(id) {
    Quickshell.execDetached(["hyprctl", "eval", Desktops.quietFocusLua({ workspace: String(id) })])
  }

  // Goes to an agent's window, even inside an editor with many. From a click, the pointer stays on the dock.
  function goToAgent(session, fromPointer) {
    if (!session || !session.address) return
    if (fromPointer === true) {
      Quickshell.execDetached(["hyprctl", "eval", Desktops.quietFocusLua({ window: "address:" + session.address })])
    } else {
      root.dispatch('hl.dsp.focus({ window = "address:' + session.address + '" })')
    }
  }

  // Goes to a desktop and opens an app there. Hyprland places the app's window on that desktop even if it
  // takes a while to start.
  function openOnDesktop(item, id) {
    if (!item || !item.launchable) return
    if (!/^[A-Za-z0-9._-]+$/.test(String(item.id))) {
      root.goToDesktop(id)
      root.launch(item)
      return
    }
    var open = "hl.exec_cmd('uwsm-app -- gtk-launch " + item.id + ".desktop', { workspace = '" + Number(id) + "' })"
    Quickshell.execDetached(["hyprctl", "eval", Desktops.quietFocusLua({ workspace: String(id) }) + "\n" + open])
  }

  function entryFor(appId) {
    if (!appId) return null
    return Desktops.entryFor(appId, root.appIndex) || DesktopEntries.heuristicLookup(String(appId))
  }

  // A desktop as the overview reads it: its title is the name someone chose, the project its editor has
  // open, or its most recent app, empty for an empty desktop, and its activity is what its agents are doing.
  function desktopSummary(tile) {
    var windows = tile.windows.map(function(window) {
      var entry = root.entryFor(window.appId)
      return { address: window.address, appId: window.appId, appName: entry && entry.name ? String(entry.name) : window.appId, focus: window.focus }
    })
    return Desktops.summary({ id: tile.id, windows: windows }, root.windowContexts, root.desktopNames[String(tile.id)] || "")
  }

  // What the agents in an app's windows are doing, or null when none of its windows were read.
  function itemActivity(item) {
    var windows = []
    ;(item.windows || []).forEach(function(toplevel) {
      var address = root.addressFor(toplevel)
      if (address !== "" && root.windowContexts[address]) windows.push({ address: address, appId: item.id })
    })
    return windows.length > 0 ? Desktops.summary({ windows: windows }, root.windowContexts, "").activity : null
  }

  // A name with what its agent is doing, for the label beside an icon or a desktop.
  function withAgent(name, activity) {
    var said = Desktops.activityLabel(activity)
    return said === "" ? name : name + " · " + said
  }

  function refreshContexts() {
    if (contextReader.running) {
      contextDelay.restart()
      return
    }
    // The windows of one process share its terminals, so each process is read once and what it runs is
    // given to every window it owns.
    var owner = {}
    var sharers = {}
    var pairs = []
    Model.windowList(Hyprland.toplevels.values || []).forEach(function(window) {
      if (window.pid <= 0) return
      if (owner[window.pid] === undefined) {
        owner[window.pid] = window.address
        sharers[window.address] = []
        pairs.push(window.address + "=" + window.pid)
      }
      sharers[owner[window.pid]].push(window.address)
    })
    if (pairs.length === 0) {
      root.terminalInfo = ({})
      return
    }
    contextReader.sharers = sharers
    contextReader.command = [root.contextScript].concat(pairs)
    contextReader.running = true
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
    } else if (entry.action === "agents") {
      root.runOmahub(["set", "dock/agents", root.showAgents ? "off" : "on"], "Couldn't change agents in the dock")
    } else if (entry.action === "desktops") {
      root.runOmahub(["set", "dock/desktops", root.showDesktops ? "off" : "on"], "Couldn't change desktops in the dock")
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

  function followAgents() {
    var next = Model.followAgents(root.agentStates, root.unseen, root.agentSessions, root.focusedAddress,
      function(session) { return Desktops.activityState(session.activity) })
    root.agentStates = next.states
    root.unseen = next.unseen
    if (next.finished.length > 0) {
      root.peeking = true
      peekTimer.restart()
    }
  }

  // SUPER + D. The cursor starts on the agent that needs you, waiting first and then one that finished out
  // of sight, or else on the app in front, or the first app.
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
    var calling = root.agentSessions.findIndex(function(session) { return session.activity.agentWaiting })
    if (calling < 0) calling = root.agentSessions.findIndex(function(session) { return root.unseen[session.id] === true })
    root.keyCursor = calling >= 0 ? root.items.length + calling : (active >= 0 ? active : (root.items.length > 0 ? 0 : -1))
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
    var desktop = root.dragDesktop >= 0 ? root.desktopTiles[root.dragDesktop] : null
    var cell = iconRepeater.itemAt(root.dragIndex)
    root.dragIndex = -1
    if (!item) return
    if (desktop) {
      if (cell) cell.startLaunch()
      root.openOnDesktop(item, desktop.id)
      return
    }
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

  FileView {
    path: root.desktopsFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.desktopNames = parsed && parsed.names ? parsed.names : ({})
      } catch (e) {}
    }
    onFileChanged: reload()
    onLoadFailed: root.desktopNames = ({})
  }

  Timer {
    id: contextDelay
    interval: 500
    onTriggered: root.refreshContexts()
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.shown
    onTriggered: root.refreshContexts()
  }

  Process {
    running: true
    command: ["hyprctl", "getoption", "animations:enabled", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var option = JSON.parse(text)
          root.stillPets = option.bool === false || option.int === 0
        } catch (e) {}
      }
    }
  }

  Process {
    id: contextReader
    property var sharers: ({})
    stdout: StdioCollector {
      onStreamFinished: {
        var list
        try { list = JSON.parse(text) } catch (e) { return }
        if (!Array.isArray(list)) return
        var next = {}
        list.forEach(function(item) {
          ;(contextReader.sharers[item.address] || [item.address]).forEach(function(address) { next[address] = item })
        })
        root.terminalInfo = next
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
      // Desktop tiles show the app used last, so a focus change matters to them too.
      if (root.showDesktops && name === "activewindowv2") coverDelay.restart()
      if (name === "activewindowv2") {
        var address = String(event.data || "").replace(/^0x/, "")
        root.focusedFromEvent = address !== "" && address !== "," ? "0x" + address : ""
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
    onTriggered: {
      root.checkCover()
      if (root.showDesktops) Hyprland.refreshToplevels()
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.enabled && root.autohide
    onTriggered: root.checkCover()
  }

  Timer {
    id: peekTimer
    interval: 2600
    onTriggered: root.peeking = false
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
            root.keyCursor = Math.min(root.items.length + root.agentSessions.length + root.desktopTiles.length - 1, root.keyCursor + 1)
          } else if (enter) {
            if (root.keyCursor < 0) {
              Quickshell.execDetached([root.omahub, "open", "overview"])
            } else if (root.keyCursor >= root.items.length + root.agentSessions.length) {
              var tile = root.desktopTiles[root.keyCursor - root.items.length - root.agentSessions.length]
              if (tile) root.dispatch('hl.dsp.focus({ workspace = "' + tile.id + '" })')
            } else if (root.keyCursor >= root.items.length) {
              root.goToAgent(root.agentSessions[root.keyCursor - root.items.length], false)
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
        root.pointerOnDock = false
        root.pointerX = -1
        root.pointerAlong = -1
        root.lingering = true
        lingerTimer.restart()
      }
      onPositionChanged: function(mouse) {
        root.pointerInside = true
        var along = root.vertical ? dockHit.y + mouse.y : dockHit.x + mouse.x
        var across = root.edge === "left" ? mouse.x : (root.edge === "right" ? dockHit.width - mouse.x : dockHit.height - mouse.y)
        var start = root.vertical ? dockBackground.y : dockBackground.x
        var end = start + dockBackground.length
        var shelfDepth = root.edgeGap + root.baseHeight
        var reach = root.pointerOnDock ? Math.max(shelfDepth, shelfDepth - root.dockPadding + root.reachAway) : shelfDepth
        root.pointerOnDock = Model.onDock(across, along, start, end, reach)
        if (!root.pointerOnDock) {
          root.pointerX = -1
          root.pointerAlong = -1
          return
        }
        var origin = (dockWindow.alongLength - root.baseWidth) / 2 + root.dockPadding + root.overviewButtonWidth
        root.pointerX = along - origin
        root.pointerAlong = along
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
        readonly property real length: (root.items.length > 0 ? (root.vertical ? iconRow.height : iconRow.width)
            : (root.desktopTiles.length > 0 ? 0 : -root.dividerWidth))
          + root.agentsLength + root.desktopsLength + root.dockPadding * 2 + root.overviewButtonWidth
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
          visible: root.items.length > 0 || root.desktopTiles.length > 0
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
          : dockBackground.x + dockBackground.width - root.dockPadding - root.desktopsLength - root.agentsLength - width
        y: root.vertical ? dockBackground.y + dockBackground.height - root.dockPadding - root.desktopsLength - root.agentsLength - height
          : dockBackground.y + root.dockPadding

        Repeater {
          id: iconRepeater
          model: root.items

          delegate: Item {
            id: cell
            required property var modelData
            required property int index

            readonly property real distance: root.pointerX < 0 ? 1e9 : root.pointerX - root.layout.centers[cell.index]
            readonly property real scaleFactor: root.magnify && root.pointerX >= 0 && root.dragIndex < 0 && !root.pointerPastApps
              ? Model.magnification(cell.distance, root.magnifyRange, root.maxScale) : 1
            readonly property bool dragged: root.dragIndex === cell.index
            readonly property var agentActivity: root.itemActivity(cell.modelData)
            readonly property string agentState: Desktops.activityState(cell.agentActivity)
            // While another icon is dragged, this one steps aside to open its landing place, or to close
            // the gap it left.
            readonly property real shift: {
              var from = root.dragIndex
              if (from < 0 || cell.dragged || root.dragDesktop >= 0) return 0
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
              text: cell.dragged ? "Remove" : root.withAgent(cell.modelData.name, cell.agentActivity)
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
              x: root.edge === "left" ? -root.reachEdge : (root.edge === "right" ? -root.clickAway : 0)
              y: root.edge === "bottom" ? -root.clickAway : 0
              width: root.vertical ? root.iconSize + root.clickAway + root.reachEdge : parent.width
              height: root.vertical ? parent.height : root.iconSize + root.clickAway + root.reachEdge
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

      // Agents between the apps and the desktops: a tile for each session with its pet, doing what the agent
      // does. Click one to go to its window.
      Item {
        id: agentRow
        visible: root.agentSessions.length > 0
        x: root.vertical ? iconRow.x : dockBackground.x + dockBackground.width - root.dockPadding - root.desktopsLength - root.agentsLength
        y: root.vertical ? dockBackground.y + dockBackground.height - root.dockPadding - root.desktopsLength - root.agentsLength
          : dockBackground.y + root.dockPadding
        width: root.vertical ? root.iconSize : root.agentsLength
        height: root.vertical ? root.agentsLength : root.iconSize

        Rectangle {
          visible: root.agentsGap > 0
          x: root.vertical ? Math.round(root.iconSize * 0.15) : root.agentsGap / 2
          y: root.vertical ? root.agentsGap / 2 : Math.round(root.iconSize * 0.15)
          width: root.vertical ? Math.round(root.iconSize * 0.7) : Math.max(1, Style.space(1))
          height: root.vertical ? Math.max(1, Style.space(1)) : Math.round(root.iconSize * 0.7)
          color: root.hairline
        }

        Repeater {
          id: agentRepeater
          model: root.agentSessions

          delegate: Item {
            id: agentTile
            required property var modelData
            required property int index

            readonly property bool hovered: root.hoveredAgent === agentTile.index
            readonly property bool keyed: root.keyboardActive && !root.menuOpen && root.keyCursor === root.items.length + agentTile.index
            readonly property string agentState: Desktops.activityState(agentTile.modelData.activity)
            readonly property real offset: root.agentsGap + agentTile.index * root.cellWidth

            x: root.vertical ? 0 : agentTile.offset
            y: root.vertical ? agentTile.offset : 0
            width: root.vertical ? root.iconSize : root.cellWidth
            height: root.vertical ? root.cellWidth : root.iconSize

            Rectangle {
              id: agentBox
              width: root.iconSize
              height: width
              x: root.vertical ? 0 : root.cellPadding
              y: root.vertical ? root.cellPadding : 0
              radius: Math.round(width * 0.23)
              color: agentTile.hovered || agentTile.keyed ? Util.alpha(Color.accent, 0.22) : Util.alpha(Color.menu.text, 0.07)
              border.width: Math.max(1, Style.space(1))
              border.color: root.hairline

              Behavior on color {
                ColorAnimation { duration: 120 }
              }

              AgentPet {
                family: agentTile.modelData.family
                choices: root.config
                mood: agentTile.agentState
                still: root.stillPets
                pixelSize: Math.max(1, Math.floor(root.iconSize * 0.8 / 16))
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
              }
            }

            // A turn that ended out of sight keeps a dot under its tile until you look at the agent.
            Rectangle {
              visible: root.unseen[agentTile.modelData.id] === true
              width: Style.space(4)
              height: width
              radius: width / 2
              x: root.edge === "left" ? -root.dotSpace + (root.dotSpace - width) / 2
                : (root.edge === "right" ? root.iconSize + (root.dotSpace - width) / 2 : agentBox.x + (agentBox.width - width) / 2)
              y: root.vertical ? agentBox.y + (agentBox.height - height) / 2 : root.iconSize + (root.dotSpace - height) / 2
              color: Color.accent
            }

            FocusRing {
              visible: agentTile.keyed
              x: agentBox.x - Style.space(4)
              y: agentBox.y - Style.space(4)
              width: agentBox.width + Style.space(8)
              height: agentBox.height + Style.space(8)
            }

            AgentCard {
              session: agentTile.modelData
              agentState: agentTile.agentState
              open: (agentTile.hovered || agentTile.keyed) && root.dragIndex < 0 && !root.menuOpen && !root.pickerOpen
              z: 10
              x: root.edge === "left" ? agentBox.x + agentBox.width + root.labelGap
                : (root.edge === "right" ? agentBox.x - width - root.labelGap : Math.round(agentBox.x + (agentBox.width - width) / 2))
              y: root.vertical ? Math.round(agentBox.y + (agentBox.height - height) / 2) : agentBox.y - height - root.labelGap
            }

            MouseArea {
              x: root.edge === "left" ? -root.reachEdge : (root.edge === "right" ? -root.clickAway : 0)
              y: root.edge === "bottom" ? -root.clickAway : 0
              width: root.vertical ? root.iconSize + root.clickAway + root.reachEdge : parent.width
              height: root.vertical ? parent.height : root.iconSize + root.clickAway + root.reachEdge
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToAgent(agentTile.modelData, true)
            }
          }
        }
      }

      // Desktops at the end of the dock: click one to go there, or drop an app on one to open it there.
      Item {
        id: desktopRow
        visible: root.desktopTiles.length > 0
        x: root.vertical ? iconRow.x : dockBackground.x + dockBackground.width - root.dockPadding - root.desktopsLength
        y: root.vertical ? dockBackground.y + dockBackground.height - root.dockPadding - root.desktopsLength : dockBackground.y + root.dockPadding
        width: root.vertical ? root.iconSize : root.desktopsLength
        height: root.vertical ? root.desktopsLength : root.iconSize

        Rectangle {
          visible: root.desktopsGap > 0
          x: root.vertical ? Math.round(root.iconSize * 0.15) : root.desktopsGap / 2
          y: root.vertical ? root.desktopsGap / 2 : Math.round(root.iconSize * 0.15)
          width: root.vertical ? Math.round(root.iconSize * 0.7) : Math.max(1, Style.space(1))
          height: root.vertical ? Math.max(1, Style.space(1)) : Math.round(root.iconSize * 0.7)
          color: root.hairline
        }

        Repeater {
          id: desktopRepeater
          model: root.desktopTiles

          delegate: Item {
            id: desk
            required property var modelData
            required property int index

            readonly property bool hovered: root.hoveredDesktop === desk.index
            readonly property bool dropping: root.dragDesktop === desk.index
            readonly property bool keyed: root.keyboardActive && !root.menuOpen && root.keyCursor === root.items.length + root.agentSessions.length + desk.index
            readonly property bool lit: desk.hovered || desk.dropping || desk.keyed
            readonly property var summary: root.desktopSummary(desk.modelData)
            readonly property string title: desk.summary.title
            readonly property string agentState: Desktops.activityState(desk.summary.activity)
            readonly property var entry: desk.modelData.windows.length > 0 ? root.entryFor(desk.modelData.windows[0].appId) : null
            readonly property real offset: root.desktopsGap + desk.index * root.cellWidth

            x: root.vertical ? 0 : desk.offset
            y: root.vertical ? desk.offset : 0
            width: root.vertical ? root.iconSize : root.cellWidth
            height: root.vertical ? root.cellWidth : root.iconSize

            // The desktop's number, and the app used last on it. The desktop in front wears the accent.
            Rectangle {
              id: deskTile
              width: root.iconSize
              height: width
              x: root.vertical ? 0 : root.cellPadding
              y: root.vertical ? root.cellPadding : 0
              radius: Math.round(width * 0.23)
              scale: desk.dropping ? 1.14 : 1
              color: desk.lit ? Util.alpha(Color.accent, 0.22) : Util.alpha(Color.menu.text, desk.modelData.active ? 0.14 : 0.07)
              border.width: Math.max(1, Style.space(1))
              border.color: desk.modelData.active || desk.dropping ? Color.accent : root.hairline

              Behavior on color {
                ColorAnimation { duration: 120 }
              }
              Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }

              Image {
                id: deskIcon
                visible: desk.entry !== null && status === Image.Ready
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(parent.height * 0.12)
                width: Math.round(parent.width * 0.5)
                height: width
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                source: desk.entry ? root.iconSource(desk.entry.icon) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
              }

              Text {
                readonly property bool small: deskIcon.visible
                x: small ? Math.round(parent.width * 0.12) : (parent.width - width) / 2
                y: small ? Math.round(parent.height * 0.06) : (parent.height - height) / 2
                textFormat: Text.PlainText
                text: String(desk.modelData.id)
                color: desk.modelData.active || desk.lit ? Color.accent : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: small ? Math.max(6, Math.min(Style.font.caption, Math.round(parent.height * 0.26)))
                  : Math.round(parent.height * 0.42)
                font.bold: true
              }
            }

            FocusRing {
              visible: desk.keyed
              x: deskTile.x - Style.space(4)
              y: deskTile.y - Style.space(4)
              width: deskTile.width + Style.space(8)
              height: deskTile.height + Style.space(8)
            }

            DockLabel {
              visible: (desk.dropping || ((desk.hovered || desk.keyed) && root.dragIndex < 0)) && !root.menuOpen && !root.pickerOpen
              text: desk.dropping ? "Open on desktop " + desk.modelData.id
                : root.withAgent(desk.title || "Desktop " + desk.modelData.id, desk.summary.activity)
              x: root.edge === "left" ? deskTile.x + deskTile.width + root.labelGap
                : (root.edge === "right" ? deskTile.x - width - root.labelGap : deskTile.x + (deskTile.width - width) / 2)
              y: root.vertical ? deskTile.y + (deskTile.height - height) / 2 : deskTile.y - height - root.labelGap
            }

            MouseArea {
              x: root.edge === "left" ? -root.reachEdge : (root.edge === "right" ? -root.clickAway : 0)
              y: root.edge === "bottom" ? -root.clickAway : 0
              width: root.vertical ? root.iconSize + root.clickAway + root.reachEdge : parent.width
              height: root.vertical ? parent.height : root.iconSize + root.clickAway + root.reachEdge
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToDesktop(desk.modelData.id)
            }
          }
        }
      }

      DockLabel {
        id: noticeLabel
        visible: root.notice !== ""
        text: root.notice
        maxWidth: root.vertical ? root.labelRoom : (root.focusedScreen ? root.focusedScreen.width : 1920) * 0.6
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
