# WindowShade v1.0.10

## 中文

### 动态效果（新）

屏幕合拢时，桌面或窗口内容会随铰链角度卷起、后退、模糊，再原样展开。

- 桌面和窗口两种模式，跟着屏幕实时渲染，三种质感：轻柔 / 标准 / 磨砂
- 触发角度可调，预览进度能拖着看
- 随设备倾斜（实验性）：给桌面效果加一点随机器姿态变化的视差，静止时不会漂移

### 折叠

- 折叠前先记录窗口状态；效果出问题时优先把窗口还原回来，并检查还原结果

### 设置

- 效果、卷帘、权限与启动、高级四个页面按 macOS 原生排版重做
- 校准、实时预览、诊断日志、恢复默认值都在页面里

设备倾斜读的是 Apple 未公开的传感器接口，之后的系统版本或别的机型可能读不到；读不到时会显示为不可用，不会用模拟数据代替。升级不会重置辅助功能或屏幕录制授权。

## English

### Dynamic effects (new)

As the lid comes down, the desktop or the window content rolls up, recedes, blurs, and unfolds again.

- Separate desktop and window modes that render the screen live, in three finishes: Silk, Shade, Frost
- Adjustable trigger angle, and a preview you can scrub
- Tilt with device (experimental): a subtle parallax that follows how the machine is held, with no drift while it is still

### Folding

- Fold state is recorded before hiding, and a failing effect puts the window back and checks that it really returned

### Settings

- Effects, Shading, Permissions, and Advanced were rebuilt around native macOS layout
- Calibration, live preview, diagnostics, and reset-to-defaults live on those pages

Device tilt reads a sensor interface Apple does not document, so later macOS versions or other Macs may not provide it. When it is unavailable the feature says so rather than substituting simulated data. Upgrading preserves Accessibility and Screen Recording authorization.
