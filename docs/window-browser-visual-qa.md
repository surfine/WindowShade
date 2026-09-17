# 窗口浏览视觉验收

这里的截图来自**生产 AppKit 组件**（`WindowBrowserPanel` /
`WindowBrowserContentView` / 卡片 / 列表 / 材质宿主），只是数据换成确定性的内置
记录与本地生成的占位画面。探针不打开、不激活、不操作任何用户窗口，也不请求屏幕
录制权限；它只短暂显示自己创建的临时面板。

## 截图

文件位置：`docs/visual-qa/window-browser/`；原始输出目录：
`.build/window-browser-shots/`（含 `manifest.txt` 记录 OS/SDK/缩放率/数据来源）。

| 场景 | 文件 | 检查结果 |
| --- | --- | --- |
| 单窗口 Dock | [dock-single.png](visual-qa/window-browser/dock-single.png) | 面板 312×349 pt，标题清楚，图片与标题优先，无大面积空白，操作条紧凑 |
| 三窗口 Dock | [dock-three.png](visual-qa/window-browser/dock-three.png) | 两列、卡片一致，强调只落在当前项 |
| 八窗口列表 | [keyboard-list-eight.png](visual-qa/window-browser/keyboard-list-eight.png) | 行高约 52 pt，长标题单行截断，选中行显示符号操作条，右侧详情对应同一窗口 |
| 键盘搜索 | [keyboard-search.png](visual-qa/window-browser/keyboard-search.png) | 搜索框在顶部，查询文本与结果集一致，选中项有强调 |
| 纸面浅色 | [paper-light.png](visual-qa/window-browser/paper-light.png) | 中性层次与细边线，无发灰/模糊/重复阴影 |
| 纸面深色 | [paper-dark.png](visual-qa/window-browser/paper-dark.png) | 深色下文字与选中边线对比正常 |
| 系统玻璃浅色 | [system-glass-light.png](visual-qa/window-browser/system-glass-light.png) | 控制层由 `NSGlassEffectView` 承载（类型断言见自动化回归） |
| 系统玻璃深色 | [system-glass-dark.png](visual-qa/window-browser/system-glass-dark.png) | 同上；截图本身不含系统合成器的折射 |
| 减少透明度 + 提高对比度 | [reduce-transparency-contrast.png](visual-qa/window-browser/reduce-transparency-contrast.png) | 不透明回退完整，选中不只靠颜色 |
| 无图像/缺权限/折叠/最小化 | [states-without-image.png](visual-qa/window-browser/states-without-image.png) | 每个卡片显示应用图标位与明确原因；已折叠/最小化不使用警告色 |
| Dock 入口的紧凑列表 | [dock-list-many.png](visual-qa/window-browser/dock-list-many.png) | 18 个窗口时列表宽 544 pt，不占满屏幕宽度，改为滚动 |

环境：macOS 27.0（26A428）、Xcode 26.6、macOS SDK 26.5、2x 缩放。

### 交互片段（真实面板状态变化）

[window-browser-interaction.gif](visual-qa/window-browser/window-browser-interaction.gif)
由生产面板连续渲染 17 帧组成，覆盖：键盘入口首次出现 → 方向键移动选择（3 帧）→
搜索逐步输入并过滤（3 帧）→ 切换为缩略图网格并移动选择 → 实时不可用回退到快照 →
切回列表并释放选择。可用来检查“点了就换、选择跟随、画面不闪断”的手感，
生成方式见下面的 `WINDOWSHADE_SHOTS_CLIP=1`。

该 GIF 是面板组件自身的帧序列，不是屏幕录制：首次 Dock 悬停、跨图标切换、图标到
面板的斜向移动、折叠再展开、失败后重试这几段录像需要辅助功能与屏幕录制授权，
本轮未运行（步骤见下文“实机验收”）。

### 这些截图能证明什么

- 布局、间距、字号、选中状态、动作条位置、搜索框位置、状态文案与材质回退都由
  生产组件渲染，设置预览与实际面板使用同一套视图。
- 系统符号图标（卷帘、图钉、暂停、最小化等）在浅深色下都能取到；没有 emoji 或
  任意 Unicode 几何字符充当图标。

### 这些截图不能证明什么

- 不能证明真实 Dock 悬停、真实窗口身份、真实焦点或真实折叠结果——那需要辅助功能
  授权与真实窗口，属于实机验收。
