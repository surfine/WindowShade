<p align="center">
  <img src="assets/windowshade-menubar.svg" alt="WindowShade" width="96"/>
</p>

<p align="center">
  <strong>WindowShade</strong><br>
  Bring the classic Mac OS window shade back to macOS.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/">Demo video</a>
</p>

<p align="center">
  <img src="assets/windowshade-hero.png" alt="WindowShade rolling windows into title bars" width="900"/>
</p>

---

WindowShade is a small macOS prototype that brings back a classic Mac gesture: fold a window into a thin strip, then unfold it from the same spot.

Sometimes you only want to peek behind a window. You do not want to close the document, hide the whole app, or send the window to the Dock and find it again. WindowShade adds that missing middle state: the content steps back, while the title, position, and way back stay where they were.

## Current state

This is a prototype, not a polished release. Today it can:

- fold and unfold the current window with `Control + Command + C`;
- fold a window by double-clicking its title bar;
- keep the system title-bar zoom behavior available through triple-click;
- keep a title-bar-like strip in place instead of sending the window to the Dock;
- preview a folded window from its strip, then restore it from the strip, menu bar, or `Control + Command + 1...9`;
- show folded windows in the menu bar and unfold everything at once;
- move other apps into a top Focus Shelf when you want to keep one app in front;
- switch between captured window chrome and a standard proxy title bar;
- start at login;
- handle a few special cases, including Quick Look, Stickies, WeChat, and Adobe apps.

Some apps still need special handling. Full-screen spaces, custom title bars, Stage Manager, and multi-display setups can break the spell.

## How it works

WindowShade uses Accessibility APIs to find the current window, ScreenCaptureKit to capture the top of it, and an AppKit overlay as the folded strip. The real window may be parked offscreen, hidden, or minimized underneath. To the user, it stays folded in place.

## Permissions

WindowShade asks for two macOS permissions:

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

The build script creates `WindowShade.app` and signs it ad-hoc by default. To keep macOS permission trust across rebuilds, sign with your own certificate:

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## Notes

The main code is in [`prototype/WindowShade.swift`](prototype/WindowShade.swift). For the history and design notes, see [`WindowShade.md`](WindowShade.md).
