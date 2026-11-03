import Foundation

/// 实时活动（两耳、紧凑、提醒）跟着“你正在用的那块屏”走（Aaron 2026-10-31 第 41–43 条）。
/// 正在用的屏 = 指针或键盘焦点窗口最近换到的那块；谁最后换的听谁的，两者都没动就留在原处。
/// 原来的那块屏没了（合盖、拔线）就挪到现在的焦点屏，再不行是内建屏、再不行是第一块。
/// 纯逻辑：屏用 UInt32 的显示器编号表示，不碰 AppKit。
struct ActiveDisplayTracker {
    private(set) var active: UInt32?
    private var lastPointer: UInt32?
    private var lastKey: UInt32?


    /// `displays`：可以承载活动的屏（让给系统的屏不在里面）；`builtin`：内建屏（可为 nil）；
    /// `pointer`、`key`：指针所在屏、焦点窗口所在屏（不在 `displays` 里的当作没有）。返回现在的活动屏。
    @discardableResult
    mutating func update(displays: [UInt32], builtin: UInt32?, pointer: UInt32?, key: UInt32?) -> UInt32? {
        guard !displays.isEmpty else {
            active = nil; lastPointer = nil; lastKey = nil
            return nil
        }
        let pointer = pointer.flatMap { displays.contains($0) ? $0 : nil }
        let key = key.flatMap { displays.contains($0) ? $0 : nil }
        if let pointer, pointer != lastPointer {
            active = pointer
        } else if let key, key != lastKey {
            active = key
        }
        lastPointer = pointer
        lastKey = key
        if let current = active, displays.contains(current) { return current }
        let builtinHere = builtin.flatMap { displays.contains($0) ? $0 : nil }
        active = key ?? pointer ?? builtinHere ?? displays.first
        return active
    }
}
