# A1 原文与字符串来源

源码中的字符串表达式原样列出。模型ID、协议字段和值不当作界面译名；真正界面用法由WORKORDER指定。纯包没有字符串则不新增文案。private动态值不写日志。

```swift
// L75
summary: "", turnID: nil, tools: [], lastUpdate: now)
// L80
summary: "", turnID: nil, tools: [], lastUpdate: now)
// L92
session.summary = suspended ? "" : summary; session.status = .running
// L97
session.summary = suspended ? "" : summary; session.status = .running
// L109
session.status = .completed; session.summary = suspended ? "" : summary
// L114
session.status = .failed; session.summary = suspended ? "" : summary
// L118
session.status = .disconnected; session.summary = ""; session.turnID = nil
// L206
sessions[key]?.summary = ""; sessions[key]?.tools.removeAll(keepingCapacity: true)
```
