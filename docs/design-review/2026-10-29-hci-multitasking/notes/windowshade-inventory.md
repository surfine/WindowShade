# WindowShade window-management interaction inventory

Read-only research for an Apple HIG / "Designing Fluid Interfaces" review. Written 2026-10-29.

## 0. Sources, method, how to read

| Source | What was read | Notes |
|---|---|---|
| Code | `main` @ `9c3806c2` (checkout is an older branch). Extracted read-only with `git archive main prototype` to `.../scratchpad/research/main-src/`; **line numbers = `git show main:prototype/<path>`** | Vendor/ excluded. Nothing was built or run. |
| Docs | `/Users/aaron/Documents/WindowShade-internal/docs/*` (design-system, design-grammar, gestures, direction, copy-guide, window-browser, notch, dominance, windowshade-requirements-status, window-management-quality-progress, handoff/AARON-DECISIONS-2026-10-29, product-reshape-spec grep) | `gestures.md` has a banner line injected between every line, so its raw line numbers are inflated; **citations use the original file line numbers**. |
| Drafts | Text dumps in `.../scratchpad/drafts-text/` (收成缩略图, 手势分组 小样, 卷轴, 手边的每一样, 安静的刘海 动效样片, 卡住时刘海开口, WindowShade 设计系统 §六/§九, 首次打开 1.0.17 小样, 1.0.17 精简 小样) plus `docs/design-drafts/_errata.json` (the "这张稿之后又定了" boxes) | HTML was not rendered; visual shape/colour judgements are out of scope. Later decisions in `_errata.json` and `AARON-DECISIONS-2026-10-29.md` override the drafts. |

Conventions: **[code]** = `path:line` on main; **[doc]** = file:line; **[draft]** = draft name. "Default" = value when the UserDefaults key is unset. Spring tokens (Core/FlickMotion.swift:151-177): `calm` .34/ζ1, `settle` .38/ζ1, `expand` .40/ζ.92, `bloom` .42/ζ.84, `catchDrop` .40/ζ.80, `glide` .42/ζ.88, `flyOut` .38/ζ.90, `pull` .36/ζ.86, `pop` .30/ζ.75, `reducedNotch` .25/ζ1, `reducedWindow` .30/ζ1 (response seconds / damping ratio). Reduce Motion switch: `Motion.reduced` (App/Motion.swift:14).

Global default ledger (Core/ReleaseDefaults.swift:32-55): ON by owner decision 2026-10-17 (device-unverified): `Notch.enabled`, `Notch.changeAlerts`, `Notch.teach`, `Notch.activitiesEnabled`, `Notch.activities.musicEnabled`, `Notch.activities.nowPlayingStream`, `Notch.mergedRow`, `Notch.minimalPresentation`, `Notch.deviceBattery.enabled`, `Notch.levelKeys.enabled`, `FileShelf.enabled`, `Dock.clickToHide` (but origin-dependent, see W19), `WindowBrowserDockEnabled`. ON and device-verified: `SplitView.divider`, `MissionControl.keys`, `Switcher.trigger` (=⌥Tab). Everything not in the ledger is OFF when new. Not in the ledger but ON by their own code: 标题栏手势 (TrackpadGestures.swift:20-23), 双击标题栏收起 (WindowShade.swift:278-281), 看一眼 (Glance.swift:188-195), 窗口浏览键盘面板 (WindowBrowserSettings.swift:75-80). OFF by their own code: 收起窗口时的动画 (Effects/EffectSession.swift:206,214), 拖到窗口上并排 (App/DropSplitRun.swift:10-13), Dock 图标上两指滑 (App/DockSwipe.swift:19-22), 卷轴里拖标题栏换位置 (Core/ScrollStrip.swift:888-899), 卷轴概览拖进刘海 (App/ScrollStripRun.swift:538-539), 中键/三指/四指 (App/WS2InputPreferences.swift:5-14).

**New installs have zero global shortcuts** (App/GlobalShortcuts.swift:162-190: `factoryHotKey` returns nil unless the install is an upgrade from ≤1.0.15 or a 1.0.16 preview). ~41 actions are recordable (GlobalShortcuts.swift:9-60).

---

## 1. Index (one row per interaction)

"Alt" = a keyboard/menu route that exists **out of the box** for a new install. "Live" = the user sees the outcome change *while* the gesture is in progress.

| ID | Interaction (UI term) | Primary inputs | Default | Alt out of box | Live feedback while moving |
|---|---|---|---|---|---|
| W1 | 收起窗口 / 展开窗口 (collapse to 卷帘条) | double-click title bar; 2-finger up/down; wheel; menu; strip double-click | ON (anim OFF) | menu only | partial: HUD + window rolls (needs Screen Recording) only for 2-finger/wheel |
| W2 | 卷帘条 (the strip itself) | click, double-click, drag, hover, green-button hover | ON | menu "已收起的窗口▸" | n/a |
| W3 | 缩略图 (collapse appearance) | same as W1, setting "收起后的样子" | OFF (strip is default) | menu | no |
| W4 | 看一眼 (peek) | hover 0.20 s, click, 2-finger pull, Force Touch, notch tile hover | ON | none | yes for pull; otherwise time-based |
| W5 | 收进刘海 / 放回 | flick up through notch, island slot, menu, notch push-up/pull-down/spread, shake | ON (Notch.enabled) | menu "收进刘海", "全部收进刘海" | island yes; push-up/spread no |
| W6 | 落点小岛 (drop island) | drag title bar toward notch | ON | none | yes (island + haptic) |
| W7 | 标题栏手势 (2-finger swipe/pinch/spread/wheel/smart-zoom) | trackpad, Magic Mouse, wheel | ON | none (shortcuts unassigned; no half/fill in menu) | HUD bar yes; window preview only for collapse/expand |
| W8 | 甩一下标题栏 (flick) | drag + fling title bar | ON (inside 标题栏手势) | none | no (result HUD after release) |
| W9 | 晃一晃 (shake) | drag + shake | ON (inside 标题栏手势) | none | no |
| W10 | Snapping: 半屏/三分/四角/网格/九等分 + keyboard ladder | swipe L/R(+turn), flick, shortcuts, island | ON | none by default (recordable) | HUD only; window teleports on commit |
| W11 | 魔法平铺 | spread; menu; island slot | ON | menu "魔法平铺" (in 整理▸) | HUD bar; result teleports |
| W12 | 卷轴 + 卷轴概览 | auto after 魔法平铺 overflow; 2-finger L/R on strip windows; spread | ON (implicit) | menu "卷轴概览" | yes (strip follows finger; overview follows spread) |
| W13 | 分屏把手 | drag 28×160 handle | ON | none | yes |
| W14 | 拖到窗口上并排 | drag title bar onto another window | OFF | none | none ("没有预览") |
| W15 | 画中画 | drag to corner (dwell), menu, shortcut, controls | ON (no toggle) | menu "画中画" | yes (ghost + 1:1 drag) |
| W16 | 侧拉 | drag to edge (dwell), menu, flick, handle | ON (no toggle) | menu "侧拉当前窗口" | yes (glass sliver + ghost) |
| W17 | 窗口浏览 (Dock hover; 选择窗口…) | Dock hover 0.25 s; menu | Dock hover ON | menu "选择窗口…" | n/a |
| W18 | 按窗口切换 (⌥Tab) | ⌥Tab | ON (⌥) | it is the keyboard route | panel |
| W19 | 让开这个 App (Dock click) + Dock swipe | re-click Dock icon; 2-finger swipe on icon | click: ON for Mac/unanswered, OFF for Windows/iPad; swipe OFF | none | none (swipe: "没有浮窗") |
| W20 | 调度中心里 ⌘W/⌘Q | ⌘W/⌘Q in Mission Control | ON | n/a | n/a |
| W21 | 带到每张桌面 | menu, shortcut | no toggle | menu | n/a |
| W22 | 刘海本体 (click ×1/2/3, long-press, hover, push/pull/swipe/pinch) | pointer + 2-finger | ON | partial | pull-down only |
| W23 | 启动台拖出图标到区域 | drag icon out of Launchpad | ON (launchpad) | n/a | yes (zone highlight) |
| W24 | 撤销上次排布 | pinch, ⌃⌘↑ on filled, shortcut | ON | recordable only | HUD |
| W25 | Keyboard shortcut set | see record | none by default | — | — |
| W26 | Menu-bar menu | click status icon | ON | — | — |
| W27 | Teaching/onboarding | coach tips, habit hints, welcome, explainer bands | ON | — | — |

---

## 2. Detailed records

### W1 收起窗口 / 展开窗口 (collapse to the 卷帘条, expand back)

