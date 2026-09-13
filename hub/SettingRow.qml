import QtQuick
import qs.Commons
import qs.Ui

// One setting in the hub. Toggles reuse Omarchy's switch, choices show their options as chips,
// and other kinds show their current label. The row owns clicks and hover; the hub owns state.
Rectangle {
  id: row

  required property var setting
  property var settingState: null
  property var options: []
  property bool busy: false
  property string error: ""
  property bool hasCursor: false
  property bool promptActive: false
  property string promptText: ""

  signal activated()
  signal chose(string value)
  signal chooseFolder()
  signal moreChosen()
  // Carries the item the mouse position is relative to, so the hub can tell a moving pointer
  // from rows scrolling under a still one.
  signal pointerMoved(var item, var mouse)

  readonly property bool isOn: row.settingState !== null && row.settingState.value === true
  readonly property bool hasChips: row.setting.kind === "choice" || row.setting.kind === "folder"
  // A choice with More… keeps its chips short: the current one and up to three others, so the
  // title always has room. The rest live behind More….
  readonly property var chipOptions: {
    var list = row.options || []
    if (!row.setting.more || list.length <= 4) return list
    var shown = []
    var others = 3
    for (var i = 0; i < list.length; i++) {
      if (list[i].current) {
        shown.push(list[i])
      } else if (others > 0) {
        shown.push(list[i])
        others--
      }
    }
    return shown
  }
  readonly property color ink: row.hasCursor ? Color.menu.selectedText : Color.menu.text

  implicitHeight: Math.max(Style.space(58), content.implicitHeight + Style.spacing.rowPaddingX * 2)
  radius: Style.cornerRadius
  color: row.hasCursor ? Color.menu.selectedBackground : "transparent"

  Behavior on color { ColorAnimation { duration: 90 } }

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: function(mouse) { row.pointerMoved(rowMouse, mouse) }
    onClicked: row.activated()
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.spacing.rowPaddingX

    Text {
      id: icon
      width: Math.round(Style.font.iconLarge * 1.6)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: row.setting.icon || ""
      color: row.ink
      opacity: 0.85
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
    }

    Column {
      width: parent.width - icon.width - control.width - parent.spacing * 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.setting.title
        color: row.ink
        elide: Text.ElideRight
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.setting.summary
        color: row.ink
        opacity: 0.65
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: row.error !== ""
        textFormat: Text.PlainText
        text: row.error
        color: Color.urgent
        wrapMode: Text.WordWrap
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      id: control
      width: row.setting.kind === "toggle" ? toggle.implicitWidth
        : row.hasChips ? choices.implicitWidth
        : row.setting.kind === "action" ? actionControl.implicitWidth
        : valueLabel.implicitWidth
      height: Math.max(toggle.implicitHeight, choices.implicitHeight, valueLabel.implicitHeight, actionControl.implicitHeight)
      anchors.verticalCenter: parent.verticalCenter

      ToggleSwitch {
        id: toggle
        visible: row.setting.kind === "toggle"
        anchors.verticalCenter: parent.verticalCenter
        checked: row.isOn
        busy: row.busy
        interactive: false
        cursorRing: false
        foreground: row.ink

        SequentialAnimation on opacity {
          running: row.busy
          loops: Animation.Infinite
          NumberAnimation { to: 0.55; duration: 600; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
        }
      }

      Row {
        id: choices
        visible: row.hasChips
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        opacity: row.busy ? 0.6 : 1

        Behavior on opacity { NumberAnimation { duration: 140 } }

        Repeater {
          model: row.hasChips ? row.chipOptions : []

          delegate: Button {
            required property var modelData
            text: modelData.label
            selected: modelData.current === true
            bordered: true
            foreground: row.ink
            fontFamily: Style.font.menuFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.spacing.md
            verticalPadding: Style.spacing.xs
            onClicked: row.chose(modelData.value)
          }
        }

        Button {
          visible: row.setting.kind === "choice" && !!row.setting.more
          text: "More…"
          bordered: true
          foreground: row.ink
          fontFamily: Style.font.menuFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xs
          onClicked: row.moreChosen()
        }

        Button {
          visible: row.setting.kind === "folder"
          text: "Choose…"
          bordered: true
          foreground: row.ink
          fontFamily: Style.font.menuFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xs
          onClicked: row.chooseFolder()
        }
      }

      Row {
        id: actionControl
        visible: row.setting.kind === "action"
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm
        opacity: row.busy ? 0.6 : 1

        Behavior on opacity { NumberAnimation { duration: 140 } }

        // The inline prompt, drawn like the search box: placeholder, typed text, blinking caret.
        BorderSurface {
          id: promptField
          visible: row.promptActive
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          height: promptTyped.implicitHeight + Style.spacing.xs * 2
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: Border.controlSpec("focus", row.ink, Color.accent)

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            visible: row.promptText === ""
            textFormat: Text.PlainText
            text: row.setting.prompt || ""
            color: row.ink
            opacity: 0.5
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              id: promptTyped
              width: Math.min(implicitWidth, promptField.width - Style.spacing.md * 2 - Style.space(2))
              textFormat: Text.PlainText
              text: row.promptText
              color: row.ink
              elide: Text.ElideLeft
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(1, Style.space(2))
              height: Style.font.caption + Style.spacing.xxs
              color: Color.accent

              SequentialAnimation on opacity {
                running: row.promptActive
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 0 }
                PauseAnimation { duration: 530 }
                NumberAnimation { to: 0; duration: 0 }
                PauseAnimation { duration: 530 }
              }
            }
          }
        }

        Button {
          anchors.verticalCenter: parent.verticalCenter
          text: row.setting.action || "Run"
          bordered: true
          selected: row.promptActive
          foreground: row.ink
          fontFamily: Style.font.menuFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.md
          verticalPadding: Style.spacing.xs
          onClicked: row.activated()
        }
      }

      Text {
        id: valueLabel
        visible: row.setting.kind !== "toggle" && !row.hasChips && row.setting.kind !== "action"
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.settingState ? row.settingState.label : ""
        color: row.ink
        opacity: 0.75
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  onBusyChanged: {
    if (!row.busy) toggle.opacity = 1
  }
}
