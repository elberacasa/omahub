import QtQuick
import Quickshell.Io
import qs.Commons
import "Pets.js" as Pets

// The active theme's named palette, read from its colors.toml, so every pet can wear a color of its own that
// the theme library does not expose. It is read again whenever the theme's colors change.
QtObject {
  id: palette

  property var colors: ({})

  property FileView file: FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: palette.colors = Pets.parsePalette(text())
    onFileChanged: reload()
    onLoadFailed: palette.colors = ({})
  }

  // Omarchy announces a new theme by pushing its colors to the theme library.
  property Connections theme: Connections {
    target: Color
    function onAccentChanged() { palette.file.reload() }
    function onBackgroundChanged() { palette.file.reload() }
    function onForegroundChanged() { palette.file.reload() }
  }
}
