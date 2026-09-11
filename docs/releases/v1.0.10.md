# WindowShade v1.0.10

让窗口折叠更有空间感，也让恢复链路更容易观察、更可靠。

下载 `WindowShade-v1.0.10.zip`，解压后打开 `WindowShade.app` 即可。签名身份与 v1.0.9 一致，覆盖安装不会重置辅助功能与屏幕录制授权。

## 中文

### 主要更新

- **动态卷帘效果**：桌面与窗口效果改用 ScreenCaptureKit 与 Metal 实时渲染，支持实时帧、窗口形变、标题栏锚定、反向过渡和恢复校验。
- **设备倾斜（实验性）**：新增“随设备倾斜”开关，为桌面效果加入轻微空间视差。Apple Silicon 的 AppleSPU HID 路径会先唤醒传感器驱动再开始采样，静止重力作为基线，只有设备姿态变化才产生偏移。
- **设置体验**：效果、卷帘、权限与启动、高级设置四个页面统一为原生 macOS 排版、材质、分组和状态反馈，并补齐样式、触发角度、校准、实时预览、诊断日志与恢复默认值。
- **恢复与边界处理**：恢复日志覆盖隐藏失败、窗口关闭、显示器变化、过期捕获会话和取消动画；动态效果无法继续时优先恢复源窗口。

### 本次构建说明

本次以同一版本号重新发布安装包，修好了设备倾斜读不到传感器的问题。旧构建只打开 HID 设备、没有向驱动请求上报，设置页因此停在“空间倾斜不可用：无法读取原始传感器报告”。现在开始采样前会先请求 `AppleSPUHIDDriver` 上报，并单独区分“系统未能唤醒传感器”“系统拒绝访问 HID 设备”“未检测到加速度计”和“收不到报告”几种情况。

已经装过 9 月 11 日那份 v1.0.10 的话，重新下载覆盖即可；版本号不变，安装包内容已更新，校验值以随附的 `.sha256` 文件为准。

### 验证

- 编译与测试：Swift 类型检查、签名 arm64 构建、核心与恢复测试、原生窗口夹具、边缘窗口测试、DuoBook shader 对照、Retina 原生合成检查，全部通过。
- 效果稳定性：30 分钟真实捕获 / 显示 soak，无中断。
- 传感器实机验证：Apple M5 MacBook Air（Mac17,4，macOS 26.5）上收到稳定的 22 字节三轴 HID 报告，静止读数约为 1g；本轮生产构建的设置页显示“角度传感器已连接 · 空间倾斜传感器已连接”。

### 已知边界

- 支持 macOS 14 及以上；按功能需要辅助功能与屏幕录制权限。
- 设备倾斜依赖 Apple 未公开的 AppleSPU HID 接口，未来 macOS 版本或其它机型可能改变属性或报告格式。系统不提供报告时功能会显示为不可用，不生成模拟数据。
- 建议在常用的 Finder、Safari、Electron 等真实窗口上做一次回归。锁屏效果、辅助进程、SIP 修改和 HDR 专用路径不在本版本范围内。

## English

WindowShade v1.0.10 makes folding feel more spatial while making recovery behavior easier to inspect and trust.

Download `WindowShade-v1.0.10.zip`, unzip it, and open `WindowShade.app`. The signing identity matches v1.0.9, so installing over an older copy keeps your Accessibility and Screen Recording grants.

### Highlights

- **Dynamic folding effects**: desktop and window effects now render in real time with ScreenCaptureKit and Metal, including live frames, window geometry, title-bar anchoring, reverse transitions, and restore verification.
- **Experimental device tilt**: a new “Tilt with device” switch adds subtle parallax to the desktop effect. The Apple Silicon AppleSPU HID path now wakes the sensor driver before sampling, keeps resting gravity as a baseline, and only reacts to changes in device attitude.
- **Refined settings**: effects, folding, permissions and startup, and advanced settings share a native macOS layout, material treatment, grouping, and status feedback, with styles, trigger angle, calibration, live preview, diagnostics, and reset-to-defaults.
- **Stronger recovery**: the recovery journal covers failed hides, closed windows, display changes, stale capture sessions, and cancelled animations, and an effect that cannot continue restores the source window first.

### About this build

This release re-uses the v1.0.10 version number with a refreshed installer that fixes device-tilt sensor reads. The previous build opened the HID device without asking the driver to report, so the settings page stayed on “Spatial tilt unavailable: could not read raw sensor reports.” Sampling now requests reports from `AppleSPUHIDDriver` first and distinguishes a driver that will not wake, a refused HID open, a missing accelerometer, and a device that never reports.

If you already installed the earlier v1.0.10 build, download and overwrite it; the version number is unchanged but the package is not. Use the attached `.sha256` file to verify the download.

### Validation

- Build and tests: Swift type checking, a signed arm64 build, core and recovery tests, native-window fixtures, edge-window tests, DuoBook shader parity, and Retina native-composite inspection all pass.
- Effect stability: a 30-minute real capture/presentation soak ran without interruption.
- Sensor hardware: on an Apple M5 MacBook Air (Mac17,4, macOS 26.5) the path produced stable 22-byte three-axis HID reports with a resting magnitude near 1g, and this production build reported “angle sensor connected · spatial tilt sensor connected” in Settings.

### Known boundaries

- macOS 14 or later. Accessibility and Screen Recording permissions are requested per feature.
- Device tilt depends on Apple’s private AppleSPU HID interface. Future macOS releases or other hardware may change its properties or report format; when reports are unavailable the feature shows as unavailable instead of synthesizing sensor data.
- A regression pass on everyday Finder, Safari, and Electron windows is still recommended. Lock-screen effects, helper agents, SIP changes, and HDR-specific paths are outside this release’s scope.
