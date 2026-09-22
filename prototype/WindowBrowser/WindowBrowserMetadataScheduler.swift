// 每个应用实例一个元数据槽：一个在途任务 + 一个最新待处理需求。
//
// 旧任务结束时，无论结果是否允许发布，都必须按槽身份完成清理，并推进仍然需要的
// 最新需求；旧请求不能删除新请求的记账。槽里带独立 JobID 与应用实例代数，
// 因此 stop/start 或 PID 复用后的旧回调不会影响新任务。

import Foundation

/// Only this ticket crosses from the main-thread scheduler to the AX queue.
/// Cancelled queued jobs cannot begin IPC; already-running calls finish normally.
final class WindowBrowserMetadataExecution: Equatable {
    private let lock = NSLock()
    private var cancelled = false
    private var started = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func begin() -> Bool {
        lock.withLock {
            guard !cancelled, !started else { return false }
            started = true
            return true
        }
    }

    func cancel() { lock.withLock { cancelled = true } }

    static func == (lhs: WindowBrowserMetadataExecution,
                    rhs: WindowBrowserMetadataExecution) -> Bool { lhs === rhs }
}

struct WindowBrowserMetadataDemand: Equatable {
    let jobID: UInt64
    let requestID: WindowBrowserRequestID
    let appInstance: ApplicationInstanceKey?
    let execution = WindowBrowserMetadataExecution()
}

struct WindowBrowserMetadataSlot: Equatable {
    private(set) var inFlight: WindowBrowserMetadataDemand?
    private(set) var pending: WindowBrowserMetadataDemand?
    /// 诊断：被最新需求覆盖掉的旧待处理需求数量。
    private(set) var coalescedCount = 0

    var isIdle: Bool { inFlight == nil && pending == nil }

    /// 新需求到达。返回需要立即启动的任务；已有在途任务时只记录最新待处理需求。
    mutating func request(jobID: UInt64,
                          requestID: WindowBrowserRequestID,
                          appInstance: ApplicationInstanceKey?) -> WindowBrowserMetadataDemand? {
        let demand = WindowBrowserMetadataDemand(jobID: jobID, requestID: requestID,
                                                 appInstance: appInstance)
        guard let current = inFlight else {
            inFlight = demand
            return demand
        }
        if current.requestID == requestID, current.appInstance == appInstance,
           !current.execution.isCancelled {
            // 同一需求已经在途：不重复排队。
            return nil
        }
        current.execution.cancel()
        if pending != nil, pending != demand { coalescedCount += 1 }
        pending?.execution.cancel()
        pending = demand
        return nil
    }

    /// 在途任务真实结束（它的完成回调已经按 JobID 核对过）。
    /// 返回接着要启动的最新需求；旧任务的完成不会清掉新版请求的记账。
    mutating func complete(jobID: UInt64) -> WindowBrowserMetadataDemand? {
        guard inFlight?.jobID == jobID else { return nil }
        inFlight = nil
        guard let next = pending else { return nil }
        pending = nil
        inFlight = next
        return next
    }

    /// 应用终止或功能停止：整槽失效。
    mutating func reset() {
        inFlight?.execution.cancel()
        pending?.execution.cancel()
        inFlight = nil
        pending = nil
    }

    /// Closing a panel cancels work but preserves an in-flight slot until its
    /// callback arrives, so reopening cannot overlap AX reads for the same app.
    mutating func cancelRequests() {
        inFlight?.execution.cancel()
        pending?.execution.cancel()
        pending = nil
    }
}

final class WindowBrowserMetadataScheduler {
    private var slots: [pid_t: WindowBrowserMetadataSlot] = [:]
    private var jobCounter: UInt64 = 0

    /// 新需求：返回 (jobID, demand) 表示需要启动；返回 nil 表示已经在途。
    func request(pid: pid_t, requestID: WindowBrowserRequestID,
                 appInstance: ApplicationInstanceKey?)
        -> (jobID: UInt64, demand: WindowBrowserMetadataDemand)? {
        jobCounter &+= 1
        let jobID = jobCounter
        var slot = slots[pid] ?? WindowBrowserMetadataSlot()
        guard let demand = slot.request(jobID: jobID, requestID: requestID,
                                        appInstance: appInstance) else {
            slots[pid] = slot
            return nil
        }
        slots[pid] = slot
        return (jobID, demand)
    }

    /// 任务结束。返回非 nil 表示要立刻启动这个最新需求。
    func complete(pid: pid_t, jobID: UInt64) -> WindowBrowserMetadataDemand? {
        guard var slot = slots[pid] else { return nil }
        let next = slot.complete(jobID: jobID)
        if slot.isIdle { slots.removeValue(forKey: pid) } else { slots[pid] = slot }
        return next
    }

    func cancel(pid: pid_t) {
        var slot = slots.removeValue(forKey: pid)
        slot?.reset()
    }

    func cancelAll() {
        for var slot in slots.values { slot.reset() }
        slots.removeAll()
    }

    func cancelRequests() {
        for pid in Array(slots.keys) { slots[pid]?.cancelRequests() }
    }

    func state(pid: pid_t) -> WindowBrowserMetadataSlot {
        slots[pid] ?? WindowBrowserMetadataSlot()
    }

    /// 诊断：当前仍占用的槽数（停止后应归零）。
    var activeSlotCount: Int { slots.count }
}
