# Mac 島的彈簧：selector 路徑不成立，真正的來源在 SwiftUI／WindowManager

> 寫於 2026-11-09，macOS 27.2（26B123）拆出的
> `System/Library/PrivateFrameworks/CampoUIInternal.framework/Versions/A/CampoUIInternal`
> （9,207,808 bytes，SHA-256 `833c34a5e77dbacbcc1eb103f4f6bbb3781ebff1df065b32512b2e0b8755c28e`）。
> 工具只有 `llvm-objdump`、`llvm-nm`、`otool`、`dyld_info` 與 Python；沒有 Ghidra、沒有真機。

## 0. 結論（先講）

`HANDOFF-campo-parity.md` 原本假設「島的每個轉場都會在 CampoUIInternal 裡呼叫
`setDampingRatio:`／`setResponse:`」。這個假設**在這個二進位裡不成立**：

- CampoUIInternal 的 `__TEXT,__objc_methname` **size = 0**（split 映像把 selector 字串
  集中到 dyld 共享池，見 §1）。
- 它全部 2,500 個 `__objc_selrefs` 沒有一個指向這兩個 selector。
- 它 1,917 個 `_objc_msgSend$…` stub 符號裡沒有 `setDampingRatio:` 或 `setResponse:`。
- 4,115 個 split 映像逐一掃 `adrp+add` 直接參照，**0 命中**。
- 二進位內 double／float 掃描也找不到 iOS SpringBoard 的那組值
  （0.574／0.39／1.2／1.1／0.92／0.24／0.255／0.289）。

島的底座動畫是 **SwiftUI `Animation`**：`SiriGlassBackdrop` 的 body 型別鏈是
`.animation(Animation?, body:)`，`_windowAnimation` 由外層一路傳進去；形狀本身
（`drawnPlatterSize`、`pinsTopPlatterWidth`／`pinsTopPlatterHeight`）是 `AnimatableData`。
所以「每個轉場一組 ObjC setter 配對」不是這顆二進位的模型，不能拿來當完成判準。

## 1. selector 字串到底在哪裡

`CampoUIInternal` 本身的 `__objc_methname` 是空的；selector 字串在 dyld 共享池：

| selector | 共享池 VM 位址 | 所在檔 |
|---|---:|---|
| `setDampingRatio:` | `0x1f481b6a0` | `dyld_shared_cache_arm64e.26.dyldreadonly` |
| `setResponse:` | `0x1f5389ca0` | 同上 |

取法：讀 `dyld_shared_cache_arm64e.26.dyldreadonly` 的 `dyld_cache_header` mapping
（`map1: vm 0x1f1274000, fileoff 0x4000`），把檔內偏移換成 VM。

## 2. 為什麼掃不到呼叫點

1. **selrefs**：把 CampoUIInternal 的 `__objc_selrefs`（`0x269569e98`，0x4e20 bytes）
   全部解碼。split 映像用的是 cache-relative 指標
   （`target = 0x180000000 + (raw - 0x10000000000000)`），
   2,500 筆裡 0 筆等於上面兩個位址。
2. **stub 符號**：`llvm-nm` 有 1,917 個 `_objc_msgSend$…`，逐字搜
   `setDampingRatio:`／`setResponse:` 都是 0。
3. **直接位址**：對 `mac272_split` 全部 4,115 個 Mach-O 的 `__text` 掃
   `adrp xN, page` + `add xN, xN, #imm`，比對兩個 selector 的完整 VM，0 命中。
   （這一步也順便證明不是「x1 暫存器」寫法的問題——任何暫存器都沒有。）

## 3. 島的動畫實際長什麼樣

`SiriGlassBackdrop`（`__TEXT.__const` 0x264009c20）的欄位：

```
sessionModel, state, subvariantName, cornerRadius, undulationScale,
placeholderGlassFraction, drawnPlatterSize, smoothness,
listeningCollapseProgress, namespace, _reduceMotion, _windowState, metrics
```

它的 nested `AnimatableData` 另有 `pinsTopPlatterWidth` / `pinsTopPlatterHeight`
（見 `mac-island-platter.md` §2）。

符號表裡的 View witness table（`_get_witness_table … SiriGlassBackdrop …`）顯示 body 是：

```
... SwiftUI.View.animation(Animation?, body:) ...
```

