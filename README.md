<p align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade app icon" width="128"/>
</p>

<p align="center">
  <strong>WindowShade</strong><br>
  Bring the classic Mac OS window shade back to macOS.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README_CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/" title="Watch the demo video">
    <img src="assets/windowshade-hero.png" alt="Watch the WindowShade demo video" width="900"/>
  </a>
  <br>
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/">Watch the demo video</a>
</p>

---

WindowShade is a small macOS menu bar app for getting windows out of the way without losing them.

It gives a window two temporary states:

- **Folded**: the window content rolls up, leaving a title-bar strip in the same place. Open it again from the strip, the menu bar, or a keyboard shortcut.
- **Pinned**: the window stays visible as a live floating preview. Move the pointer into it when you want to operate the real window.

This is useful when you only need to peek behind a window, keep an iPhone Mirroring window visible, or quiet down a busy desktop without sending everything to the Dock.

## Download

Download the latest zip from [Releases](https://github.com/surfine/WindowShade/releases), unzip it, and open `WindowShade.app`.

WindowShade lives in the menu bar. It does not show a Dock icon.

## Basic Use

- `Control + Command + C`: fold or unfold the current window.
- Double-click a window title bar: fold or unfold that window.
- Click a folded strip: show or hide a quick preview.
- `Control + Command + P`: pin or unpin the current window as a live preview.
- `Control + Command + 1...9`: unfold windows by their order in the menu.
- Menu bar: manage folded windows, pinned previews, Focus Shelf, appearance, sounds, permissions, and launch at login.

Triple-clicking the title bar keeps the system title-bar zoom behavior available.

## Notes

WindowShade works best with normal desktop windows. Apps with custom title bars, floating panels, or unusual document windows may need app-specific handling.

The app includes compatibility work for Quick Look, Stickies, WeChat, Adobe apps, and a few other non-standard windows.

## Permissions

WindowShade asks for two macOS permissions:

- Accessibility, so it can find and move windows.
- Screen Recording, so it can capture the top of a window and show live previews.

It does not upload window contents.

## Build from Source

You need macOS 14 or newer and the Xcode command line tools.

```sh
cd prototype
./build.sh
open WindowShade.app
```

The build script creates `WindowShade.app`. To keep macOS permission trust across rebuilds, sign with your own certificate:

```sh
cd prototype
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## Design Notes

The main code is in [`prototype/WindowShade.swift`](prototype/WindowShade.swift). For the history and design notes, see [`WindowShade.md`](WindowShade.md).
