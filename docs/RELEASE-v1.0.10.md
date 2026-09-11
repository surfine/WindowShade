# WindowShade v1.0.10

## 中文

### 这次更新

这一版给窗口加上动态卷帘：屏幕合拢时，桌面或窗口内容会随铰链角度卷起、后退、模糊，再原样展开。

- 动态效果：桌面和窗口两种模式，实时捕获 + Metal 渲染，三种质感（轻柔 / 标准 / 磨砂），触发角度可调，预览进度能拖着看
- 随设备倾斜（实验性）：读取 Apple Silicon 传感器，给桌面效果加一点随姿态变化的视差；静止重力作为基线，只有姿态变化才产生偏移
- 设置重做：效果、卷帘、权限与启动、高级四个页面按 macOS 原生排版重做，校准、实时预览、诊断日志、恢复默认值都在里面
- 恢复更稳：折叠前先记录窗口状态，离屏救援会验证恢复结果，效果出问题时优先还原窗口

设备倾斜读的是 Apple 未公开的传感器接口，之后的系统版本或别的机型可能读不到；读不到时会显示为不可用，不会用模拟数据代替。

升级不会重置辅助功能或屏幕录制授权。

## English

### Highlights

This release gives windows a live shade: as the lid comes down, the desktop or the window content rolls up, recedes, blurs, and unfolds again.

- Dynamic effects: separate desktop and window modes, live capture rendering through Metal, three finishes (Silk, Shade, Frost), an adjustable trigger angle, and a preview you can scrub
- Tilt with device (experimental): reads the Apple Silicon sensor for a subtle parallax that follows the machine's attitude, with resting gravity as the baseline
- Settings rebuilt: Effects, Shading, Permissions, and Advanced now follow native macOS layout, with calibration, live preview, diagnostics, and reset-to-defaults
- Steadier recovery: the fold records window state first, off-screen rescue verifies what it restores, and a failing effect puts the window back

Device tilt reads a sensor interface Apple does not document, so later macOS versions or other Macs may not provide it. When it is unavailable the feature says so rather than substituting simulated data.

Upgrading preserves Accessibility and Screen Recording authorization.
