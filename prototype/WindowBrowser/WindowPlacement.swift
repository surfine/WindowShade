// 基本窗口排布：纯数据计划 + 预览 + 执行验证 + 可撤销记录。
//
// 复用现有真实窗口身份（WindowKey）与目标解析：排布先把目标位置算成一份
// `WindowPlacementPlan`（只描述目标显示器、旧 frame、目标 frame 与原因），
// 预览层只画轮廓，不移动真实窗口；用户确认后才写 AX 位置，并在读回验证成功后
// 才登记撤销。不自动进入系统全屏，不搬运 Space，不处理跨重启身份。

import Cocoa

enum WindowPlacementAction: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    case fill
    case moveToDisplay
    case undoLast

    var title: String {
        switch self {
        case .leftHalf: return "左半屏"
        case .rightHalf: return "右半屏"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        case .center: return "居中"
        case .fill: return "填满可用区域"
        case .moveToDisplay: return "移到另一显示器"
        case .undoLast: return "撤销上次排布"
        }
    }

    var symbolName: String? {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .center: return "rectangle.center.inset.filled"
        case .fill: return "rectangle.inset.filled"
        case .moveToDisplay: return "rectangle.on.rectangle"
        case .undoLast: return "arrow.uturn.backward"
        }
    }

    /// 首批排布动作（撤销单独处理）。填满工作区域与系统全屏不同：不改变 Space。
    static var placeable: [WindowPlacementAction] {
        [.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft,
         .bottomRight, .center, .fill, .moveToDisplay]
    }
}

struct WindowPlacementPlan: Equatable {
    let target: WindowKey
    let action: WindowPlacementAction
    /// 目标显示器；nil 表示使用窗口当前所在显示器。
    let displayID: CGDirectDisplayID?
    /// 目标显示器可用工作区域的 AX 坐标（左上原点，y 向下）。
    let targetAreaAX: CGRect
    let originalFrameAX: CGRect
    let targetFrameAX: CGRect
    let reason: String
}

struct WindowPlacementUndoRecord: Equatable {
    let target: WindowKey
    let action: WindowPlacementAction
    let displayID: CGDirectDisplayID?
    let frameBeforeAX: CGRect
    let frameAfterAX: CGRect
}

enum WindowPlacementOutcome: Equatable {
    case applied(WindowPlacementUndoRecord)
    case undone(WindowPlacementUndoRecord)
    case unsupported(reason: String)
    case failed(reason: String)
    case uncertain(reason: String)
    case refused(reason: String)
}

enum WindowPlacementGeometry {
    /// 目标 frame 计算是纯几何：只输入可用工作区域、当前 frame 与窗口最小尺寸。
    static func targetFrame(action: WindowPlacementAction,
                            visibleArea: CGRect,
                            currentFrame: CGRect,
                            minimumSize: CGSize = .zero,
                            targetArea: CGRect? = nil) -> CGRect? {
        guard visibleArea.width > 40, visibleArea.height > 40 else { return nil }
        let area = targetArea ?? visibleArea
        guard area.width > 40, area.height > 40 else { return nil }
        let size = currentFrame.size
        let frame: CGRect
        switch action {
        case .leftHalf:
            frame = CGRect(x: area.minX, y: area.minY,
                           width: area.width / 2, height: area.height)
        case .rightHalf:
            frame = CGRect(x: area.midX, y: area.minY,
                           width: area.width / 2, height: area.height)
        case .topLeft:
            frame = CGRect(x: area.minX, y: area.minY,
                           width: area.width / 2, height: area.height / 2)
        case .topRight:
            frame = CGRect(x: area.midX, y: area.minY,
                           width: area.width / 2, height: area.height / 2)
        case .bottomLeft:
            frame = CGRect(x: area.minX, y: area.midY,
                           width: area.width / 2, height: area.height / 2)
        case .bottomRight:
            frame = CGRect(x: area.midX, y: area.midY,
                           width: area.width / 2, height: area.height / 2)
        case .center:
            let width = min(max(size.width, minimumSize.width), area.width)
            let height = min(max(size.height, minimumSize.height), area.height)
            frame = CGRect(x: area.midX - width / 2, y: area.midY - height / 2,
                           width: width, height: height)
        case .fill:
            frame = area
        case .moveToDisplay:
            guard targetArea != nil else {
                // 没有目标显示器时保持不动，调用方应给出明确失败原因。
                return nil
            }
            frame = movedFrame(currentFrame: currentFrame, from: visibleArea, to: area)
        case .undoLast:
            return nil
        }
        return normalized(frame, minimumSize: minimumSize, within: area)
    }

