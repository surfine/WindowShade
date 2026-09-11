# WindowShade v1.0.10

## 中文

### 这次更新

新增动态效果并继续加固恢复链路。

- 新增桌面与窗口动态开合效果，使用 ScreenCaptureKit 和 Metal 渲染
- 窗口折叠和展开支持实时帧、标题栏锚定、反向过渡和恢复校验
- 菜单保留铰链角度状态、窗口折叠、置顶预览和现有快捷键
- 恢复日志覆盖隐藏失败、窗口关闭、显示器变化和过期捕获会话
- 效果设置支持样式、触发角度、校准、实时预览和屏幕录制权限说明

验证通过 Swift 类型检查、签名 arm64 阶段构建、核心测试、恢复测试、原生窗口夹具、边缘窗口测试和 shader 对照测试。

范围：macOS 14+。锁屏效果、辅助进程、SIP 修改和 HDR 专用路径不在范围内。

## English

### Highlights

Dynamic effects and a stronger recovery path.

- Added desktop and window dynamic fold effects using ScreenCaptureKit and Metal
- Added live frames, title-bar anchoring, reverse transitions, and restore verification
- Kept hinge-angle status, window folding, pinned previews, and existing shortcuts in the menu
- Extended the recovery journal for failed hides, closed windows, display changes, and stale capture sessions
- Added effect settings for styles, trigger angle, calibration, live preview, and Screen Recording guidance

Validated with Swift type checking, a signed arm64 stage build, core tests, recovery tests, native-window fixtures, edge-window tests, and shader parity checks.

Scope: macOS 14+. Lock-screen effects, helper agents, SIP changes, and HDR-specific paths remain out of scope.
