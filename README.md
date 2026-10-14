<div align="center">

<img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade" width="112">

# WindowShade

**Roll it up. Keep its place.**<br>
Double-click a title bar and the window rolls up into a thin bar, right where it was.<br>
Double-click again and it’s back. Rest the pointer on the bar to glance at it without unrolling.<br>
A free, open-source window utility for Mac.

[![Release](https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&color=303b49)](https://github.com/surfine/WindowShade/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-303b49?style=flat-square)](#download)
[![Apple Silicon](https://img.shields.io/badge/download-Apple%20Silicon-303b49?style=flat-square)](#download)
[![License](https://img.shields.io/badge/license-MIT-303b49?style=flat-square)](LICENSE)

[**Download for Mac**](https://github.com/surfine/WindowShade/releases/latest) · [**Website**](https://windowshade.aaronlau.me/en/) · [**Intro video**](https://www.bilibili.com/video/BV1K7ag6WEdH/) (Bilibili, in Chinese) · [**Window stories**](https://windowshade.aaronlau.me/en/history/) · [简体中文](README_CN.md) · [繁體中文](README_TW.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/readme-desk-en-dark.png">
  <img src="assets/readme-desk-en.png" alt="The Reference window rolled up into a thin bar where it was, uncovering the draft behind it" width="720">
</picture>

<sub>The interactive illustration from the website: Reference rolls up, and the draft behind it shows through. <a href="https://windowshade.aaronlau.me/en/">Try it yourself →</a></sub>

</div>

## Three ways to move a window aside. Only one never makes you look for it.

When a window covers something, you probably close it or minimize it. Both work. Getting it back just takes a little effort.

| | Where the window goes | Getting it back |
| --- | --- | --- |
| **Close** | It’s gone | Open it again, then find your place again |
| **Minimize** | Into the Dock | Spot it in the Dock first |
| **Roll up** | A thin bar, right where it was | Double-click the bar |

Unlike minimizing, the window never leaves the desktop. Drag the bar somewhere else and the window opens there.

## Download

Get the latest ZIP from [Releases](https://github.com/surfine/WindowShade/releases/latest), unzip it, drag `WindowShade.app` into Applications and open it, then follow the permission prompts. It lives in the menu bar and stays out of your Dock.

- **Needs macOS 14 or later and Apple Silicon.** There’s no Intel build.
- **1.0.16 download:** 9.83 MB ZIP; the extracted app contains 25.37 MB of files (decimal MB; filesystem allocation may differ). The ZIP now carries the updater, hence the bigger size.
- **Not notarized yet.** If macOS blocks the first launch, go to System Settings → Privacy & Security and choose Open Anyway. You don’t need to turn off any system security.
- Every release ships with a SHA-256 checksum file; for what changed in each version, see the [release notes](https://github.com/surfine/WindowShade/releases).

## What it does

**Roll up.** Double-click a title bar or press `⌃⌘C` and the window rolls up into a thin bar; double-click the bar to unroll it. The bar can keep the window’s own look, or use one consistent title bar. While a bar is in front, `⌘W`, `⌘M`, `⌘H`, `⌘Q` and `⌘N` go to the window and app behind it; `⌘Q` puts the window back down first, so any “save changes?” question is where you can see it.

**Title-bar gestures.** Put the pointer on a title bar and swipe with two fingers: push up to roll up, pull down to fill the screen between the menu bar and the Dock, push up again to put it back. Nothing happens until you let go, so pulling back halfway undoes it, and a panel styled like the system volume indicator says what letting go will do. Swipe sideways for half the screen; keep swiping the same way for two thirds, then one third, and once more moves the window to the display on that side. Turn down or up after a sideways swipe to take that corner. Spreading two fingers also fills the screen, and pinching undoes the last placement. Drag a title bar, throw it and let go, and the window glides the way you threw it — up rolls up, down fills, the sides walk the same steps, and a throw aimed at a corner takes it. With an ordinary mouse, three notches of the wheel on a title bar count as one swipe; Magic Mouse support is still being checked on real hardware. Details are in the [gesture notes](docs/gestures.md).

**Glance.** Rest the pointer on the bar and a card drops down beneath it, showing the window's content at its own size; move away and it rolls back up. Click the card to unroll the window for real; on a Force Touch trackpad, pressing firmly on the bar also glances, and letting go puts it away. The bar stays put and the card hangs just below it, so it reads as a preview, not the window itself. A glance never switches the app you’re in and never moves a window. A window that was minimized when it rolled up can’t be shown live, so you see how it looked then, and the corner says so. Details are in the [glance notes](docs/glance.md).

**Carry and pin.** Press `⌃⌘G` to carry the current window to every desktop: it stays where it is, and its bar appears in the top-right corner of your other desktops. Rest on the bar for a live picture — if the window is hidden or minimized, a labelled snapshot appears instead — and click it to go there; press `⌃⌘G` again to put it down. Press `⌃⌘P` to pin a window, so it stays uncovered while you switch to anything else; the menu bar lists every pinned window and can unpin them all at once.

**Window browsing.** Rest the pointer on an app’s icon in the Dock and every window that app has open is listed, each with a picture and a title. The panel is for looking: a window changes only when you press a button on its card; Space gives a large preview without bringing the window forward; placement shows where the window will go and moves it only when you agree, and you can undo afterwards. You can also open it from Choose window… in the menu bar, or with a hot key you set — the Dock entry is off by default. The panel is temporary: it does not replace the Dock or take over Command-Tab. Details are in the [window browsing notes](docs/window-browser.md).

**An extra: close the lid, and the desktop stays put.**

<img src="assets/windowshade-lid-en.gif" alt="As the MacBook lid closes, the desktop seems to stay where it was, darker and blurrier toward the top" width="620">

On an Apple Silicon MacBook with a hinge sensor, the screen closes but the desktop seems to stay where it was, like a page behind glass, growing darker and blurrier toward the top. Open the lid and it’s back. Three styles: gentle, standard and frosted. It’s only an extra: rolling up and pinning work without it.

## This double-click is older than your Mac

In the ’90s, most Mac users knew this trick. Then the system changed course, sent windows to the Dock, and the trick was slowly forgotten. We wrote its story as a long read you can operate — [Window stories](https://windowshade.aaronlau.me/en/history/): seven chapters, four hands-on experiments, 14 primary sources. It ends at a [working System 7.5, Mac OS 8 or Mac OS X 10.1](https://windowshade.aaronlau.me/en/history/#lab), run by [Infinite Mac](https://infinitemac.org/), where you can find the setting through the original menus yourself.

Today’s WindowShade is an independent Swift / AppKit app: the old name and the old idea, with code written from scratch. It is not an Apple product, and it uses no code from Rob Johnston, Apple, or Unsanity’s WindowShade X.

## Shortcuts

Record your own in Settings → Shortcuts, or bring Rectangle’s key set over in one click. 1.0.16 presets none of these for new setups; setups upgraded from 1.0.15 or earlier keep the combinations below. Every shortcut can be changed or turned off, and if another app already uses a combination, WindowShade tells you once.

| Shortcut (upgraded setups) | What it does |
| --- | --- |
| `⌃⌘C` | Roll up or unroll the current window |
| `⌃⌘P` | Pin or unpin the current window |
| `⌃⌘G` | Carry the current window to every desktop; press again to put it down |
| `⌃⌘1…9` | Unroll a rolled-up window, in menu order |
| `⌃⌘0` | Line up the bars, or switch to a focus layout |
| `⌃⌘←` `⌃⌘→` `⌃⌘↑` `⌃⌘↓` | Place the current window: to the sides, one size down, one size up |

Double-click a title bar to roll up; double-click the bar to unroll.

## Your windows stay on your Mac

WindowShade asks for two permissions. **Accessibility**: finding, moving and restoring windows. **Screen Recording**: taking the window pictures used for previews. “Screen Recording” is just the name the system gives that permission — everything is processed on your Mac and nothing is uploaded. If the app ever quits unexpectedly, your windows go back to how they were.

Regular windows all roll up. Stickies rolls up in its own system way; apps like Adobe’s that draw their own title bars are handled separately. Full screen, Split View, Stage Manager and multiple displays still have a few gaps — try it once with the apps you use. If something goes wrong, please [report it](https://github.com/surfine/WindowShade/issues) with your macOS version, the app, and the steps.

## In development

The current download is **1.0.16** — tucked windows and the rest of the notch page above are in it, plus a three-step welcome, a “What WindowShade reads” privacy page and an interface-language switch. On a new installation, the notch, live activities, file shelf, accessory notices, volume/brightness display and Dock click-to-hide are off until enabled in Settings. [Release notes](docs/releases/v1.0.16.md) · [defaults](docs/releases/v1.0.16-defaults.md) · [gate report](docs/releases/v1.0.16-acceptance/gate-0B-verification.md)

These are not in the download yet:

- **Three interface languages.** Settings → Advanced → Interface language: **follow the system / 简体中文 / 繁體中文 / English**; it takes effect immediately, no restart.
  The Traditional build follows Taiwan usage (瀏海, 捲簾條, 快速鍵, 輔助使用), with the same coverage as the English one.
  English covers the whole Settings window and the notch sentences; a few surfaces are still being translated. [Details](docs/handoff/BATCH27-ENGLISH-HANDOFF-2026-10-12.md)
- **Touch ID in the notch** — expands the notch around the system fingerprint prompt to confirm a WindowShade request; it does not unlock macOS. [Details](docs/touch-id-island.md)
- **Launchpad and new gestures** — the Home grid with the App Library (`⌃⌘L`), Magic Tiling, the scroll strip, Picture in Picture, Slide Over with a split handle, `⌥`-Tab by window, Rectangle key import, Dock click-to-hide, and more. [Launchpad](docs/launchpad.md) · [title-bar gestures](docs/gestures.md)
- **Experimental or device-limited** — face scanning, presence locking, remote control and CarPlay have experimental and device limits; none of this claims macOS face unlock or complete CarPlay reception.

## Build and contribute

Requires macOS 14+, Xcode command line tools with the Metal compiler, and an Apple Development signing certificate.

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh --check   # Swift type checking and Metal compilation
./build.sh           # build and sign with your configured identity
open WindowShade.app
```

Set `WINDOWSHADE_CODESIGN_IDENTITY` or use an untracked `prototype/local-codesign.env`. See [DEVELOPMENT.md](DEVELOPMENT.md) for signing, isolated builds, and release instructions; interface and website copy follows the [copy guide](docs/copy-guide.md).

| In the repository | Purpose |
| --- | --- |
| [`prototype/`](prototype/) | Native app: window policies, capture, overlays, effects, and recovery |
| [`tests/`](tests/) | State, recovery, frame, Metal, and paper-component checks |
| [`site/`](site/) | Bilingual website and window stories, hosted on Cloudflare Pages |
| [`docs/performance.md`](docs/performance.md) | Measurements and approaches that did or did not work |
| [`docs/releases/`](docs/releases/) | Preserved release notes |
| [`WindowShade.md`](WindowShade.md) | Original design rationale and research notes |

For changes to window behavior, include the affected window type, what happened before and after, and the checks you ran.

## Credits and license

[MIT](LICENSE) for this project's code. Historical names and software belong to their respective authors. The window stories credit [Infinite Mac](https://infinitemac.org/), Marcin Wichary's [Frame of preference](https://aresluna.org/frame-of-preference/), and [AI System 6](https://github.com/surfine/AI-System-6) for its era-rendering reference. Bundled font and reference-asset licenses are retained in [`site/public/fonts/`](site/public/fonts/).
