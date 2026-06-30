# WindowShade

WindowShade is a small macOS prototype that rolls a window up in place.

Press `Control + Command + C`, or double-click a title bar, and the window folds into a thin strip. Press it again and the window comes back where it was.

The idea comes from classic Mac OS. Dock minimize, Mission Control, Stage Manager, and tiling all have their place. This is for the smaller moment when a window is simply in the way, and you still want it to come back from the same spot.

## What works now

- Menu bar app, no Dock icon.
- Fold and unfold the current window with `Control + Command + C`.
- Double-click title bars to fold, double-click folded strips to restore.
- Restore folded windows from the menu bar menu.
- Two strip styles: captured window chrome, or a standard proxy title bar.
- Basic preview, arranging, sound, and permission settings.

This is still a prototype. Some apps behave oddly. Full-screen spaces, custom title bars, Stage Manager, and multi-display setups still need care.

## Permissions

WindowShade asks for:

- Accessibility, so it can find and move windows.
- Screen Recording, so it can capture the top of a window for the folded strip.

It does not upload window contents. Local diagnostics go to `/tmp/windowshade.log`; those logs can include app names, window titles, and file paths.

## Build

You need macOS 14 or newer and the Xcode command line tools.

```sh
cd prototype
./build.sh
open WindowShade.app
```

The build script creates `WindowShade.app` and signs it ad-hoc by default. If you want macOS to keep Accessibility and Screen Recording trust across rebuilds, sign with your own certificate:

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## More notes

The code lives in [`prototype/WindowShade.swift`](prototype/WindowShade.swift).

For the history and design thinking behind the prototype, see [`WindowShade.md`](WindowShade.md).
