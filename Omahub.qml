import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property int sectionIndex: 0

  readonly property var sections: [
    { name: "Discover", icon: "󰀻" },
    { name: "Installed", icon: "󰄬" },
    { name: "Themes", icon: "󰏘" },
    { name: "Plugins", icon: "󰐱" },
    { name: "Services", icon: "󰒓" }
  ]

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.panelGap
  property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int tabHeight: Math.max(Style.spacing.controlHeight, Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(960), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function selectSection(index) {
    root.sectionIndex = (index + root.sections.length) % root.sections.length
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omahub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab) {
            root.selectSection(root.sectionIndex - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab) {
            root.selectSection(root.sectionIndex + 1)
            event.accepted = true
          } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.sections.length) {
            root.selectSection(event.key - Qt.Key_1)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Omahub"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxl

            Repeater {
              model: [
                { keys: ["h", "l"], label: "Sections" },
                { keys: ["esc"], label: "Close" }
              ]

              delegate: Row {
                id: hint
                required property var modelData
                spacing: Style.spacing.sm

                Repeater {
                  model: hint.modelData.keys

                  delegate: Rectangle {
                    required property string modelData
                    width: Math.max(height, keyLabel.implicitWidth + Style.spacing.md * 2)
                    height: keyLabel.implicitHeight + Style.spacing.xxs * 2
                    radius: root.cornerRadius
                    color: "transparent"
                    border.width: Style.normalBorderWidth
                    border.color: Util.alpha(root.foreground, 0.28)

                    Text {
                      id: keyLabel
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: parent.modelData
                      color: root.foreground
                      opacity: 0.72
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.spacing.xs
                  textFormat: Text.PlainText
                  text: hint.modelData.label
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Row {
          id: tabs
          width: parent.width
          height: root.tabHeight
          spacing: Style.spacing.sm

          Repeater {
            model: root.sections

            delegate: Rectangle {
              id: tab
              required property int index
              required property var modelData

              readonly property bool active: index === root.sectionIndex

              width: tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2
              height: tabs.height
              radius: root.cornerRadius
              color: active ? root.selectedBackground : (tabMouse.containsMouse ? Style.hoverFill : "transparent")

              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: tabLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: tab.modelData.icon + "  " + tab.modelData.name
                color: tab.active ? root.selectedText : root.foreground
                opacity: tab.active ? 1 : 0.72
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }

              MouseArea {
                id: tabMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectSection(tab.index)
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.normalBorderWidth
          color: Util.alpha(root.border, 0.28)
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.tabHeight - Style.normalBorderWidth - root.contentSpacing * 3

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.sections[root.sectionIndex].icon
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.sections[root.sectionIndex].name + " is not built yet."
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }
      }
    }
  }
}
