// 甩一下标题栏之后，让那扇窗口带着甩出去的速度滑进位置（路径见 FlickGlidePath）。
//
// 能动别的 App 窗口的只有辅助功能接口：跨进程的 SkyLight 移动在开着 SIP 的系统上会被静默忽略
// （见 FoldTransaction 里的实测记录）。所以在自己的串行队列上逐帧设置位置；位置便宜，App 不用重新排版。
// 尺寸要 App 重新排版：快的每秒改 60 次（位置照样每秒 120 次）；慢的在刚松手时一次改到位，之后只挪位置。实测一个简单的 App 改一次尺寸要 5–12 毫秒，每帧都改会把位置拖到每秒 76 帧。
// 每一帧都按“现在是第几毫秒”到路径上取值：哪一帧卡了就跳过去，不会越走越慢，落点和时长都不变。
// 最后按“尺寸、位置各两遍”校准一次，和其它排布一样准。随时可以取消（再次按住这扇窗就停在原地）。

import Cocoa
import ApplicationServices

final class WindowGlide: @unchecked Sendable {
    struct Report {
        var observed: CGRect
        var frames: Int
        var sizeSets: Int
        /// 最慢的一次辅助功能调用：看得出那个 App 跟不跟得上。
        var slowestCall: TimeInterval
        var elapsed: TimeInterval
        var cancelled: Bool
        /// 那个 App 卡住了（一次调用超过 80 毫秒），直接跳到终点。
        var gaveUp: Bool
    }

    private static let frameInterval = 1.0 / 120
    /// 每次滑行一条自己的队列：等它停手时只等它自己，不会被另一扇正在滑的窗口拖住。
    private let queue = DispatchQueue(label: "WindowShade.window-glide", qos: .userInteractive)

    let id: CGWindowID
    let path: FlickGlidePath
    private let element: AXUIElement
    private let lock = NSLock()
    private var isCancelled = false
    /// 同一扇窗上一次还没停手的滑行：开跑前在自己的队列上等它停下，主线程不用等。
    private let predecessor: WindowGlide?
    private let running = DispatchGroup()

    init(id: CGWindowID, element: AXUIElement, path: FlickGlidePath, after predecessor: WindowGlide? = nil) {
        self.id = id
        self.element = element
        self.path = path
        self.predecessor = predecessor
        predecessor?.cancel()
    }

    /// 停在当下的位置，不再校准到终点。
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    /// 停下，并等滑行线程真的停手再返回：之后马上要设窗口位置时用，免得滑行线程再补一帧把它挪走。
    /// 最多等一帧（那个 App 卡住时等到辅助功能调用超时）。不要在滑行自己的队列上调用。
    func cancelAndWait() {
        cancel()
        queue.sync {}
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    /// completion 在主线程上回调。
    func start(completion: @escaping @MainActor (Report) -> Void) {
        running.enter()
        queue.async { [self] in
            predecessor?.running.wait()
            let report = run()
            running.leave()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(report) }
            }
        }
    }

    private func run() -> Report {
        let began = CACurrentMediaTime()
        let duration = path.duration
        var frames = 0
        var sizeSets = 0
        var slowest: TimeInterval = 0
        var appliedSize = path.from.size
        var sizeEvery: TimeInterval = 1.0 / 60
        var lastSizeAt = -Double.infinity
        var gaveUp = false

        func timed(_ call: () -> Void) -> TimeInterval {
            let start = CACurrentMediaTime()
            call()
            let cost = CACurrentMediaTime() - start
            slowest = max(slowest, cost)
            return cost
        }

        while !cancelled {
            let t = CACurrentMediaTime() - began
            if t >= duration { break }
            let frame = path.frame(at: t)
            if sizeEvery.isFinite, t - lastSizeAt >= sizeEvery,
               abs(frame.width - appliedSize.width) >= 2 || abs(frame.height - appliedSize.height) >= 2 {
                let cost = timed { setAXSize(element, frame.size) }
                sizeSets += 1
                appliedSize = frame.size
                lastSizeAt = t
                if cost > 0.012 {
                    // 这个 App 改尺寸慢（Electron 一类实测 30–80 毫秒）：趁刚松手一次改到位，后面只挪位置，
                    // 滑行才跑得满帧。尺寸的变化落在松手那一刻，眼睛本来就在等窗口变。
                    _ = timed { setAXSize(element, path.to.size) }
                    sizeSets += 1
                    appliedSize = path.to.size
                    sizeEvery = .infinity
                } else {
                    sizeEvery = 1.0 / 60
                }
            }
            guard !cancelled else { break }
            let cost = timed { setAXPosition(element, frame.origin) }
            frames += 1
            if cost > 0.08 {
                gaveUp = true
                break
            }
            // 对齐到下一帧（120Hz）；这一帧已经晚了就立刻算下一帧。
            let now = CACurrentMediaTime()
            let next = began + (floor((now - began) / Self.frameInterval) + 1) * Self.frameInterval
            if next > now { usleep(useconds_t((next - now) * 1_000_000)) }
        }

        let wasCancelled = cancelled
        if !wasCancelled {
            _ = timed {
                if !cancelled { setAXSize(element, path.to.size) }
                if !cancelled { setAXPosition(element, path.to.origin) }
                if !cancelled { setAXSize(element, path.to.size) }
                if !cancelled { setAXPosition(element, path.to.origin) }
            }
        }
        let observed = CGRect(origin: axPosition(element) ?? path.to.origin, size: axSize(element) ?? path.to.size)
        return Report(observed: observed, frames: frames, sizeSets: sizeSets, slowestCall: slowest,
                      elapsed: CACurrentMediaTime() - began, cancelled: cancelled, gaveUp: gaveUp)
    }
}