而且 `ExpandedMacAssistantIslandSiriView`、`DetachedAssistantIslandView`、
`MacAssistantIslandCausticLayer`、`ThinkingWaveGlassView`、
`MacIslandSizedContentPlaceholder` 都有 `_windowAnimation` 欄位；
`MacIslandPresentationContextDelegate` 的型別引用裡有
`Optional<SpotlightUIShared.WindowSizingAnimation>`。

→ 底座的形狀動畫不是本地常數，是**外面傳進來的 `Animation`**。

## 4. CampoUIInternal 自己的 `Animation.spring` 呼叫點

`0x268083930` 這個 stub 的呼叫約定是三個 double（response、dampingFraction、
blendDuration = 0），回傳 SwiftUI `Animation`；依呼叫形狀判定是
`Animation.spring(response:dampingFraction:blendDuration:)`（**推論**，沒有符號可證明）。
全檔 19 個呼叫點，落點如下：

| 檔案（literal pool 字串） | 參數 |
|---|---|
| `ChatGridView.swift` | (0.5, 1.0) |
| `AttachmentGridView.swift` | (0.5, 1.0) |
| `ChatInputView.swift` | (0.5, 1.0) |
| `ThinkingWaveGlassView.swift` | (0.4, 0.75)、(0.6, 0.75)、(0.5, 1.0) |
| `DetachedAssistantIslandView.swift` | (0.5, 1.0) |
| `InlineThinkingView.swift` | (0.5, 1.0) |
| 無字串的函式 | (0.15, 0.85, blend 0.25)、(0.35, 1.0)、(1.0, 1.0) |

**沒有一個在底座／`SiriGlassBackdrop` 的 body 裡。** 這些是聊天、附件、思考波、
detached 視圖的動畫，不是島的展開／收合。

## 5. Mac 真正的候選來源（尚未接到 Motion）

### 5.1 WindowManager：`WindowSpringBehavior` 預設

`WindowManager.framework` 的 `WindowManagerSpringBehavior` 欄位是
`dampingRatio, response, initialVelocity`（24 bytes）。`__TEXT` 有兩個靜態初始化：

| 位址 | 寫入 global | 值 |
|---|---|---|
| `0x1d2aa5758` | `0x1ed183cd0` | `(damping 1.0, response 0.38, velocity 0)` |
| `0x1d2aa5794` | `0x1ed183cf0` | `(damping 1.0, response 0.30, velocity 0)` |

（`ldr q0, [0x1d2b257f0]` = 1.0/0.38；`ldr q0, [0x1d2b25800]` = 1.0/0.30；
`str xzr` 把 velocity 設 0。）

`SpotlightUIInternal.WindowAnimationContext` 的欄位包含 `initialBehavior`，
`MacIslandPresentationContextDelegate` 又接收 `WindowSizingAnimation?`。
**這是最像「島的底座跟視窗一起用同一條彈簧」的鏈**，但還沒有直接把
`WindowSpringBehavior` → `WindowSizingAnimation` → `SiriGlassBackdrop` 的
資料流釘死，所以不能直接拿 0.38／0.30 寫進 `Motion.notchSpring`。

### 5.2 SpotlightUIInternal：四個已解出的 `Animation.spring` token

`0x2b00958e0` 是同一種三 double 的 `Animation.spring` stub：

| 位址 | 值 | 備註 |
|---|---|---|
| `0x2ade95a50` | `(0.4, 0.7)` | 存到 global `0x2e1b7eb90` |
| `0x2ade994dc` | `(0.2, 0.7)` | 內聯 |
| `0x2adeef4f8` | `(0.2, 1.0)` | 內聯 |
| `0x2aded6730` | `(0.5, 1.0)` | 條件式 optional |

這些是 Spotlight 視窗／翻譯動畫的 token，尚未證明哪一個是島的
`WindowSizingAnimation.expansion`／`collapse`。

## 6. 要完成「一比一」還缺什麼

三條可走的路，按可證性排序：

1. **把 5.1 的鏈釘死**：找 `WindowAnimationContext.initialBehavior` 的型別與
   `WindowSizingAnimation` 的建構點，證明島的 `_windowAnimation` 就是用
   `WindowSpringBehavior` 造的。若成立，展開／收合只有兩組
   `(1.0, 0.38)`／`(1.0, 0.30)`，不是九組；Motion 應改成**方向**而不是形狀取令牌。
2. **把 5.2 的 token 對到 `WindowSizingAnimation`**：需要解析 SpotlightUIInternal
   的 `WindowAnimationCoordinator` 或 `WindowTranslation.Animation` 建構點。
