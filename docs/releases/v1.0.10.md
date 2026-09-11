# WindowShade v1.0.10

## 中文

### 这次更新

这一版把窗口折叠做成了实时效果，并补上了设备倾斜。

- 动态效果：桌面和窗口的卷帘改用 ScreenCaptureKit 与 Metal 实时渲染，支持实时帧、标题栏锚定、反向过渡和恢复校验
- 随设备倾斜（实验性）：设置 → 效果 里的开关，读取 Apple Silicon 的传感器，给桌面效果加一点空间视差
- 设置重做：效果、卷帘、权限与启动、高级四个页面按原生 macOS 的排版和材质重排，样式、触发角度、校准、实时预览和诊断日志都能直接调
- 恢复更稳：隐藏失败、窗口关闭、显示器变化、过期捕获会话和取消动画都会留下记录；效果出问题时先还原窗口

设备倾斜走的是 Apple 没有公开的 HID 接口，以后的系统版本或别的机型可能读不到；读不到时会显示为不可用，不会用模拟数据糊过去。

升级不会重置辅助功能或屏幕录制授权。

## English

### Highlights

This release turns folding into a real-time effect and adds device tilt.

- Dynamic effects: desktop and window shades now render live with ScreenCaptureKit and Metal, with live frames, title-bar anchoring, reverse transitions, and restore verification
- Tilt with device (experimental): a switch under Settings → Effects reads the Apple Silicon sensor to add a little parallax to the desktop effect
- Settings rebuilt: Effects, Shading, Permissions, and Advanced now follow native macOS layout and materials, with styles, trigger angle, calibration, live preview, and diagnostics on the page
- Steadier recovery: failed hides, closed windows, display changes, stale capture sessions, and cancelled animations all leave a record, and a failing effect restores the window first

Device tilt uses an HID interface Apple doesn't document, so later macOS versions or other Macs may not provide it. When reports are unavailable the feature shows as unavailable rather than faking data.

Upgrading preserves Accessibility and Screen Recording authorization.
