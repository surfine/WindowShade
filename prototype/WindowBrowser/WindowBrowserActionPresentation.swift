// 动作与状态的唯一呈现模型。
//
// 卡片、列表行、右键菜单、快捷键提示与 VoiceOver 自定义动作都读取同一份
// `WindowBrowserActionItem`，能力判断只在 `WindowBrowserActionPolicy.preflight`
// 一处发生，因此不会出现“一处禁用、另一处仍可点”。

import Cocoa

struct WindowBrowserActionItem: Equatable {
    let action: WindowBrowserAction
    let title: String
    let symbolName: String?
    let isEnabled: Bool
    let disabledReason: String?
    let isDestructive: Bool
    let isBusy: Bool
    /// 该动作当前已经处于开启/生效状态（例如正在置顶预览）。
    let isOn: Bool
    /// 卡片/列表行的紧凑操作条默认显示哪些动作；其余动作放在“更多”菜单里。
    let isPrimary: Bool
}

enum WindowBrowserActionPresentation {
    struct Context: Equatable {
        var hasAccessibility: Bool
        var hasScreenRecording: Bool
        var isBusy: Bool
        var isSelected: Bool
        var isContextMenuOpen: Bool

        init(hasAccessibility: Bool = true,
             hasScreenRecording: Bool = true,
             isBusy: Bool = false,
             isSelected: Bool = false,
             isContextMenuOpen: Bool = false) {
            self.hasAccessibility = hasAccessibility
            self.hasScreenRecording = hasScreenRecording
            self.isBusy = isBusy
            self.isSelected = isSelected
            self.isContextMenuOpen = isContextMenuOpen
        }
    }

    /// 卡片/列表行/菜单都按这个顺序展示。
    static let orderedActions: [WindowBrowserAction] = [
        .activate, .fold, .unfold, .pinPreview, .unpinPreview, .minimize, .close
    ]

    /// 紧凑操作条常驻的动作；其余动作通过“更多”菜单或上下文菜单到达。
    static let primaryActions: [WindowBrowserAction] = [
        .fold, .unfold, .pinPreview, .unpinPreview
    ]

    static func items(for record: WindowRecord, context: Context) -> [WindowBrowserActionItem] {
        orderedActions.compactMap { item(for: $0, record: record, context: context) }
    }

    static func item(for action: WindowBrowserAction, record: WindowRecord,
                     context: Context) -> WindowBrowserActionItem? {
        // 折叠/展开是同一位置上的互斥动作，只展示当前适用的一个。
        if action == .fold && record.shadeState == .folded { return nil }
        if action == .unfold && record.shadeState != .folded { return nil }
        if action == .unpinPreview && record.pinState != .running { return nil }
        if action == .pinPreview && record.pinState == .running { return nil }
        if action == .minimize && record.isMinimized { return nil }

        let outcome = WindowBrowserActionPolicy.preflight(
            action: action, record: record,
            hasAccessibility: context.hasAccessibility,
            hasScreenRecording: context.hasScreenRecording)
        let blocked = context.isBusy && action != .activate && action != .unpinPreview
        let enabled: Bool
        let reason: String?
        if blocked {
            enabled = false
            reason = "操作正在进行中"
        } else if let outcome {
            switch outcome {
            case .completed:
                // 已经是目标状态：保留条目但置灰，避免出现“点了没反应”的按钮。
                enabled = false
                reason = nil
            case .unsupported(let text):
                enabled = false
                reason = text
            case .permissionRequired(let kind):
                enabled = false
                reason = kind == .accessibility
                    ? "需要辅助功能权限" : "需要屏幕录制权限"
            case .busy:
                enabled = false
                reason = "操作正在进行中"
            case .targetGone:
                enabled = false
                reason = "窗口已不存在"
            case .awaitingUser(let text), .uncertain(let text):
                enabled = false
                reason = text
            case .failed(let text):
                enabled = false
                reason = text
            }
        } else {
            enabled = true
            reason = nil
        }
        return WindowBrowserActionItem(
            action: action,
            title: title(for: action, record: record),
            symbolName: symbolName(for: action, record: record),
            isEnabled: enabled,
            disabledReason: reason,
            isDestructive: action == .close,
            isBusy: context.isBusy && !blocked,
            isOn: isOn(action: action, record: record),
            isPrimary: primaryActions.contains(action))
    }

    static func title(for action: WindowBrowserAction, record: WindowRecord) -> String {
        switch action {
        case .activate:
            return record.shadeState == .folded ? "展开" : "激活"
        case .fold:
            return "折叠"
        case .unfold:
            return "展开"
        case .pinPreview:
            return record.shadeState == .folded ? "展开并置顶预览" : "置顶预览"
        case .unpinPreview:
            return "取消置顶"
        case .minimize:
            return "最小化"
        case .close:
            return "关闭窗口"
        }
    }