| Field | Evidence |
|---|---|
| Inputs / device | (a) **double-click title bar** (mouse or trackpad tap-tap), default ON, swallowed by an active event tap so the system zoom/minimize never fires; the **third click** performs the system action (settings text "三击标题栏会缩放窗口", App/WS2SettingsInfo.swift:248-249; App/EventTapCallback.swift:84-96). Any held modifier (⌥ ⌘ ⇧ ⌃) skips (EventTapCallback.swift:65-74) although docs/UI only say "按住 Option". (b) **two-finger up** on title bar (filled window: first undoes the fill) / **down on the strip** (Core/TrackpadGesture.swift:395-404, 417). (c) **wheel**: 24 pt per notch, 3 notches arm, 0.3 s quiet ends (TrackpadGestures.swift:45-46; gestures.md:367). (d) smart-zoom double-tap on strip = expand (TrackpadGesture.swift:430-439). (e) menu 收起窗口/展开窗口 (MenuBarController.swift:124, 386-394). (f) recordable shortcut `toggleShade`; ⌃⌘↑/⌃⌘↓ ladder (GlobalShortcuts.swift:10, 17-18). (g) middle-click / 3-finger tap / window-browser button: OFF or unverified. |
| Feedback while moving | Two-finger/wheel only: HUD 290×63 glass pill 10 pt under the title bar (GestureHUD.swift:129, 256-267) with 1:1 progress bar; **the real window also rolls under the fingers** via a cover plate (0.55 rolled at arm, fully rolled at ≈1.8× threshold; TrackpadGestures.swift:52, 1097-1099; gestures.md:304). Needs Screen Recording and Reduce Motion off (Effects/WindowFoldEffects.swift:47-51, 64-71). Armed: bar turns accent, end icon `pop`, haptic `.alignment` (TrackpadGestures.swift:979-981; GestureHUD.swift:448-456). Double-click: no HUD. |
| End-of-gesture decision | Direction locks after 10 pt, a new direction needs 1.25× (TrackpadGesture.swift:444, 454); arm at 56 pt; release = distance + velocity projection `v/1000·r/(1-r)`, r=.99 (≈ v×0.099 s, last 50 ms) must reach 56 pt; ≥18 pt travel (TrackpadGesture.swift:446, 452, 460, 462, 540-560, 681-684). Same direction again within 0.6 s is ignored (TrackpadGestures.swift:49, 1115-1118). Double-click: system double-click interval; tap decision times out at **500 ms and then passes the click to the app** (EventTapCallback.swift:51, 105-118). |
| Animation | Roll: `FoldTransition` critically damped, **fold = `settle`, unfold = `calm`** (Effects/FoldDriver.swift:70-95). Only with 设置→效果→"收起窗口时的动画" **ON (default OFF: EffectSession.swift:206,214)** and Screen Recording; otherwise the collapse is a swap with no roll. Finger-follow ignores that toggle (WindowFoldEffects.swift:43-51). Strip then fades in ~0.12 s (Notch.swift:918-919 comment). Reduced motion: no follow, HUD only; `Motion.fadeDuration` elsewhere. |
| Interruptible? | Finger phase: yes (pull back or change direction → cover returns, real window never touched; TrackpadGestures.swift:1109-1113; WindowFoldEffects.swift:523-532). After release: the roll spring can reverse internally, but **new gestures are ignored while the window is settling** (`isSettling`, TrackpadGestures.swift:931-936). Duplicate fold requests deduped (ShadeController.swift:243-248). |
| Undo / recover | Expand via strip (double-click, 2-finger down, ⌃⌘↓, menu 已收起的窗口▸, notch row, window browser). Collapse is **not** in the 撤销上次排布 ledger (ledger = frames only; TrackpadGestures.swift:2130-2147). |
| Keyboard / menu alt | Menu item always; shortcut unassigned for new installs (GlobalShortcuts.swift:162-190). |
| Discoverability | Welcome A1 makes the user practise double-click (App/WelcomeFlow.swift:1-60); coach tip `.shade` "两指上推收起" (Core/GestureCoach.swift:29, 71); settings explainer bands; HUD labels. |
| Accessibility | Strip = group "WindowShade 卷帘：<app — title>", help "双击展开窗口…", custom action 展开窗口, VO-press = expand (Overlay/SystemAppearance.swift:403-411; ShadeStrip.swift:579-597). HUD posts a VoiceOver announcement **only after commit** (GestureHUD.swift:183-184, 203-205). Status item value "N 个收起的窗口" (SystemAppearance.swift:415-419). |
| Default | Double-click ON; 标题栏手势 ON; animation OFF. |
| Known gaps | (1) The system double-click action is displaced to the 3rd click; on timeout (>500 ms main-thread decision) the first double-click can still zoom the window (log string "titlebar-tap: decision timed out", EventTapCallback.swift:113). (2) The signature "roll" motion is absent by default (animation OFF) and silently needs Screen Recording. (3) The same collapse reached by menu/shortcut/double-click has no HUD feedback, by 2-finger has HUD+roll. (4) Draft says up = collapse everywhere, but flick-up near the notch tucks instead (W5/W8). |

### W2 卷帘条 (the collapsed strip)

| Field | Evidence |
|---|---|
| Inputs | **single click = peek (看一眼) immediately**, **double-click = expand**, drag = move strip, hover = full-title tooltip when truncated (ShadeStrip.swift:517, 599-620). Hover on the green button 0.55 s forwards the system window-management popover to the real window (ShadeStrip.swift:376-392). ⌘N/⌘H/⌘M/⌘Q/⌘W typed while the strip is key are forwarded to the app behind (ShadeStrip.swift:105-123, 186-190; Thumbnail.swift:34-36). Pointer on the green button at appearance must leave once before hover forwarding re-arms (gestures.md:819-825 region; NativeProxyOverlayWindow). |
| Feedback | Hover highlight; peek card; no cursor change recorded. |
| Decision | Click = open peek now (Core/GlanceIntent.swift `clicked`); double-click interval = system. |
| Animation | Install fade ~0.12 s; reduce motion → `fadeDuration`. |
| Interruptible | n/a (discrete). |
| Undo | Expand (double-click / menu / ⌃⌘↓ / notch row). |
| Keyboard / menu | Strip windows can become key and forward ⌘N/⌘H/⌘M/⌘Q/⌘W to the app behind (ShadeStrip.swift:105-123, 186-190), but no Tab/arrow route to *reach* a strip without the mouse was found. Menu 已收起的窗口▸ lists up to 9 with ⌃⌘1…9 only for upgraders, rest in "更多收起的窗口（N）" (StandardMenu.swift:61-80; MenuBarController.swift:170-200). |
| Accessibility | See W1. Classic-style strips expose 3 child buttons (关闭/缩放/展开) (ShadeStrip.swift:705-792); real-device VoiceOver/FKA traversal still "待验收" (window-management-quality-progress.md "后续工作" item 3). |
| Default | ON. |
| Known gaps | Single click opens a peek rather than restoring (differs from thumbnail W3 where single click expands, Thumbnail.swift:9-10, and from Dock/minimized-window convention). Copy conflict: VoiceOver says "卷帘" while the glossary mandates "卷帘条" (copy-guide.md fixed-vocab row 25; SystemAppearance.swift:406). |

### W3 缩略图 (collapse appearance = thumbnail)

| Field | Evidence |
|---|---|
| Inputs | Setting 收起后的样子: 跟原来一样 / 统一标题栏 / 缩略图 (App/CollapseAppearanceSettings.swift:13-18). Collapse inputs are W1's. Hover 0.22 s (comment) → peek; **single click expands**; press-drag moves; menu "整理缩略图 / 恢复缩略图原位" (⌃⌘0 only for upgraders). |
| Feedback | Strip replaced by an in-place small picture; screenshot flies into it with `settle` (no bounce); hover makes it opaque, card grows to original size with live frame (Thumbnail.swift:1-25). |
| Decision | Dwell; click. Opacity slider 0-70% (ShadeTranslucency.swift:13-19), forced opaque with Reduce Transparency. |
| Animation | `settle` collapse, expand flight .38/.1; reduced → fade, no flight (Thumbnail.swift:335-337, 365-369, 553, 760-765). |
| Interruptible | Click mid-flight not specified. |
| Undo | Click / menu. |
| Keyboard | menu only. |
| Accessibility | VO name "展开窗口：<app>" (WindowShade.swift:700). |
| Default | OFF (strip is default; draft 收成缩略图 option A recommended, Aaron chose A 2026-09-29, direction.md:93-98). |
| Known gaps | Word collision: 缩略图 = this collapse mode **and** the window-browser grid style (WindowBrowserSettings.swift:44-48). Code comment still cites 0.22 s dwell while GlanceIntent.swift:19 is 0.20 (design-grammar.md:281 acknowledges). Header comment cites ⌃⌘0 (default no longer assigned). |

### W4 看一眼 (peek)

| Field | Evidence |
|---|---|
| Inputs | Pointer dwell on strip/thumbnail/carry strip; click; **2-finger pull-down on the strip** (card unrolls under the fingers; release early = stays as peek, release full = expand) (TrackpadGestures.swift:1041-1063, 1102-1107; gestures.md:568); **Force Touch stage 2 while held** (TrackpadGestures.swift:1775-1811); hover a notch-row tile 0.20 s (Motion.swift:37); scroll-strip edge sliver 0.3 s (draft 卷轴). |
| Feedback | Card grows at the window's own place/size; first shows the stored "收起时的画面", live stream swaps in; "不是实时画面" label for minimized/hidden/other-desktop/slide-over cases (copy-guide.md rows 36-37). |
| Decision | `intentDelay` 0.20 s, `leaveGrace` 0.16 s, menu handoff 1.2 s (Core/GlanceIntent.swift:19-23). |
| Animation | Roll down/up via `pull`/`settle` tokens (Overlay/GlancePanel.swift:232-310, 395); draft 收成缩略图 cites 卷下 0.18 / 卷上 0.14 s; reduced → fade (`Motion.Spring.reducedNotch.response`) (GlancePanel.swift:234-262, 375-382, 407-412, 439-444). |
| Interruptible | Yes: moving to another strip switches without closing (GlanceIntent.swift `sample` .open→.arming); leaving cancels after 0.16 s. |
| Undo | Move away. |
| Keyboard / menu | **None** (hover/click/gesture only). |
| Accessibility | Card is an image element "看一眼：<title>", help "单击打开这个窗口", `accessibilityPerformPress` opens it (GlancePanel.swift:108-137). |
| Default | `GlanceEnabled` ON (Glance.swift:188-195). |
| Known gaps | Peek is the only way to look without restoring, yet it has no keyboard route. Docs/drafts still say 0.22 s (glance.md, motion-direction.md, 收成缩略图 draft) vs code 0.20. |

### W5 收进刘海 / 放回 (tuck into the notch, put back)

| Field | Evidence |
|---|---|
| Inputs | **Tuck**: (a) flick title bar **upward on a path that crosses the notch slot ±80 pt** (Notch.swift:628-636; TrackpadGestures.swift:1658-1664) — otherwise the same flick collapses in place; (b) release on the island centre slot (W6); (c) menu "收进刘海" for the focused window (MenuBarController.swift:125-127; Notch.swift:1623-1641, refusal text "这个窗口收不进去"); (d) 全部收进刘海 (menu, `tuckAll`, shortcut unassigned) (Notch.swift:1643-1670); (e) **2-finger push-up on notch (>60 pt)** = tuck all on that screen (Notch.swift:5558-5560, 524-540); (f) **spread on notch (>0.18) = the same `.back` → tuck all** (Notch.swift:5575-5586); (g) shake (others) (W9); (h) Launchpad icon drop on notch (LaunchpadModel.swift:195); (i) strip-overview drag (OFF by default). **Put back**: hover notch 0.12 s → row of ≤8 tiles → click a tile (flies out); 2-finger pull-down (taken if distance>12 and projected>70, r=.99; Notch.swift:3929-3950); repeat 全部收进刘海; shake again. |
| Feedback | Window screenshot flies to the notch centre with release velocity, hidden by the camera housing, island "swallow" pulse (Notch.swift:866-873); compact ears show last app icon + count (≥26 pt free on both sides else a 8-pt chin of dots) (notch.md:24-34); toast "收进了 N 扇 / 两指往下拉刘海，整批拿回来" (Notch.swift:1660-1666); failure texts "收起状态未确认" (Notch.swift:888-890). Push-up/spread have **no feedback during motion**. |
| Decision | Aim test; island release; push-up = |travel|>60 pt with no velocity projection; pull-down uses projection. |
| Animation | Into notch `settle` (no bounce, target is a hole); out `flyOut` with `rowCollapseLag`; island morph via `Motion.notchSpring` (Motion.swift:112-122); Reduce Motion: no flight, cross-fade (Notch.swift:989-992; design-system.md:518). |
| Interruptible | Before release yes. **After release the flight cannot be cancelled** (`fly` has no cancel path, Notch.swift:2246-2262); draft "半路打断：没松手前改方向，窗口跟手回来" (WindowShade 设计系统.html §六) is only true before release. |
| Undo / recover | 放回 (above). Not part of 撤销上次排布. Hidden state: the tucked window's strip is kept at alpha 0 and mouse-transparent (Notch.swift:918-944) so it is reachable only through the notch. No-notch screens: only a 190-pt "invisible notch" slot at menu-bar centre; row stays closed when nothing is tucked (design-system.md:521-526; Notch.swift:1048-1054). |
| Keyboard / menu alt | Menu: 收进刘海, 全部收进刘海 (in 整理▸). Shortcuts none by default. Notch row keyboard focus (`notchShelf`) unassigned by default. |
| Discoverability | Coach `.notchHome` ("点刘海回主屏幕 / 两指往上推…", GestureCoach.swift:49, 68) the first time the pointer rests on an empty notch (Notch.swift:1053); post-hoc toast after tuckAll. |
| Accessibility | Notch has 37 a11y/ 30 Reduce-Motion references (Notch.swift). Tile-level VO names not inspected in detail. |
| Default | `Notch.enabled` ON (owner decision), device-unverified (ReleaseDefaults.swift:34). When OFF, shake/others collapse to strips instead (MagicTilingRun.swift:253-263). |
| Known gaps | (1) Spread on notch tucks everything (undocumented: notch.md:47 only says pinch→home). (2) `.back` means *navigate back* when the Launchpad is showing but *tuck all* otherwise (Notch.swift:516-530). (3) design-system.md:511,519 itself lists single-window tuck without keyboard/menu as a gap (now menu exists; shortcut still unassigned). |

