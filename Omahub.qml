import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ui"
import "ui/Hub.js" as Hub

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
  property var pendingStates: ({})
  property var pendingOptions: ({})
  property string sectionId: "keyboard"
  property int cursor: 0
  property string query: ""
  property bool searching: false
  property string busyId: ""
  property var queue: []

  readonly property string omahub: Qt.resolvedUrl("bin/omahub").toString().replace("file://", "")
  readonly property var sections: Hub.sections(root.catalog)
  readonly property var rows: Hub.rows(root.catalog, root.sectionId, root.query)
  readonly property var summary: Hub.keyboardSummary(root.states)
  readonly property var pending: Hub.pendingRecommended(root.states)
  readonly property bool showKeyboardCard: root.query === "" && root.sectionId === "keyboard" && root.summary !== null

  readonly property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  readonly property int headerHeight: Math.max(Style.space(40), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int sidebarWidth: Style.space(190)

  // Reads every setting's state, one line per setting. Answers are applied together when the read
  // finishes, so rows, the keyboard card, and its progress never appear half filled.
  readonly property string stateScript: "bin=$1\nshift\n"
    + "for entry in \"$@\"; do\n"
    + "  id=${entry%|*}\n"
    + "  kind=${entry##*|}\n"
    + "  state=$(\"$bin\" get \"$id\" 2>/dev/null) || state=null\n"
    + "  options=null\n"
    + "  if [[ $kind == \"choice\" ]]; then\n"
    + "    options=$(\"$bin\" options \"$id\" 2>/dev/null) || options=null\n"
    + "  fi\n"
    + "  printf '%s\\t%s\\t%s\\n' \"$id\" \"${state:-null}\" \"${options:-null}\"\n"
    + "done"

  // The plugin stays loaded, so read settings once at startup and the first SUPER + A opens on real state.
  Component.onCompleted: root.refresh()

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload.section) root.sectionId = payload.section

    root.query = ""
    root.searching = false
    root.cursor = 0
    exitAnimation.stop()
    root.mounted = true
    root.opened = true
    enterAnimation.restart()
    pointerGate.reset()
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
    var list = Hub.parseCatalog(text)
    root.loading = false
    if (list === null) {
      root.loadError = "Omahub could not read its settings."
      return
    }
    root.catalog = list
    if (list.length > 0 && !Hub.hasSection(list, root.sectionId)) root.sectionId = Hub.sections(list)[0].id
    root.readStates()
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
    var parsed = Hub.parseStateLine(line)
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
      var state = Hub.parseJson(setOutput.text)
      if (state) {
        var nextStates = Object.assign({}, root.states)
        nextStates[id] = state
        root.states = nextStates
      }
    } else {
      var nextErrors = Object.assign({}, root.errors)
      nextErrors[id] = Hub.errorText(setErrors.text)
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
    }
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
    var list = root.sections
    if (list.length === 0) return
    var index = list.findIndex(function(section) { return section.id === root.sectionId })
    root.selectSection(list[(index + delta + list.length) % list.length].id)
  }

  function setQuery(text) {
    root.query = text
    root.cursor = 0
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
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
            if (root.query !== "" || root.searching) {
              root.setQuery("")
              root.searching = false
            } else {
              root.close()
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
            root.searching = true
          } else if (plain && printable) {
            root.searching = true
            root.setQuery(root.query + event.text)
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
              text: "Omahub"
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          BorderSurface {
            id: searchBox
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
            width: root.sidebarWidth
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
            anchors.left: sidebar.right
            anchors.leftMargin: Style.spacing.lg
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.normalBorderWidth
            color: Util.alpha(Color.menu.border, 0.28)
          }

          Item {
            id: mainPane
            anchors.left: divider.right
            anchors.leftMargin: Style.spacing.lg
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
                onActivated: root.activate(index)
                onChose: function(value) {
                  root.cursor = index
                  root.setValue(modelData.id, value)
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
              { keys: ["h", "l"], label: "Sections", hidden: root.sections.length < 2 },
              { keys: ["space"], label: "Change" },
              { keys: ["/"], label: "Search" },
              { keys: ["esc"], label: "Close" }
            ].filter(function(hint) { return !hint.hidden })

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
        }
      }
    }
  }
}
