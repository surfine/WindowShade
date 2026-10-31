import Cocoa

/// 设置 → 高级 · 实验，「刷脸解锁（实验）」下面一行：代填登录密码（D11 第 6 步）。
///
/// 跟刷脸解锁同一个开关：开关关着、预览旗标也没开时这一行不出现（`WS2Exposure.showsRow(.autofillVoiceprint, …)`）。
/// 三个动作：存密码（先在本机核对对不对，再存进 Touch ID 保护的钥匙串）、用 Touch ID 打开这一段（密码进内存，
/// 解锁后或 4 小时后清掉）、删除。风险那一句只按攻击矩阵的实测结果写（`FaceAttackMatrix.claim`）。
extension AppDelegate {
    static let faceAutofillStatusID = NSUserInterfaceItemIdentifier("face-autofill-status")

    /// 这一行要不要出现（实验卡片组装时问）。
    var showsFaceAutofillRow: Bool {
        WS2Exposure.showsRow(.autofillVoiceprint, previewOn: WS2Preview.isOn,
                             pageAlreadyShown: UserDefaults.standard.bool(forKey: FaceScanExperiment.enabledKey),
                             moved: WS2Exposure.moved())
    }

    func makeFaceAutofillRow() -> NSView {
        let save = NSButton(title: WSL10n.text("face.autofill.save", zh: "存密码…"),
                            target: self, action: #selector(prefSaveAutofillPassword(_:)))
        save.bezelStyle = .rounded
        save.tag = 1
        let arm = NSButton(title: WSL10n.text("face.autofill.arm", zh: "用 Touch ID 打开"),
                           target: self, action: #selector(prefArmAutofill(_:)))
        arm.bezelStyle = .rounded
        arm.tag = 2
        let remove = NSButton(title: WSL10n.text("menu.delete", zh: "删除"),
                              target: self, action: #selector(prefRemoveAutofillPassword(_:)))
        remove.bezelStyle = .rounded
        remove.tag = 3
        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.identifier = Self.faceAutofillStatusID
        let controls = NSStackView(views: [save, arm, remove, status])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.setAccessibilityLabel(WSL10n.text("face.autofill.name", zh: "代填登录密码"))
        updateFaceAutofillControls(controls)
        FaceAutofillController.shared?.onChange = { [weak self, weak controls] in
            guard let controls else { return }
            self?.updateFaceAutofillControls(controls)
        }
        return makeUnifiedControlRow(name: WSL10n.setting("face.autofill.name", zh: "代填登录密码"),
                                     subtitle: Self.faceAutofillRisk(), control: controls)
    }

    /// 风险那一句：只说测过的。今天五种都没测。
    static func faceAutofillRisk(_ claim: FaceAttackMatrix.Claim = FaceAttackMatrix.claim()) -> SettingsText {
        switch claim {
        case .untested:
            return WSL10n.setting("face.autofill.risk.untested", zh: "实验：还没测过能不能挡住照片、录像和别人")
        case .knownWeak:
            return WSL10n.setting("face.autofill.risk.weak", zh: "实验：实测有挡不住的情况，先别用")
        case .allBlocked:
            return WSL10n.setting("face.autofill.risk.tested", zh: "实验：照片、手机屏幕、录像、别人、别的手机都实测挡住了")
        }
    }

    private func updateFaceAutofillControls(_ stack: NSStackView) {
        let faceOn = UserDefaults.standard.bool(forKey: FaceScanExperiment.enabledKey)
        let controller = FaceAutofillController.shared
        let stored = controller?.hasStoredPassword ?? false
        let armed = controller?.isArmed ?? false
        for case let button as NSButton in stack.views {
            switch button.tag {
            case 1: button.isEnabled = faceOn && controller != nil
            case 2: button.isEnabled = faceOn && stored && !armed
            case 3: button.isEnabled = faceOn && stored
            default: break
            }
        }
        guard let field = stack.views.compactMap({ $0 as? NSTextField })
            .first(where: { $0.identifier == Self.faceAutofillStatusID }) else { return }
        if !faceOn || controller == nil {
            field.stringValue = ""
        } else if !stored {
            field.stringValue = WSL10n.text("face.autofill.status.none", zh: "还没存")
        } else if armed, !Self.faceAutofillHasPhone() {
            // 决定 74：锁屏时的第二道只认配对过的 iPhone（遥控器那条加密连线）。没有它，闸门永远交回系统。
            field.stringValue = WSL10n.text("face.autofill.status.needsPhone", zh: "已打开，还要在遥控模式里配对你的 iPhone")
        } else if armed {
            field.stringValue = WSL10n.text("face.autofill.status.armed", zh: "已打开，解锁后清掉")
        } else {
            field.stringValue = WSL10n.text("face.autofill.status.stored", zh: "已存，还没打开")
        }
    }

    /// 遥控模式开着、至少配对过一台 iPhone（决定 74 的第二道来源）。
    private static func faceAutofillHasPhone() -> Bool {
        guard let host = (NSApp.delegate as? AppDelegate)?.inputController.remoteHostForSettings else { return false }
        return host.enabled && !host.pairedPeers.isEmpty
    }

    private func faceAutofillStack(from sender: NSView) -> NSStackView? { sender.superview as? NSStackView }

    private func setFaceAutofillStatus(_ text: String, near sender: NSView) {
        guard let stack = faceAutofillStack(from: sender),
              let field = stack.views.compactMap({ $0 as? NSTextField })
                .first(where: { $0.identifier == Self.faceAutofillStatusID }) else { return }
        field.stringValue = text
    }

    @objc func prefSaveAutofillPassword(_ sender: NSButton) {
        guard let controller = FaceAutofillController.shared else { NSSound.beep(); return }
        guard UnlockPasswordKeychainStore.biometryAvailable else {
            setFaceAutofillStatus(WSL10n.text("face.autofill.status.noTouchID", zh: "这台 Mac 没有可用的 Touch ID"), near: sender)
            return
        }
        let alert = NSAlert()
        alert.messageText = WSL10n.text("face.autofill.alert.title", zh: "存登录密码")
        alert.informativeText = WSL10n.text("face.autofill.alert.body",
            zh: "锁屏时认出你、手机或手表也对上，就替你输入。密码存在这台 Mac 的钥匙串里，按 Touch ID 才取得出来。")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = WSL10n.text("face.autofill.alert.placeholder", zh: "这台 Mac 的登录密码")
        alert.accessoryView = field
        alert.addButton(withTitle: WSL10n.text("face.autofill.alert.save", zh: "存"))
        alert.addButton(withTitle: WSL10n.text("face.autofill.alert.cancel", zh: "取消"))
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        var bytes = Array(field.stringValue.utf8)
        field.stringValue = ""
        guard response == .alertFirstButtonReturn, !bytes.isEmpty else { return }
        setFaceAutofillStatus(WSL10n.text("face.autofill.status.checking", zh: "正在核对…"), near: sender)
        // 输入框里的那份 String 清不掉（AppKit 自己持有），这里能清的只有我们自己的字节。
        let password = UnlockPasswordBytes(consuming: &bytes)
        controller.save(password) { [weak self, weak sender] result in
            guard let self, let sender else { return }
            switch result {
            case .saved:
                // 存好就请你按一次 Touch ID 打开这一段（第一次用）。
                self.prefArmAutofill(sender)
            case .wrongPassword:
                self.setFaceAutofillStatus(WSL10n.text("face.autofill.status.wrong", zh: "密码不对，没有存"), near: sender)
            case .unavailable:
                self.setFaceAutofillStatus(WSL10n.text("face.autofill.status.unavailable", zh: "这台 Mac 现在存不了"), near: sender)
            }
        }
    }

    @objc func prefArmAutofill(_ sender: NSButton) {
        guard let controller = FaceAutofillController.shared else { NSSound.beep(); return }
        controller.arm { [weak self, weak sender] result in
            guard let self, let sender, let stack = self.faceAutofillStack(from: sender) else { return }
            self.updateFaceAutofillControls(stack)
            switch result {
            case .armed: break
            case .cancelled:
                self.setFaceAutofillStatus(WSL10n.text("face.autofill.status.stored", zh: "已存，还没打开"), near: sender)
            case .unavailable, .locked:
                self.setFaceAutofillStatus(WSL10n.text("face.autofill.status.armFailed", zh: "没打开，指纹改过就要重新存"),
                                           near: sender)
            }
        }
    }

    @objc func prefRemoveAutofillPassword(_ sender: NSButton) {
        guard let controller = FaceAutofillController.shared else { NSSound.beep(); return }
        controller.remove { [weak self, weak sender] in
            guard let self, let sender, let stack = self.faceAutofillStack(from: sender) else { return }
            self.updateFaceAutofillControls(stack)
        }
    }
}
