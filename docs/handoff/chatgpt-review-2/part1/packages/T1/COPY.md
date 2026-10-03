# T1 原文与字符串来源

源码中的字符串表达式原样列出。模型ID、协议字段和值不当作界面译名；真正界面用法由WORKORDER指定。纯包没有字符串则不新增文案。private动态值不写日志。

```swift
// L34
private(set) var day = ""
// L59
if seconds <= 60 { return "\(seconds / 60):\(String(format: "%02llu", seconds % 60))" }
// L60
return "\((seconds + 59) / 60) 分"
// L64
return "\(seconds / 60):\(String(format: "%02llu", seconds % 60))"
```
