# WindowShade design notes

WindowShade was a classic Mac OS gesture: double-click a window title bar and the window rolled up, leaving only the title bar behind. Double-click again and it opened back up.

That sounds small, but the detail matters. The window did not leave the desktop. It did not go to the Dock. It stayed where your eyes and hands expected it to be.

This prototype is an attempt to bring that old interaction back to modern macOS.

## Why this exists

Modern macOS already has many ways to manage windows: Dock minimize, Mission Control, Stage Manager, full screen, and tiling. They are useful, but they often move the recovery point somewhere else.

WindowShade is for a smaller moment.

A window is covering something. You do not want to close it. You do not want to reorganize the workspace. You just want it to get out of the way for a second.

So it folds.

## A little history

WindowShade did not begin as an Apple system feature. The early version is usually credited to Rob Johnston, who wrote it as a third-party utility for classic Mac OS. Apple later bought the rights and shipped the behavior with System 7.5 in 1994.

By Mac OS X, the built-in feature was gone. The system moved toward Dock minimize, Expose, and later Mission Control. Third-party tools such as WindowShade X, WindowMizer, and Deskovery kept the idea alive in different forms.

There is still one first-party trace of the old feeling: Stickies. Its notes can collapse into little colored strips. They keep their place and their identity. They feel less like minimized windows and more like folded pieces of paper.

That is the part worth keeping.

## How the prototype works

Modern macOS does not let one app redraw another app's windows directly. WindowShade works around that.

The current prototype:

1. Finds the focused window with Accessibility APIs.
2. Captures the top of the window with ScreenCaptureKit.
3. Creates an AppKit overlay strip in the same place.
4. Hides, parks, or minimizes the real window.
5. Restores the real window when the strip is opened again.

The main code is in `prototype/WindowShade.swift`.

There are two visible styles:

- A captured strip that keeps the original window chrome.
- A standard proxy title bar for a cleaner, more uniform look.

Both are compromises. The goal is not to perfectly recreate classic Mac OS. The goal is to preserve the useful part: the window is still here, just folded.

## Current limits

Some apps are simple. Some are not.

Custom title bars, full-screen spaces, Stage Manager, multi-display setups, and professional apps with floating panels can all break the illusion. Stickies also needs to be left alone, because it already has its own native folding behavior.

The prototype also uses private or semi-private system behavior in a few places. That makes it useful for exploration, but it is not a polished distribution build.

## Design rule

The rule I keep coming back to is simple:

If a window is only temporarily in the way, the way back should stay in the same place.
