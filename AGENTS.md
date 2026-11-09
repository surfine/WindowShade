# WindowShade — agent instructions

macOS window utility (Swift/AppKit, macOS 15+), a web site under `site/`, and
promo/film work under `promo/`, `film/`, `video/`.

## Motion and performance red lines

Animate `transform` and `opacity` only; never animate layout properties
(width, height, top, left, margin). Do not read layout
(`getBoundingClientRect`, `offsetHeight`) inside a per-frame loop; batch reads
before writes. Motion never blocks input, and work longer than one frame
leaves the main thread. `will-change` is temporary and removed once the
animation ends. Honour `prefers-reduced-motion`.

Budget at p75 mobile: LCP ≤ 2.5 s, CLS ≤ 0.1, INP ≤ 200 ms. Report a
performance result only from a measured Lighthouse or Performance-panel run.

Before adding motion, answer three questions: should this move at all, is the
animated property composite-only, and does it stay smooth when interrupted.

## Skill routing

Load the named skill before starting the task, not after.

| Task | Skill |
| --- | --- |
| AppKit/Swift window behaviour, menus, drag, clipboard | `mac-arsed-mac-app` |
| Writing or reviewing Swift | `write-swift` |
| Apple platform UI review | `hig-ui-review` |
| Choosing a platform pattern | `hig-platforms`; colour/type/dark mode `hig-foundations`; onboarding/loading `hig-patterns` |
| Controls, toggles, sliders, text fields | `hig-components-controls` |
| Widgets, notifications, Live Activities | `hig-components-system` |
| Web site visual style | `design-taste-frontend`; polish `emil-design-eng` |
| Apple-style web motion | `apple-design`; implementation `animate` |
| Phone and touch behaviour | `mobile-native` |
| Worst-case data on a component | `break-ui` |
| Hard bug or a slowdown | `diagnosing-bugs` |
| Promo film | `windowshade-promo`, then `remotion-best-practices` and its `remotion-*` sub-skills |
| Video direction not decided yet | `motion-doctrine` |
| Stylised code film | `opuscar-plus`; style library `lemo-opuscar` |
| FFmpeg commands | `ffmpeg-apple-silicon` |
| Traditional Chinese (Taiwan) README | `zh-hant-localization` |
| Test strategy or plan | `testing-strategy` |
| Feature spec or PRD | `write-spec` |
| Reviewing a UI or a design | `design-critique` |
| UI microcopy, error text, empty states | `ux-copy` |
| Accessibility audit (WCAG) | `accessibility-review` |
| GitHub PR review comments | `gh-address-comments`; failing CI `gh-fix-ci` |

### Explicit request only

| Task (only when asked) | Skill |
| --- | --- |
| Turning existing photos or clips into a story film | `album-to-story` |
| A stylised art-animation segment | `huashu-art-motion` |
| A Hairline isometric line figure | `hairline-create` |

## Repo rules

`site/` is plain HTML/CSS/JS — no framework, no bundler. `Topit/` is the Xcode
project; build verification is `xcodebuild` against the scheme in
`Topit.xcodeproj`. Do not commit rendered media from `promo/`, `film/` or
`video/`.
