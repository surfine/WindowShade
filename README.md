# WindowShade

WindowShade is a macOS menu bar prototype for rolling a window up in place. It keeps a title-bar-like strip on the desktop, then restores the real window when you need it again.

It is inspired by the classic Mac OS WindowShade interaction. The goal is not to replace Dock minimize, Mission Control, Stage Manager, or tiling. It fills a smaller gap: sometimes a window is just in the way, but you still want its position and identity to stay where they were.

## What it does

- Lives in the menu bar and stays out of the Dock.
- `Control + Command + C` folds or unfolds the current window.
- Double-clicking a title bar can fold the window; double-clicking a folded strip unfolds it.
- Folded windows stay listed in the menu bar menu.
- `Control + Command + 1...9` restores folded windows by menu order.
- Includes two visible styles: a screenshot-based native strip and a standard proxy title bar.
- Provides menu preview, hover preview, arrange/restore commands, sound settings, and permission helpers.

## How it works

The active prototype is [`prototype/WindowShade.swift`](prototype/WindowShade.swift). It uses Accessibility APIs to identify and restore windows, ScreenCaptureKit to capture the original window chrome, and AppKit overlay windows to keep a folded strip in place.

Because modern macOS does not let a third-party app directly redraw another app's window internals, WindowShade uses a proxy approach: it leaves a visible strip behind, then hides, parks, or minimizes the real window as an implementation fallback.

## Permissions

WindowShade needs two macOS permissions:

- Accessibility: read, move, focus, and restore windows.
- Screen Recording: capture the top chrome of a window and previews.

The prototype does not upload window contents. Diagnostic logs are written locally to `/tmp/windowshade.log`; logs may contain app names, window titles, and local file paths from the windows you fold.

## Build

Requirements:

- macOS 14 or newer
- Xcode command line tools / Swift compiler

Build a local app bundle:

```sh
cd prototype
./build.sh
open WindowShade.app
```

The public `build.sh` creates `WindowShade.app` and signs it ad-hoc by default. If you want a stable local TCC identity across rebuilds, pass your own signing certificate:

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

You can also compile only the executable:

```sh
cd prototype
swiftc -O -o windowshade WindowShade.swift   -framework Cocoa -framework Carbon -framework ApplicationServices   -framework ScreenCaptureKit -framework QuartzCore -framework CoreText   -framework ServiceManagement
```

## Notes

This is a prototype. It uses private or semi-private system behavior in a few places to make the interaction possible on modern macOS. Some apps, full-screen spaces, Stage Manager layouts, custom title bars, and multi-display setups may need special handling.

For design background and historical notes, see [`WindowShade.md`](WindowShade.md).