### W6 落点小岛 (drop island)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar toward the notch (mouse or trackpad drag). Visible after **10 pt** of travel (Core/MagicTiling.swift:244-247), "offered" inside the zone inflated by (-140, -160), "armed" inside the 340×84 pt zone under the notch, **5 slots × 68 pt: 左半屏 / 铺满屏幕 / 收进刘海 / 魔法平铺 / 右半屏** (Notch.swift:2439-2459, 2904-2908, 2925-2931). |
| Feedback | Island hangs down (`catchDrop`), slot symbols + titles, armed slot ringed in accent; haptic `.alignment` on arm and on slot change (Notch.swift:3802-3813); slots that cannot fit the window's minimum size are greyed (Notch.swift:2912-2923). Release: check-mark + haptic `.levelChange`, 0.55 s hold (Notch.swift:3666-3680). |
| Decision | Pure position at release; speed ignored (TrackpadGestures.swift:1500 "不看快慢"). Release on a greyed slot = cancel. |
| Animation | `catchDrop` (initial velocity "现在否" per design-system.md:344); reduced `reducedNotch`; haptic skipped when reduced only for strip landing (Notch.swift:3821). |
| Interruptible | Yes until release: leave the zone and the island retracts (`calm`); the window stays in the hand. |
| Undo | Halves/fill/magic enter the placement ledger (W24); tuck → 放回. Releasing outside = nothing happens. |
| Keyboard / menu alt | None for the island itself; each slot has a menu/shortcut counterpart (tuck, magic tile) except halves/fill which have no menu item. |
| Discoverability | No dedicated coach tip; learnt by dragging toward the notch. |
| Accessibility | Pointer-drag only; no VO/Switch Control route (counterparts only through shortcuts that are unassigned by default). |
| Default | ON, but lives inside the 标题栏手势 monitor (App/TrackpadGestures.swift:219-249), i.e. **turning 标题栏手势 OFF also removes the island, slide-over/PiP drop hints, flick and shake**. |
| Known gaps | Not offered during resize drags or file drags (file drags get their own 3-slot island, Notch.swift:643-662). Colour/fill of the armed state has a pending design change (design-system.md §6-2). |

### W7 标题栏手势 (two-finger swipe / pinch / spread / wheel / smart-zoom on a title bar)