    /// 跨显示器搬运：按可用区域的归一化位置映射，绝不直接复制像素坐标。
    static func movedFrame(currentFrame: CGRect, from sourceArea: CGRect,
                           to targetArea: CGRect) -> CGRect {
        guard sourceArea.width > 1, sourceArea.height > 1 else {
            return CGRect(x: targetArea.minX, y: targetArea.minY,
                          width: min(currentFrame.width, targetArea.width),
                          height: min(currentFrame.height, targetArea.height))
        }
        let normalizedX = (currentFrame.minX - sourceArea.minX) / sourceArea.width
        let normalizedY = (currentFrame.minY - sourceArea.minY) / sourceArea.height
        let width = min(currentFrame.width, targetArea.width)
        let height = min(currentFrame.height, targetArea.height)
        let x = targetArea.minX + normalizedX * targetArea.width
        let y = targetArea.minY + normalizedY * targetArea.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func normalized(_ frame: CGRect, minimumSize: CGSize,
                           within area: CGRect) -> CGRect {
        var result = frame
        if minimumSize.width > 0 { result.size.width = max(result.width, minimumSize.width) }
        if minimumSize.height > 0 { result.size.height = max(result.height, minimumSize.height) }
        result.size.width = min(result.width, area.width)
        result.size.height = min(result.height, area.height)
        if result.minX < area.minX { result.origin.x = area.minX }
        if result.maxX > area.maxX { result.origin.x = area.maxX - result.width }
        if result.minY < area.minY { result.origin.y = area.minY }
        if result.maxY > area.maxY { result.origin.y = area.maxY - result.height }
        return result
    }
}

enum WindowPlacementPolicy {
    /// 组装一份计划。返回 nil 表示这个动作在当前情况下没有可行目标。
    static func plan(action: WindowPlacementAction,
                     target: WindowKey,
                     originalFrameAX: CGRect,
                     visibleAreaAX: CGRect,
                     targetAreaAX: CGRect? = nil,
                     displayID: CGDirectDisplayID? = nil,
                     minimumSize: CGSize = .zero) -> WindowPlacementPlan? {
        guard action != .undoLast else { return nil }
        guard let frame = WindowPlacementGeometry.targetFrame(
            action: action, visibleArea: visibleAreaAX, currentFrame: originalFrameAX,
            minimumSize: minimumSize, targetArea: targetAreaAX) else { return nil }
        return WindowPlacementPlan(target: target,
                                   action: action,
                                   displayID: displayID,
                                   targetAreaAX: targetAreaAX ?? visibleAreaAX,
                                   originalFrameAX: originalFrameAX,
                                   targetFrameAX: frame,
                                   reason: action.title)
    }

    /// 执行结果是否与计划一致（容差 2pt，允许系统做最小尺寸等合理修正）。
    static func matches(_ observed: CGRect, plan: WindowPlacementPlan,
                        tolerance: CGFloat = 2) -> Bool {
        abs(observed.minX - plan.targetFrameAX.minX) <= tolerance
            && abs(observed.minY - plan.targetFrameAX.minY) <= tolerance
            && abs(observed.width - plan.targetFrameAX.width) <= tolerance
            && abs(observed.height - plan.targetFrameAX.height) <= tolerance
    }

    /// 撤销前核对：窗口当前 frame 是否仍是排布完成时的样子。
    /// 用户已经手动移走时拒绝回放，避免突然覆盖用户的新安排。
    static func canUndo(record: WindowPlacementUndoRecord,
                        currentFrame: CGRect?, tolerance: CGFloat = 2) -> Bool {
        guard let currentFrame else { return false }
        return abs(currentFrame.minX - record.frameAfterAX.minX) <= tolerance
            && abs(currentFrame.minY - record.frameAfterAX.minY) <= tolerance
            && abs(currentFrame.width - record.frameAfterAX.width) <= tolerance
            && abs(currentFrame.height - record.frameAfterAX.height) <= tolerance
    }
}

protocol WindowPlacementBackend: AnyObject {
    /// 读取目标窗口当前 frame（AX 坐标）；目标不存在时返回 nil。
    func readFrame(of target: WindowKey, completion: @escaping (CGRect?) -> Void)
    /// 设置位置与尺寸；completion 表示两次写调用是否都成功投递。
    func writeFrame(_ frame: CGRect, to target: WindowKey,
                    completion: @escaping (Bool) -> Void)
}

protocol WindowPlacementPreviewPresenting: AnyObject {
    func show(plan: WindowPlacementPlan)
    func dismiss()
}

final class WindowPlacementController {
    weak var backend: WindowPlacementBackend?
    private let scheduler: WindowBrowserScheduler
    private let verificationDelay: TimeInterval
    private(set) var undoRecord: WindowPlacementUndoRecord?
    private(set) var previewedPlan: WindowPlacementPlan?
    weak var previewPresenter: WindowPlacementPreviewPresenting?

    init(backend: WindowPlacementBackend,
         scheduler: WindowBrowserScheduler,
         previewPresenter: WindowPlacementPreviewPresenting? = nil,
         verificationDelay: TimeInterval = 0.15) {
        self.backend = backend
        self.scheduler = scheduler
        self.previewPresenter = previewPresenter
        self.verificationDelay = verificationDelay
    }

