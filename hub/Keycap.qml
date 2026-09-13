import QtQuick
import qs.Commons

// The Omahub keycap, drawn from the same pixel grid as the brand assets but in the active
// theme's colors, so it matches every Omarchy theme.
Item {
  id: root

  property int cell: Math.max(1, Style.space(2))
  property color body: Util.alpha(Color.menu.text, 0.9)
  property color lip: Util.alpha(Color.menu.text, 0.35)
  property color legend: Color.accent

  readonly property var grid: [
    ".#########.",
    "#.........#",
    "#....a....#",
    "#...a.a...#",
    "#..a...a..#",
    "#..aaaaa..#",
    "#..a...a..#",
    "#..a...a..#",
    "#.........#",
    "#.........#",
    ".#########.",
    "..lllllll.."
  ]
  readonly property int columns: grid[0].length

  implicitWidth: columns * cell
  implicitHeight: grid.length * cell

  Repeater {
    model: root.grid.length * root.columns

    delegate: Rectangle {
      required property int index

      readonly property string pixel: root.grid[Math.floor(index / root.columns)].charAt(index % root.columns)

      visible: pixel !== "."
      x: (index % root.columns) * root.cell
      y: Math.floor(index / root.columns) * root.cell
      width: root.cell
      height: root.cell
      color: pixel === "a" ? root.legend : pixel === "l" ? root.lip : root.body
    }
  }
}
