import Cocoa
import CryptoKit

/// 实际 owned 会话样件：用真实 `WS2OwnedLaunchController` 驱动
/// `tests/fixtures/conductor-backend.py` 合成 stdio 后端，在离屏 NotchPanel 里
/// 捕获各阶段画面。不运行真实 codex、真实项目、账号、网络、浏览器或产品 main。
///
/// 适用约束（docs/handoff/START-HERE-deepseek.md 总则）：
/// - 「不假装成功」：每一步失败即停止，绝不盲重试；结果只记录实际观测。
/// - 不合成键盘/鼠标事件：只派发本地诊断按钮action，不点击发送/登录/授权。
/// - 自造项目放系统临时目录的独有目录，避开真实祖先配置；错误路径保留证据、不删输出。
/// - `NSApp` activationPolicy = .prohibited；所有面板置 x = -8000 并验证不与其
///   它任何屏幕相交；只允许宿主自身把面板 orderFront 到屏幕外，不激活、不抢焦点。
@main enum OwnedPhasePreview {
    enum Failure: Error { case check(String) }

    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fixture = repo.appendingPathComponent("tests/fixtures/conductor-backend.py")
        let fixtureSHA = try sha256(fixture)

        // 生产门禁拒绝祖先 .codex/.agents；不能把样件项目放在用户仓库或 HOME 下。
        let buildRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let tempRoot = buildRoot.appendingPathComponent("owned-phase-preview-" + UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // 复制已有 backend 再 chmod，绝不改动原 fixture。
        let backend = tempRoot.appendingPathComponent("synthetic-codex.py")
        let original=try String(contentsOf:fixture,encoding:.utf8)
        let anchor="        emit({\"method\": \"turn/started\", \"params\": {\"threadId\": thread, \"turn\": {\"id\": turn}}})"
        guard original.components(separatedBy:anchor).count==2 else { throw Failure.check("synthetic backend delta anchor") }
        let extraDelta="\n        if text.endswith('native-preview'):\n            emit({'method': 'item/agentMessage/delta', 'params': {'threadId': thread, 'turnId': turn, 'delta': '合成后端回复 · 仅供界面检查\\n' + ('这段长回复用于检查换行、滚动和输入区域，不代表真实助手结果。\\n' * 12)}})"
        let augmented=original.replacingOccurrences(of:anchor,with:anchor+extraDelta)
        try Data(augmented.utf8).write(to:backend)
        try Data(augmented.utf8).write(to:output.appendingPathComponent("synthetic-preview-backend.py"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backend.path)
        let backendSHA = try sha256(backend)

        var frames: [[String: Any]] = []
        var controllers: [WS2OwnedLaunchController] = []
        var report: [String: Any] = [
            "synthetic": true, "noRealAssistant": true,
            "fixtureSource": "tests/fixtures/conductor-backend.py",
            "fixtureSHA256": fixtureSHA, "backendCopySHA256": backendSHA,
            "backendCopy": backend.path, "temporaryRoot": tempRoot.path,
            "activationPolicy": "prohibited",
            "note": "真实 WS2OwnedLaunchController + 合成 stdio 后端；未联系真实助手、账号、网络或浏览器。"]

        do {
            // 产品运行时也只有一份 owned 控制器；换外观不新建第二个会话所有者。
            let controller = WS2OwnedLaunchController(profileRoot: tempRoot.appendingPathComponent("profile"), mayUse: { true })
            controllers.append(controller)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let label = appearance == .aqua ? "light" : "dark"
                let runRoot = tempRoot.appendingPathComponent(label, isDirectory: true)
                let project = runRoot.appendingPathComponent(String(repeating:"long-project-",count:16)+"native-preview", isDirectory: true)
                try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

                // 受控渲染：允许视图认为输入有效，但绝不 performClick，也绝不触发用户动作。
                var owned = WS2OwnedSessionView(controller: controller)
                owned.inputIsCurrent = { true }
                owned.onCancel = {}
                owned.openModelPicker = {}
                owned.openConductorPage = {}

                // 第一轮为idle，第二轮为stopped；记录实际相位，不伪造回到初始状态。
                try capture(name: "before-launch", appearance: appearance, label: label, view: owned,
                            controller: controller, output: output, frames: &frames)
                owned.revoke()

                guard controller.selectProject(project) else { throw Failure.check("selectProject status=\(controller.status) notice=\(controller.notice)") }
                guard controller.selectExecutable(backend) else { throw Failure.check("selectExecutable") }
                guard controller.launch(consent: true) else {
                    throw Failure.check("launch status=\(controller.status) notice=\(controller.notice) project=\(controller.projectURL?.path ?? "nil") executable=\(controller.executableURL?.path ?? "nil")")
                }
                try await until("phase == .ready") { controller.phase == .ready }

                owned = WS2OwnedSessionView(controller: controller)
                owned.inputIsCurrent = { true }
                owned.onCancel = {}
                owned.openModelPicker = {}
                owned.openConductorPage = {}

                // ready：模型来自合成后端的 model/list，不是伪造的 controller 字段。
                guard controller.chooseModel("fixture-a") else { throw Failure.check("chooseModel fixture-a") }
                guard controller.chooseEffort("medium") else { throw Failure.check("chooseEffort medium") }
                guard controller.model == "fixture-a", controller.effort == "medium" else { throw Failure.check("ready model/effort projection") }

                // 在既有 14 帧流程之前，对同一张实际视图做有界输入投影检查。
                try await inputChecks(appearance: appearance, label: label, controller: controller, output: output)

                let picker = WS2ModelPickerView(controller: controller)
                picker.hostScreenWidth = 1440
                picker.renderDevices([])
                picker.sync()
                picker.inputIsCurrent = { true }
                let pickerRows = controller.models.keys.sorted()
                guard !pickerRows.isEmpty else { throw Failure.check("synthetic backend models present") }
                try capture(name: "ready", appearance: appearance, label: label, view: owned,
                            controller: controller, output: output, frames: &frames)
                try capture(name: "ready-model-picker", appearance: appearance, label: label, view: picker,
                            controller: controller, output: output, frames: &frames, extra: ["pickerWidth": 1440, "pickerModels": pickerRows])
                picker.revoke()
                owned.revoke()

                owned = WS2OwnedSessionView(controller: controller)
                owned.inputIsCurrent = { true }
                owned.onCancel = {}
                owned.openModelPicker = {}
                owned.openConductorPage = {}

                // draft：合成草稿文字，不发任何 RPC。
                guard controller.editDraft("设计样件草稿 native-preview") else { throw Failure.check("editDraft") }
                try capture(name: "draft", appearance: appearance, label: label, view: owned,
                            controller: controller, output: output, frames: &frames)

                // running：只向这个 mock 发送 hold native-preview，后端不结算这一轮。
                guard controller.send("hold native-preview", hasMarkedText: false) else { throw Failure.check("send hold") }
                try await until("phase running and synthetic reply") { controller.phase == .running && controller.text.contains("合成后端回复") }
                try capture(name: "running", appearance: appearance, label: label, view: owned,
                            controller: controller, output: output, frames: &frames)
                owned.revoke()

                // completed：只对这个 mock 的当前轮 interrupt，等 turn/completed 通知；
                // 真实后端把 interrupted 结算成 .ready（status 助手已停止），如实记录后，
                // 再用一次显式回合抵达实际 .completed 相位。
                guard let runningTarget = controller.conductorTarget, let runningTurn = controller.conductorTurn else { throw Failure.check("running target/turn") }
                guard controller.interruptConductor(target: runningTarget, turn: runningTurn) else { throw Failure.check("interruptConductor") }
                try await until("interrupt acknowledged") { controller.phase == .ready && controller.canSend }
                let interruptPhase = String(describing: controller.phase)
                let interruptStatus = controller.status

                guard controller.canSend else { throw Failure.check("canSend after interrupt settlement") }
                guard controller.editDraft("finish native-preview") else { throw Failure.check("editDraft finish") }
                guard controller.send("finish native-preview", hasMarkedText: false) else { throw Failure.check("send finish") }
                try await until("phase == .completed") { controller.phase == .completed }
                let done = WS2OwnedSessionView(controller: controller)
                done.inputIsCurrent = { true }
                done.onCancel = {}
                done.openModelPicker = {}
                done.openConductorPage = {}
                try capture(name: "completed", appearance: appearance, label: label, view: done,
                            controller: controller, output: output, frames: &frames,
                            extra: ["interruptPhase": interruptPhase, "interruptStatus": interruptStatus])
                done.revoke()

                // stopped：stop(clearPrivate:true) 后等 !isBusy，再看子进程回收结果。
                let before = controller.observedReaps
                controller.stop(clearPrivate: true)
                try await until("!isBusy after stop") { !controller.isBusy }
                let stopped = WS2OwnedSessionView(controller: controller)
                stopped.inputIsCurrent = { true }
                stopped.onCancel = {}
                stopped.openModelPicker = {}
                stopped.openConductorPage = {}
                try capture(name: "stopped", appearance: appearance, label: label, view: stopped,
                            controller: controller, output: output, frames: &frames,
                            extra: ["reapsObserved": controller.observedReaps - before])
                stopped.revoke()
            }
        } catch {
            report["failureControllers"] = controllers.map { ["phase": String(describing: $0.phase), "status": $0.status,
                "notice": $0.notice, "busy": $0.isBusy, "reaps": $0.observedReaps] as [String: Any] }
            // 错误路径也必须停子进程，并保留失败证据（不删临时目录、不删输出）。
            for controller in controllers { controller.stop(clearPrivate: true) }
            for controller in controllers {
                let deadline = ProcessInfo.processInfo.systemUptime + 8
                while controller.isBusy, ProcessInfo.processInfo.systemUptime < deadline {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
            report["failure"] = String(describing: error)
            report["childReaped"] = controllers.allSatisfy { !$0.isBusy }
            report["temporaryRemoved"] = false
            report["temporaryPreserved"] = true
            try write(report: report, frames: frames, to: output)
            print("FAILED owned phase preview: \(error); child stopped, evidence preserved at \(tempRoot.path)")
            exit(1)
        }

        // 成功路径：全部子进程已回收后，只删自己造的临时目录；输出保留。
        let reaped = controllers.allSatisfy { !$0.isBusy }
        var removed = false
        if reaped, tempRoot.deletingLastPathComponent() == buildRoot {
            do { try FileManager.default.removeItem(at: tempRoot); removed = true } catch { removed = false }
        }
        report["childReaped"] = reaped
        report["controllerCount"] = controllers.count
        report["temporaryRemoved"] = removed
        report["temporaryPathStillOnDisk"] = FileManager.default.fileExists(atPath: tempRoot.path)
        report["frames"] = frames.map { ["phase": $0["phase"] ?? "", "parentAppearance": $0["parentAppearance"] ?? "", "image": $0["image"] ?? ""] }
        try write(report: report, frames: frames, to: output)
        print("Rendered \(frames.count) actual owned-phase frames with a synthetic stdio backend; child reaped: \(reaped); temp removed: \(removed).")
        if !reaped || !removed { exit(1) }
    }

    // MARK: - 有界输入投影检查
    // 对 controller ready 且 fixture-a/medium 已选时挂载的同一张实际 owned 视图做
    // 输入投影检查。仅设置视图状态与文档文本，只派发本地导航/诊断action，不点提交/激活面板/
    // 连接真实助手或网络。任一断言失败即抛 Failure.check 并记录首个错误。

    @MainActor private static func inputChecks(appearance: NSAppearance.Name, label: String,
                                               controller: WS2OwnedLaunchController, output: URL) async throws {
        var checks: [[String: Any]] = []
        var firstError: String?
        func record(_ name: String, _ expected: String, _ actual: String, _ passed: Bool) {
            var entry: [String: Any] = ["name": name, "expected": expected, "actual": actual, "passed": passed]
            if !passed, firstError == nil { firstError = "\(name): expected \(expected), actual \(actual)" }
            if !passed { entry["firstError"] = firstError ?? "" }
            checks.append(entry)
        }
        func flush() throws {
            var document: [String: Any] = ["label": label, "parentAppearance": appearance.rawValue,
                "checks": checks, "synthetic": true, "noRealAssistant": true,
                "performedSubmissionClick":false,"localDiagnosticActionDispatches":2,"localNavigationActionDispatches":12,"activated":NSApp.isActive,
                "note": "实际输入投影与本地诊断action派发；没有发送/登录点击，没有真实助手或网络；逐帧另验屏幕外位置。"]
            if let error = firstError { document["firstError"] = error; document["passed"] = false } else { document["passed"] = true }
            let data=try JSONSerialization.data(withJSONObject:document,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:output.appendingPathComponent("\(label)-input-checks.json"))
        }

        let view = WS2OwnedSessionView(controller: controller)
        view.inputIsCurrent = { true }
        view.onCancel = {}
        var pickerVisits=0,conductorVisits=0
        view.openModelPicker = { pickerVisits += 1 }
        view.openConductorPage = { conductorVisits += 1 }
        view.render()
        guard let pickerButton=findButton(titled:"选择模型…",in:view),
              let conductorButton=findButton(titled:"指挥模式",in:view),
              let pickerAction=pickerButton.action,let conductorAction=conductorButton.action else {
            throw Failure.check("navigation controls/actions missing")
        }
        func dispatchNavigation() {
            _=NSApp.sendAction(pickerAction,to:pickerButton.target,from:pickerButton)
            _=NSApp.sendAction(conductorAction,to:conductorButton.target,from:conductorButton)
        }
        guard let editable = editableTextView(in: view) else {
            record("editable-textview-present", "1", "0", false); try flush()
            throw Failure.check("input checks: editable NSTextView not found")
        }
        guard let sendButton = findButton(titled: "发送", in: view) else {
            record("send-button-present", "1", "0", false); try flush()
            throw Failure.check("input checks: send NSButton(\"发送\") not found")
        }
        let prepared = controller.model == "fixture-a" && controller.effort == "medium" && controller.canSend
        record("precondition-ready-fixture-a-medium", "true", prepared.description, prepared)

        // 1) 外部草稿更新 / 清空同步。
        _ = controller.editDraft("外部草稿 native-input-check")
        view.render()
        record("external-draft-update-syncs", "外部草稿 native-input-check", editable.string, editable.string == "外部草稿 native-input-check")
        _ = controller.editDraft("")
        view.render()
        record("external-draft-clear-syncs", "", editable.string, editable.string.isEmpty)

        // 2) 空白草稿禁用发送。
        editable.string = "   \n\t "
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editable))
        record("blank-draft-disables-send", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)

        // 3) 有效草稿启用发送。
        editable.string = "有效草稿 native-input-check"
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editable))
        record("valid-draft-enables-send", "enabled", enabledWord(sendButton.isEnabled), sendButton.isEnabled)
        record("valid-draft-adopted-by-controller", "有效草稿 native-input-check", controller.draft, controller.draft == "有效草稿 native-input-check")

        record("valid-draft-enables-navigation","true",(pickerButton.isEnabled && conductorButton.isEnabled).description,pickerButton.isEnabled && conductorButton.isEnabled)
        dispatchNavigation()
        record("valid-navigation-delivers-once","1/1","\(pickerVisits)/\(conductorVisits)",pickerVisits==1 && conductorVisits==1)
        record("valid-navigation-keeps-controller-draft","有效草稿 native-input-check",controller.draft,controller.draft==editable.string)

        // Exact UTF8 limit is valid; one multibyte character crosses it.
        editable.string=String(repeating:"a",count:65_536)
        view.textDidChange(Notification(name:NSText.didChangeNotification,object:editable))
        record("exact-byte-limit-enables-navigation","true",(pickerButton.isEnabled && conductorButton.isEnabled).description,pickerButton.isEnabled && conductorButton.isEnabled)
        editable.string += "中"
        view.textDidChange(Notification(name:NSText.didChangeNotification,object:editable))
        record("multibyte-over-limit-disables-navigation","false",(pickerButton.isEnabled || conductorButton.isEnabled).description,!pickerButton.isEnabled && !conductorButton.isEnabled)
        dispatchNavigation()
        record("over-limit-action-guards-navigation","1/1","\(pickerVisits)/\(conductorVisits)",pickerVisits==1 && conductorVisits==1)
        record("over-limit-navigation-keeps-local-draft","65539","\(editable.string.utf8.count)",editable.string.utf8.count==65_539)
        record("over-limit-navigation-keeps-last-accepted-draft","65536","\(controller.draft.utf8.count)",controller.draft.utf8.count==65_536)

        // 4) 超过 65536 UTF8 字节禁用，且后续 render 保留被拒草稿。
        let tooLong = String(repeating: "a", count: 65_537)
        editable.string = tooLong
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editable))
        record("over-limit-draft-disables-send", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)
        view.render()
        record("over-limit-render-keeps-rejected-text", "65537", "\(editable.string.utf8.count)", editable.string.utf8.count == 65_537)
        record("over-limit-render-keeps-send-disabled", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)

        // Isolate composition from the previous size failure: valid and enabled first.
        editable.string="组合输入 native-input-check"
        view.textDidChange(Notification(name:NSText.didChangeNotification,object:editable))
        record("before-marking-send-enabled","enabled",enabledWord(sendButton.isEnabled),sendButton.isEnabled)
        // 5) 真实组合输入能力：setMarkedText 期间禁用，unmarkText 后恢复。
        editable.setMarkedText("zhong", selectedRange: NSRange(location: 0, length: 5), replacementRange: NSRange(location: 0, length: 0))
        view.render()
        let markedActive = editable.hasMarkedText()
        record("marked-text-active", "true", markedActive.description, markedActive)
        record("marked-text-disables-send", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)
        record("marked-text-disables-navigation","false",(pickerButton.isEnabled || conductorButton.isEnabled).description,!pickerButton.isEnabled && !conductorButton.isEnabled)
        let markedDraft=editable.string,acceptedDraft=controller.draft
        dispatchNavigation()
        record("marked-action-guards-navigation","1/1","\(pickerVisits)/\(conductorVisits)",pickerVisits==1 && conductorVisits==1)
        record("marked-navigation-keeps-composition","true",editable.hasMarkedText().description,editable.hasMarkedText() && editable.string==markedDraft && controller.draft==acceptedDraft)
        editable.string = "组合完成 native-input-check"
        editable.unmarkText()
        view.textDidChange(Notification(name: NSText.didChangeNotification, object: editable))
        record("unmark-clears-marked-text", "false", editable.hasMarkedText().description, !editable.hasMarkedText())
        record("unmark-restores-send", "enabled", enabledWord(sendButton.isEnabled), sendButton.isEnabled)
        record("unmark-restores-navigation","true",(pickerButton.isEnabled && conductorButton.isEnabled).description,pickerButton.isEnabled && conductorButton.isEnabled)
        dispatchNavigation()
        record("unmark-navigation-delivers-once","2/2","\(pickerVisits)/\(conductorVisits)",pickerVisits==2 && conductorVisits==2)
        view.openModelPicker=nil;view.openConductorPage=nil;view.render()
        record("missing-destination-disables-navigation","false",(pickerButton.isEnabled || conductorButton.isEnabled).description,!pickerButton.isEnabled && !conductorButton.isEnabled)
        view.openModelPicker={pickerVisits += 1};view.openConductorPage={conductorVisits += 1};view.render()

        let panel=NotchPanel(notch:NSRect(x:-8000,y:866.5,width:185,height:33.5),virtual:false)
        panel.isReleasedWhenClosed=false;panel.appearance=NSAppearance(named:appearance)
        panel.alphaValue=0;panel.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopWindow))-1)
        defer { panel.setInteraction(nil,animated:false);panel.close() }
        panel.setInteraction(view,animated:false);view.render()
        let collapsed=view.interactionSize.height
        let originalFrame=panel.frame
        if let diagnostic=findButton(titled:"查看诊断",in:view),let action=diagnostic.action {
            let dispatched=NSApp.sendAction(action,to:diagnostic.target,from:diagnostic)
            record("diagnostic-action-dispatched","true",dispatched.description,dispatched)
            view.render()
            record("same-owner-expands-for-diagnostics","larger","\(view.interactionSize.height)",view.interactionSize.height>collapsed)
            let grew=await waitForFrame { panel.frame.height>originalFrame.height+50 }
            record("actual-panel-frame-expands","larger",NSStringFromRect(panel.frame),grew)
            _=NSApp.sendAction(action,to:diagnostic.target,from:diagnostic);view.render()
            record("same-owner-restores-content-height","\(collapsed)","\(view.interactionSize.height)",abs(view.interactionSize.height-collapsed)<1)
            let restored=await waitForFrame { abs(panel.frame.height-originalFrame.height)<1.5 }
            record("actual-panel-frame-restores","\(originalFrame.height)",NSStringFromRect(panel.frame),restored)
        } else { record("diagnostic-button-present","true","false",false) }
        let offscreen = !NSScreen.screens.contains{$0.frame.intersects(panel.frame)}
        record("same-owner-resize-offscreen","true",NSStringFromRect(panel.frame),offscreen)
        record("same-owner-resize-inactive","false",NSApp.isActive.description,!NSApp.isActive)
        // 6) inputIsCurrent=false 后 render 禁用按钮（不点击提交）。
        view.inputIsCurrent = { false }
        view.render()
        record("stale-input-disables-send", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)
        record("stale-input-disables-navigation","false",(pickerButton.isEnabled || conductorButton.isEnabled).description,!pickerButton.isEnabled && !conductorButton.isEnabled)
        dispatchNavigation()
        record("stale-action-guards-navigation","2/2","\(pickerVisits)/\(conductorVisits)",pickerVisits==2 && conductorVisits==2)

        // 7) revoke 后旧按钮必须 disabled；若生产未禁用则记录失败，不修改生产。
        view.revoke()
        record("revoked-send-disabled", "disabled", enabledWord(sendButton.isEnabled), !sendButton.isEnabled)
        dispatchNavigation()
        record("revoked-action-guards-navigation","2/2","\(pickerVisits)/\(conductorVisits)",pickerVisits==2 && conductorVisits==2)
        let revokedConductor=findButton(titled:"指挥模式",in:view)
        record("conductor-button-present","true",(revokedConductor != nil).description,revokedConductor != nil)
        let revokedConductorEnabled = revokedConductor?.isEnabled ?? true
        record("revoked-open-conductor-disabled", "disabled", enabledWord(revokedConductorEnabled),
               !revokedConductorEnabled)

        // 8) 恢复 controller.editDraft("") 及其后的原流程。
        _ = controller.editDraft("")
        record("controller-draft-restored-empty", "0", "\(controller.draft.utf8.count)", controller.draft.isEmpty)

        try flush()
        if let error = firstError { throw Failure.check("input checks first failure: \(error)") }
    }

    @MainActor private static func waitForFrame(_ predicate:()->Bool) async -> Bool {
        let deadline=ProcessInfo.processInfo.systemUptime+2
        while !predicate(),ProcessInfo.processInfo.systemUptime<deadline { try? await Task.sleep(nanoseconds:10_000_000) }
        return predicate()
    }

    /// 递归查找实际可编辑输入 NSTextView（组合/草稿输入框）。
    @MainActor private static func editableTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.isEditable { return text }
        for child in view.subviews {
            if let found = editableTextView(in: child) { return found }
        }
        return nil
    }

    /// 递归查找指定标题的 NSButton。
    @MainActor private static func findButton(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title { return button }
        for child in view.subviews {
            if let found = findButton(titled: title, in: child) { return found }
        }
        return nil
    }

    @MainActor private static func enabledWord(_ value: Bool) -> String { value ? "enabled" : "disabled" }

    // MARK: - 捕获

    @MainActor private static func capture(name: String, appearance: NSAppearance.Name, label: String,
                                           view originalView: NSView & WS2LeaseContent, controller: WS2OwnedLaunchController,
                                           output: URL, frames: inout [[String: Any]],
                                           extra: [String: Any] = [:]) throws {
        let view: NSView & WS2LeaseContent
        if let picker = originalView as? WS2ModelPickerView {
            picker.inputIsCurrent = { true }; picker.sync(); view = picker
        } else {
            // 每帧读当前控制器；不能复用已经 revoke 的卡，也不能拿旧草稿/按钮冒充新相位。
            let owned = WS2OwnedSessionView(controller: controller)
            owned.inputIsCurrent = { true }; owned.openModelPicker = {}; owned.openConductorPage = {}
            owned.render(); view = owned
        }
        let panel = NotchPanel(notch: NSRect(x: -8000, y: 866.5, width: 185, height: 33.5), virtual: false)
        panel.isReleasedWhenClosed = false
        panel.alphaValue=0
        panel.appearance = NSAppearance(named: appearance)
        defer { view.revoke(); panel.setInteraction(nil, animated: false); panel.close() }
        panel.setInteraction(view, animated: false)
        if let owned=view as? WS2OwnedSessionView { owned.render() }
        guard let canvas = panel.contentView else { throw Failure.check("panel contentView") }
        canvas.layoutSubtreeIfNeeded()
        let intersects = NSScreen.screens.contains { $0.frame.intersects(panel.frame) }
        guard !intersects && !NSApp.isActive else { throw Failure.check("panel offscreen/nonactive for \(name)") }

        let file = "\(label)-\(name).png"
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { throw Failure.check("bitmap for \(name)") }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure.check("png for \(name)") }
        try data.write(to: output.appendingPathComponent(file))

        var frame: [String: Any] = [
            "phase": String(describing: controller.phase),
            "status": controller.status,
            "notice": controller.notice,
            "draft": controller.draft,"replyText":controller.text,
            "model": controller.model ?? "", "effort": controller.effort ?? "",
            "isBusy": controller.isBusy, "parentAppearance": appearance.rawValue,
            "image": file, "offscreenX": -8000,
            "width": canvas.bounds.width, "height": canvas.bounds.height,
            "contentWidth": view.bounds.width, "contentHeight": view.bounds.height,
            "visibleWindow":panel.isVisible,"panelAlpha":panel.alphaValue, "intersectsScreen": intersects, "activeApplication": NSApp.isActive,
            "synthetic": true, "noRealAssistant": true,
            "buttons": buttons(in: view), "visibleLabels":visibleLabels(in:view)]
        for (key, value) in extra { frame[key] = value }
        frames.append(frame)

    }

    @MainActor private static func visibleLabels(in view:NSView) -> [[String:Any]] {
        var result:[[String:Any]]=[]
        func walk(_ node:NSView) {
            if let label=node as? NSTextField,!label.isHiddenOrHasHiddenAncestor {
                let rect=label.convert(label.bounds,to:view)
                result.append(["text":label.stringValue,"withinContent":view.bounds.contains(rect),
                    "x":rect.minX,"y":rect.minY,"width":rect.width,"height":rect.height])
            }
            node.subviews.forEach(walk)
        }
        walk(view);return result
    }

    @MainActor private static func buttons(in view: NSView) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func walk(_ node: NSView) {
            if let popup = node as? NSPopUpButton {
                result.append(["title": popup.titleOfSelectedItem ?? popup.title, "enabled": popup.isEnabled, "hidden": popup.isHiddenOrHasHiddenAncestor])
            } else if let button = node as? NSButton {
                result.append(["title": button.title, "enabled": button.isEnabled, "hidden": button.isHiddenOrHasHiddenAncestor])
            }
            node.subviews.forEach(walk)
        }
        walk(view)
        return result
    }

    // MARK: - 工具

    @MainActor private static func until(_ label: String, _ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard predicate() else { throw Failure.check("timed out waiting for \(label)") }
    }

    private static func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func write(report: [String: Any], frames: [[String: Any]], to output: URL) throws {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("owned-phases.json"))
        try JSONSerialization.data(withJSONObject: ["frames": frames], options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("frames.json"))
    }
}