    var canUndo: Bool { undoRecord != nil }

    /// 只画目标位置轮廓，不移动真实窗口。
    func preview(_ plan: WindowPlacementPlan) {
        previewedPlan = plan
        previewPresenter?.show(plan: plan)
    }

    /// 取消预览不改变真实窗口。
    func cancelPreview() {
        previewedPlan = nil
        previewPresenter?.dismiss()
    }

    func apply(_ plan: WindowPlacementPlan,
               completion: @escaping (WindowPlacementOutcome) -> Void) {
        guard let backend else {
            completion(.failed(reason: "排布后端已释放"))
            return
        }
        cancelPreview()
        backend.readFrame(of: plan.target) { [weak self] frameBefore in
            guard let self else { return }
            guard let frameBefore else {
                completion(.unsupported(reason: "窗口已不存在"))
                return
            }
            backend.writeFrame(plan.targetFrameAX, to: plan.target) { wrote in
                guard wrote else {
                    completion(.failed(reason: "系统拒绝了移动或调整尺寸"))
                    return
                }
                _ = self.scheduler.schedule(after: self.verificationDelay) { [weak self] in
                    guard let self else { return }
                    backend.readFrame(of: plan.target) { observed in
                        guard let observed else {
                            completion(.uncertain(reason: "排布后无法确认窗口状态"))
                            return
                        }
                        guard WindowPlacementPolicy.matches(observed, plan: plan) else {
                            completion(.uncertain(
                                reason: "窗口未达到目标位置（可能受最小尺寸限制）"))
                            return
                        }
                        let record = WindowPlacementUndoRecord(
                            target: plan.target, action: plan.action,
                            displayID: plan.displayID,
                            frameBeforeAX: frameBefore, frameAfterAX: observed)
                        self.undoRecord = record
                        completion(.applied(record))
                    }
                }
            }
        }
    }

    func undoLast(completion: @escaping (WindowPlacementOutcome) -> Void) {
        guard let backend else {
            completion(.failed(reason: "排布后端已释放"))
            return
        }
        guard let record = undoRecord else {
            completion(.unsupported(reason: "没有可撤销的排布"))
            return
        }
        backend.readFrame(of: record.target) { [weak self] current in
            guard let self else { return }
            guard WindowPlacementPolicy.canUndo(record: record, currentFrame: current) else {
                self.undoRecord = nil
                completion(.refused(reason: "窗口已被移动，撤销不再适用"))
                return
            }
            backend.writeFrame(record.frameBeforeAX, to: record.target) { wrote in
                guard wrote else {
                    completion(.failed(reason: "系统拒绝了撤销"))
                    return
                }
                _ = self.scheduler.schedule(after: self.verificationDelay) { [weak self] in
                    guard let self else { return }
                    backend.readFrame(of: record.target) { observed in
                        guard let observed else {
                            completion(.uncertain(reason: "撤销后无法确认窗口状态"))
                            return
                        }
                        let restored = abs(observed.minX - record.frameBeforeAX.minX) <= 2
                            && abs(observed.minY - record.frameBeforeAX.minY) <= 2
                            && abs(observed.width - record.frameBeforeAX.width) <= 2
                            && abs(observed.height - record.frameBeforeAX.height) <= 2
                        guard restored else {
                            completion(.uncertain(reason: "撤销后的位置与记录不一致"))
                            return
                        }
                        self.undoRecord = nil
                        completion(.undone(record))
                    }
                }
            }
        }
    }
}

/// 排布预览窗口：只画目标位置轮廓，点击穿透、不激活、不改变任何窗口。
final class WindowPlacementPreviewWindow: NSPanel, WindowPlacementPreviewPresenting {
    private let outlineLayer = CAShapeLayer()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        let content = NSView(frame: .zero)
        content.wantsLayer = true
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.lineWidth = 2
        outlineLayer.lineDashPattern = [6, 4]
        outlineLayer.cornerRadius = 8
        outlineLayer.strokeColor = NSColor.controlAccentColor.cgColor
        content.layer?.addSublayer(outlineLayer)
        contentView = content
    }

    func show(plan: WindowPlacementPlan) {
        // 与项目其它 AX 坐标转换共用同一条规则：以主屏高度为翻转基线。
        let baseline = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.maxY
            ?? NSScreen.main?.frame.maxY ?? 0
        let panelFrame = WindowBrowserGeometry.cocoaFrame(
            fromAXPosition: plan.targetFrameAX.origin,
            size: plan.targetFrameAX.size,
            baselineY: baseline)
        setFrame(panelFrame, display: true)
        outlineLayer.frame = contentView?.bounds ?? .zero
        outlineLayer.path = CGPath(roundedRect: contentView?.bounds ?? .zero,
                                   cornerWidth: 8, cornerHeight: 8, transform: nil)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