    static func symbolName(for action: WindowBrowserAction, record: WindowRecord) -> String? {
        switch action {
        case .activate:
            return record.shadeState == .folded ? "rectangle.expand.vertical" : "arrow.up.forward.app"
        case .fold:
            return "rectangle.compress.vertical"
        case .unfold:
            return "rectangle.expand.vertical"
        case .pinPreview:
            return "pin"
        case .unpinPreview:
            return "pin.slash"
        case .minimize:
            return "minus"
        case .close:
            return "xmark"
        }
    }

    private static func isOn(action: WindowBrowserAction,
                             record: WindowRecord) -> Bool {
        switch action {
        case .pinPreview, .unpinPreview: return record.pinState == .running
        case .fold: return record.shadeState == .folded
        default: return false
        }
    }
}

/// 状态的统一呈现：文字 + 系统符号 + 是否警告色。
/// 正常卷起、离屏停放、最小化都不是错误，只有真实失败才使用警告色。
struct WindowBrowserStatusPresentation: Equatable {
    let text: String
    let symbolName: String?
    let isWarning: Bool
    let isSnapshot: Bool

    var hasVisibleText: Bool { !text.isEmpty }
}

enum WindowBrowserStatusPresentationFactory {
    static func make(record: WindowRecord, hasSnapshot: Bool) -> WindowBrowserStatusPresentation {
        switch (record.shadeState, record.pinState, record.systemVisibility) {
        case (.restoring, _, _):
            return WindowBrowserStatusPresentation(
                text: "正在展开", symbolName: "arrow.triangle.2.circlepath",
                isWarning: false, isSnapshot: false)
        case (.folded, .running, _):
            return WindowBrowserStatusPresentation(
                text: "已折叠 · 置顶预览", symbolName: "curtains.closed",
                isWarning: false, isSnapshot: false)
        case (.folded, .suspended, _):
            return WindowBrowserStatusPresentation(
                text: "已折叠 · 预览已暂停", symbolName: "curtains.closed",
                isWarning: false, isSnapshot: false)
        case (.folded, _, _):
            // 已折叠且物理离屏是正常状态，不使用异常警告。
            return WindowBrowserStatusPresentation(
                text: "已折叠", symbolName: "curtains.closed",
                isWarning: false, isSnapshot: false)
        case (_, .running, _):
            return WindowBrowserStatusPresentation(
                text: "置顶预览", symbolName: "pin",
                isWarning: false, isSnapshot: false)
        case (_, .suspended, _):
            return WindowBrowserStatusPresentation(
                text: "预览已暂停", symbolName: "pause.circle",
                isWarning: false, isSnapshot: false)
        case (_, _, .minimized):
            return WindowBrowserStatusPresentation(
                text: hasSnapshot ? "已最小化 · 快照" : "已最小化",
                symbolName: "minus.square", isWarning: false, isSnapshot: hasSnapshot)
        case (_, _, .applicationHidden):
            return WindowBrowserStatusPresentation(
                text: hasSnapshot ? "应用已隐藏 · 快照" : "应用已隐藏",
                symbolName: "eye.slash", isWarning: false, isSnapshot: hasSnapshot)
        case (_, _, .offScreen):
            return WindowBrowserStatusPresentation(
                text: "屏幕外", symbolName: "rectangle.dashed",
                isWarning: false, isSnapshot: false)
        case (_, _, .unknown):
            return WindowBrowserStatusPresentation(
                text: "", symbolName: nil, isWarning: false, isSnapshot: false)
        default:
            // 普通窗口只展示标题，不重复写“打开”。
            return WindowBrowserStatusPresentation(
                text: "", symbolName: nil, isWarning: false, isSnapshot: false)
        }
    }

    /// 真实失败/权限说明：只有这一类才使用警告色。
    static func failure(_ text: String) -> WindowBrowserStatusPresentation {
        WindowBrowserStatusPresentation(text: text, symbolName: "exclamationmark.triangle",
                                        isWarning: true, isSnapshot: false)
    }
}

/// 动作结果的 VoiceOver 播报文案（纯函数，便于断言）。
/// 只在真实操作结束后播报一句结果，不对悬停、列表刷新或缩略图到达逐条播报。
enum WindowBrowserAccessibilityAnnouncement {
    static func text(for outcome: WindowBrowserActionOutcome,
                     action: WindowBrowserAction,
                     windowTitle: String) -> String? {
        let target = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = target.isEmpty ? "" : "：\(target)"
        switch outcome {
        case .completed:
            return "\(actionTitle(action))完成\(suffix)"
        case .awaitingUser(let reason):
            return reason
        case .permissionRequired(let kind):
            return kind == .accessibility ? "需要辅助功能权限" : "需要屏幕录制权限"
        case .failed(let reason), .uncertain(let reason), .unsupported(let reason):
            return reason
        case .busy:
            return "操作正在进行中"
        case .targetGone:
            return "窗口已不存在"
        }
    }

