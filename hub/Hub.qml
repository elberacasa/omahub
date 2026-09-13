import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "HubModel.js" as Model

Item {
  id: root

  property bool opened: false
  property bool mounted: false
  property var catalog: []
  property var states: ({})
  property var options: ({})
  property var errors: ({})
  property bool loading: true
  property string loadError: ""
  property bool statesStale: false
  property bool statesReady: false
  property string promptId: ""
  property string promptText: ""
  property string pendingSetting: ""
  readonly property string promptAction: {
    var setting = root.settingById(root.promptId)
    return setting && setting.action ? setting.action : "Run"
  }
  property var pendingStates: ({})
  property var pendingOptions: ({})
  property string view: "hub"
  property string sectionId: "keyboard"
  property int cursor: 0
  property string query: ""
  property bool searching: false
  property string busyId: ""
  property var queue: []

  readonly property string omahub: Qt.resolvedUrl("../bin/omahub").toString().replace("file://", "")
  readonly property string welcomeMarker: Quickshell.env("HOME") + "/.local/state/omahub/welcomed"
  readonly property string firstRunScript: "if [[ -e $1 ]]; then\n  exit 1\nfi\nmkdir -p \"$(dirname \"$1\")\"\ntouch \"$1\""
  readonly property var sections: Model.sections(root.catalog)
  readonly property var rows: root.view === "welcome"
    ? Model.welcomeRows(root.catalog, root.states)
    : Model.rows(root.catalog, root.sectionId, root.query)
  readonly property var summary: Model.keyboardSummary(root.states)
  readonly property var pending: Model.pendingRecommended(root.states)
  readonly property bool showKeyboardCard: root.summary !== null && root.query === ""
    && (root.view === "welcome" || root.sectionId === "keyboard")

  readonly property int cardWidth: Math.min(Style.space(root.view === "welcome" ? 760 : 980), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  readonly property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int sidebarWidth: Style.space(190)

  // Reads every setting's state, one line per setting. Answers are applied together when the read
  // finishes, so rows, the keyboard card, and its progress never appear half filled.
  // Every setting is read at once, each into its own file, and printed together when all are done.
  readonly property string stateScript: "bin=$1\nshift\n"
    + "dir=$(mktemp -d)\n"
    + "trap 'rm -rf \"$dir\"' EXIT\n"
    + "i=0\n"
    + "for entry in \"$@\"; do\n"
    + "  (\n"
    + "    id=${entry%|*}\n"
    + "    kind=${entry##*|}\n"
    + "    state=$(\"$bin\" get \"$id\" 2>/dev/null) || state=null\n"
    + "    options=null\n"
    + "    if [[ $kind == \"choice\" || $kind == \"folder\" ]]; then\n"
    + "      options=$(\"$bin\" options \"$id\" 2>/dev/null) || options=null\n"
    + "    fi\n"
    + "    printf '%s\\t%s\\t%s\\n' \"$id\" \"${state:-null}\" \"${options:-null}\" >\"$dir/$i\"\n"
    + "  ) &\n"
    + "  i=$((i + 1))\n"
    + "done\n"
    + "wait\n"
    + "cat \"$dir\"/* 2>/dev/null"

  // The plugin stays loaded, so read settings once at startup and the first SUPER + A opens on real state.
  // The very first load also shows the welcome, once.
  Component.onCompleted: {
    root.refresh()
    firstRun.running = true
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload.section) root.sectionId = payload.section
    root.view = payload.view === "welcome" ? "welcome" : "hub"

    root.query = ""
    root.searching = false
    root.cursor = 0
    root.cancelPrompt()
    root.pendingSetting = payload.setting ? String(payload.setting) : ""
    exitAnimation.stop()
    root.mounted = true
    root.opened = true
    enterAnimation.restart()
    pointerGate.reset()
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    Qt.callLater(root.applyPendingSetting)
  }

  function close() {
    if (!root.mounted) return
    root.opened = false
    enterAnimation.stop()
    exitAnimation.restart()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function refresh() {
    root.loadError = ""
    if (root.catalog.length === 0) root.loading = true
    if (!catalogProcess.running) catalogProcess.running = true
  }

  function loadCatalog(text) {
    var list = Model.parseCatalog(text)
    root.loading = false
    if (list === null) {
      root.loadError = "Omahub could not read its settings."
      return
    }
    root.catalog = list
    if (list.length > 0 && !Model.hasSection(list, root.sectionId)) root.sectionId = Model.sections(list)[0].id
    root.readStates()
    Qt.callLater(root.applyPendingSetting)
  }

  function readStates() {
    if (stateProcess.running) {
      root.statesStale = true
      return
    }
    var entries = root.catalog.map(function(setting) { return setting.id + "|" + setting.kind })
    root.pendingStates = {}
    root.pendingOptions = {}
    stateProcess.command = ["bash", "-c", root.stateScript, "omahub-states", root.omahub].concat(entries)
    stateProcess.running = true
  }

  function applyStateLine(line) {
    var parsed = Model.parseStateLine(line)
    if (!parsed) return
    root.pendingStates[parsed.id] = parsed.state
    if (parsed.options) root.pendingOptions[parsed.id] = parsed.options
  }

  function commitStates() {
    // A change finished while this read ran, so its answers may already be out of date.
    if (root.statesStale) {
      root.statesStale = false
      Qt.callLater(root.readStates)
      return
    }
    root.states = Object.assign({}, root.states, root.pendingStates)
    root.options = Object.assign({}, root.options, root.pendingOptions)
    root.statesReady = true
  }

  function setValue(id, value) {
    if (root.busyId !== "") {
      root.queue = root.queue.concat([[id, value]])
      return
    }
    var nextErrors = Object.assign({}, root.errors)
    delete nextErrors[id]
    root.errors = nextErrors
    root.busyId = id
    setProcess.command = [root.omahub, "set", id, value]
    setProcess.running = true
  }

  function finishSet(exitCode) {
    var id = root.busyId
    if (id === "") return

    if (exitCode === 0) {
      var state = Model.parseJson(setOutput.text)
      if (state) {
        var nextStates = Object.assign({}, root.states)
        nextStates[id] = state
        root.states = nextStates
      }
      var finished = root.settingById(id)
      if (finished && finished.closes) root.close()
    } else {
      var nextErrors = Object.assign({}, root.errors)
      nextErrors[id] = Model.errorText(setErrors.text)
      root.errors = nextErrors
    }

    root.busyId = ""
    if (root.queue.length > 0) {
      var next = root.queue[0]
      root.queue = root.queue.slice(1)
      root.setValue(next[0], next[1])
    } else {
      root.readStates()
    }
  }

  function activate(index) {
    var setting = root.rows[index]
    if (!setting) return
    root.cursor = index
    if (setting.kind === "toggle") {
      var on = root.states[setting.id] && root.states[setting.id].value === true
      root.setValue(setting.id, on ? "off" : "on")
    } else if (setting.kind === "choice") {
      var choices = root.options[setting.id] || []
      if (choices.length === 0) return
      var current = choices.findIndex(function(option) { return option.current })
      root.setValue(setting.id, choices[(current + 1) % choices.length].value)
    } else if (setting.kind === "folder") {
      root.chooseFolder(setting)
    } else if (setting.kind === "action") {
      if (root.promptId === setting.id) root.submitPrompt()
      else if (setting.prompt) root.beginPrompt(index)
      else root.setValue(setting.id, "run")
    }
  }

  // An action with a prompt asks for its value inline, the way search does: type, Enter to run,
  // Esc to cancel.
  function beginPrompt(index) {
    var setting = root.rows[index]
    if (!setting) return
    root.searching = false
    root.cursor = index
    root.promptId = setting.id
    root.promptText = ""
  }

  function cancelPrompt() {
    root.promptId = ""
    root.promptText = ""
  }

  function submitPrompt() {
    var text = root.promptText.trim()
    if (text === "") return
    var id = root.promptId
    root.cancelPrompt()
    root.setValue(id, text)
  }

  // More choices live in Omarchy's own menu, which installs what is missing.
  function openMore(setting) {
    if (!setting.more) return
    root.close()
    Quickshell.execDetached(["omarchy-menu", "summon", setting.more])
  }

  function settingById(id) {
    for (var i = 0; i < root.catalog.length; i++) {
      if (root.catalog[i].id === id) return root.catalog[i]
    }
    return null
  }

  // `omahub open <setting>` lands on that row, and starts its prompt when it has one.
  function applyPendingSetting() {
    if (!root.pendingSetting || root.catalog.length === 0) return
    var id = root.pendingSetting
    root.pendingSetting = ""
    for (var i = 0; i < root.rows.length; i++) {
      if (root.rows[i].id !== id) continue
      if (root.rows[i].prompt) root.beginPrompt(i)
      else root.cursor = i
      revealTimer.restart()
      return
    }
  }

  // The folder chooser is a normal window, so the hub steps aside while it is open and
  // comes back where it was.
  function chooseFolder(setting) {
    if (folderProcess.running) return
    folderProcess.settingId = setting.id
    folderProcess.returnCursor = root.cursor
    folderProcess.command = ["omarchy-file-select", "--directory", "--title", setting.title]
    root.close()
    folderProcess.running = true
  }

  function finishChooseFolder(exitCode, path) {
    var cursor = folderProcess.returnCursor
    root.open(JSON.stringify({ section: root.sectionId }))
    root.cursor = cursor
    if (exitCode === 0 && path !== "") root.setValue(folderProcess.settingId, path)
  }

  function applyRecommended() {
    root.pending.forEach(function(id) { root.setValue(id, "on") })
  }

  function moveCursor(delta) {
    if (root.rows.length === 0) return
    pointerGate.reset()
    root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + delta))
    settingsList.positionViewAtIndex(root.cursor, ListView.Contain)
  }

  function selectSection(id) {
    root.sectionId = id
    root.cursor = 0
    root.query = ""
    root.searching = false
    sectionFade.restart()
  }

  function moveSection(delta) {
    if (root.view !== "hub") return
    var list = root.sections
    if (list.length === 0) return
    var index = list.findIndex(function(section) { return section.id === root.sectionId })
    root.selectSection(list[(index + delta + list.length) % list.length].id)
  }

  function setQuery(text) {
    root.query = text
    root.cursor = 0
  }

  // Leaves the welcome for the full hub, searching with whatever was typed.
  function showAll(text) {
    root.view = "hub"
    root.searching = true
    root.setQuery(text)
    sectionFade.restart()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (root.promptId !== "") return
    root.cursor = index
  }

  Process {
    id: catalogProcess
    command: [root.omahub, "settings", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.loadCatalog(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.catalog.length === 0) {
        root.loading = false
        root.loadError = "Omahub could not read its settings."
      }
    }
  }

  Process {
    id: stateProcess
    stdout: SplitParser {
      onRead: function(line) { root.applyStateLine(line) }
    }
    onExited: root.commitStates()
  }

  Process {
    id: firstRun
    command: ["bash", "-c", root.firstRunScript, "omahub-first-run", root.welcomeMarker]
    onExited: function(exitCode) {
      if (exitCode === 0) welcomeTimer.start()
    }
  }

  // Lets the desktop settle and settings finish reading, so the welcome opens complete.
  Timer {
    id: welcomeTimer
    interval: 1200
    onTriggered: {
      if (root.loadError !== "" || root.opened) return
      if (!root.statesReady) {
        welcomeTimer.restart()
        return
      }
      root.open(JSON.stringify({ view: "welcome" }))
    }
  }

  // A row reached by `omahub open <setting>` scrolls into view once the list has laid it out.
  Timer {
    id: revealTimer
    interval: 80
    onTriggered: settingsList.positionViewAtIndex(root.cursor, ListView.Contain)
  }

  Process {
    id: folderProcess
    property string settingId: ""
    property int returnCursor: 0
    stdout: StdioCollector { id: folderOutput }
    onExited: function(exitCode) {
      Qt.callLater(function() { root.finishChooseFolder(exitCode, folderOutput.text.trim()) })
    }
  }

  Process {
    id: setProcess
    stdout: StdioCollector { id: setOutput }
    stderr: StdioCollector { id: setErrors }
    onExited: function(exitCode) {
      Qt.callLater(function() { root.finishSet(exitCode) })
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  ParallelAnimation {
    id: enterAnimation
    NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
    NumberAnimation { target: rise; property: "y"; from: Style.space(10); to: 0; duration: 240; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: exitAnimation
    ParallelAnimation {
      NumberAnimation { target: card; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InCubic }
      NumberAnimation { target: rise; property: "y"; to: Style.space(6); duration: 120; easing.type: Easing.InCubic }
    }
    ScriptAction { script: root.mounted = false }
  }

  PanelWindow {
    id: panel
    visible: root.mounted
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: card.opacity
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      // Only while shown, so opening in a different view never resizes during the fade in.
      Behavior on width {
        enabled: root.opened && card.opacity === 1
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
      }
      height: root.cardHeight
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      opacity: 0

      transform: Translate { id: rise }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          var printable = event.text.length === 1 && event.text.charCodeAt(0) > 32 && event.text.charCodeAt(0) !== 127

          if (event.key === Qt.Key_Escape) {
            if (root.promptId !== "") {
              root.cancelPrompt()
            } else if (root.query !== "" || root.searching) {
              root.setQuery("")
              root.searching = false
            } else {
              root.close()
            }
          } else if (root.promptId !== "") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.submitPrompt()
            } else if (Util.editsFilter(event, root.promptText)) {
              root.promptText = Util.editedFilter(event, root.promptText)
            } else if (event.key === Qt.Key_Backspace) {
              root.promptText = root.promptText.slice(0, -1)
            } else if (plain && (printable || event.key === Qt.Key_Space)) {
              root.promptText = root.promptText + event.text
            }
          } else if (root.searching) {
            if (Util.editsFilter(event, root.query)) {
              root.setQuery(Util.editedFilter(event, root.query))
            } else if (event.key === Qt.Key_Backspace) {
              root.searching = false
            } else if (event.key === Qt.Key_Down) {
              root.moveCursor(1)
            } else if (event.key === Qt.Key_Up) {
              root.moveCursor(-1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activate(root.cursor)
            } else if (event.key === Qt.Key_Tab) {
              root.searching = false
            } else if (plain && (printable || event.key === Qt.Key_Space)) {
              root.setQuery(root.query + event.text)
            } else {
              return
            }
          } else if (event.key === Qt.Key_Down || event.text === "j") {
            root.moveCursor(1)
          } else if (event.key === Qt.Key_Up || event.text === "k") {
            root.moveCursor(-1)
          } else if (event.key === Qt.Key_Left || event.text === "h" || event.key === Qt.Key_Backtab) {
            root.moveSection(-1)
          } else if (event.key === Qt.Key_Right || event.text === "l" || event.key === Qt.Key_Tab) {
            root.moveSection(1)
          } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.cursor)
          } else if (event.text === "/") {
            if (root.view === "welcome") root.showAll("")
            else root.searching = true
          } else if (plain && printable) {
            if (root.view === "welcome") {
              root.showAll(event.text)
            } else {
              root.searching = true
              root.setQuery(root.query + event.text)
            }
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        Item {
          id: header
          width: parent.width
          height: root.headerHeight

          Row {
            id: brand
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Keycap {
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.view === "welcome" ? "Welcome to Omahub" : "Omahub"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - brand.width - Style.spacing.panelGap)
            visible: root.view === "welcome"
            textFormat: Text.PlainText
            text: "Pick the Mac touches you want. Change them anytime."
            color: Color.menu.text
            opacity: 0.6
            elide: Text.ElideRight
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }

          BorderSurface {
            id: searchBox
            visible: root.view === "hub"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(Style.space(420), parent.width - brand.width - Style.spacing.panelGap)
            height: root.headerHeight
            radius: Style.cornerRadius
            color: Style.controlFill(root.searching, searchMouse.containsMouse, Color.menu.text, Color.accent)
            borderSpec: Border.controlSpec(root.searching ? "focus" : (searchMouse.containsMouse ? "hover-cursor" : "normal"), Color.menu.text, Color.accent)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              spacing: Style.spacing.md

              Text {
                id: searchGlyph
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰍉"
                color: Color.menu.text
                opacity: 0.6
                font.family: Style.font.family
                font.pixelSize: Style.font.icon
              }

              Text {
                id: searchText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - searchGlyph.width - slashHint.width - caret.width - parent.spacing * 3)
                textFormat: Text.PlainText
                text: root.query !== "" ? root.query : (root.searching ? "" : "Search settings")
                color: Color.menu.text
                opacity: root.query !== "" ? 1 : 0.5
                elide: Text.ElideLeft
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
              }

              Rectangle {
                id: caret
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Style.space(2))
                height: Style.font.body + Style.spacing.xs
                color: Color.accent
                visible: root.searching

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

            Rectangle {
              id: slashHint
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.searching
              width: slashLabel.implicitWidth + Style.spacing.md * 2
              height: slashLabel.implicitHeight + Style.spacing.xxs * 2
              radius: Style.cornerRadius
              color: "transparent"
              border.width: Style.normalBorderWidth
              border.color: Util.alpha(Color.menu.text, 0.28)

              Text {
                id: slashLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "/"
                color: Color.menu.text
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: searchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              onClicked: root.searching = true
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - footer.height - parent.spacing * 2

          Column {
            id: sidebar
            visible: root.view === "hub"
            width: root.view === "hub" ? root.sidebarWidth : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Style.spacing.xs

            Repeater {
              model: root.sections

              delegate: Button {
                required property var modelData
                width: sidebar.width
                leftAlign: true
                iconText: modelData.icon
                text: modelData.label
                selected: root.query === "" && root.sectionId === modelData.id
                foreground: Color.menu.text
                fontFamily: Style.font.menuFamily
                onClicked: root.selectSection(modelData.id)
              }
            }
          }

          Rectangle {
            id: divider
            visible: root.view === "hub"
            anchors.left: sidebar.right
            anchors.leftMargin: root.view === "hub" ? Style.spacing.lg : 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.view === "hub" ? Style.normalBorderWidth : 0
            color: Util.alpha(Color.menu.border, 0.28)
          }

          Item {
            id: mainPane
            anchors.left: divider.right
            anchors.leftMargin: root.view === "hub" ? Style.spacing.lg : 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            NumberAnimation {
              id: sectionFade
              target: mainPane
              property: "opacity"
              from: 0.35
              to: 1
              duration: 160
              easing.type: Easing.OutCubic
            }

            Column {
              visible: root.loadError === "" && !root.statesReady
              width: parent.width
              spacing: Style.spacing.sm

              Repeater {
                model: 4

                delegate: Rectangle {
                  width: parent.width
                  height: Style.space(58)
                  radius: Style.cornerRadius
                  color: Util.alpha(Color.menu.text, 0.06)

                  SequentialAnimation on opacity {
                    running: root.mounted && !root.statesReady
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                  }
                }
              }
            }

            Column {
              visible: root.loadError !== ""
              anchors.centerIn: parent
              spacing: Style.spacing.lg

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.loadError
                color: Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
              }

              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Try again"
                bordered: true
                foreground: Color.menu.text
                onClicked: root.refresh()
              }
            }

            ListView {
              id: settingsList
              anchors.fill: parent
              visible: root.loadError === "" && root.statesReady
              clip: true
              spacing: Style.spacing.xs
              boundsBehavior: Flickable.StopAtBounds
              model: root.rows

              header: Item {
                width: settingsList.width
                height: root.showKeyboardCard ? keyboardCard.height + Style.spacing.lg : 0
                visible: root.showKeyboardCard

                BorderSurface {
                  id: keyboardCard
                  width: parent.width
                  height: keyboardContent.implicitHeight + Style.spacing.panelPadding * 2
                  radius: Style.cornerRadius
                  color: Util.alpha(Color.menu.text, 0.04)
                  borderSpec: Border.controlSpec("normal", Color.menu.text, Color.accent)

                  Row {
                    id: keyboardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.panelPadding
                    anchors.rightMargin: Style.spacing.panelPadding
                    spacing: Style.spacing.panelPadding

                    Keycap {
                      anchors.verticalCenter: parent.verticalCenter
                      cell: Math.max(1, Style.space(3))
                    }

                    Column {
                      width: parent.width - Style.space(33) - recommendButton.width - parent.spacing * 2
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.spacing.xs

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.summary ? root.summary.name : ""
                        color: Color.menu.text
                        elide: Text.ElideRight
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.title
                        font.bold: true
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.summary ? root.summary.detail : ""
                        color: Color.menu.text
                        opacity: 0.7
                        wrapMode: Text.WordWrap
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.summary ? root.summary.progress : ""
                        color: root.summary && root.summary.complete ? Color.accent : Color.menu.text
                        opacity: root.summary && root.summary.complete ? 1 : 0.7
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Button {
                      id: recommendButton
                      anchors.verticalCenter: parent.verticalCenter
                      visible: root.pending.length > 0
                      text: "Turn on recommended"
                      bordered: true
                      selected: true
                      foreground: Color.menu.text
                      fontFamily: Style.font.menuFamily
                      onClicked: root.applyRecommended()
                    }
                  }
                }
              }

              delegate: SettingRow {
                required property int index
                required property var modelData

                width: settingsList.width
                setting: modelData
                settingState: root.states[modelData.id] || null
                options: root.options[modelData.id] || []
                busy: root.busyId === modelData.id
                error: root.errors[modelData.id] || ""
                hasCursor: index === root.cursor
                promptActive: root.promptId === modelData.id
                promptText: root.promptId === modelData.id ? root.promptText : ""
                onActivated: root.activate(index)
                onMoreChosen: root.openMore(modelData)
                onChose: function(value) {
                  root.cursor = index
                  root.setValue(modelData.id, value)
                }
                onChooseFolder: {
                  root.cursor = index
                  root.chooseFolder(modelData)
                }
                onPointerMoved: function(item, mouse) { root.selectFromPointer(index, item, mouse) }
              }
            }

            Column {
              visible: root.loadError === "" && root.catalog.length > 0 && root.rows.length === 0
              anchors.centerIn: parent
              spacing: Style.spacing.md

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: "󰍉"
                color: Color.menu.text
                opacity: 0.4
                font.family: Style.font.family
                font.pixelSize: Style.font.displayLarge
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.query !== "" ? "No settings match “" + root.query + "”" : "Nothing here yet"
                color: Color.menu.text
                opacity: 0.7
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.title
              }
            }
          }
        }

        Row {
          id: footer
          anchors.right: parent.right
          spacing: Style.spacing.xxl

          Repeater {
            model: [
              { keys: ["j", "k"], label: "Move" },
              { keys: ["h", "l"], label: "Sections", hidden: root.view !== "hub" || root.sections.length < 2 },
              { keys: ["space"], label: "Change" },
              { keys: ["/"], label: root.view === "welcome" ? "All settings" : "Search" },
              { keys: ["esc"], label: "Close", hidden: root.view === "welcome" },
              { keys: ["enter"], label: root.promptAction, prompt: true },
              { keys: ["esc"], label: "Cancel", prompt: true }
            ].filter(function(hint) {
              return root.promptId !== "" ? hint.prompt === true : hint.prompt !== true && !hint.hidden
            })

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
                  color: "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: Util.alpha(Color.menu.text, 0.28)

                  Text {
                    id: keyText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: parent.modelData
                    color: Color.menu.text
                    opacity: 0.72
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
                opacity: 0.5
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.view === "welcome"
            text: "Done"
            bordered: true
            selected: true
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            onClicked: root.close()
          }
        }
      }
    }
  }
}