3. ~~**等 27.3 Mac 映像**：27.3 beta 的 `CampoUIInternal` 可能改走 AnimationKit；
   目前 `/Volumes/TiPlus 7100/ws-macos-27.3/` 的 AppleArchive 索引層未解。~~
   已完成，見 §7：27.3 仍然沒有改走 AnimationKit。

**§6 與 §7.5 的關係（2026-11-09 補）**：§6 說「在 1 或 2 成立之前不改
`Motion.notchSpring`」，指的是**外層 `WindowSizingAnimation`** 那條鏈。§7 找到的是
另一條更直接的來源：27.3 `MacAssistantIslandSessionModel` 自己的 `#islandSizing`
token。§7.5 已用後者接進 `Motion.notchSpring`，**取代 §6 的暫緩條件**；但 §6 的
1／2 仍是 `.hidden` 收合由誰承接的未解問題，見 §7.4 與 Phase 3。

## 7. macOS 27.3 beta（26C5035r）的複核（2026-11-09）

### 7.1 怎麼把 27.3 系統卷拆出來

`/Volumes/TiPlus 7100/ws-macos-27.3/` 的 `SharedSupport.dmg` 內是
`com_apple_MobileAsset_MacSoftwareUpdate/fa26b26a…aea`（19 GB，AEA 加密）。
AEA 解密後不是普通 tar，而是兩層：

1. 外層是 **chunked AppleArchive**：55 個 `DAT` blob，每個 blob 是一個內層
   AppleArchive；`DAT` 前面有 `TYP/YOP/LBL` 欄位。
2. 內層才是檔案樹（`AssetData/payloadv2/...`），其中：
   - `basesystem_patches/arm64eBaseSystem.dmg`（`BXDIFF50`）
   - `image_patches/cryptex-system-arm64e`（`RIDIFF10`，1,554,542,282 bytes）
   - `image_patches/cryptex-system-arm64e.x1`（delta on 上者）
   - `image_patches/cryptex-app`、`cryptex-system-rosetta`
   - `fixup.manifest`、`payloadv2.bom`、`image_patches.plist`

`cryptex-system-arm64e` 直接套在 27.2 的 system cryptex 上（不需要 base）：

```bash
cd "/Volumes/TiPlus 7100/tmp273"
ipsw ota patch rsr --cryptex "/Volumes/TiPlus 7100/tmp273/cryptex-system-arm64e"
# -> cryptex-system-arm64e.dmg (2.7 GB, raw APFS, macOS 27.3 26C5035r)
hdiutil attach -readonly -nobrowse cryptex-system-arm64e.dmg
ipsw dyld split .../System/Library/dyld/dyld_shared_cache_arm64e -o split273
```

產物留在外接碟，勿重跑：

| 路徑 | 內容 |
|---|---|
| `/Volumes/TiPlus 7100/tmp273/cryptex-system-arm64e.dmg` | 27.3 系統 APFS 映像（2.7 GB） |
| `/Volumes/TiPlus 7100/tmp273/split273/` | 27.3 dyld cache 拆出的 4,142 個映像 |

### 7.2 結果：27.3 也沒有 selector，也沒有 AnimationKit

`CampoUIInternal`（27.3）：

- SHA-256 `51bddcd19eebb6552b3933fe73ae93b40d4ffa436c10c5b8c784727bdcf747aa`（9.6 MB）。
- `__objc_methname` 仍然 size = 0；`setDampingRatio:`／`setResponse:` 字串只存在
  27.3 共享池（`0x1f48d4930`／`0x1f4960ab0`）。
- 2,537 個 `__objc_selrefs` 沒有一筆指向它們；1,947 個 `_objc_msgSend$…` stub
  也沒有這兩個 selector。
- 全 4,142 個 27.3 映像掃描：85 個 selector 命中，全部是 AnimationKit／
  UIKitCore／Network 等既有使用者；**CampoUIInternal、SpotlightUIInternal、
  WindowManager、AssistantIsland 都是 0**。`adrp+add` 直接參照 0 命中。
- 沒有任何 `AnimationKit`／`SpringAnimationBehaviorSettings` 字串或依賴。

島的動畫模型也沒有變：`SiriGlassBackdrop` body 仍是
`.animation(Animation?, body:)`，仍有 `Optional<WindowSizingAnimation>`。

### 7.3 但 27.3 多了明確的島彈簧 token（新線索）

