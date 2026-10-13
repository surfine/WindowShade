import Cocoa

/// Mounted exclusively by the existing Island/NotchPanel. No secondary product window.
@MainActor final class WS2OwnedSessionView: NSView, WS2LeaseContent, NSTextViewDelegate {
    var onCancel:(()->Void)?
    var openModelPicker: (() -> Void)?
    /// D15：进入指挥页（只读／改草稿与模型，不发命令）。
    var openConductorPage: (() -> Void)?
    var inputIsCurrent:()->Bool = { false }
    var interactionSize:NSSize { NSSize(width:620,height:contentHeight) }
    private var contentHeight:CGFloat=420
    private let stack=NSStackView()
    private let controller:WS2OwnedLaunchController
    private let project=NSTextField(labelWithString:WSL10n.text("owned.ui.noProject", zh: "尚未选择项目"))
    private let executable=NSTextField(labelWithString:WSL10n.text("owned.ui.noExecutable", zh: "尚未选择 Codex"))
    private let status=NSTextField(wrappingLabelWithString:"")
    private let note=NSTextField(wrappingLabelWithString:"")
    private let model=NSPopUpButton(frame:.zero,pullsDown:false)
    private let effort=NSPopUpButton(frame:.zero,pullsDown:false)
    private let browseModels=NSButton(title:WSL10n.text("owned.ui.browseModels", zh: "选择模型…"),target:nil,action:nil)
    private let openConductor=NSButton(title:WSL10n.text("conductor.settings.mode", zh: "指挥模式"),target:nil,action:nil)
    private let draft=NSTextView(),output=NSTextView()
    private let outputScroll=NSScrollView()
    private let chooseProject=NSButton(title:WSL10n.text("owned.ui.chooseProject", zh: "选择项目…"),target:nil,action:nil)
    private let chooseExecutable=NSButton(title:WSL10n.text("owned.ui.chooseExecutable", zh: "选择 Codex…"),target:nil,action:nil)
    private let launch=NSButton(title:WSL10n.text("owned.ui.launch", zh: "启动"),target:nil,action:nil)
    private let login=NSButton(title:WSL10n.text("owned.ui.login", zh: "登录 ChatGPT"),target:nil,action:nil)
    private let cancelLogin=NSButton(title:WSL10n.text("owned.ui.cancelLogin", zh: "取消登录"),target:nil,action:nil)
    private let logout=NSButton(title:WSL10n.text("owned.ui.logout", zh: "退出登录"),target:nil,action:nil)
    private let resume=NSButton(title:WSL10n.text("owned.ui.resume", zh: "恢复上次会话"),target:nil,action:nil)
    private let send=NSButton(title:WSL10n.text("conductor.send", zh: "发送"),target:nil,action:nil)
    private let interrupt=NSButton(title:WSL10n.text("conductor.stopTurn", zh: "停止本轮"),target:nil,action:nil)
    private let stop=NSButton(title:WSL10n.text("owned.ui.stop", zh: "断开助手"),target:nil,action:nil)
    private let consent=NSButton(checkboxWithTitle:WSL10n.text("owned.ui.consent", zh: "运行所选 Codex；查询可能发送项目内容并消耗我的账号额度"),target:nil,action:nil)
    private let diagnostic=NSButton(checkboxWithTitle:WSL10n.text("owned.ui.diagnosticTail", zh: "仅本次保留诊断尾部"),target:nil,action:nil)
    private let diagnostics=NSButton(title:WSL10n.text("owned.ui.viewDiagnostics", zh: "查看诊断"),target:nil,action:nil)
    private var renderTask:Task<Void,Never>?
    private var modelIDs:[String]=[],effortIDs:[String]=[]
    private var rejectedDraft=false
    private var displayingDiagnostics=false
    private let heading=NSTextField(labelWithString:WSL10n.text("notch.kind.session", zh: "编程会话"))
    private let setup=NSStackView()
    private let launchActions=NSStackView()
    private let modelActions=NSStackView()
    private let accountActions=NSStackView()
    private let composer=WS2OwnedDraftScrollView()
    private let replyHeading=NSTextField(labelWithString:WSL10n.text("owned.ui.replyHeading", zh: "助手回复"))
    private let composerHeading=NSTextField(labelWithString:WSL10n.text("owned.ui.composerHeading", zh: "给助手的文字"))
    init(controller:WS2OwnedLaunchController) {
        self.controller=controller;super.init(frame:.zero)
        stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12
        let viewport=NSScrollView();viewport.hasVerticalScroller=true;viewport.drawsBackground=false
        viewport.translatesAutoresizingMaskIntoConstraints=false;addSubview(viewport)
        NSLayoutConstraint.activate([viewport.leadingAnchor.constraint(equalTo:leadingAnchor),viewport.trailingAnchor.constraint(equalTo:trailingAnchor),viewport.topAnchor.constraint(equalTo:topAnchor),viewport.bottomAnchor.constraint(equalTo:bottomAnchor)])
        let document=WS2OwnedDocumentView();document.translatesAutoresizingMaskIntoConstraints=false;viewport.documentView=document
        stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:viewport.contentView.widthAnchor),stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-14)])
        heading.font = .systemFont(ofSize:15,weight:.semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        heading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        status.font = .systemFont(ofSize:11)
        status.textColor = NSColor.white.withAlphaComponent(0.68)
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        func row(_ views:[NSView]) -> NSStackView {
            let r=NSStackView(views:views);r.orientation = .horizontal;r.spacing=8;r.alignment = .centerY
            return r
        }
        setup.orientation = .vertical;setup.alignment = .leading;setup.spacing=9
        stack.addArrangedSubview(setup)
        setup.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        for (button,selector) in [(chooseProject,#selector(pickProject)),(chooseExecutable,#selector(pickExecutable)),(launch,#selector(start)),(login,#selector(logIn)),(cancelLogin,#selector(cancelLogIn)),(logout,#selector(logOut)),(resume,#selector(resumeSession)),(send,#selector(sendDraft)),(interrupt,#selector(interruptTurn)),(stop,#selector(stopSession)),(diagnostics,#selector(toggleDiagnostics))] {
            button.target=self;button.action=selector;button.bezelStyle = .rounded
            button.controlSize = .small
            button.setContentHuggingPriority(.required,for:.horizontal)
        }
        for label in [project,executable] { label.lineBreakMode = .byTruncatingMiddle;label.font = .systemFont(ofSize:11);label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal) }
        let preparationRows:[[NSView]] = [[chooseProject,project],[chooseExecutable,executable]]
        for fields in preparationRows {
            let fieldsRow=row(fields)
            setup.addArrangedSubview(fieldsRow)
            fieldsRow.widthAnchor.constraint(equalTo:setup.widthAnchor).isActive=true
        }
        consent.font = .systemFont(ofSize:11);consent.target=self;consent.action=#selector(consentChanged)
        consent.toolTip=WSL10n.text("owned.ui.consent.tip", zh: "仅在点击启动后运行。登录和会话文件由 Codex 存在 WindowShade 的独立目录中，不修改你原有的 ~/.codex。只读不等于离线或只允许读取所选目录。")
        setup.addArrangedSubview(consent)
        diagnostic.font = .systemFont(ofSize:11);diagnostic.toolTip=WSL10n.text("owned.ui.diagnostic.tip", zh: "最多保留 64 KiB 内存诊断，可能含路径和敏感内容。不会自动上传或导出。");setup.addArrangedSubview(diagnostic)
        launchActions.orientation = .horizontal;launchActions.spacing=8
        for button in [launch,login,cancelLogin,resume] { launchActions.addArrangedSubview(button) }
        stack.addArrangedSubview(launchActions)
        model.target=self;model.action=#selector(selectModel);effort.target=self;effort.action=#selector(selectEffort)
        model.setAccessibilityLabel(WSL10n.text("owned.ui.modelLabel", zh: "实际可用模型"));effort.setAccessibilityLabel(WSL10n.text("owned.ui.effortLabel", zh: "该模型支持的思考程度"))
        browseModels.target=self;browseModels.action=#selector(showModelPicker)
        browseModels.image=NSImage(systemSymbolName:"gamecontroller",accessibilityDescription:nil)
        browseModels.toolTip=WSL10n.text("owned.ui.browseModels.tip", zh: "在列表里选择模型，也能本次启用手柄。不会发送文字。")
        openConductor.target=self;openConductor.action=#selector(showConductor)
        openConductor.bezelStyle = .rounded
        openConductor.toolTip=WSL10n.text("owned.ui.openConductor.tip", zh: "打开指挥页。只改草稿和模型，不会发送或批准命令。")
        modelActions.orientation = .horizontal;modelActions.spacing=8
        for view in [model,effort,browseModels,openConductor] { modelActions.addArrangedSubview(view) }
        stack.addArrangedSubview(modelActions)
        modelActions.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        model.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        model.setContentHuggingPriority(.defaultLow,for:.horizontal)
        model.cell?.lineBreakMode = .byTruncatingMiddle
        for control in [effort,browseModels,openConductor] {
            control.setContentCompressionResistancePriority(.required,for:.horizontal)
            control.setContentHuggingPriority(.required,for:.horizontal)
        }
        for label in [replyHeading,composerHeading] {
            label.font = .systemFont(ofSize:11);label.textColor = NSColor.white.withAlphaComponent(0.68)
        }
        stack.addArrangedSubview(replyHeading)
        outputScroll.hasVerticalScroller=true;outputScroll.borderType = .noBorder
        outputScroll.drawsBackground=false
        configure(output,editable:false);outputScroll.documentView=output
        output.textContainerInset=NSSize(width:0,height:2)
        stack.addArrangedSubview(outputScroll);outputScroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;outputScroll.heightAnchor.constraint(equalToConstant:100).isActive=true
        stack.addArrangedSubview(composerHeading)
        composer.hasVerticalScroller=true;composer.borderType = .noBorder
        composer.drawsBackground=false;composer.wantsLayer=true
        composer.layer?.cornerRadius=12;composer.layer?.masksToBounds=true
        configure(draft,editable:true);draft.delegate=self;draft.string=controller.draft;draft.setAccessibilityLabel(WSL10n.text("owned.ui.draftLabel", zh: "发送给助手的文字"))
        draft.textContainerInset=NSSize(width:10,height:8)
        composer.documentView=draft;stack.addArrangedSubview(composer);composer.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;composer.heightAnchor.constraint(equalToConstant:72).isActive=true
        send.toolTip=WSL10n.text("owned.ui.send.tip", zh: "发送按钮才会提交。中文组合输入未完成时不会发送；回车只换行。")
        stack.addArrangedSubview(row([send,interrupt]))
        accountActions.orientation = .horizontal;accountActions.spacing=8
        for button in [stop,logout,diagnostics] { accountActions.addArrangedSubview(button) }
        stack.addArrangedSubview(accountActions)
        note.font = .systemFont(ofSize:11);note.textColor = NSColor.white.withAlphaComponent(0.68);stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        render()
    }
    required init?(coder:NSCoder) { nil }
    private func configure(_ text:NSTextView,editable:Bool) {
        text.isEditable=editable;text.isSelectable=true;text.isRichText=false;text.importsGraphics=false
        text.isAutomaticLinkDetectionEnabled=false;text.font = .systemFont(ofSize:12)
        text.drawsBackground=false;text.textColor = .white;text.insertionPointColor = .white
        text.textContainer?.lineFragmentPadding=0
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
        project.stringValue=controller.projectURL?.lastPathComponent ?? WSL10n.text("owned.ui.noProject", zh: "尚未选择项目");project.toolTip=controller.projectURL?.path
        heading.stringValue=controller.isBusy ? (controller.projectURL?.lastPathComponent ?? WSL10n.text("notch.kind.session", zh: "编程会话")) : WSL10n.text("notch.kind.session", zh: "编程会话")
        heading.toolTip=controller.projectURL?.path
        executable.stringValue=controller.executableURL?.path ?? WSL10n.text("owned.ui.noExecutable", zh: "尚未选择 Codex");executable.toolTip=executable.stringValue
        status.stringValue=controller.status
        note.stringValue=rejectedDraft ? WSL10n.text("owned.ui.draftTooLong", zh: "文字太长，暂时不能发送。") : (controller.notice.isEmpty ? WSL10n.text("owned.ui.extraPermission", zh: "需要额外权限的操作会被拒绝。") : controller.notice)
        let next=controller.models.keys.sorted()
        if next != modelIDs || model.numberOfItems==0 { modelIDs=next;model.removeAllItems();model.addItems(withTitles:[WSL10n.text("conductor.pickModel", zh: "请选择模型")]+next) }
        model.selectItem(at:controller.model.flatMap{modelIDs.firstIndex(of:$0)}.map{$0+1} ?? 0)
        model.toolTip=controller.model
        let efforts=controller.model.flatMap{controller.models[$0]}?.sorted() ?? []
        if efforts != effortIDs || effort.numberOfItems==0 { effortIDs=efforts;effort.removeAllItems();effort.addItems(withTitles:[WSL10n.text("conductor.effort", zh: "程度")]+efforts) }
        effort.selectItem(at:controller.effort.flatMap{effortIDs.firstIndex(of:$0)}.map{$0+1} ?? 0)
        if !draft.hasMarkedText(),!rejectedDraft,draft.string != controller.draft { draft.string=controller.draft }
        let fresh=inputIsCurrent()
        chooseProject.isEnabled=fresh && !controller.isBusy;chooseExecutable.isEnabled=chooseProject.isEnabled
        consent.isEnabled = !controller.isBusy;diagnostic.isEnabled = !controller.isBusy
        launch.isEnabled=fresh && consent.state == .on && controller.canLaunch
        login.isEnabled=fresh && controller.canLogin;cancelLogin.isEnabled=fresh && controller.phase == .signedOut && !controller.canLogin
        logout.isEnabled=fresh && controller.canLogout;resume.isEnabled=fresh && controller.canResume
        model.isEnabled=fresh && controller.canChooseModel
        effort.isEnabled=model.isEnabled && controller.model != nil
        let canKeepDraft = !draft.hasMarkedText() && draft.string.utf8.count<=65_536
        browseModels.isEnabled=fresh && controller.canChooseModel && canKeepDraft && openModelPicker != nil
        openConductor.isEnabled=fresh && canKeepDraft && openConductorPage != nil
        send.isEnabled=fresh && controller.canSend && !draft.hasMarkedText()
            && !draft.string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
            && draft.string.utf8.count<=65_536
        interrupt.isEnabled=fresh && controller.canInterrupt
        stop.isEnabled=fresh && controller.isBusy;diagnostics.isEnabled=fresh
        // Keep preparation out of the active conversation; actions follow actual capabilities.
        setup.isHidden=controller.isBusy
        launch.isHidden=controller.isBusy
        login.isHidden = !controller.canLogin
        cancelLogin.isHidden = !(controller.phase == .signedOut && !controller.canLogin)
        resume.isHidden = !controller.canResume
        launchActions.isHidden=launch.isHidden && login.isHidden && cancelLogin.isHidden && resume.isHidden
        logout.isHidden = !controller.canLogout
        stop.isHidden = !controller.isBusy
        interrupt.isHidden = !controller.canInterrupt && controller.phase != .interrupting
        let showsComposer=controller.isBusy && [.ready,.running,.completed,.failed,.sending,.creatingThread,.interrupting].contains(controller.phase)
        modelActions.isHidden = !showsComposer
        composer.isHidden = !showsComposer;composerHeading.isHidden = !showsComposer;send.isHidden = !showsComposer
        draft.isEditable=fresh && showsComposer
        let value=displayingDiagnostics ? controller.diagnostics:controller.text
        outputScroll.isHidden=value.isEmpty && !displayingDiagnostics
        replyHeading.isHidden=outputScroll.isHidden
        replyHeading.stringValue=displayingDiagnostics ? WSL10n.text("owned.ui.diagnostics", zh: "诊断信息"):WSL10n.text("owned.ui.replyHeading", zh: "助手回复")
        if output.string != value {
            let wasAtEnd=outputScroll.contentView.bounds.maxY>=output.bounds.maxY-24
            output.string=value
            if wasAtEnd { output.scrollToEndOfDocument(nil) }
        }
        // Use the existing island resize path; only the currently mounted owner may resize it.
        layoutSubtreeIfNeeded()
        let requested=max(interactionMinimumHeight,min(480,ceil(stack.fittingSize.height+28)))
        if abs(requested-contentHeight)>=1 {
            let opening=requested>contentHeight;contentHeight=requested
            if let panel=window as? NotchPanel,panel.isShowingInteraction(self) {
                panel.interactionSizeChanged(opening:opening)
            }
        }
    }
    func textDidChange(_ notification:Notification) {
        guard inputIsCurrent() else { return }
        rejectedDraft = !controller.editDraft(draft.string)
        render()
    }
    private func choose(directory:Bool) {
        guard inputIsCurrent(),!controller.isBusy else { return }
        let picker=NSOpenPanel();picker.canChooseDirectories=directory;picker.canChooseFiles = !directory
        picker.allowsMultipleSelection=false;picker.canCreateDirectories=false;picker.prompt=directory ? WSL10n.text("owned.ui.useProject", zh: "使用这个项目"):WSL10n.text("owned.ui.useProgram", zh: "使用这个程序")
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
        guard inputIsCurrent(),!draft.hasMarkedText() else { return }
        guard controller.editDraft(draft.string) else { return }
        openConductorPage?()
    }
    @objc private func selectModel() { guard inputIsCurrent(),model.indexOfSelectedItem>0 else { return };_=controller.chooseModel(modelIDs[model.indexOfSelectedItem-1]) }
    @objc private func selectEffort() { guard inputIsCurrent(),effort.indexOfSelectedItem>0 else { return };_=controller.chooseEffort(effortIDs[effort.indexOfSelectedItem-1]) }
    @objc private func sendDraft() { guard inputIsCurrent() else { return };_=controller.send(draft.string,hasMarkedText:draft.hasMarkedText()) }
    @objc private func interruptTurn() { guard inputIsCurrent() else { return };_=controller.interrupt() }
    @objc private func stopSession() { guard inputIsCurrent() else { return };controller.stop() }
    @objc private func toggleDiagnostics() { guard inputIsCurrent() else { return };displayingDiagnostics.toggle();diagnostics.title=displayingDiagnostics ? "返回回复":WSL10n.text("owned.ui.viewDiagnostics", zh: "查看诊断");render() }
    func revoke() {
        renderTask?.cancel();renderTask=nil;inputIsCurrent={false}
        for button in [chooseProject,chooseExecutable,launch,login,cancelLogin,logout,resume,send,interrupt,stop,diagnostics,consent,diagnostic,model,effort,browseModels,openConductor] { button.isEnabled=false }
        draft.isEditable=false;draft.inputContext?.discardMarkedText();draft.string="";output.string="";onCancel?()
    }
}

@MainActor private final class WS2OwnedDocumentView:NSView { override var isFlipped:Bool { true } }

@MainActor private final class WS2OwnedDraftScrollView:NSScrollView {
    override func draw(_ dirtyRect:NSRect) {
        super.draw(dirtyRect)
        let outline=NSBezierPath(roundedRect:bounds.insetBy(dx:0.25,dy:0.25),xRadius:12,yRadius:12)
        NSColor.white.withAlphaComponent(0.06).setFill();outline.fill()
        NSColor.white.withAlphaComponent(0.10).setStroke();outline.lineWidth=0.5;outline.stroke()
    }
}
