<h1 align="center">
  <img src="assets/app-icon/windowshade-app-icon.png" alt="WindowShade app icon" width="128"/><br>
  WindowShade
</h1>

<p align="center">
  <strong>A window is in the way, and you don't want to close it.</strong><br>
  A small macOS menu bar app that rolls windows up like a shade.
</p>

<p align="center">
  <a href="https://github.com/surfine/WindowShade/releases/latest"><img src="https://img.shields.io/github/v/release/surfine/WindowShade?style=flat-square&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square" alt="macOS 14+">
  <a href="README_CN.md"><img src="https://img.shields.io/badge/readme-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-blue?style=flat-square" alt="Simplified Chinese README"></a>
</p>

---

![The desktop folding as the lid closes](assets/windowshade-demo.gif)

WindowShade rolls a window's content into a slim strip that keeps its place, its title, and its one-click way back. It is not minimized and it does not go to the Dock: nothing you arranged on the desktop moves.

It fits the small moments — a reference document covering the draft you are writing, or a desktop that simply needs to be quieter for a minute without disturbing the layout.

## Three things

### Folding

`⌃⌘C` or a title-bar double-click rolls a window's content into a strip that keeps its place, its title, and its way back. Click the strip to preview, click again to open. `⌃⌘1…9` unfolds in menu order, and `⌃⌘0` tidies the strips or switches to a focus layout. Two styles (native capture or proxy title bar), with translucency, fold sounds, and launch at login.

### Pinned previews

`⌃⌘P` turns a window into an always-visible live preview. It follows its source window, drops to a lower frame rate while idle to save power, and suits references, mirrors, and dashboards.

### Dynamic effects

As the lid closes, the desktop or the window content rolls up, recedes, blurs, and unfolds again. Three finishes (Silk, Shade, Frost), an adjustable trigger angle, and a preview you can scrub. “Tilt with device” is experimental: a subtle parallax that follows how the machine is held.

## Settings

![The dynamic effects page in Settings](assets/windowshade-settings.png)

Effects, Shading, Permissions, and Advanced follow native macOS layout: three finishes (Silk, Shade, Frost), trigger angle, calibration, live preview, diagnostics, and reset-to-defaults. The menu bar carries the current window, the window list, and hinge-angle status. “Tilt with device” is experimental and adds a subtle parallax that follows how the machine is held.

## Shortcuts

| Action | Shortcut / gesture |
| --- | --- |
| Fold or unfold the current window | `⌃⌘C` |
| Fold or unfold a specific window | Double-click its title bar |
| Preview a folded window | Click its strip |
| Pin or unpin the current window | `⌃⌘P` |
| Unfold by menu order | `⌃⌘1…9` |
| Arrange strips / focus layout | `⌃⌘0` |

## Permissions and privacy

WindowShade uses two macOS permissions as needed, plus one experimental local sensor read:

- **Accessibility** — to find, move, focus, and restore windows.
- **Screen Recording** — to capture title bars, window previews, and the dynamic effects.
- **Apple Silicon accelerometer** — not a system permission. With “Tilt with device” enabled, the effect reads a local HID report; some models or security contexts report it as unavailable.

Live preview is off by default and only checks Screen Recording access when you turn it on. Window contents never leave your Mac.

## Compatibility

Most ordinary desktop windows work directly. Apps with custom title bars (Chrome, Electron) receive dedicated handling; full-screen, Split View, Stage Manager, multi-display, and sandboxed apps may need additional work.

Dynamic effects need a Mac whose hinge reports an angle (Apple Silicon MacBooks); device tilt additionally needs the system to expose the AppleSPU accelerometer.

## Download

Get the latest zip from [Releases](https://github.com/surfine/WindowShade/releases/latest), unzip it, and open `WindowShade.app`. It lives in the menu bar and does not show a Dock icon.

- Requires macOS 14 or later
- The signing identity is unchanged, so installing over an older copy keeps your Accessibility and Screen Recording grants

## Build from source

You need macOS 14+, Xcode command line tools, and an Apple Development certificate for signing.

```sh
git clone https://github.com/surfine/WindowShade.git
cd WindowShade/prototype
./build.sh
open WindowShade.app
```

To only check compilation:

```sh
./build.sh --check
```

Set the signing identity through `WINDOWSHADE_CODESIGN_IDENTITY` or a local untracked `prototype/local-codesign.env`. Build, test, and release details are in DEVELOPMENT.md.

## Project layout

Everything lives under `prototype/`, split by responsibility: `App/` for menus, settings, and the fold entry points, `Capture/` for screenshots and caching, `Effects/` for the dynamic effects and rendering, `Recovery/` for the restore journal and window rescue, plus `Overlay/`, `Window/`, `Compatibility/`, and `Private/` for the isolated private-API calls. Design background is in WindowShade.md.

## License

[MIT](LICENSE). The effects, sensor, and recovery paths are all implemented in this repository.