27.3 的 `CampoUIInternal/MacAssistantIslandSessionModel.swift` 新增了四個
static animation token，`#islandSizing` 的函式（`0x2653ee080`）會用到：

| global | 值 | 來源 |
|---|---|---|
| `0x274434230` | 預設 animation（`0x2680b8cd0`） | `0x2653edd1c` |
| `0x274434238` | 預設 animation（`0x2680b8cd0`） | `0x2653edd74` |
| `0x274434240` | spring：mass 2.0 / stiffness 619.0216 / damping 52.7788 → **response ≈ 0.3572、dampingRatio 0.75** | `0x2653edd3c` |
| `0x274434248` | spring：**response 0.408、dampingRatio 0.27** | `0x2653edd94`，`0x2653b6ac0` 的 physics 轉換 |

同一顆二進位另有 `(0.6, 0.75)`／`(0.4, 0.75)` 兩個 `Animation.spring` token
（`0x274434250`／`0x274434258`），但使用點不在 `#islandSizing`，而是在
ThinkingWave／其他 view。

**這是目前最接近「Mac 島自己的轉場彈簧」的證據**：27.3 不再只靠外層
`WindowSizingAnimation`，`MacAssistantIslandSessionModel` 自己就有兩組彈簧。

### 7.4 `#islandSizing` 的分支對到哪個狀態

`0x2653ee080` 先用 `0x2653ef564` 取一個 0…5 的動畫 tag，再在
`0x2653ef204` 的 jump table 分流（tag > 3 會 clamp 到 0）：

| tag | jump target | 用的 token | 對應狀態（由呼叫點的 log 字串直接證得） |
|---:|---|---|---|
| 0 | `0x2653ee6f0` | `+0x248`（0.408／0.27） | `.siri(.listening)` |
| 1 | `0x2653ee964` | base `+0x240`（≈0.3571／0.75） | `.siri(.thinking)` |
| 2 | `0x2653ee738` | base `+0x240` | `.siri(.response)` |
| 3 | `0x2653ee7bc` | base `+0x240` | `.siri(.transient)` |
| 4 | `0x2653ef1e0` | 直接 return，不跑尺寸動畫 | `.hidden` |
| 5 | clamp 到 0 | `+0x248` | `.prompt` |

tag 的寫入點是 `0x2653dac14`（再呼叫 `0x2653ddfe8` 比較新舊 tag），每個
呼叫點都直接帶著狀態的 log 字串與常數：

| tag | 證據（呼叫點） |
|---:|---|
| 0 | `"transition(to: .siri(.listening))"`、`"#launchListening Presenting listening docked to the cutout"` → `sturb wzr` |
| 1 | `"transition(to: .siri(.thinking))"` → `w24 = #0x1`，存進 tag byte |
| 2 | `"transition(to: .siri(.response))"` → `mov w8, #0x2; strb w8` |
| 3 | `"#transientBreakout Transitioning to in-island transient state"` → `mov w8, #0x3` |
| 4 | `"#islandWindow ... Transitioning to .hidden!"` → `mov w8, #0x4` |
| 5 | `"transition(to: .prompt)"`、`"Escape key pressed ... transitioning to prompt"` → `mov w8, #0x5` |

base `+0x240` 是在 jump table 之前（`0x2653ee588`）設好的交易動畫；tag 0
的 case 用 `+0x248` 覆蓋，tag 1–3 回到 base，tag 4 直接返回。呼叫點也對得上：
`#islandSizing Thinking size requested` 在 tag 1／4 呼叫，`Response size requested`
在 tag 2／4 呼叫。

### 7.5 已接進 `Motion.notchSpring`（2026-11-09）

`Motion.notchSpring` 現在只用這兩組 27.3 Mac 值：

| WindowShade 狀態 | 令牌 | 27.3 來源 |
|---|---|---|
| `.listening`／`.prompt`（認證、畫手勢、錄音、等你的會話） | `islandPrompt` `(0.408, 0.27)` | `+0x248`，tag 0／5 |
| `.thinking`／`.response`／`.transient` | `islandSizing` `(0.3571428536916519, 0.7500006097576885)` | `+0x240`，tag 1–3 |
| `.hidden`（收合） | `islandHidden` `(0.3, 0.8, bounce 0.2)` | `WindowSizingAnimation.default` → `AxisAnimation.default`（§7.6） |
| 減少動態效果 | `reducedNotch` | 不變 |

