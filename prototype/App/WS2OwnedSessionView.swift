import Cocoa

/// Mounted exclusively by the existing Island/NotchPanel. No secondary product window.
@MainActor final class WS2OwnedSessionView: NSView, WS2LeaseContent, NSTextViewDelegate {
    var onCancel:(()->Void)?
    var openModelPicker: (() -> Void)?
    /// D15：进入指挥页（只读／改草稿与模型，不发命令）。
    var openConductorPage: (() -> Void)?
    var inputIsCurrent:()->Bool = { false }
    var interactionSize:NSSize { NSSize(width:620,height:560) }
    private let controller:WS2OwnedLaunchController
    private let project=NSTextField(labelWithString:"尚未选择项目")
    private let executable=NSTextField(labelWithString:"尚未选择 Codex")
    private let status=NSTextField(wrappingLabelWithString:"")
    private let note=NSTextField(wrappingLabelWithString:"")
    private let model=NSPopUpButton(frame:.zero,pullsDown:false)
    private let effort=NSPopUpButton(frame:.zero,pullsDown:false)
    private let browseModels=NSButton(title:"选择模型…",target:nil,action:nil)
    private let openConductor=NSButton(title:"指挥模式",target:nil,action:nil)
    private let draft=NSTextView(),output=NSTextView()
    private let outputScroll=NSScrollView()
    private let chooseProject=NSButton(title:"选择项目…",target:nil,action:nil)
    private let chooseExecutable=NSButton(title:"选择 Codex…",target:nil,action:nil)
    private let launch=NSButton(title:"启动",target:nil,action:nil)
    private let login=NSButton(title:"登录 ChatGPT",target:nil,action:nil)
    private let cancelLogin=NSButton(title:"取消登录",target:nil,action:nil)
    private let logout=NSButton(title:"退出登录",target:nil,action:nil)
    private let resume=NSButton(title:"恢复上次会话",target:nil,action:nil)
    private let send=NSButton(title:"发送",target:nil,action:nil)
    private let interrupt=NSButton(title:"停止本轮",target:nil,action:nil)
    private let stop=NSButton(title:"断开助手",target:nil,action:nil)
    private let consent=NSButton(checkboxWithTitle:"运行所选 Codex；查询可能发送项目内容并消耗我的账号额度",target:nil,action:nil)
    private let diagnostic=NSButton(checkboxWithTitle:"仅本次保留诊断尾部",target:nil,action:nil)
    private let diagnostics=NSButton(title:"查看诊断",target:nil,action:nil)
    private var renderTask:Task<Void,Never>?
    private var modelIDs:[String]=[],effortIDs:[String]=[]
    private var displayingDiagnostics=false
    init(controller:WS2OwnedLaunchController) {
        self.controller=controller;super.init(frame:.zero)
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=9
        let viewport=NSScrollView();viewport.hasVerticalScroller=true;viewport.drawsBackground=false
        viewport.translatesAutoresizingMaskIntoConstraints=false;addSubview(viewport)
        NSLayoutConstraint.activate([viewport.leadingAnchor.constraint(equalTo:leadingAnchor),viewport.trailingAnchor.constraint(equalTo:trailingAnchor),viewport.topAnchor.constraint(equalTo:topAnchor),viewport.bottomAnchor.constraint(equalTo:bottomAnchor)])
        let document=WS2OwnedDocumentView();document.translatesAutoresizingMaskIntoConstraints=false;viewport.documentView=document
        stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:viewport.contentView.widthAnchor),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-14)])
        let heading=NSTextField(labelWithString:"编程会话 · 只读查询");heading.font = .systemFont(ofSize:15,weight:.semibold);stack.addArrangedSubview(heading)
        func row(_ views:[NSView]) -> NSStackView { let r=NSStackView(views:views);r.orientation = .horizontal;r.spacing=8;return r }
        for (button,selector) in [(chooseProject,#selector(pickProject)),(chooseExecutable,#selector(pickExecutable)),(launch,#selector(start)),(login,#selector(logIn)),(cancelLogin,#selector(cancelLogIn)),(logout,#selector(logOut)),(resume,#selector(resumeSession)),(send,#selector(sendDraft)),(interrupt,#selector(interruptTurn)),(stop,#selector(stopSession)),(diagnostics,#selector(toggleDiagnostics))] {
            button.target=self;button.action=selector;button.bezelStyle = .rounded
        }
        for label in [project,executable] { label.lineBreakMode = .byTruncatingMiddle;label.font = .systemFont(ofSize:11);label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal) }
        stack.addArrangedSubview(row([chooseProject,project]));stack.addArrangedSubview(row([chooseExecutable,executable]))
        consent.font = .systemFont(ofSize:11);consent.target=self;consent.action=#selector(consentChanged)
        consent.toolTip="仅在点击启动后运行。登录和会话文件由 Codex 存在 WindowShade 的独立目录中，不修改你原有的 ~/.codex。只读不等于离线或只允许读取所选目录。"
        stack.addArrangedSubview(consent)
        diagnostic.font = .systemFont(ofSize:11);diagnostic.toolTip="最多保留 64 KiB 内存诊断，可能含路径和敏感内容。不会自动上传或导出。";stack.addArrangedSubview(diagnostic)
        stack.addArrangedSubview(row([launch,login,cancelLogin,logout,resume]))
        model.target=self;model.action=#selector(selectModel);effort.target=self;effort.action=#selector(selectEffort)
        model.setAccessibilityLabel("实际可用模型");effort.setAccessibilityLabel("该模型支持的思考程度")
        browseModels.target=self;browseModels.action=#selector(showModelPicker)
        browseModels.image=NSImage(systemSymbolName:"gamecontroller",accessibilityDescription:nil)
        browseModels.toolTip="在列表里选择模型，也能本次启用手柄。不会发送文字。"
        openConductor.target=self;openConductor.action=#selector(showConductor)
        openConductor.bezelStyle = .rounded
        openConductor.toolTip="打开指挥页。只改草稿和模型，不会发送或批准命令。"
        stack.addArrangedSubview(row([model,effort,browseModels,openConductor,status]));status.font = .systemFont(ofSize:11)
        outputScroll.hasVerticalScroller=true;outputScroll.borderType = .bezelBorder
        configure(output,editable:false);outputScroll.documentView=output
        stack.addArrangedSubview(outputScroll);outputScroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;outputScroll.heightAnchor.constraint(equalToConstant:125).isActive=true
        let composer=NSScrollView();composer.hasVerticalScroller=true;composer.borderType = .bezelBorder
        configure(draft,editable:true);draft.delegate=self;draft.string=controller.draft;draft.setAccessibilityLabel("发送给助手的文字")
        composer.documentView=draft;stack.addArrangedSubview(composer);composer.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;composer.heightAnchor.constraint(equalToConstant:72).isActive=true
        send.toolTip="发送按钮才会提交。中文组合输入未完成时不会发送；回车只换行。"
        stack.addArrangedSubview(row([send,interrupt,stop,diagnostics]))
        note.font = .systemFont(ofSize:11);note.textColor = .secondaryLabelColor;stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        render()
    }
    required init?(coder:NSCoder) { nil }
    private func configure(_ text:NSTextView,editable:Bool) {
        text.isEditable=editable;text.isSelectable=true;text.isRichText=false;text.importsGraphics=false
        text.isAutomaticLinkDetectionEnabled=false;text.font = .systemFont(ofSize:12)
        text.isHorizontallyResizable=false;text.isVerticallyResizable=true;text.autoresizingMask=[.width]
        text.textContainer?.widthTracksTextView=true;text.textContainerInset=NSSize(width:5,height:5)
        text.minSize = .zero;text.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
    }
    func scheduleRender() {
        guard renderTask==nil else { return }
        renderTask=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:60_000_000) } catch { return }
            guard let self else { return };self.renderTask=nil;self.render()
        }
    }
    func render() {
        project.stringValue=controller.projectURL?.path ?? "尚未选择项目";project.toolTip=project.stringValue
        executable.stringValue=controller.executableURL?.path ?? "尚未选择 Codex";executable.toolTip=executable.stringValue
        status.stringValue=controller.status;note.stringValue=controller.notice.isEmpty ? "模型和程度来自当前助手。需要额外权限的操作会被拒绝。":controller.notice
        let next=controller.models.keys.sorted()
        if next != modelIDs || model.numberOfItems==0 { modelIDs=next;model.removeAllItems();model.addItems(withTitles:["请选择模型"]+next) }
        model.selectItem(at:controller.model.flatMap{modelIDs.firstIndex(of:$0)}.map{$0+1} ?? 0)
        let efforts=controller.model.flatMap{controller.models[$0]}?.sorted() ?? []
        if efforts != effortIDs || effort.numberOfItems==0 { effortIDs=efforts;effort.removeAllItems();effort.addItems(withTitles:["程度"]+efforts) }
        effort.selectItem(at:controller.effort.flatMap{effortIDs.firstIndex(of:$0)}.map{$0+1} ?? 0)
        let fresh=inputIsCurrent()
        chooseProject.isEnabled=fresh && !controller.isBusy;chooseExecutable.isEnabled=chooseProject.isEnabled
        consent.isEnabled = !controller.isBusy;diagnostic.isEnabled = !controller.isBusy
        launch.isEnabled=fresh && consent.state == .on && controller.canLaunch
        login.isEnabled=fresh && controller.canLogin;cancelLogin.isEnabled=fresh && controller.phase == .signedOut && !controller.canLogin
        logout.isEnabled=fresh && controller.canLogout;resume.isEnabled=fresh && controller.canResume
        model.isEnabled=fresh && !controller.models.isEmpty && [.ready,.completed,.failed].contains(controller.phase)
        effort.isEnabled=model.isEnabled && controller.model != nil
        browseModels.isEnabled=fresh && controller.canChooseModel && !draft.hasMarkedText()
        openConductor.isEnabled=fresh && openConductorPage != nil
        send.isEnabled=fresh && controller.canSend;interrupt.isEnabled=fresh && controller.canInterrupt
        stop.isEnabled=fresh && controller.isBusy;diagnostics.isEnabled=fresh
        let value=displayingDiagnostics ? controller.diagnostics:controller.text
        if output.string != value {
            let wasAtEnd=outputScroll.contentView.bounds.maxY>=output.bounds.maxY-24
            output.string=value
            if wasAtEnd { output.scrollToEndOfDocument(nil) }
        }
    }
    func textDidChange(_ notification:Notification) {
        guard inputIsCurrent() else { return }
        if !controller.editDraft(draft.string) { note.stringValue="文字超过 64 KiB，暂时不能发送。" }
    }
    private func choose(directory:Bool) {
        guard inputIsCurrent(),!controller.isBusy else { return }
        let picker=NSOpenPanel();picker.canChooseDirectories=directory;picker.canChooseFiles = !directory
        picker.allowsMultipleSelection=false;picker.canCreateDirectories=false;picker.prompt=directory ? "使用这个项目":"使用这个程序"
        picker.begin { [weak self] result in
            MainActor.assumeIsolated {
                guard let self,self.inputIsCurrent(),result == .OK,let url=picker.url else { return }
                if directory { _=self.controller.selectProject(url) } else { _=self.controller.selectExecutable(url) };self.render()
            }
        }
    }
    @objc private func pickProject() { choose(directory:true) }
    @objc private func pickExecutable() { choose(directory:false) }
    @objc private func consentChanged() { render() }
    @objc private func start() { guard inputIsCurrent() else { return };_=controller.launch(consent:consent.state == .on,diagnostics:diagnostic.state == .on);render() }
    @objc private func logIn() { guard inputIsCurrent() else { return };_=controller.login() }
    @objc private func cancelLogIn() { guard inputIsCurrent() else { return };controller.cancelLogin() }
    @objc private func logOut() { guard inputIsCurrent() else { return };_=controller.logout() }
    @objc private func resumeSession() { guard inputIsCurrent() else { return };_=controller.resumeLast() }
    @objc private func showModelPicker() {
        guard inputIsCurrent(),controller.canChooseModel,!draft.hasMarkedText() else { return }
        guard controller.editDraft(draft.string) else { return }
        openModelPicker?()
    }
    @objc private func showConductor() {
        guard inputIsCurrent() else { return }
        guard controller.editDraft(draft.string) else { return }
        openConductorPage?()
    }
    @objc private func selectModel() { guard inputIsCurrent(),model.indexOfSelectedItem>0 else { return };_=controller.chooseModel(modelIDs[model.indexOfSelectedItem-1]) }
    @objc private func selectEffort() { guard inputIsCurrent(),effort.indexOfSelectedItem>0 else { return };_=controller.chooseEffort(effortIDs[effort.indexOfSelectedItem-1]) }
    @objc private func sendDraft() { guard inputIsCurrent() else { return };_=controller.send(draft.string,hasMarkedText:draft.hasMarkedText()) }
    @objc private func interruptTurn() { guard inputIsCurrent() else { return };_=controller.interrupt() }
    @objc private func stopSession() { guard inputIsCurrent() else { return };controller.stop() }
    @objc private func toggleDiagnostics() { guard inputIsCurrent() else { return };displayingDiagnostics.toggle();diagnostics.title=displayingDiagnostics ? "返回回复":"查看诊断";render() }
    func revoke() { renderTask?.cancel();renderTask=nil;inputIsCurrent={false};draft.inputContext?.discardMarkedText();draft.string="";output.string="";onCancel?() }
}

@MainActor private final class WS2OwnedDocumentView:NSView { override var isFlipped:Bool { true } }
