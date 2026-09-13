# Changelog

Notable changes to Omahub Capture. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Floating thumbnail that slides into the corner after a screenshot and leaves on its own.
- Click to open the editor. Drag the file into any app. Right-click for Copy, Open in Editor, Show in Files, Move to Trash, or Close, with j, k, Enter, and Esc.
- Sideways swipe or wheel tilt to dismiss. Hovering, dragging, or an open menu keeps it on screen.
- Keycap mark with a 4 legend, for SUPER + SHIFT + 4, in `assets/`.
- A Save to section in the right-click menu: the current folder, Pictures, Downloads, Documents, or any folder. Saving moves the screenshot, makes that folder the default through Omarchy's `OMARCHY_SCREENSHOT_DIR`, and dismisses the card.
- Drag the thumbnail to the right to throw it away. It follows the pointer and springs back on a short drag.

### Changed

- Smoother slide in and out. The glide no longer lands in one visible jump, and no faint strip lingers at the screen edge on the way out.

### Fixed

- Clicks missed the thumbnail because its input region followed the slide-in transform.
- Dropping the thumbnail onto a window now dismisses it right away instead of waiting for its timer.
- The thumbnail shows the whole screenshot. Tall captures get a narrower card instead of being cropped.