| Field | Evidence |
|---|---|
| Inputs | Trackpad 2-finger swipe (Magic Mouse 1-finger swipe is the same event), pinch/spread (read-only event tap, separate thread: TrackpadGestures.swift:2239-2268), wheel (3 notches), smart-zoom double-tap (2-finger trackpad / 1-finger Magic Mouse) toggles 铺满 ⇄ 还原 (TrackpadGesture.swift:430-439). **Map** (TrackpadGesture.swift:389-404): up = collapse (or undo fill), down = 铺满 (not if already filled), left/right = ladder (½→⅔→⅓→neighbour screen), turn after a full L/R = corner/grid/ninth, spread = 魔法平铺, pinch = 撤销上次排布. Scroll-strip window: vertical = column width ladder (:409-414). Strip: down only (:417). |
| Feedback | HUD pill anchored 10 pt under the title bar, 290×63, fixed radius 24, start icon → end icon, 1:1 fill that always runs in the finger's direction; armed = accent + `pop` + haptic; unavailable actions still show with an explanation instead of silence (TrackpadGesture.swift:366-370). For 左/右/角/平铺 there is **no window outline or window motion**, only the bar; only collapse/expand also move the real window (TrackpadGestures.swift:1065-1099). |
| Decision | Zone: coarse band ≤160 pt below the window top (WindowServer), then **async AX confirmation** (nothing shows or executes before it returns): not over scrollable content, inside the title-bar height (gestures.md:1162-1200; TrackpadGestures.swift:43, 535-745). App-owned directions yield (Safari tabs: left/right to Safari; whole swipe ignored if the first direction was the app's: TrackpadGesture.swift:738-760; gestures.md:1045-1095). Arm 56 pt; turn needs 44 pt of vertical after arming with ≥1.2× dominance (TrackpadGesture.swift:448-450); spread/pinch arm at 0.22 cumulative, minimum 0.08, hysteresis 0.03 (:456-458). Release uses projection r=.99 and last 50 ms (:460-462). Swish running = title-bar gestures yield (TrackpadGestures.swift:33-40). |
| Animation | HUD fade in 0.12 s (0.08 if already visible), hold 0.45 s + 0.2 s fade after commit, 1.4 s when a note is added, cancel 0.15 s (GestureHUD.swift:169-171, 195-222); `pop` ζ.75 on the end icon; none of the left/right/fill/magic results animate: **frames are set instantly (AX size+position written twice)** (TrackpadGestures.swift:1913-1932, 2044-2049), unlike a flick landing (W8). |
| Interruptible | Yes: pull back to start or reverse; new direction must beat old by 1.25×; cancelled sessions leave the window untouched. Same-direction repeat inside 0.6 s ignored. Gestures ignored while a window is settling. |
| Undo | Pinch; ⌃⌘↑ on a filled window; shortcut 撤销上次排布; "没有可撤销的排布" HUD when empty. |
| Keyboard / menu alt | Ladder via ⌃⌘←→↑↓ **only for upgraders**; new installs: record in Settings→快捷键 (menu has no 左/右半屏/铺满/撤销). HUD shows "keyboard hit" identically. |
| Discoverability | Coach `.halves`, `.magic`, `.shade` (3 shows, 300 s apart, used→never again; GestureCoach.swift:13-40, 82-86); settings page 手势 with a 手指 line per row and a read-only mapping table (App/WS2GestureRows.swift:1-55; draft 手势分组 小样); Welcome T-page segment 手势与卷轴 (draft 首次打开 1.0.17 小样 line 94). |
| Accessibility | HUD: VO announcement after commit only; haptic is the only non-visual armed signal and is unconfirmed for a background app (gestures.md:1096-1160 note). Magic Mouse has no haptics; relies on colour change (gestures.md:169-172 region). Reduce Motion: no crossfade/pop. Reduce Transparency: opaque pill. Increase Contrast: border `labelColor` (design-system.md:571). |
| Default | 标题栏手势 ON (TrackpadGestures.swift:20-23). |
| Known gaps | (1) Feedback gated on async AX verification (latency not measured here). (2) No target preview for halves/thirds/corners/ninths although the window browser draws a dashed outline for the same targets (window-browser.md "拖到屏幕边"). (3) The corner "turn" is a hidden 2-stage gesture (arm → turn 44 pt) taught only by coach/docs. (4) Direction semantic reversed vs Swish/iPad (up = collapse, not maximize) by design (gestures.md:208-210, 670). |

### W8 甩一下标题栏 (flick)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar (mouse; 3-finger-drag trackpad; direct touch assumed for future) and fling, lift = lift decision. Release speed ≥ 1400 pt/s (900 for direct touch), ≥65% of the drag's peak, direction within 30° of an axis = ladder step; 30-60° = corner (Core/TrackpadGesture.swift:273-318, Core/FlickMotion.swift:89-91 (65% of peak) and 100-129). |
| Feedback | None before release except the drop hints (island / slide-over / PiP). After release: the window **glides** (spring) to the target and the HUD names the result at the target's title bar (TrackpadGestures.swift:1676-1683). |
| Decision | `judgeFlick`: ≥0.08 s, ≥3 samples, window followed ≥50% of the pointer, size unchanged, not within 3 pt of a screen edge (system edge tiling owns that), 3-finger repositioning ignored (TrackpadGestures.swift:1564-1617). Upward fling through the notch = tuck, else = collapse; flick on a Slide-Over window toward its edge = stash. |
| Animation | `WindowGlide`: position `glide` (.42/.88) carrying release velocity, size zero-velocity `settle`, 120 Hz position / 60 Hz size, overshoot ≤28 pt; slow apps (>25 ms/move) or still-open drags use a screenshot proxy glide (TrackpadGestures.swift:1690-1710; FlickMotion.swift:151-177, 189-194). Reduce Motion: `reducedWindow` .30/ζ1 **still slides the real window** (Motion.swift:126-130) although design-system.md:349 says reduced = fade. |
| Interruptible | Yes: grabbing the gliding window stops it at the current place (TrackpadGestures.swift:1236-1243); undo goes back to the pre-grab frame. |
| Undo | Pinch / shortcut; ledger stores the pre-drag frame. |
| Keyboard / menu alt | The ladder shortcuts (unassigned). |
| Discoverability | Docs only; no coach tip (`CoachTip` list has none for flick). |
| Accessibility | Pointer-only; HUD announces after the fact. |
| Default | ON inside 标题栏手势. |
| Known gaps | No pre-release preview of the landing cell; the same destination glides here but teleports for swipe/keyboard (W7/W10). |

### W9 晃一晃 (shake)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar and shake: ≥3 reversals within 0.8 s, each leg ≥28 pt, path ≥2.5× net displacement; **works on both axes** (Core/WindowShake.swift:10-46) although docs say 左右 (gestures.md:556). |
| Feedback | Nothing until the 3rd reversal fires; then other windows on this screen fly into the notch (or become strips when the notch is off) and the notch says "别的 N 扇收进了刘海 / 拖着它再晃一下，都放回来" (MagicTilingRun.swift:229-268). |
| Decision | Discrete detector; one shake per drag (`shook`), the drag then no longer counts as a flick (TrackpadGestures.swift:1295-1301). |
| Animation | tuck flights (W5). |
| Interruptible | No. |
| Undo | Shake again **with the same keeper window** while its away set is still tucked/strip'd (MagicTilingRun.swift:233-241); shaking a different window overwrites the remembered set (`shaken`), so the first batch must be restored from the notch. |
| Keyboard / menu alt | None (the nearest is 全部收进刘海, which also hides the front window). |
| Discoverability | Coach `.shake` ("试试晃一晃标题栏") (GestureCoach.swift:19, 66). |
| Accessibility | Gross-motor gesture, no alternative; Reduce-Motion: tuck flights become fades. |
| Default | ON, no separate toggle. |
| Known gaps | Accidental trigger risk while dragging; hidden per-keeper state; same-app non-minimizable windows silently stay (gestures.md:556-566). |

### W10 Snapping: 半屏 / 三分之一 / 三分之二 / 四角 / 网格 / 九等分, and the keyboard ladder

| Field | Evidence |
|---|---|
| Inputs | 2-finger L/R on a title bar; L/R then **turn** up/down after arming (corners, ≥44 pt vertical, ≥1.2× dominance) (TrackpadGesture.swift:243-267, 448-450); flick (W8); island slots 左半屏/右半屏/铺满 (W6); keyboard ladder ⌃⌘←→↑↓ (upgraders only) incl. 0.8 s "key turn" for corners (TrackpadGesture.swift:96-107); recordable per-cell shortcuts (halves, thirds, ⅔, quarters, fill, centre, larger/smaller, 上/下半屏, previous/next display) (GlobalShortcuts.swift:9-60); one-click presets "用 Rectangle 的快捷键" (⌃⌥ set) and "方向键换成字母" WASD/IJKL/HJKL (gestures.md:718-855); Launchpad icon drop (W23); window-browser card menu 排布▸. Ladder: ½ → ⅔ → ⅓, push again = neighbour screen (landing on the shared half), ⅓ then walks centre→right; inside a top/bottom row the same ladder is the 3×2 "网格"; a sixth + turn = 3×3 "九等分" (TrackpadGesture.swift:206-267). System drag-to-edge tiling is deliberately **not** replicated (gestures.md:712). |
| Feedback | HUD pill with window glyph → target glyph; no outline of the target cell; windows **teleport** on commit (AX set size+position twice, TrackpadGestures.swift:1913-1932, 2044-2049). Fixed-size / min-size windows are centred in the cell with the note "这个窗口不能改大小，放在了正中" (TrackpadGestures.swift:1919-1930). A window that is collapsed/tucked/PiP/hidden-slide-over refuses with "先展开这扇窗 / 先把这扇窗从刘海放回来 / 先让这扇窗回到原处 / 先拉出侧拉的窗口" (TrackpadGestures.swift:886-893). |
| Decision | W7 thresholds; keyboard = instant; same ladder for all inputs so the result depends on the window's *current cell* (`ScreenTile`), recognised within 4 pt tolerance (TrackpadGestures.swift:962-965). Gaps between tiles from 设置→卷帘→排布: 不留/窄 8/宽 16 (ArrangeGap; gestures.md:535). |
| Animation | None for swipe/keyboard/menu; `glide` only for flick (W8). HUD per W7. |
| Interruptible | Pre-commit yes. Post-commit n/a (instant). |
| Undo | One slot per window `undoRecords[id]`; invalid as soon as the window was moved by hand (`canUndoPlacement`, TrackpadGestures.swift:943-952); pinch, ⌃⌘↑ on filled, shortcut. After a display change, placed windows are re-fitted to the same layout after 1.5 s, only if their size was untouched (gestures.md:331-353). |
| Keyboard / menu alt | **No menu items** for halves/thirds/corners/fill/undo in the status menu (MenuBarController.swift:118-243). Shortcuts unassigned by default (GlobalShortcuts.swift:162-190). |
| Discoverability | Coach `.halves` ("试试两指左滑"), `.rectangle` ("换成熟悉的键位"); stuck-habit rules for Windows/iPad habits (HabitRules; stuck-habits.md); settings 手势 page. |
| Accessibility | HUD VO announcement after commit; nothing during. Keyboard route exists but only after the user records a key. |
| Default | Inside 标题栏手势 ON; keyboard none. |
| Known gaps | (1) V5 claim "每个手势都有菜单或快捷键可以代替" (design-system.md:397) and "菜单和设置里每个动作都还在、都能录" (gestures.md:595) are true only for *recordable* shortcuts; nothing works out of the box and the menu has none of these. (2) "↑" = collapse differs from Rectangle/Swish/iPad "maximize" (documented choice, gestures.md:208-210, 670). (3) Same target, instant on swipe but glided on flick. |

### W11 魔法平铺 (Magic tile)

| Field | Evidence |
|---|---|
| Inputs | Spread on a title bar (0.22 cumulative arm); menu 魔法平铺 (in 整理▸); recordable shortcut (⌃⌘M only for 1.0.16-preview users); island slot (W6). |
| Feedback | HUD bar while spreading; on commit a one-line HUD summary (e.g. "5:5 …") (MagicTilingRun.swift:149-156); windows jump to their cells. |
| Decision | Main window = the one under the gesture (menu/shortcut: rule-based pick, front window gets a bonus); role by app category decides share 5:5 / 6:4 / 7:3 (side column <420 pt steps down a share), chat apps → Slide Over, overflow → scroll strip if both screen sides are free, else tucked into the notch; only standard, non-full-screen windows ≥240×160, max 12 candidates (MagicTilingRun.swift:44-70; gestures.md:439-477). |
| Animation | None (instant frames). |
| Interruptible | Pre-release yes (HUD only). |
| Undo | **Pinch any arranged window = whole batch back** (tucked ones released, slide-over exited, strip stopped) (MagicTilingRun.swift:200-218). Single windows moved by hand are skipped so new arrangements are never overwritten. |
| Keyboard / menu alt | Menu 魔法平铺. |
| Discoverability | Coach `.magic` and a "fiddle" rule (3 manual moves in 60 s, GestureCoach.swift:85-86). |
| Accessibility | HUD VO after commit. |
| Default | ON (no toggle). |
| Known gaps | Opaque automation: the app-category rules and what goes to Slide Over / notch / strip are not visible or adjustable before commit; no preview. |

### W12 卷轴 (scrolling strip) and 卷轴概览

| Field | Evidence |
|---|---|
| Inputs | **Implicit entry**: 魔法平铺 overflow turns the extra windows into columns parked off-screen right (only when both screen sides are free; not portrait; gestures.md:478-534; MagicTilingRun.swift:143-185). 2-finger L/R on any strip window's title bar scrolls the whole strip 1:1 (rubber band c=.55 at the ends, release projection, snaps to a column edge); up/down = column width ⅓/½/⅔/整屏, narrowest + up = collapse; **spread on a strip window = 卷轴概览** (whole strip scaled to ≤0.5; click a window to pull its column in; ←→, Return, Esc); ⌃⌘←/→ moves focus column; ⌃⌘[ / ⌃⌘] join/leave a column (default unassigned); title-bar drag between columns (default OFF, Core/ScrollStrip.swift:888-899); overview drag into notch (default OFF, ScrollStripRun.swift:538-539); notch-row left segment drag-out returns a window to the strip. Menu: **卷轴概览 exists in 整理▸** (MenuBarController.swift:146-149; StandardMenu.stripOverviewItem). |
| Feedback | Strip windows move per-app on background queues, newest target only (slow apps skip frames); overview opacity/zoom follow the spread (ScrollStripOverview.swift:98-171); parked columns show a 10-pt sliver; hovering the sliver 0.3 s = peek card; first strip start teaches via coach after 1.6 s (MagicTilingRun.swift:181-184). |
| Decision | 8-pt direction decision (TrackpadGestures.swift:412-448); finger speed over last 150 ms with a synthetic zero-displacement point at lift; stop = now + v×0.5 s (r .998) snapped to the nearest column edge; focus moves only if the focused column scrolled fully off (draft 卷轴 rules). Overview opens if projected progress >½. |
| Animation | Scroll settle `glide`-like (draft: "停稳 glide .42/.88, ≤1.2 s"); overview release uses `settle` .38/ζ1 with finger velocity (ScrollStripOverview.swift:158-171); fades `Motion.fadeDuration` (:105, 213). **No Reduce-Motion branch for the overview zoom** (only the fade length) although the draft says "减少动态效果时 0.25 秒淡入淡出". |
| Interruptible | Yes: re-grab a gliding strip; spread can be released and retracts; Esc/click-away/space change/lock closes the overview (StripInterruptions, ScrollStripOverview.swift:63-67). |
| Undo | Pinch any strip window = entire batch back (MagicTilingRun.swift:200-218); closing/minimising/slide-over/drag-out windows leave their column. |
| Keyboard / menu alt | Menu 卷轴概览; ←→ / Return / Esc inside overview; ⌃⌘←→ only for upgraders. |
| Accessibility | Overview items are buttons "<title>，第 N 列" with custom actions 移到左/右边一列、并进左/右边这一列、收进刘海 (draft 卷轴 "VoiceOver"; ScrollStripOverview.swift a11y refs). Strip-peek card has none (ScrollStripPeek.swift). |
| Default | Entered automatically (no toggle); sub-features OFF as listed. |
| Known gaps | **Hidden mode**: the same title-bar swipes change meaning once a window belongs to a strip (L/R scrolls the strip instead of half-screen; spread opens the overview instead of 魔法平铺); only edge slivers + one coach tip signal it. gestures.md "还没有菜单项和快捷键，鼠标暂时打不开它" is stale because the menu item exists. |

### W13 分屏把手 (split handle)

| Field | Evidence |
|---|---|
| Inputs | Drag the 28×160-pt handle that appears between two windows that exactly fill a screen (or any tiled seam, 3/4/6/9-way) (App/SplitView.swift:563; gestures.md:1000-1044). |
| Feedback | Handle fades in/out (`Motion.fadeDuration`, :584); both windows resize together via per-window latest-value writers; rubber band past the allowed range; background scan of the WindowServer window table every 2 s (0.5 s while a handle shows) plus on app switch/arrange/space change (SplitView.swift:8-10). |
| Decision | Release speed picks the nearest of ⅙/¼/⅓/½… where each window stays ≥240 pt; pushing to the screen edge sends the pushed window to Slide Over and fills the other (two-window case only) (gestures.md:1000-1044). |
| Animation | Analytic `settle` (or `reducedWindow` when reduced), per-frame AX writes (SplitView.swift:608-620). |
| Interruptible | Yes: re-grab stops the glides first (Drag/Settling classes, :32-60). |
| Undo | Partner windows share undo records: pinch/⌃⌘↑ on one reverts both (TrackpadGestures.swift:2150-2160). Setting 设置→卷帘→排布→分屏把手 turns it off. |
| Keyboard / menu alt | None found (no increment/adjust action: SplitView.swift:668-670 only sets role `.splitter` + label "拖动调整两个窗口的大小"). |
| Discoverability | Coach `.splitBar` ("拖分屏把手"). |
| Accessibility | Splitter role + label; no VO adjustment, no keyboard resize. |
| Default | ON (ReleaseDefaults.swift:52, device-verified). |
| Known gaps | Polling timer (2 s) vs the "常驻耗电" constraint (direction.md:21); possible overlap with macOS's own tiled-window divider is **not determined**. |

### W14 拖到窗口上并排 (drop split)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar and release over another window; the dragged one takes a side (MagicTiling.dropTarget). Island/edge/PiP/slide-over/flick win first (App/DropSplitRun.swift:1-6). |
| Feedback | **None** ("没有预览：目前没有能复用的半屏提示浮层，不另起一个", DropSplitRun.swift:5). |
| Decision | Pointer position over the top window at release; not for slide-over windows. |
| Animation / interrupt | n/a. |
| Undo | Both windows get linked undo records (pinch/⌃⌘↑ reverts both). |
| Keyboard / menu alt | None. |
| Discoverability | Settings only. |
| Default | **OFF** (DropSplitRun.swift:10-13); vocabulary entry exists in copy-guide.md row 59. |
| Known gaps | A drop outcome with no preview is the clearest violation of the project's own principle "松手前看得见结果" (design-system.md §2 #4/#7). |

### W15 画中画 (picture-in-picture for any window)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar into a 120×120-pt corner zone (14 pt inset) and **dwell 0.25 s** (PictureInPictureViews.swift:296-345); menu "画中画" (needs Accessibility **and** Screen Recording, MenuBarController.swift:144); recordable shortcut; hover controls: ✕ close (TL), 回到原处 (TR), 上一页/播放暂停/下一页 (centre), 只看一块 crop (BR); pinch or **⌘+scroll** cycles 3 sizes (240/360/520 pt wide, ≤45% of screen) (PictureInPictureViews.swift:231-234; Core/PiPLayout.swift:34-46); double-click returns; scroll passes to the source window. |
| Feedback | Corner glass + ghost outline once armed (like W16); live 15 fps (30 on hover, stopped when stashed); original window parks off-screen leaving 2 pt (crash-recovery record written first). |
| Decision | Release projection r=.998 picks the nearest corner or stashes on a left/right edge with a 16×76 "拿回画中画" tab; multiple PiPs stack in a corner. |
| Animation | `glide` via `FlickGlidePath.honoringMotion` (PictureInPicture.swift:588); controls fade `Motion.fadeDuration` (PictureInPictureViews.swift:133-139). |
| Interruptible | Drag is 1:1 and redirectable until release. |
| Undo | 回到原处 / double-click / menu toggle / crash recovery on next launch. |
| Keyboard / menu alt | Menu + recordable shortcut; no keyboard for controls found. |
| Accessibility | Group "画中画", each button has a tooltip/label; **上一页/下一页 are literal strings, not localised** (PictureInPictureViews.swift:~64-66); stash tab is a button "拿回画中画" (:252-265). |
| Default | No toggle; copy says "任意窗口画中画" came from iPad (design-system.md §8 #4 decided to keep ON). |
| Known gaps | Overlaps the system PiP's corner placement for video; Stage Manager/ hot-corner interaction **not determined**. |

### W16 侧拉 (Slide Over)

| Field | Evidence |
|---|---|
| Inputs | Drag a title bar into a 72×220-pt zone centred vertically, 8 pt inside either screen edge, **dwell 0.25 s** to arm; neighbour-screen edges refused (App/SlideOverDropHint.swift:15-60); menu 侧拉当前窗口 / 收起 / 拉出 / 退出; recordable shortcut; flick toward the docked side stashes it (TrackpadGestures.swift:1597-1602); tab/handle: click or inward swipe pulls it out; glass frame drag moves, corner arc resizes. |
| Feedback | Glass sliver + arrow at the edge, then a bordered ghost where the window will land; 4-pt sliver stays after stashing (SlideOver.swift:66). |
| Decision | Position + dwell; stash by projection (FluidMotion.projection, SlideOverMotion.swift:21). |
| Animation | Real window moves via `WindowGlide` with release velocity (SlideOver.swift:263-264, 672); tab content `glide`/`settle` tokens (:1102-1180); reduced = `reducedWindow`. |
| Interruptible | Yes (grab mid-glide: SlideOver.swift:464-480). Only one Slide-Over window; starting another exits the first (header comment). |
| Undo | 退出侧拉 / drag to centre / menu. Magic-tile undo exits it. |
| Keyboard / menu alt | Menu + shortcut (unassigned by default). |
| Discoverability | Coach `.slideOverHandle`; one-time notice about assigning the app to all desktops (SlideOver.swift:452-458). |
| Accessibility | Handle button "拉出侧拉的窗口", resize handle "调整侧拉窗口的大小" (SlideOver.swift:973-977; SlideOverChrome.swift:393-395). |
| Default | No toggle (kept ON, design-system.md §8 #4). |
| Known gaps | Hotspot geometry collides conceptually with system edge tiling and with the other drop targets (see 3.7). |

### W17 窗口浏览 (Dock hover panel, "选择窗口…")

| Field | Evidence |
|---|---|
| Inputs | **Dock hover**: show after **0.25 s**, hide after 0.18 s (WindowBrowser/WindowBrowserGeometry.swift:81-82); yields to the Dock's own menu on right-click, Ctrl-click or a 0.45 s press (WindowBrowserController.swift:566-598). **Keyboard panel**: menu "选择窗口…" (in 整理▸, enabled by `keyboardPanelEnabled`) or an optional recorded hotkey (needs ⌃ or ⌥). Panel keys: arrows by real column count, Home/End/PgUp/PgDn, Return, Space = Quick Look, ⌘F search, Esc, **⌘W close, ⌘M minimise, ⌃⌘F enter full screen** (WindowBrowserContentView.swift:1201-1241; WindowBrowserActionPresentation.swift:420-431). Card: click = activate/expand; hover action bar (collapse/expand, pin preview, new window ⌘N); right-click: close, minimise, full screen, new window, 让开这个 App, 退出 App, 排布▸; **红黄绿 on the card = close / minimise / enter full screen** (WindowBrowserTrafficLights.swift:1-92). **Drag a card out**: ≤40 pt from left/right = halves, top = fill, dwell at edge = slide-over; dashed outline; Esc/drop on panel = cancel (window-browser.md:43-56). |
| Feedback | Panel fades in ≈140-180 ms and out ≈100-120 ms; Reduce Motion = no animation (WindowBrowserPanel.swift:146-153); live preview OFF by default (0.4 s after selection, 8 fps ≤640×400); drag shows a dashed target outline. |
| Decision | Dwell; explicit click/Return only — hover/search never changes windows (window-browser.md:143). |
| Animation | Appearance/disappear fades only; closing a card shrinks it ~0.16 s while neighbours reflow. |
| Interruptible | Hover re-targets; Esc; leaving the icon hides after grace. |
| Undo | Arrange from the card is recorded in the same ledger (W24). |
| Keyboard alt | It *is* the keyboard path for choosing a window. |
| Discoverability | One-time first-run hint (WindowBrowserSettings.swift:21-27); settings explainer. |
| Accessibility | Cards expose labels/actions (WindowBrowserCardView.swift 15 refs, ContentView 11); traffic-light buttons are non-focusable custom views (`acceptsFirstResponder=false`) that add glyphs so state is not colour-only. |
| Default | Dock hover ON (owner decision, ReleaseDefaults.swift:48); keyboard panel ON; hotkey none. |
| Known gaps | Traffic-light colours are hard-coded sRGB (WindowBrowserTrafficLights.swift:28-33) against design-system §4.3 "只用系统语义色"; 2026-10-29 decision makes the card's green = full screen **only** while the strip's green forwards the system tiling popover (ShadeStrip.swift:376-392). window-browser.md contradicts itself: "新面板不添加淡入…" (:164) vs "约 160 ms 的淡入" (:166). |

### W18 按窗口切换 (⌥Tab window switcher)

| Field | Evidence |
|---|---|
| Inputs | Hold ⌥ (or ⌘, optional) and tap Tab; quick tap = switch to the previous window without a panel; hold ≥0.15 s = panel; Tab/⇧Tab/←→, digits 1-9, typing/`/` filters, Return, Esc, click; **⌥W closes the selected window, ⌥Q quits its app (panel stays)** (App/WindowSwitcher.swift:1-12). |
| Feedback | Panel of cards (screenshot, icon, title; numbers on first 9); collapsed/tucked windows are listed after the visible ones and restored when picked (marked "收着"). |
| Decision | Modifier release commits; in search mode only Return/click commits. |
| Animation | No animation tokens found; reduce-motion references: none. |
| Interruptible | Esc. |
| Undo | n/a (⌥W/⌥Q are destructive and unconfirmed by the panel). |
| Keyboard alt | It is the keyboard route. Default ⌥Tab ON (ReleaseDefaults.swift:54, device-verified); ⌘Tab replacement optional. |
| Discoverability | Coach `.switcher` ("按窗口切换"). |
| Accessibility | 3 a11y refs; no VoiceOver traversal evidence. |
| Known gaps | Event tap on keyDown at head of the session stream with its own thread; ⌥Tab can collide with app shortcuts (not determined). |

### W19 让开这个 App (Dock click) and Dock-icon swipe

| Field | Evidence |
|---|---|
| Inputs | **Re-click the frontmost app's Dock icon** when it has visible windows = hide it like ⌘H; second click = system unhide (App/DockClickHide.swift:1-60). Guard: if the app has minimized/other-desktop/off-screen windows it does **not** hide and instead restores one minimized window (Core/DockClickGuard.swift; gestures.md:856-900). **Two-finger swipe on a Dock icon**: up = all windows of that app, down = hide app (App/DockSwipe.swift:1-35; ≥56 pt, ≥2× vertical dominance, ≤1.5 s). Window-browser card menu has the same 让开这个 App. |
| Feedback | Click: first time the notch says "它让开了 / 再点一下 Dock 图标就回来" (coach `.dockHide`); swipe: **no HUD, conclusion at lift** (gestures.md:925). |
| Decision | Press/release on the same icon without drag; swipe thresholds above; yields to Swish and to Dock's `scroll-to-open`. |
| Animation | System's hide animation only. |
| Interruptible | No. |
| Undo | Click the Dock icon again. |
| Keyboard alt | ⌘H (the same action). |
| Accessibility | Event-based, no UI. |
| Default | Click: `Dock.clickToHide` = **depends on the "之前常用" answer**: ON for Mac/unanswered, OFF for Windows/iPad, ON for 1.0.16-preview installs (Core/DockClickGuard.swift:93-100; ReleaseDefaults.swift:46). Swipe OFF (DockSwipe.swift:19-22). |
| Known gaps | **Direction semantics invert across surfaces**: down on a title bar = bigger/fill, down on a Dock icon = hide (docs say deliberate, gestures.md:901-965 and 928). The default of a behaviour is driven by an onboarding answer that 1.0.18 made optional and moved to the tour page (WelcomeFlow.swift:1-8). |

### W20 调度中心里按 ⌘W / ⌘Q

| Field | Evidence |
|---|---|
| Inputs | While Mission Control is open, ⌘W closes the window under the pointer, ⌘Q quits its app; detection by WindowManager's `ExposeShieldWindow` (App/MissionControlKeys.swift:1-12; Core/MissionControlPick.swift). Other modifiers pass through; if no safe target, the key is swallowed rather than hitting the front app. |
| Feedback | The window disappears (system). No WindowShade UI. |
| Undo | App-level (unsaved-changes dialogs are the app's). |
| Default | ON (ReleaseDefaults.swift:53, device-verified); toggle in 设置→窗口浏览. |
| Known gaps | Active event tap that changes ⌘W semantics system-wide while MC is up; ⌘Q has no confirmation; no VO story. |

### W21 带到每张桌面 (carry)

| Field | Evidence |
|---|---|
| Inputs | Menu 带到每张桌面 (in 整理▸), recordable shortcut (⌃⌘G only for upgraders); stop via the × (30-pt zone) on the strip or the menu (App/Carry.swift:1-6, 28-62). |
| Feedback | The window stays on its desktop; **every other desktop (incl. full-screen spaces) gets a 260×30 strip top-right**, 10 pt from the side, 8 pt from the top, radius 9, one row, overflow → "更多窗口" menu (Core/CarryShelfLayout.swift:5-8, 23-26; Carry.swift:12-30). Hover = live peek (first frame ≈86 ms measured), click the picture = go back to the window (Carry.swift:1-9). |
| Animation | Fade/peek tokens; panel `animationBehavior = .none`; `canBecomeKey = false`. |
| Undo | × / menu / shortcut. |
| Keyboard alt | Shortcut only (unassigned). Strip itself cannot take focus. |
| Accessibility | Button "带到每张桌面：<title>", help "停在上面看一眼，单击画面回到这个窗口", press action (Carry.swift:73-116). |
| Default | No toggle. |
| Known gaps | Top-right placement can sit on menu-bar-adjacent content in every desktop; inclusion in full-screen spaces not verified; one of four overlapping "keep in view" features (see 3.4). |

### W22 刘海本体 (the notch itself as an input surface)

| Field | Evidence |
|---|---|
| Inputs / meaning | **Click ×1 = 回到主屏幕 (启动台), ×2 = 调度中心, ×3 = 这个 App 的所有窗口**, resolved after `min(doubleClickInterval, 0.3 s)`; mouse-down already "pulses" the island (Notch.swift:3187-3203, 5370-5387, 1714-1743). **Long-press 0.5 s** = open the shelf with keyboard focus (or Launchpad Today when no activities) (Notch.swift:5379-5384, 492-500). **Hover** 0.12 s dwell expands the row (`Motion.Hold.notchDwell`, Motion.swift:39); optional hover guard (hint only 3 pt, speed/stillness rules) is OFF by default (NotchHoverPolicy; design-grammar.md:302). **2-finger pull-down** (1:1, rubber band, projection r=.99) = bring back the last tucked window/batch, else Launchpad home (Notch.swift:510-514, 3929-3950). **2-finger push-up >60 pt** = tuck all (Notch.swift:5558). **2-finger L/R >60 pt** = previous/next App (1.5 s trail, "上一个/下一个" flash) or Launchpad page (Notch.swift:5557, 1672-1696). **Pinch in** = home, **spread** = same as push-up (`.back`) (Notch.swift:5575-5586). **Smart-zoom** toggles the row (5451). **Right-click** = activity menu (5450). Files dropped/held 0.35 s on the notch open "用哪个 App 打开" (Notch.swift:5464-5498). Esc cancels (cancelOperation). |
| Feedback | Only the pull-down and activity swipes move the island 1:1; the others commit with no motion until the result (toast "收进了 N 扇…", app-switch flash). |
| Decision | Distance (60 pt) for push/swipe (no velocity), projection for pull-down, pinch 0.18. |
| Animation | Morph tokens per shape: minimum `calm`, compact/chin `settle`, alert `bloom`, expanded `expand`, interaction/meter `pop`, drop `catchDrop`; Reduce Motion → `reducedNotch` and frames set directly (Motion.swift:112-122; design-grammar.md:256). |
| Interruptible | Pull-down yes (finger-driven, springs with finger velocity, cancel springs back); pressed/hold cancel when a scroll/pinch starts (Notch.swift:5519, 5577). |
| Undo / recover | Pull-down/menu/⌃⌘H run again. |
| Keyboard / menu alt | Menu: 启动台, 全部收进刘海, 收进刘海; row keyboard focus `notchShelf` unassigned by default; no keyboard for "上一个/下一个 App" or Mission Control. |
| Discoverability | Coach `.notchHome` on first rest over an empty notch; toast after tuck-all; draft 卡住时刘海开口 for stuck habits. |
| Accessibility | 37 a11y / 30 Reduce-Motion references in Notch.swift; alerts post VoiceOver announcements (Notch.swift:1555-1575); Increase Contrast hairline .14→.5 (Notch.swift:2430-2432). |
| Default | `Notch.enabled` ON. |
| Known gaps | (1) Multi-click action is delayed up to 0.3 s (design-system.md §6-14 wants press feedback without waiting; pulse exists, action still waits). (2) One surface carries ~12 gestures with context-dependent meaning (`.back`, horizontal swipe, pinch differ when Launchpad is open). (3) §6-6 "刘海手势全程跟手、可以改方向" (design-system.md:669-672) is still not done for push-up/horizontal/pinch. |

### W23 启动台 → drag an app icon out to place its window

| Field | Evidence |
|---|---|
| Inputs | Drag an icon out of the Launchpad and release: **outer 6% of screen width (48-96 pt) = Slide Over; up to 30% = half; upper/lower 25% of the half zone = quarter; top 12% centre = fill; notch = tuck; elsewhere = just open** (Core/LaunchpadModel.swift:176-209; App/LaunchpadController.swift:554-567). |
| Feedback | The drag "platter" morphs per zone (260×170 open, 150×230 half, 190×130 quarter, 110×230 slide-over, 120×68 notch) with `expand` springs, target rectangle outlined, edge tabs light up (LaunchpadView.swift:1470-1540). |
| Animation | Springs from tokens; `reduced` flag passed (LaunchpadView 1 reduce refs). |
| Interruptible | Yes until release. |
| Undo | Placement ledger via `placeFromLaunchpad`. |
| Keyboard alt | Launchpad has its own keys (LaunchpadKeysProbe); no keyboard route for the placement. |
| Default | Launchpad opens from notch click / menu 启动台 / shortcut (unassigned). |
| Known gaps | Zone ordering differs from title-bar and window-browser drags (see 3.7). |

### W24 撤销上次排布 (undo) — cross-cutting

| Field | Evidence |
|---|---|
| Inputs | 2-finger pinch on the title bar; ⌃⌘↑ on a window that was filled by gesture; recordable shortcut (Rectangle preset ⌃⌥⌫); notch/strip: pinch any window of a magic/strip batch. **No menu item in the status menu.** |
| Scope | **Frame placements only**, one slot per window, discarded when the window has since been moved by hand (TrackpadGestures.swift:943-952, 2130-2147). Whole-batch undo for 魔法平铺/卷轴 (MagicTilingRun.swift:200-218); linked pair for split/drop-split (TrackpadGestures.swift:2150-2160). Not covered: collapse (use 展开), tuck (放回), slide-over (退出侧拉), PiP (回到原处), 让开 (click Dock again), close/quit. |
| Feedback | HUD ("撤销上次排布" or "没有可撤销的排布"); window jumps back (instant) except after a flick where it glides to the pre-grab frame. |
| Gaps | The word 撤销 means a frame restore here but each other "putting back" has its own verb (3.4). System ⌘Z is not involved. |

### W25 Keyboard shortcut set (all recordable; new install = none)

| Action | Upgrader default | Presets / notes |
|---|---|---|
| 收起或展开当前窗口 / 整理卷帘条 / 置顶 / 把当前窗口带到每张桌面 | ⌃⌘C / ⌃⌘0 / ⌃⌘P / ⌃⌘G | `GlobalShortcuts.swift:170-175` |
| 变小一级 / 变大一级 / 左半屏 / 右半屏 | ⌃⌘↑ / ↓ / ← / → (+0.8 s key-turn for corners) | Rectangle preset ⌃⌥←→↑↓ etc.; WASD/IJKL/HJKL preset swaps these four to ⌃⌥+letter (gestures.md:718-855) |
| 侧拉 / 启动台 / 魔法平铺 / 移到另一块屏幕 / 全部收进刘海 | ⌃⌘S / L / M / N / H only for 1.0.16-preview users | GlobalShortcuts.swift:178-184 |
| everything else (single tuck, PiP, thirds, quarters, fill, centre, larger/smaller, undo, previous display, join column, notch row, timers, window-browser hotkey, 暂时取消全部置顶) | none | window-browser hotkey must include ⌃ or ⌥ (window-browser.md:132) |
| Non-recordable: ⌥Tab switcher (ON), ⌘W/⌘Q in Mission Control (ON), ⌘F/⌘W/⌘M/⌃⌘F inside the window browser, ←→/Return/Esc in the strip overview | | Rectangle running = its keys win and WindowShade yields (gestures.md:718-740) |

### W26 Menu-bar menu (status item)

Top level (MenuBarController.swift:59-243): dynamic rows (权限 warning, running 番茄钟, coding session waiting, 置顶▸) then **收起窗口/展开窗口, 收进刘海, 置顶, 整理▸, 启动台, 已收起的窗口▸, 设置…, 关于, update, (开发▸), 退出**. 整理▸ = 侧拉/退出侧拉, 画中画, 魔法平铺, 卷轴概览, 移到另一块屏幕 (only with >1 display), 带到每张桌面, 整理卷帘条/缩略图, 全部收进刘海, 选择窗口…. Several items are disabled without Accessibility or Screen Recording (ax/screen flags, :80-168). **Absent**: 左/右半屏, 铺满, 上/下半屏, 四角, 三分, 撤销上次排布, 晃一晃, 让开这个 App. Design intent "顶层固定 9 项" (MenuBarController.swift:67-68). VoiceOver: status item value "N 个收起的窗口" (SystemAppearance.swift:415-419). The standard main menu (关闭/最小化/卷轴概览) exists only for key equivalents because the app is LSUIElement (StandardMenu.swift:1-12).

### W27 Teaching, hints and onboarding (cross-cutting)

| Mechanism | Evidence |
|---|---|
| Gesture coach | 12 tips: halves, magic, shake, switcher, notchHome, stripScroll, dockHide, shade, splitBar, slideOverHandle, rectangle, pip (Core/GestureCoach.swift:13-40); **max 3 shows each, ≥300 s between any two coach/habit hints, "used" = never again, tapping the hint dismisses it for good** (GestureCoach.swift:82-86; Notch.swift:1555-1575). Shown in the notch alert for **2.6 s** (default `Motion.Hold.alert`, Notch.swift:3333) with a VoiceOver announcement. |
| Stuck-habit hints | 6.6 s alert with demo, small ✕ closes this occurrence only, tap performs the Mac action (Notch+Habit.swift:30-52; design-grammar.md:268). Rules cover Windows shortcuts (Ctrl+C…, Alt+F4) and iPad gestures; silent in terminals, IDEs, games, password fields, screen sharing (draft 卡住时刘海开口). |
| Welcome (1.0.18) | A1 practise the **double-click** on a sandbox window → A2 permissions (辅助功能 required, 屏幕录制 optional) → T four-segment tour (刘海 / 窗口浏览 / 手势与卷轴 / 菜单栏); U1/N1 for upgraders (App/WelcomeFlow.swift:1-60; Core/WhatsNew1018Changes.swift:1-40; draft 首次打开 1.0.17 小样). |
| Settings explainer bands | Each settings page has a 640×200 band; the row under the pointer/keyboard focus plays its scene (draft 首次打开 1.0.17 小样 lines 150-175; App/SettingsExplainerHost.swift). |
| Others | One-time window-browser hint (WindowBrowserSettings.swift:21-27); Slide-Over all-desktops notice (SlideOver.swift:452-458); "手指" caption per gesture row (WS2GestureRows.swift). |
| Gaps | Teaching is notch-bound: a window-management gesture is taught only if the notch is on, the pointer rests there, and the 5-minute pacing allows; nothing teaches W6/W8/W14/W19-swipe/title-bar long-press. The only hands-on practice in onboarding is the double-click (A1); the two-finger ladder and spread are only *demonstrated* in the T tour (draft 首次打开 1.0.17 小样 line 94), never practised. |

---

## 3. Cross-cutting findings

### 3.1 Keyboard / menu coverage (HIG: every gesture needs a non-gesture path)

| Interaction | Menu item | Default shortcut (new) | Recordable | Notes |
|---|---|---|---|---|
| Collapse/expand | yes | none | yes | |
| Tuck one / all | yes / yes | none | yes | notch row focus `notchShelf` recordable |
| Left/right half, fill, undo, corners, thirds | **no** | none | yes | only via Settings→快捷键 or presets |
| 魔法平铺 | yes | none | yes | |
| 卷轴概览 | yes | none | no (←→ inside) | |
| Slide Over / PiP / Carry | yes | none | yes | |
| 窗口浏览 | yes | none | yes | |
| 看一眼 | no | — | — | hover/click only |
| 晃一晃 / 甩一下 / 落点小岛 / 分屏把手 / 拖到窗口上并排 / 卷轴列宽 | no | — | no | pointer-only |
| 让开这个 App | no (card menu only) | ⌘H exists | — | |
| Notch: switch App, Mission Control | no | — | — | |

### 3.2 Conflicts with built-in macOS features

1. **Title-bar double-click (System Settings → Desktop & Dock → zoom/minimize)**: default ON; WindowShade swallows the 2nd click and moves the system action to the 3rd click; held modifiers skip; if the main-thread decision exceeds 500 ms the click is passed through (App/EventTapCallback.swift:51-118; settings sub-lines in WS2SettingsInfo.swift:248-249).
2. **macOS 15+ edge/corner tiling**: not replicated (gestures.md:712); flick yields within 3 pt of an edge (TrackpadGestures.swift:1578-1584); Slide Over zone is inset 8 pt "避开系统平铺" (SlideOverDropHint.swift:4); but Launchpad drops map the outermost strip to Slide Over, the reverse ordering of the system (W23).
3. **Green button / Move & Resize**: the strip forwards the system tiling popover after a 0.55 s hover (ShadeStrip.swift:376-392); the window-browser card's green does **only** "进入全屏" (decision 2026-10-29; WindowBrowserTrafficLights.swift:1-8) and is custom-drawn.
4. **Native full screen**: collapse refuses (ShadeController.swift plan "reject fullscreen"); placements/magic tile skip AXFullScreen windows (MagicTilingRun.swift:33-70 (line 58)); the notch draws nothing on a native full-screen space except authentication/lock (Notch.swift:3235 `yieldsToSystem`); PiP and Carry deliberately float above full-screen apps (PictureInPicture.swift header; Carry.swift:19).
5. **Stage Manager**: only a partial adaptation (strip-card detection `StageStrip`, Core/StageStrip.swift); VM runs of fold-timing pass, "展开一扇时另一扇也跟着回来" recorded as a known limitation; other categories not_run (product-reshape-spec.md:113, 726-735).
6. **Mission Control**: notch double-click opens it (Notch.swift:1727-1736); ⌘W/⌘Q inside it are re-defined by a global event tap (MissionControlKeys.swift:1-12); ⌘W there closes the pointed window while the system sends it to the front app.
7. **⌘Tab / ⌘H / ⌘M**: ⌘Tab untouched by default (⌥Tab added; ⌘Tab replacement optional); 让开 = ⌘H; 收起 deliberately replaces 最小化 (draft 为什么不用最小化), but ⌘M still exists and the window browser offers 最小化.
8. **Native Split View / system tile handles**: WindowShade's 分屏把手 appears for any two windows that exactly fill a screen — behaviour next to system-tiled pairs **not determined**.
9. **Native PiP / hot corners**: PiP's 120×120 corner zones and the system's PiP/hot-corner placement may coincide — **not determined**.

### 3.3 Mode errors and hidden states

| # | State | Why it matters | Evidence |
|---|---|---|---|
| H1 | **Scroll-strip mode**: entered automatically by 魔法平铺 overflow; title-bar L/R, up/down and spread change meaning for strip windows; no persistent indicator except 10-pt edge slivers | Same gesture, different result by invisible context | MagicTilingRun.swift:143-185; TrackpadGesture.swift:409-414 |
| H2 | **Tucked windows are invisible**: real strip kept at alpha 0, mouse-transparent; only reachable via notch row (or the 190-pt invisible-notch slot on external displays, which does not even expand when nothing is tucked) | "Where did my window go" | Notch.swift:918-944, 1048-1054 |
| H3 | **Parked windows**: Slide-Over stash leaves 4 pt on screen, PiP source leaves 2 pt; crash-recovery records bring them back next launch | Window exists but is not visible/reachable except via handle/tab | SlideOver.swift:66; PictureInPicture.swift header |
| H4 | **Shake memory** (`shaken`) belongs to one keeper window; shaking another overwrites it | Second shake may not restore | MagicTilingRun.swift:233-266 |
| H5 | **One switch, many features**: 标题栏手势 OFF also disables flick, shake, drop island, Slide-Over/PiP drop hints, drop-split, strip title-drag, press-hold menu | Setting text only mentions swipes/flick | TrackpadGestures.swift:219-249 |
| H6 | **Onboarding answer changes defaults/hints** ("之前常用": Windows/iPad/Mac): Dock click-hide default, which habit hints speak | Hidden coupling; 1.0.18 made the question optional | Core/DockClickGuard.swift:93-100; Core/SwitcherOrigin.swift:1-12; WelcomeFlow.swift:1-8 |
| H7 | **Context-dependent notch gestures** (Launchpad open vs not) | `.back` = navigate back or tuck all | Notch.swift:516-530 |
| H8 | **Animation OFF + Screen Recording** decide whether collapse has any motion and whether finger-follow exists | Permission-dependent feel | EffectSession.swift:206; WindowFoldEffects.swift:64-71 |
| H9 | **Hidden title-bar long-press** (0.55 s with the button down, pointer still) pops a 5-item menu (收起窗口/左半屏/右半屏/铺满屏幕/魔法平铺); undocumented | Competes with drag-start; no teaching | TrackpadGestures.swift:1257, 1388-1421 |
| H10 | **Away-state refusals**: placement/key ladder refuse on collapsed/tucked/PiP/stashed windows with a hint instead of acting | Good mitigation, but it is a mode | TrackpadGestures.swift:886-893 |
| H11 | **Hover-guard OFF by default**: the notch row expands after 0.12 s on any rest | Accidental expansion near menu-bar items | Notch.swift:3839-3880; design-grammar.md:302 |

### 3.4 Same idea, different words or gestures

**Words**

| Idea | Terms in use (evidence) |
|---|---|
| Put a window away | 收起窗口 (strip) / 收进刘海 / 让开这个 App / 侧拉 / 画中画 / 带到每张桌面 (keeps it) / 最小化 (system, still offered) (copy-guide.md rows 24-25, 57, 62, 71, 76) |
| Bring it back | 展开窗口 / 放回 / 还原 (minimised) / 拉出 (slide-over) / 去 (other desktop) / 回到原处 (PiP) / 拿回画中画 (tab) / 恢复卷帘条原位 / 全部展开 / 点 Dock 图标回来 / 撤销上次排布 (frames) |
| 让开 | Dock hide (copy-guide row 62) **and** "别的窗口一下让开" in the shake tip (GestureCoach.swift:19, 66) **and** "⌃⌘↑ 是让开" (gestures.md:670) **and** "被推过去的那一扇让开进侧拉" (gestures.md:1000-1044) **and** "窗口浏览马上让开" for the Dock menu |
| 卷帘 vs 卷帘条 | Glossary: 卷帘条; copy rule 4 says explain it as "收起窗口（卷帘）"; VoiceOver label says "WindowShade 卷帘：…" (SystemAppearance.swift:406) |
| 缩略图 | collapse mode (copy-guide row 26) **and** window-browser grid style (WindowBrowserSettings.swift:44-48) **and** images in notch tiles |
| Keep something in view | 置顶 (pinned live preview), 侧拉, 画中画, 带到每张桌面 — four features with overlapping purpose |

**Gestures (same input, different meaning by surface)**

| Input | Meanings |
|---|---|
| Pinch in | title bar = undo placement; notch = home; PiP = smaller (3 sizes) |
| Spread | title bar = 魔法平铺; strip-window title bar = 卷轴概览; **notch = tuck all**; PiP = larger |
| Push up / "up" | title bar = collapse (or undo fill); notch = tuck all (or "back" in Launchpad); flick-up = collapse **or** tuck depending on aim; Dock icon swipe up = show all windows of the app |
| Down | title bar = fill/expand; notch pull-down = bring back; Dock icon swipe down = hide app |
| Click | strip = peek; thumbnail = expand; notch = home (×1) / Mission Control (×2) / App Exposé (×3); title bar ×2 = collapse, ×3 = system zoom |
| Long press | title bar 0.55 s = menu; notch 0.5 s = shelf; Dock icon 0.45 s = Dock menu (WindowShade yields) |
| Edge drop | see 3.7 |
| Dwell | see timing zoo below |

**Timing zoo** (no shared dwell token beyond `Motion.Hold.notchDwell` 0.12 and `tileDwell` 0.20, Motion.swift:34-42): 0.12 notch hover; 0.15 switcher panel; 0.16 peek leave; 0.18 Dock-panel hide; 0.20 peek/tile; 0.22 (docs) peek; 0.25 Dock-panel show, Slide-Over/PiP arm; ≤0.3 notch click disambiguation, wheel quiet, strip-sliver peek; 0.35 file-on-notch; 0.45 Dock long-press, HUD commit hold; 0.5 notch long-press; 0.55 title-bar hold, strip green hover, notch confirm hold; 0.6 commit cooldown; 0.8 shake window, key-turn window; 1.2 menu→peek handoff; coach 2.6 s vs habit 6.6 s.

### 3.5 Gestures with no feedback during the motion

| Gesture | What exists | Evidence |
|---|---|---|
| 甩一下标题栏 | none before release; result HUD at the landing title bar | TrackpadGestures.swift:1676-1683 |
| 晃一晃 | none until the 3rd reversal; toast afterwards | WindowShake.swift; MagicTilingRun.swift:260-266 |
| 拖到窗口上并排 | **explicitly no preview** | DropSplitRun.swift:5 |
| Notch push-up / horizontal / pinch / spread | none until commit (then toast / flash) | Notch.swift:5516-5586 |
| Dock-icon 2-finger swipe | "没有浮窗", verdict at lift | gestures.md:925 |
| Title-bar left/right/corner/grid/spread/pinch | HUD bar only; no target outline, window does not move until commit | TrackpadGestures.swift:1065-1099 |
| Double-click collapse / menu / shortcut | no HUD; no roll unless animation ON | W1 |
| Notch hover | 3-pt hint only with hover guard ON (default OFF) | design-grammar.md:302 |
| Whole HUD | not shown until async AX verification returns | TrackpadGestures.swift:969-976, 1013-1032 |

### 3.6 Accessibility matrix (what the code does)

| Surface | Reduce Motion | Reduce Transparency | Increase Contrast | VoiceOver / keyboard |
|---|---|---|---|---|
| HUD | no crossfade, no `pop` (GestureHUD.swift:358, 445) | opaque pill (:463-490) | border `labelColor` (design-system.md:571) | announces action **after** commit; nothing during |
| Strip / thumbnail | fade only, no flight (Thumbnail.swift:365-369, 553, 760) | thumbnail forced opaque (Thumbnail.swift:11) | border via SystemAppearancePolicy | group + custom action; press = expand; real-device traversal pending |
| Notch | `reducedNotch`, frames direct, no swallow | black anyway | hairline .14→.5 (Notch.swift:2431) | 37 refs; alerts announce |
| Glance | fade (GlancePanel.swift:258-262…) | — | — | image element, press opens |
| Real-window glides (flick, Slide Over, PiP, split, strip) | `reducedWindow` .30/ζ1 — **still slides** (Motion.swift:126-130) | — | — | handles labelled; no adjust actions |
| Strip overview | fade length only; zoom spring unchanged (ScrollStripOverview.swift:105, 161, 213) | — | — | buttons with custom actions |
| Window browser | no animation (WindowBrowserPanel.swift:146-153) | opaque background option/auto | stronger border | cards labelled; traffic lights not focusable |
| Switcher | no refs found | — | — | 3 refs |
| Drag-only features (island, flick, shake, drop-split, split handle, slide-over/PiP drops) | n/a | n/a | n/a | **no VoiceOver/Switch Control path**; the alternates are unassigned shortcuts |

### 3.7 Drop-target geometry across surfaces (same spatial idea, different outcome)

| Drag source | Left/right edge | Corners | Top centre | Notes |
|---|---|---|---|---|
| macOS (title-bar drag, 15+) | edge = half | corner = quarter | top = fill | system; WindowShade yields within 3 pt (TrackpadGestures.swift:1578-1584) |
| WindowShade title-bar drag | Slide-Over zone x∈[8,80] pt × 220 pt tall at mid-height, dwell 0.25 s (SlideOverDropHint.swift:15-60) | PiP 120×120 at 14 pt inset, dwell 0.25 s (PictureInPictureViews.swift:307-345) | drop island 340×84: 左半屏/铺满/收进刘海/魔法平铺/右半屏 (Notch.swift:2439-2459) | all three appear only after ≥16 pt travel (TrackpadGestures.swift:1309) |
| Window-browser card drag | ≤40 pt = half; dwell = Slide-Over | — | top edge = fill | window-browser.md:43-56 |
| Launchpad icon drag | outer 6% (48-96 pt) = **Slide Over**; next to 30% = half | upper/lower 25% of the half zone = quarter | top 12% centre = fill; notch = tuck | LaunchpadModel.swift:176-209 |
| Strip-overview drag | — | — | notch = tuck (OFF) | ScrollStripRun.swift:538-539 |

### 3.8 Contradictions between drafts, docs and code

| # | Claim | Reality | Evidence |
|---|---|---|---|
| 1 | "每个手势都有菜单或快捷键可以代替" / "菜单和设置里每个动作都还在" | Menu lacks halves/fill/undo/thirds/corners; new installs have no shortcuts; shake, flick, island, split handle, drop-split have no alternative | design-system.md:397, gestures.md:595 vs MenuBarController.swift:118-243, GlobalShortcuts.swift:162-190 |
| 2 | Teaching tip stays `coach.hold` 6.6 s | Gesture-coach tips use the default 2.6 s; only stuck-habit hints use 6.6 s | design-system.md §4.7 + `_errata.json` vs Notch.swift:1555-1570, 3333; Notch+Habit.swift:50 |
| 3 | Reduce Motion: overview "0.25 秒淡入淡出" | zoom spring `settle` always runs | draft 卷轴 vs ScrollStripOverview.swift:161 |
| 4 | Reduce Motion: moves become fades (`reduced`) | real-window glides still slide (slower, no bounce) | design-system.md:349 vs Motion.swift:126-130 |
| 5 | Peek dwell 0.22 s | 0.20 s | docs/Thumbnail.swift:6 vs GlanceIntent.swift:19; design-grammar.md:281 |
| 6 | Window browser "不添加淡入" and "约 160 ms 的淡入" | same file contradicts itself; code ≈140-180 ms | window-browser.md:164-166; WindowBrowserPanel.swift:146-153 |
| 7 | 卷轴概览 "还没有菜单项…鼠标暂时打不开它" | menu item exists in 整理▸ | gestures.md ("卷轴" bullet) vs MenuBarController.swift:146-149 |
| 8 | Notch pinch = "回主屏幕" only | spread = tuck all | notch.md:47 vs Notch.swift:5575-5586 |
| 9 | 晃一晃 = 左右来回 | detector also fires on vertical shakes | gestures.md:556 vs WindowShake.swift:19 |
| 10 | "按住 Option 双击不收起" | any of ⌥⌘⇧⌃ skips | settings text vs EventTapCallback.swift:65-74 |
| 11 | Title-bar long-press menu | implemented, documented nowhere | TrackpadGestures.swift:1257, 1388-1421 |
| 12 | "只用系统语义色" | window-browser traffic lights use fixed sRGB | design-system.md §4.3 vs WindowBrowserTrafficLights.swift:28-33 |
| 13 | §6-14 "单击不等双击间隔，先给按下的反馈" | still waits ≤0.3 s (pulse on mouse-down exists) | design-system.md:709-713 vs Notch.swift:3187-3203 |
| 14 | ⌃⌘0 as the way to arrange thumbnails | not assigned on new installs; code comment/draft still cite it | Thumbnail.swift:16-17; 收成缩略图 draft vs `_errata.json` |
| 15 | draft "收进与放回… 没松手前改方向，窗口跟手回来" | flight cannot be cancelled after release | 设计系统 draft §六 vs Notch.swift:2246-2262 |
| 16 | Collapse is the product's signature "roll" | roll animation defaults OFF and needs Screen Recording | EffectSession.swift:206; WindowFoldEffects.swift:64-71 |
| 17 | design-system §5.11 three-step welcome | superseded by A1/A2/T | `_errata.json` (欢迎使用…, 首次打开…) |
| 18 | Untranslated strings | PiP "上一页/下一页" literals | PictureInPictureViews.swift:~64-66 |

### 3.9 Could not determine (no evidence in this pass)

- Real-device behaviour of Magic Mouse, 3-finger drag lifts and background-app haptics (gestures.md "还没在真设备上确认的"; GestureHUD armed haptic unverified for a non-frontmost app).
- VoiceOver / Full Keyboard Access traversal of strips, notch row, overview, PiP, Slide Over (window-management-quality-progress.md "待验收").
- AX-verification latency before the HUD appears (only the 140/100 ms fold-follow numbers are documented, gestures.md:304-318).
- Interaction of the split handle with system-tiled windows; PiP/Slide-Over zones vs system PiP and hot corners; Stage Manager for every feature except fold (not_run).
- Visual design judgments for the HTML drafts (not rendered), pixel geometry, colour/contrast numbers.
- Window-browser hover internals, Preferences UI wording and the complete per-row default table were only sampled.
