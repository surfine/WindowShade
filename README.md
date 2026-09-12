<div align="center">

<img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade" width="112">

<samp>A CLASSIC MAC GESTURE, BACK IN PLACE.</samp>

# WindowShade

**Make room. Keep your place.**<br>
Roll a window up to its title bar. Bring it back where you left it.<br>
A native macOS menu bar utility, with pinned previews and lid-driven desktop effects.

[![Release](https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&color=303b49)](https://github.com/surfine/WindowShade/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-14%2B-303b49?style=flat-square)](#download)
[![Apple Silicon](https://img.shields.io/badge/download-Apple%20Silicon-303b49?style=flat-square)](#download)
[![License](https://img.shields.io/badge/license-MIT-303b49?style=flat-square)](LICENSE)

[**DOWNLOAD**](https://github.com/surfine/WindowShade/releases/latest) · [**PRODUCT SITE**](https://windowshade.pages.dev/en/) · [**INTERACTIVE HISTORY**](https://windowshade.pages.dev/en/history/) · [简体中文](README_CN.md)

![WindowShade's desktop effect responding as the MacBook lid closes](assets/windowshade-demo.gif)

<sub>A REAL CAPTURE OF THE LID-DRIVEN DESKTOP EFFECT. WINDOW FOLDING ALSO WORKS WITH A SHORTCUT OR TITLE-BAR GESTURE.</sub>

</div>

## A little less window. The same place.

A reference document covers the draft you are writing. You need the space for a moment, and you want to remember where that document was.

WindowShade leaves a slim strip on the desktop with the window's title and a way back. Double-click the strip to restore the window. Drag the strip, and the window opens at its new position. It keeps the small spatial cues that make a busy desktop feel like your own.

## What's new in 1.0.11

- **A calmer native interface.** A four-page AppKit settings window, shared paper edges and shadows, and clearer preview and permission states. Light and dark appearances follow macOS.
- **Less repeated work when folding a group.** Window discovery and capture preparation are shared where possible; bulk folding skips overlapping animations. Fold animations measure the window's top region before presenting their cover.
- **A home for the product and its history.** A bilingual website, seven chapters of interactive archaeology, and real old Mac systems you can boot in your browser.

[Release notes and downloads →](https://github.com/surfine/WindowShade/releases/tag/v1.0.11)

## Three ways to make room

| | What it does | A useful moment |
| --- | --- | --- |
| **Fold a window** | `⌃⌘C` or double-click the title bar. Keep a strip in place; double-click it to unfold. Choose a captured top region or a standard title bar. | Move a reference out of the way without losing its place. |
| **Pin a preview** | `⌃⌘P` creates a floating live view of a window. Its capture rate drops while idle. | Keep a reference, mirror, or dashboard visible beside your work. |
| **Feel the lid move** | On a supported MacBook, the desktop rolls, recedes, or blurs as the lid moves. Silk, Shade, and Frost finishes; adjustable trigger and a scrubbable preview. | A small physical connection between the computer and its screen. |

Window folding animations accompany manual fold and unfold actions. The lid sensor drives the desktop effect. Experimental device tilt adds a small parallax when the Mac exposes the required sensor.

## Native where you use it

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/windowshade-settings-dark.png">
  <img src="assets/windowshade-settings.png" alt="WindowShade's native settings: a sidebar, paper preview, and controls for dynamic effects" width="100%">
</picture>

<sub>REAL APPKIT SETTINGS, SHOWN IN YOUR GITHUB THEME. CAPTURED IN THE ISOLATED DESIGN PREVIEW; SENSORS ARE NOT RUNNING IN THIS IMAGE.</sub>

Effects, Shading, Permissions & Startup, and Advanced keep related controls together. The menu bar holds your window list and the controls you need during work. There is no Dock icon.

## An old idea worth keeping

The useful part of window shading is **continuity**: contents can move out of sight while their place stays visible. A small gesture can be a preference. A folded window can still tell you what it holds.

| A few stops in the archive | What to look for |
| --- | --- |
| **1994 · A small utility** | A January Mini’app’les newsletter lists WindowShade 1.2, credited to Rob Johnston / Interactive Technologies, with a 1989–92 copyright range. That range is not a verified first-release date. |
| **System 7.5 · A personal rhythm** | The control panel offers two or three clicks, modifier keys, and sound. |
| **Mac OS 8 · A visible control** | A dedicated collapse box makes the action part of the window frame. |
| **Mac OS X and beyond · Other ways to make room** | The Dock, later Exposé, third-party utilities, and the surviving roll-up behavior in Stickies tell different parts of the story. |

[**Explore the illustrated, source-linked history →**](https://windowshade.pages.dev/en/history/)

Try the reconstructed controls, compare folding with minimizing, or boot System 7.5, Mac OS 8.0, and Mac OS X 10.1 through [Infinite Mac](https://infinitemac.org/). Reconstructions are identified as such, and original sources are linked beside the story.

Today's WindowShade is an **independent Swift / AppKit implementation**, inspired by that interaction. It is not a continuation of Rob Johnston's code, Apple's implementation, or Unsanity's WindowShade X. The [original design and research notes](WindowShade.md) remain in the repository; the interactive essay carries later source corrections.

## Download

Get **WindowShade-v1.0.11.zip** from [Releases](https://github.com/surfine/WindowShade/releases/latest), unzip it, move `WindowShade.app` to Applications, and open it. It appears in the menu bar.

- **macOS 14+ · Apple Silicon.** The downloadable build is arm64; an Intel binary is not included.
- **Apple Development signed, not notarized.** If macOS blocks the first launch, use its **System Settings → Privacy & Security → Open Anyway** flow for the app you downloaded. Do not disable Gatekeeper.
- The bundle identifier and signing identity are retained for upgrades. macOS may still ask for permissions again depending on the installation and system state.
- Each release includes a SHA-256 checksum alongside the zip.

## Shortcuts

| Action | Shortcut / gesture |
| --- | --- |
| Fold or unfold the current window | `⌃⌘C` |
| Fold a specific window | Double-click its title bar |
| Restore a folded window | Double-click its strip |
| Preview a folded window | Hover; captured strips also reveal a preview on click |
| Pin or unpin the current window | `⌃⌘P` |
| Unfold by menu order | `⌃⌘1…9` |
| Arrange strips / focus layout | `⌃⌘0` |

## Permissions, recovery, and compatibility

**Accessibility** finds, moves, focuses, and restores windows. **Screen Recording** supplies captured strips, previews, and effects. Live preview is off by default and checks recording access when enabled. Window contents are processed locally on your Mac.

Before hiding a captured window, the app records recovery information. Restore checks and a persistent recovery journal help bring parked windows back after an interrupted session. Different apps need different hiding strategies, including offscreen placement, hiding, or minimizing; a strip is the visible interface to that work.

Ordinary desktop windows are the main target. Custom toolbars can still need application-specific handling; full-screen, Split View, Stage Manager, Adobe workspaces, and multi-display arrangements have compatibility limits. Captured toolbar artwork does not make every pictured button interactive. [Report a reproducible window case](https://github.com/surfine/WindowShade/issues) with your macOS version, app version, and steps.

The lid effect requires a supported hinge-angle sensor. Experimental tilt additionally requires the local AppleSPU accelerometer interface; unavailable hardware is shown as unavailable.

## Build and contribute

Requires macOS 14+, Xcode command line tools with the Metal compiler, and an Apple Development signing certificate.

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh --check   # Swift type checking and Metal compilation
./build.sh           # build and sign with your configured identity
open WindowShade.app
```

Set `WINDOWSHADE_CODESIGN_IDENTITY` or use an untracked `prototype/local-codesign.env`. This project uses a `swiftc` build script. See [DEVELOPMENT.md](DEVELOPMENT.md) for signing, isolated builds, and release instructions.

| In the repository | Purpose |
| --- | --- |
| [`prototype/`](prototype/) | Native app: window policies, capture, overlays, effects, and recovery |
| [`tests/`](tests/) | State, recovery, frame, Metal, and paper-component checks |
| [`site/`](site/) | Bilingual product site and interactive history, hosted on Cloudflare Pages |
| [`docs/performance.md`](docs/performance.md) | Measurements and approaches that did or did not work |
| [`docs/releases/`](docs/releases/) | Preserved release notes |
| [`WindowShade.md`](WindowShade.md) | Original design rationale and research notes |

For changes to window behavior, include the affected app and window type, what happened before and after, and the checks you ran. The existing compatibility and recovery boundaries matter more than a broad claim of support.

## Credits and license

[MIT](LICENSE) for this project's code. Historical names and software belong to their respective authors. The history experience credits [Infinite Mac](https://infinitemac.org/), Marcin Wichary's [Frame of preference](https://aresluna.org/frame-of-preference/), and [AI System 6](https://github.com/surfine/AI-System-6) for its era-rendering reference. Bundled font and reference-asset licenses are retained in [`site/public/fonts/`](site/public/fonts/).
