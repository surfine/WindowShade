# 门 2 几何放宽记录（逐条，护栏要求）

消费者对 zh 帧做逐标签几何 0.5pt 对比时，有两条标签在基线与当前帧之间不一致。
逐条核查后确认：**两条都是改动前就存在的 wrappingLabel 折行/自然宽歧义，且基线自身在同一
run 内就不稳定**，不是本批语言迁移引入。按护栏"判据不许私放宽；要放宽只允许逐条、写入证据、
并说明原判据为何不成立"记录如下（第27批交接 §4 的滑杆行是第三条同类，已由门 0 以产品实测
形态钉住，不在本文件范围）。

## 1. 「需要已绑定身份的蓝牙读回来源」（x 漂移）

- 位置：卷帘页「专注与输入」补充面板四条 gate 注记之一（`WS2SupplementPane.swift:40`，
  `NSTextField(wrappingLabelWithString:)`，11pt 折行标签）。
- 现象：before 基线（本次重建，`/tmp/batch27-before/out`）四个 zh 帧的 x = 82 / 484.5 /
  348.5 / 82——同一 run 内四帧三个位置；dark-696 帧里四条注记三条落在行中位（463–495.5）、
  一条落在行首（82）。after 四帧全部稳定 x=82。
- 核查：两树该文件几何代码同构（本批只把字符串换成 `WSL10n.text` 包装，行构造未动）；
  before/after 的其余三条注记 x 逐帧一致（473.5/495.5/463）。折行起点由求解器在等价约束
  间二选一，环境敏感。
- 处置：几何对比跳过该标签的 x/w（y/h 仍核对；文本与 ax 仍全量核对）。

## 2. 「名单里还没有 App」（宽漂移）

- 位置：卷帘页专注行的空态说明（`WS2FocusSettings.swift:41` 走 `WS2SettingsCopy` 行构造；
  同文还在 `PrivateAppListSettings.swift:124`），wrappingLabel。
- 现象：before 基线 dark-560 宽 94、light-560 宽 476（同一 run 两帧不一致，即"自然宽"与
  "拉满"两形态）；light-696/dark-696 均宽 612（拉满）。after 四帧全部稳定：560 两帧 476、
  696 两帧 612。
- 核查：同上，两树几何代码同构；基线自身取到两种形态，判据在歧义行上不成立
  （与交接 §4 记录的滑杆行"基线快照本身有歧义"同一性质）。
- 处置：几何对比跳过该标签的 x/w。

## 证据

- before 基线帧：`native/before/frames.json`（本次重建版）
- after 帧：`native/after/frames.json`
- 复跑命令：`python3 tools/design-qa/check-settings-shade-language-preview.py <after> --baseline <before>/out`
- 消费者最终输出：`native/consumer-final.json`（passed=true, 10 帧, 519 输入零漂移）
