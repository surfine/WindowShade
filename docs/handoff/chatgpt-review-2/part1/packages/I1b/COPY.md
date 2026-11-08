# I1b 原文与字符串来源

源码中的字符串表达式原样列出。模型ID、协议字段和值不当作界面译名；真正界面用法由WORKORDER指定。纯包没有字符串则不新增文案。private动态值不写日志。

```swift
// L30
return Result(kind: .unknown, mayRewrite: false, reason: "事件来源未确认")
// L33
return Result(kind: .siriRemote, mayRewrite: false, reason: "遥控器不用滚轮改写")
// L36
return Result(kind: .magicMouse, mayRewrite: true, reason: "已关联妙控鼠标")
// L39
return Result(kind: .trackpad, mayRewrite: false, reason: "保留触控板原事件")
// L42
return Result(kind: .wheelMouse, mayRewrite: true, reason: "已关联离散滚轮")
// L44
return Result(kind: .unknown, mayRewrite: false, reason: "设备和事件证据不足")
```
