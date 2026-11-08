# D2 原文与字符串来源

源码中的字符串表达式原样列出。模型ID、协议字段和值不当作界面译名；真正界面用法由WORKORDER指定。纯包没有字符串则不新增文案。private动态值不写日志。

```swift
// L22
guard isValid else { return .unavailable("能力信息不可用，保持原设置") }
// L30
supportedEfforts.contains("xhigh"), let workflow = ultracodeWorkflowID {
// L31
return .supported(WS2.ExecutionConfig(model: model, effort: "xhigh", workflowID: workflow,
// L33
caption: "ultracode · xhigh · 工作流程开启")
// L35
return .unavailable(requested == .ultra ? "没有 ultra，保持原设置" : "这个模型没有 \(value)，保持 \(current)")
// L41
return model.provider == .claudeCode && config.effort == "xhigh" &&
// L60
guard (1...4).contains(number) else { return .unavailable("模型只有四个位置") }
// L61
guard let model = slots[number - 1] else { return .unavailable("位置 \(number) 的模型不可用") }
// L63
guard matches.count == 1 else { return .unavailable("位置 \(number) 的模型不可用") }
```
