# D1 原文与字符串来源

源码中的字符串表达式原样列出。模型ID、协议字段和值不当作界面译名；真正界面用法由WORKORDER指定。纯包没有字符串则不新增文案。private动态值不写日志。

```swift
// L17
case .hidden: return ""
// L18
case .connected(let project, let provider, let effort): return "指挥 · \(project) · \(provider.displayName) · \(effort)"
// L19
case .domain(let model): return model ? "现在选模型" : "现在选档位"
// L20
case .trajectory: return "抬手才判定"
// L22
case .next(let current, let next): return "这一轮 \(current) · 下一轮 \(next)"
// L23
case .cost(let label): return "\(label)　点一下确认"
// L24
case .sessions: return "会话列表"
// L25
case .waitingForAudio: return "没有收到声音"
// L26
case .listening(let source): return "\(source) · 松开出草稿"
// L27
case .transcribing: return "正在转写"
// L29
case .sent: return "发出去了"
// L30
case .accepted(let provider, let effort): return effort.map { "\(provider.displayName) 接受了 · \($0)" } ?? "实际档位还没确认"
// L31
case .running: return "开始跑了" // turnID 是不透明 ID，不能伪装成“第 4 轮”。
// L32
case .steering: return "正在补进这一轮"
// L33
case .steered: return "已补进这一轮"
// L34
case .stopping: return "正在停止…"
// L35
case .stopped: return "已停止"
// L36
case .completed(let summary): return "完成 · \(summary)"
// L37
case .approval(let summary): return "想执行 \(summary)"
// L38
case .voiceChallenge: return "念出这句话，或在 Mac 上用 Touch ID"
// L39
case .authenticating: return "正在确认"
// L40
case .discardDraft: return "再按一次返回丢掉草稿"
// L41
case .disconnected: return "遥控器断开了"
// L42
case .revoked: return "这台 iPhone 不能再指挥"
// L43
case .exited(let running): return running ? "已退出指挥模式 · 任务还在跑" : "已退出指挥模式"
// L44
case .muted(let yes): return yes ? "提示音已关" : "提示音已开"
// L160
private var candidateLabel = ""
// L197
if let current = context, current.peerID != envelope.context.peerID { return show(.message("另一台 iPhone 正在指挥")) }
// L224
effects += show(.message("能力信息变了，请重新选择档位"))
// L240
guard item.baseDraftRevision == draftRevision else { return show(.message("草稿已修改，未覆盖")) }
// L245
capture = nil; source = nil; effects += show(.message("麦克风断开了，草稿保留"))
// L262
effects += show(.message("后端拒绝了，草稿保留"))
// L272
effects += show(.message("要的 \(requested.effort)，实际 \(config.effort)"))
// L287
case .notExecuted: recoverDraft(item); effects += show(.message("这次没有执行，草稿保留"))
// L312
approval = nil; challenge = nil; approvalBusy = false; effects += show(.message("已处理"))
// L399
stroke = nil; return show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")"))
// L421
case .failure: return show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")")) + sound("未识别")
// L431
return show(.message("这个模型不支持当前档位，保持原设置"))
// L436
nextConfig = config; return [.stageConfig(config)] + show(.staged(label: "下一轮 · \(cap.model.modelID)"))
// L448
case .tone(let n): gestureName = ["一声","二声","三声","四声"][n - 1]
// L449
case .beats(let n): gestureName = ["一拍","二拍","三拍","四拍","五拍","六拍"][n - 1]
// L451
return [.stageConfig(config)] + show(runningTurn != nil ? .next(current: currentConfig?.effort ?? "实际档位还没确认", next: config.effort) : .staged(label: "\(gestureName) · \(label)　下一轮")) + sound("已识别")
// L466
return [.stageConfig(c.binding.config)] + show(.staged(label: "已确认"))
// L483
guard backendReady, let context else { return show(.message("正在确认后端状态")) }
// L484
guard command == nil, uncertainCommand == nil else { return show(.message("等待后端确认，不重复发送")) }
// L485
guard capture == nil else { return show(.message("先结束录音")) }
// L490
return show(.message("草稿来自另一个会话，请先修改或丢弃"))
// L498
capabilities.contains(where: { $0.accepts(config) }) else { return show(.message("能力信息不可用，请重新选择")) }
// L503
return proposeCost(config, label: config.workflowID == nil ? config.effort : "ultracode · xhigh · 工作流程开启", sequence: gate.lastSequence, now: now)
// L520
guard let source else { return show(.message("没有可用的麦克风")) }
// L540
return show(text.isEmpty ? .message("草稿已清空") : .draft(text))
// L551
if sessionList != nil { sessionList = nil; return show(.message("已取消")) }
// L552
if candidate != nil { candidate = nil; costVault.invalidate(); costBinding = nil; return show(.message("已取消")) }
// L555
return [approvalEffect(request, confirmation: Confirmation(beganAt: now, sequence: gate.lastSequence), confirm: false, deny: true, voice: false)] + show(.message("不允许"))
// L560
return show(.message("草稿已丢弃"))
// L573
guard !choices.isEmpty else { return show(.message("没有可用的会话")) }
// L580
return show(.sessions(choices.map { "\($0.label) · \($0.context.session.provider.displayName) · \($0.running ? "在跑" : "空闲")" }, selected: index))
// L587
effects += show(.message("审批已交回原处"))
// L595
candidate = nil; costVault.invalidate(); costBinding = nil; effects += show(.message("确认已过期"))
// L599
else { capture = nil; effects += show(.message("转写没有完成，草稿保留")) }
// L603
effects.append(.requestCommandStatus(c.id, context)); effects += show(.message("结果还没确认，不重复发送"))
// L610
stroke = nil; effects += show(.message("没认出，保持 \(nextConfig?.effort ?? "原设置")"))
```
