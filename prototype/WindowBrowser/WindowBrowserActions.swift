// 明确目标的动作入口。UI 只提交 WindowKey 和动作，不直接调用 AX 写函数，
// 也不直接修改 shaded / 置顶会话。
//
// 本文件里的协调器是纯逻辑：外部系统通过 WindowBrowserActionBackend 注入，
// 时间通过 WindowBrowserScheduler 注入，因此可以不做真实 sleep 地测试
// 防重入、同义合并、超时与“超时后仍执行”的行为。

import Foundation

// MARK: - 调度

final class WindowBrowserScheduledWork {
    private let lock = NSLock()
    private var cancelled = false
    private var cancelAction: (() -> Void)?

    init(onCancel: (() -> Void)? = nil) {
        self.cancelAction = onCancel
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let action = cancelAction
        cancelAction = nil
        lock.unlock()
        action?()
    }
}

protocol WindowBrowserScheduler: AnyObject {
    func async(_ work: @escaping () -> Void)
    func schedule(after delay: TimeInterval,
                  _ work: @escaping () -> Void) -> WindowBrowserScheduledWork
}

final class WindowBrowserMainQueueScheduler: WindowBrowserScheduler {
    func async(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    func schedule(after delay: TimeInterval,
                  _ work: @escaping () -> Void) -> WindowBrowserScheduledWork {
        let item = DispatchWorkItem(block: work)
        let scheduled = WindowBrowserScheduledWork(onCancel: { item.cancel() })
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
            guard !item.isCancelled else { return }
            item.perform()
        }
        return scheduled
    }
}

// MARK: - 后端契约

/// 单次完成门：桥接 completion 在正常返回、失败、超时、取消竞争时只允许生效一次。
final class WindowBrowserSingleShotCompletion<Value> {
    private let lock = NSLock()
    private var finished = false
    private let body: (Value) -> Void

    init(_ body: @escaping (Value) -> Void) {
        self.body = body
    }

    @discardableResult
    func call(_ value: Value) -> Bool {
        lock.lock()
        let first = !finished
        finished = true
        lock.unlock()
        if first { body(value) }
        return first
    }

