import Foundation

/// 拷贝进度的来源（实验，默认关：defaults 键 `Activities.copyProgress`）。
///
/// 用系统自己的文件进度订阅口（NSProgress 按文件地址订阅），订阅用户主目录下的“下载”“桌面”“文稿”。
/// Finder 拷贝或移动文件时会把进度发布出来，系统把它交给订阅的人：我们只读它的比例、已完成和总量、
/// 第几个共几个，以及正在拷的文件名；不读文件内容，也不去数目录。
/// 没有轮询：数变了才来（KVO），收到后合并成每 0.25 秒至多一次；拷完或被取消，系统通知收尾；关掉就拆订阅。
@MainActor
final class CopyProgressSource {
    nonisolated static let enabledKey = "Activities.copyProgress"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    /// 数变了之后最多隔多久告诉刘海一次。
    nonisolated static let coalesce: TimeInterval = 0.25

    var onChange: ((CopyProgressUpdate) -> Void)?
    private var tracker = CopyProgressTracker()
    private var subscribers: [Any] = []
    private var epoch = 0
    private var nextID = 0

    /// 订阅的三个地方，都在用户主目录下。
    private static func folders() -> [URL] {
        [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory, .documentDirectory].compactMap {
            FileManager.default.urls(for: $0, in: .userDomainMask).first
        }
    }

    func start() {
        guard subscribers.isEmpty, Self.isEnabled else { return }
        epoch += 1
        let token = epoch
        for folder in Self.folders() {
            // 系统在哪个线程调用这个回调不确定：回调里只拿数，换成值再回到主线程。
            let subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
                guard progress.kind == .file, progress.fileOperationKind == .copying else { return nil }
                let watcher = CopyProgressWatcher(progress: progress) { event in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.receive(event, epoch: token) }
                    }
                }
                return { watcher.finish() }
            }
            subscribers.append(subscriber)
        }
    }

    func stop() {
        epoch += 1
        for subscriber in subscribers { Progress.removeSubscriber(subscriber) }
        subscribers.removeAll()
        tracker.reset()
    }

    private func receive(_ event: CopyProgressWatcher.Event, epoch token: Int) {
        guard token == epoch, !subscribers.isEmpty else { return }
        let update: CopyProgressUpdate
        switch event {
        case .changed(let id, let snapshot):
            update = tracker.update(id: id, snapshot: snapshot)
        case .ended(let id, let snapshot, let cancelled):
            update = tracker.end(id: id, outcome: CopyProgressTracker.outcome(final: snapshot, cancelled: cancelled), final: snapshot)
        }
        onChange?(update)
    }
}

/// 盯着一件系统发布的拷贝进度。KVO 在任何线程都可能来：状态都在锁里，对外只发值。
private final class CopyProgressWatcher: NSObject, @unchecked Sendable {
    enum Event: Sendable {
        case changed(id: Int, snapshot: CopyProgressSnapshot)
        case ended(id: Int, snapshot: CopyProgressSnapshot, cancelled: Bool)
    }

    private static let idLock = NSLock()
    nonisolated(unsafe) private static var idCounter = 0
    private static func makeID() -> Int {
        idLock.lock(); defer { idLock.unlock() }
        idCounter += 1
        return idCounter
    }

    private let id = CopyProgressWatcher.makeID()
    /// 变化和结束都从这一条串行队列发出去：结束一定排在最后一次变化后面，不会被旧的变化“复活”。
    private let queue = DispatchQueue(label: "com.windowshade.activities.copy", qos: .utility)
    private let progress: Progress
    private let send: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var scheduled = false
    private var finished = false
    private var observations: [NSKeyValueObservation] = []

    init(progress: Progress, send: @escaping @Sendable (Event) -> Void) {
        self.progress = progress
        self.send = send
        super.init()
        // 比例、已完成、总量任何一个变了，都只是“该告诉刘海了”：合并后再取一次值。
        observations = [
            progress.observe(\.fractionCompleted, options: []) { [weak self] _, _ in self?.schedule() },
            progress.observe(\.completedUnitCount, options: []) { [weak self] _, _ in self?.schedule() },
            progress.observe(\.totalUnitCount, options: []) { [weak self] _, _ in self?.schedule() },
        ]
        schedule()
    }

    private func snapshot() -> CopyProgressSnapshot {
        CopyProgressSnapshot(fractionCompleted: progress.fractionCompleted,
                             completedUnitCount: progress.completedUnitCount,
                             totalUnitCount: progress.totalUnitCount,
                             isIndeterminate: progress.isIndeterminate,
                             fileCompletedCount: progress.fileCompletedCount,
                             fileTotalCount: progress.fileTotalCount,
                             name: progress.fileURL?.lastPathComponent)
    }

    /// 合并：0.25 秒内的多次变化只发一次。
    private func schedule() {
        lock.lock()
        guard !scheduled, !finished else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        queue.asyncAfter(deadline: .now() + CopyProgressSource.coalesce) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.scheduled = false
            let done = self.finished
            self.lock.unlock()
            guard !done else { return }
            self.send(.changed(id: self.id, snapshot: self.snapshot()))
        }
    }

    /// 系统收回了这件进度：拷完、被取消或中途停了。
    func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        observations.removeAll()
        queue.async { [self] in
            send(.ended(id: id, snapshot: snapshot(), cancelled: progress.isCancelled))
        }
    }
}
