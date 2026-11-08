# 系统灵動岛：系统怎么判断、我们怎么让位（韧体实证，2026-11-08）

> 对应拍板第 18 / 28 / 38 条。目标：只有「顶部归系统灵動岛」的机器让位，旧刘海机照常画我们的岛；
> 判断来源必须和系统自己一致，不靠机型猜。

## 1. 系统只有一句判断（最硬的证据）

在本机 macOS 27.0.1（26A434）的 dyld shared cache 里，`-[_HKBehavior currentDeviceSupportsDynamicIsland]`
的反汇编就是一条 MobileGestalt 查询：

```
0x21e16e8f4  pacibsp
...
0x21e16e900  adrp x0, 0x27a6b3000
0x21e16e904  add  x0, x0, #0xc18        ; "DeviceSupportsDynamicIsland"
0x21e16e908  mov  x1, #0
0x21e16e90c  bl   j__MGCopyAnswer
0x21e16e910  ldp  fp, lr, [sp], #0x10
...
0x21e16e924  b    j__objc_autoreleaseReturnValue
```

- 取法：`ipsw dyld disass <DSC> --symbol "-[_HKBehavior currentDeviceSupportsDynamicIsland]"`
  `--symbol-image /System/Library/Frameworks/HealthKit.framework/Versions/A/HealthKit`
- 结论：系统判断「这台机器有没有灵動岛」= `MGCopyAnswer("DeviceSupportsDynamicIsland")`，一个布尔。
  没有第二套机型表可对；HealthKit 只是恰好挂了这个门（`_HKBehavior` 是全系统用的设备能力工具类）。

本机实测（Mac17,4 / M5 MacBook Air，27.0.1）：

```
DeviceSupportsDynamicIsland = false
ProductType                 = Mac17,4
DeviceClass                 = Mac
```

## 2. macOS 上的灵動岛是实时活动的宿主，不是给 App 画画的

27.0.1 的 WidgetKit 导出表里已经有整套 iOS 同款 API（`ipsw dyld tbd` 可复现）：

| 符号 | 含义 |
|---|---|
| `WidgetKit.DynamicIsland` | 岛的视图容器（`view(for:metrics:)`、`expandedContentWidth(for:)`） |
| `WidgetKit.DynamicIslandCompactLayout` `.default` / `.narrow` / `.flexible` | 紧凑样式的三种布局 |
| `DynamicIslandExpandedRegion` / `…RegionPosition` / `…VerticalPlacement` | 展开时左、右、中、下四块与竖直落位 |
| `ExpandedDynamicIslandTopShift`、`liveActivityDynamicIslandAvatarDiameter`、`liveActivityDynamicIslandBadgeDiameter` | 几何量（CGFloat 全局） |
| `isDynamicIslandLimitedInWidth`、`supportedDynamicIslandCompactLayouts` | 宽度受限与能力声明 |
| `ActivityKit` + `WidgetKit` 的 `JindoViewTag` / `JindoMetricsDefinition` | 内部把岛叫 Jindo（跟“岛”同一套命名） |

也就是说：**系统的岛由系统（实时活动宿主）画，App 只提供 `DynamicIsland` 描述的内容**。
第三方在岛的画面上再画一层，既会被系统盖掉、也会和实时活动抢位置——这就是拍板第 18 条要求让位的原因。

## 3. macOS 27.3（26C5035r）固件

- macOS 没有分机型的 IPSW，只有 `UniversalMac_<version>_<build>_Restore.ipsw`。
- 27.3 是 beta，ipsw.me 未收录；走官方软体更新目录拿到 19 GB `InstallAssistant.pkg`，
  内含 AEA 加密的 `com_apple_MobileAsset_MacSoftwareUpdate`（19,058,917,376 bytes，`_UnarchivedSize` 19,844,325,376）。
  FCS 私钥在 `__FCSKeyURL`（`wkms-public.apple.com/fcs-keys/…`），用 `ipsw fw aea --pem` 解得开。
- 27.3 支援的主板（资产里的 `SupportedDeviceModels`，66 个资产）新增 **K114cAP / K114sAP / K116cAP / K116sAP**，
  与旧有的 J 系列（J713/J714/J716… M4 Pro/Max 世代）并列——K 系列即 2026 年这批新 MacBook Pro。
- 未解项（诚实标注）：解开后的 19.8 GB 是 Apple Archive（`AA01`）但 entry 只有 55 个、无 `PAT`/`DAT` 栏位，
  目前停在索引层，还没有拿到 27.3 自己的 dyld shared cache。上面的 API 证据来自 27.0.1 正式版（同一大版本，
  27.0.1 已含完整岛 API）；等真机或拿到 27.3 系统卷时再复核一次。

## 4. 我们怎么用

`Core/SystemIsland.swift`：同一个来源、问一次、按开机缓存。

- `SystemIsland.raw`：1 有 / 0 没有 / -1 问不到（`dlopen` + `dlsym` `MGCopyAnswer`）。
- `SystemIsland.answer`：`raw` 加真机复核开关 `Notch.systemIsland`（`on` / `off`，其余听系统）。
- 问不到 → `unknown`，**不当成有岛**（不抢顶部）。

接入点（`App/Notch.swift`）：

| 位置 | 行为 |
|---|---|
| `NotchController.systemIsland(on:)` | 只有内建屏（`CGDisplayIsBuiltin`）算，外接屏照旧 |
| `slot(on:)` → `SlotKind.systemIsland` | 顶部这段不归我们 |
| `install()` | 按 kind 建面板；换主人时重造 |
| `applyShapes()` | 岛机不要曲线、不要胶囊 |
| `refitShoulders()` | 岛机不画肩 |
| `updateVisibility()` | 岛机不露面（授权层除外） |
| `aims` / `dragMoved` / `tuckFocused` / `tuckAll` | 不朝岛甩、不垂落点小岛、明说收不进去（菜单与两指手势都走这里） |
| `DisplayShapes.notched` | 岛机不读 `bezelPath`、不排形状计算 |

`Notch.systemIsland` 的读取点已按仓库规定登记在 `tools/privacy/registry.json`（signal `settings`），
`tests/run-privacy-registry-check.sh` 通过。

## 5. 真机要验证的三件事（11-06 之后）

1. `--notch-shape` 探针第一行会打印 `INFO system-island: present/absent/unknown (raw=N)`。
   岛机上应是 `present`；如果 AppKit 仍然报 `auxiliaryTopLeftArea`，我们的 kind 判断会先赢，面板不会画。
2. 岛的几何：目前不猜。系统的紧凑/展开尺寸由实时活动宿主决定，`WidgetKit` 只暴露上面那几个量；
   要量就量系统岛的**外框**（`NSScreen.safeAreaInsets` 与辅助区）而不是我们的面板。
3. 实时活动：拍板第 18 条说“尽量走系统”。`WidgetKit.DynamicIsland` 在 macOS 已可用，
   我们的活动要不要改成 ActivityKit 投稿，等真机上验证系统的岛收不收第三方活动再定。
