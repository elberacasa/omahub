import QtQuick
import qs.Commons

// A word of the Omahub brand set in pixels from the same grid as assets/omahub.txt, never in a font that may not be
// installed, and in the active theme's colors: the lowercase omahub wordmark, or pets, for the pet universe. Both
// share a baseline, and pets hangs its p below it.
Item {
  id: root

  property string word: "omahub"
  property int cell: Math.max(1, Style.space(2))
  property color color: Color.menu.text

  readonly property var grids: ({
    omahub: [
      "..................#...........#....",
      "..................#...........#....",
      ".###..##.#...###..####..#...#.####.",
      "#...#.#.#.#.....#.#...#.#...#.#...#",
      "#...#.#.#.#..####.#...#.#...#.#...#",
      "#...#.#.#.#.#...#.#...#.#...#.#...#",
      ".###..#.#.#..####.#...#..####.####.",
      "...................................",
      "..................................."
    ],
    pets: [
      "......................",
      ".............#........",
      "####...###..####..####",
      "#...#.#...#..#...#....",
      "#...#.#####..#....###.",
      "#...#.#......#.......#",
      "####...####...##.####.",
      "#.....................",
      "#....................."
    ]
  })
  readonly property var grid: root.grids[root.word] || root.grids.omahub
  readonly property int columns: root.grid[0].length

  implicitWidth: root.columns * root.cell
  implicitHeight: root.grid.length * root.cell

  Repeater {
    model: root.grid.length * root.columns

    delegate: Rectangle {
      required property int index

      visible: root.grid[Math.floor(index / root.columns)].charAt(index % root.columns) === "#"
      x: (index % root.columns) * root.cell
      y: Math.floor(index / root.columns) * root.cell
      width: root.cell
      height: root.cell
      color: root.color
    }
  }
}