    private static func actionTitle(_ action: WindowBrowserAction) -> String {
        switch action {
        case .activate: return "激活"
        case .fold: return "折叠"
        case .unfold: return "展开"
        case .pinPreview: return "置顶预览"
        case .unpinPreview: return "取消置顶预览"
        case .close: return "关闭窗口"
        case .minimize: return "最小化"
        }
    }
}

/// 页脚结果状态的播报规则（纯函数）：
/// 只播报“结果性”状态（例如实时预览回退、排布结果、首次说明），且只在内容变化时
/// 播报一次；常规的“正在刷新窗口…”这类刷新型状态不打断读屏。
enum WindowBrowserStatusAnnouncement {
    static func shouldAnnounce(isResultStatus: Bool, status: String, previous: String?) -> Bool {
        let clean = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isResultStatus, !clean.isEmpty else { return false }
        return clean != previous
    }
}

/// Space 大图只读预览的纯策略：取图来源、窗口尺寸与无图时的说明。
enum WindowBrowserQuickLookSource: Equatable {
    /// 服务缓存里仍然新鲜的画面。
    case thumbnail
    /// 服务缓存里的过期画面：合法但可能已经过期，界面上要标成快照。
    case staleSnapshot
    /// 折叠窗口保存的最后画面。
    case foldSnapshot
    case applicationIcon
}

enum WindowBrowserQuickLookPolicy {
    /// 取图顺序：新鲜缓存 → 过期快照 → 折叠快照 → 应用图标 + 说明。
    /// 新鲜/过期由调用方（缩略图服务）判定，这里只做优先级。
    static func source(hasThumbnail: Bool,
                       hasStaleSnapshot: Bool = false,
                       hasFoldSnapshot: Bool) -> WindowBrowserQuickLookSource {
        if hasThumbnail { return .thumbnail }
        if hasStaleSnapshot { return .staleSnapshot }
        if hasFoldSnapshot { return .foldSnapshot }
        return .applicationIcon
    }

    /// 大图窗口：按图片比例放进当前屏幕可见区域的约 70%，并留出标题/说明的空间。
    static func frame(imageSize: CGSize, visibleFrame: NSRect,
                      maximumFraction: CGFloat = 0.7,
                      chromeHeight: CGFloat = 44) -> NSRect {
        // 小屏/异常可用区域下也要留在屏幕内：上限先钳到可用区域本身，
        // 最后再把结果矩形整体夹回可见区域。
        let safeVisible = NSRect(x: visibleFrame.minX, y: visibleFrame.minY,
                                 width: max(80, visibleFrame.width),
                                 height: max(80, visibleFrame.height))
        let maxWidth = min(safeVisible.width, max(120, safeVisible.width * maximumFraction))
        let maxHeight = min(safeVisible.height,
                            max(80, safeVisible.height * maximumFraction - chromeHeight))
        let safeImage = CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
        let scale = min(1, min(maxWidth / safeImage.width, maxHeight / safeImage.height))
        let size = CGSize(width: min(maxWidth, ceil(safeImage.width * scale)),
                          height: min(safeVisible.height,
                                      ceil(safeImage.height * scale) + chromeHeight))
        let rect = NSRect(x: safeVisible.midX - size.width / 2,
                          y: safeVisible.midY - size.height / 2,
                          width: size.width, height: size.height)
        return WindowBrowserGeometry.clamp(rect, into: safeVisible)
    }

    /// 没有画面时给出的原因（大图预览不能让用户面对一块空白）。
    static func message(for source: WindowBrowserQuickLookSource,
                        isMinimized: Bool = false,
                        isFolded: Bool = false,
                        hasScreenRecording: Bool = true) -> String? {
        switch source {
        case .thumbnail: return nil
        case .staleSnapshot: return "快照（画面可能已过期）"
        case .foldSnapshot: return "折叠时保存的快照"
        case .applicationIcon:
            if !hasScreenRecording { return "缺少屏幕录制权限，暂时只能显示应用图标" }
            if isFolded { return "折叠窗口没有已保存的画面" }
            if isMinimized { return "最小化窗口没有快照，暂时只能显示应用图标" }
            return "暂时没有可用的窗口画面"
        }
    }
}

/// 系统符号的统一入口：验证符号在当前运行系统上存在，缺失时返回 nil，
/// 视图回落到项目自绘图形或纯文字，不把任意 Unicode 几何字符当图标。
enum WindowBrowserSymbol {
    static func image(named name: String?,
                      accessibilityDescription: String? = nil,
                      pointSize: CGFloat = 13,
                      weight: NSFont.Weight = .regular) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let image = NSImage(systemSymbolName: name,
                                  accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.isTemplate = true
        return configured
    }
}
