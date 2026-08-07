<h1 align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade app icon" width="128"/><br>
  WindowShade
</h1>

<p align="center">
  <strong>Fold windows out of the way without losing their place.</strong><br>
  A small macOS menu bar app that brings back the classic window shade gesture for modern desktops.
</p>

<p align="center">
  <a href="https://github.com/surfine/WindowShade/releases/latest"><img src="https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&label=release" alt="Latest release"></a>
  <a href="https://github.com/surfine/WindowShade/stargazers"><img src="https://img.shields.io/github/stars/surfine/WindowShade?style=flat-square" alt="GitHub stars"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <a href="README_CN.md"><img src="https://img.shields.io/badge/readme-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-blue?style=flat-square" alt="Simplified Chinese README"></a>
</p>

<p align="center">
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/" title="Watch the demo video">
    <img src="assets/windowshade-hero.png" alt="Watch the WindowShade demo video" width="900"/>
  </a>
  <br>
  <a href="https://www.bilibili.com/video/BV1m5Kf6bE6k/">Watch the demo video</a>
</p>

---

WindowShade is for the little desktop moment that macOS still makes oddly expensive: a window is in the way, but it still belongs exactly where you put it.

It folds the window content into a slim title-bar strip, keeping the window identifiable and exactly where your layout put it. Open it again from the strip, the menu bar, or a shortcut, without digging through the Dock or rearranging your workspace.

## What It Does

| Mode | What happens | Good for |
| --- | --- | --- |
| **Folded** | Keep the title bar in place and roll the window content away. | Peeking behind a window, clearing clutter, keeping a document's place. |
| **Pinned** | Keep a window visible as a live floating preview. | Reference windows, iPhone Mirroring, dashboards, things you want to watch. |

## Why WindowShade?

macOS already has Dock minimization, Mission Control, Spaces, Stage Manager, and tiling. WindowShade is smaller than all of those. It helps when you want to keep a group of open windows arranged as part of your workflow, while temporarily clearing the content that is blocking your view.

Expose and Mission Control are great for finding windows. Dock minimization is good for putting a window away. WindowShade is for the in-between case: leave the window where it is, but roll up its content for now.

## Highlights

- Fold the current window with `Control + Command + C`.
- Double-click a title bar to fold or unfold that window.
- Click a folded strip to preview the hidden content.
- Pin a window as a live floating preview with `Control + Command + P`.
- Restore folded windows with `Control + Command + 1...9` or from the menu bar.
- Choose native-looking strips, standard title bars, transparency, sounds, Focus Shelf, and launch at login.

## Download

Download the latest zip from [Releases](https://github.com/surfine/WindowShade/releases/latest), unzip it, and open `WindowShade.app`.

WindowShade lives in the menu bar. It does not show a Dock icon.

## Basic Use

| Action | Shortcut / gesture |
| --- | --- |
| Fold or unfold the current window | `Control + Command + C` |
| Fold or unfold a specific window | Double-click its title bar |
| Preview a folded window | Click its folded strip |
| Pin or unpin the current window | `Control + Command + P` |
| Unfold by menu order | `Control + Command + 1...9` |
| Manage everything | Menu bar icon |

Triple-clicking the title bar keeps the system title-bar zoom behavior available.

## Notes

WindowShade works best with ordinary desktop windows. Apps with custom title bars may need app-specific handling.

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