`.minimum`（收合）在系統裡是 tag 4，**不跑島自己的尺寸動畫**；收合由窗口尺寸的
默認動畫承接，該默認值已在 27.3 釘死（§7.6），所以 WindowShade 用 `islandHidden`，
不再借用 `islandSizing`。

實時活動撐起緊湊兩耳時，活動自己也可以選：錄音與「等你」的編程會話用
`islandPrompt`（tag 5 的 prompt 語義），其餘活動落回 `islandSizing`；
見 `Core/NotchActivityMotion.swift` 與 `NotchController.motionState()`。
其餘形狀到狀態的對應是「使用者注意力」＝ prompt/listening、「內容變化」＝
thinking/response/transient，寫在 `Motion.notchSpring` 的註解裡。

### 7.6 `.hidden` 的收合由誰承接（2026-11-09 追蹤結果）

結論：**已證得**。`WindowSizingAnimation.default` 的兩軸都用
`Spring(duration: 0.3, bounce: 0.2)`；`islandHidden` 已落地，`.hidden` 不再借用
`islandSizing`。

證據鏈（全部在 27.3 映像內）：

1. `#islandSizing`（`0x2653ee080`）在 tag 4（`.hidden`）直接 return，不跑島自己的
   尺寸動畫；收合由外層 window sizing 承接。
2. `SpotlightUIShared.WindowSizingAnimation.default` getter（`0x22f9efc10`）把
   `AxisAnimation.default` 同時複製給 horizontal／vertical。
3. `AxisAnimation.default` 的 lazy 初始化器（`0x22f9ef4bc`）用
   `0x3FD3333333333333`（0.3）與 `0x3FC999999999999A`（0.2）構造
   `SwiftUI.Spring.init(duration:bounce:)`（stub `0x23005c940`），再呼叫
   `Animation.spring(_:blendDuration:)`（stub `0x23006f150`）。
4. 因此 `.hidden` = response 0.3、dampingRatio 0.8（bounce 0.2）。

早期「未證得」的記錄保留在下面，作否證過程：

27.3 的二進位證據：

1. `WindowSizingAnimation`（SpotlightUIShared）不是參數化的彈簧，而是
   `expansion / collapse / alongside / alongsideWithContext` 四個案例；
   每個案例的 `AxisAnimation` 只存 `SwiftUI.Animation`
   （`__swift5_reflstr` 的 `horizontal.vertical…` 與
   `_symbolic 7SwiftUI9AnimationV`）。真正的數值在「誰造 Animation」那一層。
2. SpotlightUIShared／SpotlightUIInternal／CampoUIInternal 三個 27.3 映像裡
   **都掃不到** 0.4／0.7 這組 double 或 float 常數（各 0 命中；0.5、1.0、0.2
   倒是有零星資料常數，但沒有成對出現在 `Animation.spring` 呼叫附近）。
   → 27.3 的 sizing Animation 不是由 Spotlight 自己硬編碼的常數造的；
   §5.2 的 27.2 token 不能直接搬到 27.3。
3. 島的 `_windowAnimation` 在 Campo 的 `_symbolic` 表裡與
   `SpotlightUIShared.WindowSizingAnimation`、`ResultPlatterBehavior`
   相鄰（`0x93aa6f`／`0x93ab2f`），可確認是 optional 的這兩種型別。
   但 Campo 只有一筆 `WindowManager.WindowManagerSpringBehavior` 的
   `_symbolic` 參照（`0x94fb20`），且落在 ChatID／AgentCanvas 的型別鏈裡，
   **不能**證明島的 sizing 用它。
4. WindowManager 的 `SpringBehavior` 預設仍是
   `response 0.38 / dampingRatio 1.0` 與 `response 0.30 / dampingRatio 1.0`
   （`0x131a90` 靜態初始化；accessor `0x1d319dee0` 回 1.0、
   `0x1d319dee8` 回 0.38、`0x1d319def4` 回 0.30）。這是島窗口鏈裡唯一的
   具體彈簧數值，但沒有釘死到 `.hidden`。

以上 1–4 是「為什麼不能直接用 WindowManager 0.38／0.30」的否證；
`.hidden` 的真正來源在同一輪後續分析裡釘死：`WindowSizingAnimation.default`
的軸動畫（§7.6 開頭）。因此 `.hidden` 用 `islandHidden`，WindowManager 的
0.38／0.30 仍不進島的令牌表。