    var hasFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

enum WindowBrowserTargetValidation: Equatable {
    case valid
    case gone
    case unverifiable(reason: String)
    case permissionMissing(WindowBrowserPermissionKind)
}

/// 激活动作的终态判定：区分“已请求”“已聚焦”和“无法确认”。
/// 目标仍然存在不等于焦点已经到达，因此不能拿存在当成功。
enum WindowBrowserActivationVerification {
    static func outcome(targetFocused: Bool,
                        stillPresent: Bool) -> WindowBrowserActionOutcome {
        if targetFocused { return .completed }
        return stillPresent
            ? .uncertain(reason: "点了，但不确定窗口是否到了最前面")
            : .targetGone
    }
}

protocol WindowBrowserActionBackend: AnyObject {
    /// 执行前重新核对目标身份、能力与最新状态。不得根据标题猜测替代目标。
    func validate(target: WindowKey,
                  completion: @escaping (WindowBrowserTargetValidation) -> Void)
    /// 后端必须保证 completion 恰好调用一次。
    func perform(action: WindowBrowserAction,
                 target: WindowKey,
                 completion: @escaping (WindowBrowserActionOutcome) -> Void)
}

// MARK: - 预检策略

enum WindowBrowserActionPolicy {
    /// 动作开始前的静态检查：能力、权限与明显状态冲突。返回 nil 表示可以继续。
    static func preflight(action: WindowBrowserAction,
                          record: WindowRecord,
                          hasAccessibility: Bool,
                          hasScreenRecording: Bool) -> WindowBrowserActionOutcome? {
        switch action {
        case .activate:
            guard record.capabilities.contains(.activate) else {
                return .unsupported(reason: "这个窗口不支持激活")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
        case .fold:
            guard record.shadeState != .folded else { return .completed }
            guard record.shadeState != .restoring else { return .busy }
            guard record.capabilities.contains(.fold) else {
                return .unsupported(reason: "这个窗口不能收起来")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
        case .unfold:
            guard record.shadeState == .folded else {
                // 执行前发现窗口已经是展开的：安全地按完成处理，不得反向再折一次。
                return record.shadeState == .restoring ? .busy : .completed
            }
            guard record.capabilities.contains(.unfold) else {
                return .unsupported(reason: "只能用它自己的方式恢复")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
        case .pinPreview:
            guard record.capabilities.contains(.pinPreview) else {
                return .unsupported(reason: "这个窗口不能置顶预览")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
            guard hasScreenRecording else { return .permissionRequired(kind: .screenRecording) }
            if record.shadeState == .folded {
                // 已折叠窗口的按钮写“展开并置顶预览”，先走恢复。
                guard record.capabilities.contains(.unfold) else {
                    return .unsupported(reason: "收起的窗口找不到恢复入口")
                }
            }
            if record.pinState == .suspended {
                // 暂停中的置顶会话不能被悬停或新入口偷偷恢复/另建流。
                return .unsupported(reason: "置顶预览已暂停，先在菜单里打开")
            }
        case .unpinPreview:
            guard record.pinState != .none else { return .completed }
            guard record.capabilities.contains(.unpinPreview) else {
                return .unsupported(reason: "没有可取消的置顶预览")
            }
        case .close:
            guard record.capabilities.contains(.close) else {
                return .unsupported(reason: "这个窗口不能关闭")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
        case .minimize:
            if record.isMinimized { return .completed }
            guard record.capabilities.contains(.minimize) else {
                return .unsupported(reason: "这个窗口不能最小化")
            }
            guard hasAccessibility else { return .permissionRequired(kind: .accessibility) }
        }
        return nil
    }
}

// MARK: - 协调器

final class WindowBrowserActionCoordinator {
    struct Submission {
        let id: UUID
        let action: WindowBrowserAction
        let target: WindowKey
        var completions: [(WindowBrowserActionOutcome) -> Void]
        var didEmitOutcome = false
        var timeoutWork: WindowBrowserScheduledWork?
    }

    typealias LateOutcomeHandler = (WindowBrowserActionOutcome, WindowBrowserAction, WindowKey) -> Void

    private weak var backend: WindowBrowserActionBackend?
    private let scheduler: WindowBrowserScheduler
    private let timeout: TimeInterval
    private let onLateOutcome: LateOutcomeHandler?
    /// 同一 PID 下最多挂起的写操作数。超过就回 busy，不无限累积用户连续点击。
    private let maxQueuedPerPID: Int

    private var activeByPID: [pid_t: Submission] = [:]
    private var queueByPID: [pid_t: [Submission]] = [:]
    private var allSubmissions: [UUID: Submission] = [:]

    init(backend: WindowBrowserActionBackend,
         scheduler: WindowBrowserScheduler,
         timeout: TimeInterval = 6.0,
         maxQueuedPerPID: Int = 2,
         onLateOutcome: LateOutcomeHandler? = nil) {
        self.backend = backend
        self.scheduler = scheduler
        self.timeout = timeout
        self.maxQueuedPerPID = max(1, maxQueuedPerPID)
        self.onLateOutcome = onLateOutcome
    }

    /// 提交动作。
    /// - 同一窗口 + 同义动作：合并到同一完成回调列表。
    /// - 同一窗口 + 相反动作：直接回 busy，绝不在写操作进行中排队相反操作。
    /// - 同一 PID 的其他窗口：进入有界串行队列，先后执行（任务书要求同一 PID 串行）。
    /// - 队列已满：回 busy，不无限累积用户连续点击。
    func submit(action: WindowBrowserAction, target: WindowKey,
                completion: @escaping (WindowBrowserActionOutcome) -> Void) {
        let pid = target.application.pid
        if var active = activeByPID[pid],
           active.target == target, active.action == action {
            active.completions.append(completion)
            activeByPID[pid] = active
            allSubmissions[active.id] = active
            return
        }
        if var queued = queueByPID[pid],
           let index = queued.firstIndex(where: { $0.target == target && $0.action == action }) {
            queued[index].completions.append(completion)
            queueByPID[pid] = queued
            return
        }
        if let active = activeByPID[pid] {
            if active.target == target {
                // 同一个真实窗口在写操作进行中：拒绝相反/不同动作。
                completion(.busy)
                return
            }
            guard (queueByPID[pid]?.count ?? 0) < maxQueuedPerPID else {
                completion(.busy)
                return
            }
        }
        let submission = Submission(id: UUID(), action: action, target: target,
                                    completions: [completion])
        allSubmissions[submission.id] = submission
        queueByPID[pid, default: []].append(submission)
        pump(pid: pid)
    }

    func isBusy(windowKey: WindowKey) -> Bool {
        let pid = windowKey.application.pid
        if let active = activeByPID[pid], active.target == windowKey { return true }
        return queueByPID[pid]?.contains(where: { $0.target == windowKey }) ?? false
    }

    func isBusy(pid: pid_t) -> Bool {
        activeByPID[pid] != nil || !(queueByPID[pid]?.isEmpty ?? true)
    }

    func busyWindowKeys() -> Set<WindowKey> {
        var keys = Set(activeByPID.values.map(\.target))
        for queued in queueByPID.values {
            keys.formUnion(queued.map(\.target))
        }
        return keys
    }

    /// 面板关闭/应用终止时调用。已经开始的同步 AX 事务不能被取消，仍会真实完成；
    /// 协调器不再把它当作可写目标，也绝不在它完成前启动相反动作。
    func cancelPending(for pid: pid_t) {
        for queued in queueByPID.removeValue(forKey: pid) ?? [] {
            allSubmissions.removeValue(forKey: queued.id)
            queued.timeoutWork?.cancel()
            if !queued.didEmitOutcome {
                queued.completions.forEach { $0(.uncertain(reason: "已取消，但操作可能还在进行")) }
            }
        }
    }

    func cancelAll() {
        for pid in Array(queueByPID.keys) { cancelPending(for: pid) }
    }

    var activeCount: Int { activeByPID.count }
    var queuedCount: Int { queueByPID.values.reduce(0) { $0 + $1.count } }

    // MARK: 内部

    private func pump(pid: pid_t) {
        guard activeByPID[pid] == nil,
              var next = queueByPID[pid]?.first else { return }
        queueByPID[pid]?.removeFirst()
        if queueByPID[pid]?.isEmpty == true { queueByPID.removeValue(forKey: pid) }
        next.timeoutWork = scheduler.schedule(after: timeout) { [weak self] in
            self?.emitTimeout(submissionID: next.id)
        }
        activeByPID[pid] = next
        allSubmissions[next.id] = next
        guard let backend else {
            finish(pid: pid, submissionID: next.id, outcome: .failed(reason: "操作没能完成"))
            return
        }
        backend.validate(target: next.target) { [weak self] validation in
            guard let self else { return }
            self.scheduler.async { self.handleValidation(pid: pid,
                                                         submissionID: next.id,
                                                         validation: validation) }
        }
    }

    private func handleValidation(pid: pid_t, submissionID: UUID,
                                  validation: WindowBrowserTargetValidation) {
        guard let submission = activeByPID[pid], submission.id == submissionID else { return }
        switch validation {
        case .valid:
            let action = submission.action
            let target = submission.target
            guard let backend = self.backend else {
                self.finish(pid: pid, submissionID: submissionID,
                            outcome: .failed(reason: "操作没能完成"))
                return
            }
            backend.perform(action: action, target: target) { [weak self] outcome in
                guard let self else { return }
                self.scheduler.async {
                    self.finish(pid: pid, submissionID: submissionID, outcome: outcome)
                }
            }
        case .gone:
            finish(pid: pid, submissionID: submissionID, outcome: .targetGone)
        case .unverifiable(let reason):
            finish(pid: pid, submissionID: submissionID,
                   outcome: .uncertain(reason: "没能确认是哪一扇窗口：\(reason)"))
        case .permissionMissing(let kind):
            finish(pid: pid, submissionID: submissionID,
                   outcome: .permissionRequired(kind: kind))
        }
    }

    private func emitTimeout(submissionID: UUID) {
        guard let pid = activeByPID.first(where: { $0.value.id == submissionID })?.key,
              var submission = activeByPID[pid] else { return }
        guard !submission.didEmitOutcome else { return }
        submission.didEmitOutcome = true
        activeByPID[pid] = submission
        allSubmissions[submissionID] = submission
        // 超时只影响 UI/调用方的“等待”状态：底层同步 AX/捕获调用可能已经无法取消，
        // 仍然占据该 PID 的写额度，直到它真实返回。
        submission.completions.forEach {
            $0(.uncertain(reason: "操作超时，可能还在进行"))
        }
    }

    private func finish(pid: pid_t, submissionID: UUID,
                        outcome: WindowBrowserActionOutcome) {
        guard let submission = activeByPID[pid], submission.id == submissionID else {
            // 已经超时/取消的迟到结果只做记账，不再投递 UI。
            if let known = allSubmissions[submissionID], known.didEmitOutcome {
                onLateOutcome?(outcome, known.action, known.target)
            }
            return
        }
        submission.timeoutWork?.cancel()
        activeByPID.removeValue(forKey: pid)
        allSubmissions.removeValue(forKey: submissionID)
        if !submission.didEmitOutcome {
            submission.completions.forEach { $0(outcome) }
        } else {
            onLateOutcome?(outcome, submission.action, submission.target)
        }
        scheduler.async { [weak self] in self?.pump(pid: pid) }
    }
}