- 系统玻璃的折射需要由系统合成器合成到真实桌面背景上；组件位图只能证明控制层是
  真实的 `NSGlassEffectView`，不能代替整窗截屏。
- 占位画面的颜色块是本地生成的测试数据，与任何用户窗口内容无关。
- 离屏渲染下 AppKit 不会创建视口外的复用单元，因此“120 条滚动只保留可见单元”的
  进一步证据来自性能对照与实机步骤，而不是这组静态图。
- 只覆盖 2x 缩放：本机没有 1x 显示器，1x 的细线锐利度未实测（代码按 backing scale
  对齐像素，见 `WindowBrowserSurfaceStyle.hairlineWidth(for:)`）。
- “细节复杂背景”未实测：纸面路径的面板是不透明的，背景复杂度不进入面板内部；玻璃
  路径在动态桌面上的可读性需要整窗截图（屏幕录制授权）才能判断，本轮只有控制层承载
  真实 `NSGlassEffectView` 的类型证据。

## 隔离验收入口

```sh
cd prototype && ./build.sh --stage          # 隔离构建，不停止正在运行的应用
cd ..
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --window-browser-shots .build/window-browser-shots
```

探针参数：`WINDOWSHADE_SHOTS_DEBUG=1` 会额外打印第一张卡片的 frame 摘要，便于排查
布局回归；`WINDOWSHADE_SHOTS_CLIP=1` 会额外输出
`window-browser-interaction.gif`。已有的只读探针（`--window-browser-catalog-probe`、
`--window-browser-hover-probe`、`--window-browser-thumbnail-probe`、
`--window-browser-idle-probe` 等）继续保留，用于实机诊断。

## 实机只读探针（1.0.13 已安装构建，2026-09-18 运行）

安装 1.0.13 到本机后，用同一个已授权 bundle 跑只读探针：

```sh
prototype/WindowShade.app/Contents/MacOS/WindowShade --window-browser-catalog-probe
# apps=15 windows=17 empty=4 failed=0 total=371ms slowestApp=42ms mainThreadMaxGap=6ms
# resolve identity=0ms geometry=0ms capabilities=0ms
```

真实窗口发现与身份解析通过生产路径执行：15 个应用、17 个窗口，0 失败，最慢应用
42 ms，主线程最大停顿 6 ms；按完整身份的解析（identity/geometry/capabilities）
各 0 ms。功能开启后的实时日志也确认观察器在真实 Dock 上重建成功
（`dock-hover: observer rebuilt ... lists=1`），并写入了 §17.1 的 `perf-summary`。

仍未通过的实机项：`--window-browser-hover-probe` 用合成坐标驱动 AX 命中，真实指针
不在 Dock 上时不返回应用图标（`icon-hit did not resolve a target`，
`notificationsReliable=false`），因此“真实悬停产出目标”必须由人把指针停在 Dock
图标上验证，合成坐标无法替代。

## 实机验收（其余项目未运行）

下面的检查需要辅助功能与屏幕录制授权，并且会真实操作窗口，因此**必须由用户明确
执行**，本轮没有运行：

1. 在带授权的构建上打开设置 → 窗口浏览 → 开启 Dock 悬停。
2. 悬停一个正在运行的应用图标：面板应在约 200–250 ms 后出现，且不改变其他应用
   的键盘焦点（用另一应用保持输入焦点验证）。
3. 在同一应用图标上左右滑动（Dock 放大）：面板内容不重建、选择不丢失。
4. 从图标斜向移动到面板：经过走廊不闪退，进入面板后不自动关闭。
5. 网格/列表切换：画面不闪断，实时流不重新建立（看日志
   `perf: live-first-frame` 只出现一次）。
6. 键盘入口：Escape 关闭、Return 激活、搜索框内输入法与左右键正常。
7. 排布：先“预览”再执行，撤销回到原位置；手动移走窗口后撤销被拒绝。
8. 关闭功能与退出：日志出现 `window-browser: stopped; new resources released` 与
   `perf: panel-resources-released`，原有折叠窗口仍可恢复。

记录模板：逐项写“通过/失败/未运行”，附日志片段（`/tmp/windowshade.log` 中
`perf:` 与 `window-browser:` 前缀）与必要的录屏片段。
