# Contributing to WindowShade

Thanks for helping. WindowShade is a small, one-person project, so the most useful things are clear bug reports and focused pull requests.

**中文：** 欢迎用中文提 issue 和 PR。下面的规则中英文一样。

## Reporting a bug

Open a [bug report](https://github.com/surfine/WindowShade/issues/new/choose). Please include:

- the WindowShade version (Settings → Advanced → About) and your macOS version and Mac model;
- what you did, what you expected, and what happened instead;
- if it's about a specific app's windows, which app and version.

Settings → Advanced → About → Export diagnostics saves a folder on your Mac; nothing is sent automatically. Look through it before you attach it, and attach only if you're comfortable sharing it.

Questions and ideas go to [Discussions](https://github.com/surfine/WindowShade/discussions) rather than issues.

## Building

You need macOS 15 or later on Apple Silicon and the current Xcode. Then:

```bash
cd prototype
./build.sh --check
```

`--check` compiles with Swift 6 strict concurrency and warnings as errors, and runs the localization, privacy-registry and copy checks. CI runs the same command on every push. The full build, signing and release flow is in [DEVELOPMENT.md](DEVELOPMENT.md) (in Chinese).

## Pull requests

- Keep one change per pull request, and say what you checked (which command, which apps, which macOS).
- `./build.sh --check` must pass.
- User-facing text follows the [copy guide](docs/copy-guide.md): say what the user sees, not how it's implemented, and use one name for one thing. New strings go into `prototype/Localization/Localizable.xcstrings` in all three languages (简体中文, 繁體中文, English).
- Interface changes need a before/after screenshot.
- Behaviour that is on by default should have been tried on a real Mac, not only in tests.

By contributing you agree that your work is released under the [MIT License](LICENSE).

## Code of conduct

Be kind. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
