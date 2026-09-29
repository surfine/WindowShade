// 启动台的异步图像缓存：一代对应一套尺寸，旧任务只能结算自己，不能覆盖新屏幕的图。
import Cocoa

@MainActor
final class LaunchpadArtwork {
    struct Drawing {
        let path: String
        let icon: CGImage?
        let label: CGImage?
    }
    typealias Renderer = ([LaunchpadApp], CGFloat, CGFloat, @escaping ([Drawing]) -> Void) -> Void
    private struct Entry {
        let drawing: Drawing
        var used: UInt64
        var bytes: Int {
            [drawing.icon, drawing.label].compactMap { $0 }.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        }
    }
    private var entries: [String: Entry] = [:]
    private var loading: Set<String> = []
    private var generation: UInt64 = 0
    private var clock: UInt64 = 0
    private var width: CGFloat = 0
    private var scale: CGFloat = 0
    private let budget: Int
    private let renderer: Renderer

    init(budget: Int = 32 * 1024 * 1024, renderer: @escaping Renderer = LaunchpadArtwork.render) {
        self.budget = budget
        self.renderer = renderer
    }

    func art(for path: String) -> (CGImage?, CGImage?) {
        guard var entry = entries[path] else { return (nil, nil) }
        clock &+= 1
        entry.used = clock
        entries[path] = entry
        return (entry.drawing.icon, entry.drawing.label)
    }

    func request(_ apps: [LaunchpadApp], width: CGFloat, scale: CGFloat, arrived: @escaping (Set<String>) -> Void) {
        guard width > 0, scale > 0, width.isFinite, scale.isFinite else { return }
        if self.width != width || self.scale != scale {
            self.width = width; self.scale = scale
            generation &+= 1
            entries.removeAll()
            loading.removeAll()
        }
        let ticket = generation
        var seen = Set<String>()
        let missing = apps.filter { entries[$0.path] == nil && !loading.contains($0.path) && seen.insert($0.path).inserted }
        guard !missing.isEmpty else { return }
        loading.formUnion(missing.map(\.path))
        renderer(missing, width, scale) { [weak self] drawings in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, ticket == self.generation else { return }
                    let requested = Set(missing.map(\.path))
                    self.loading.subtract(requested)
                    for drawing in drawings where requested.contains(drawing.path) {
                        self.clock &+= 1
                        self.entries[drawing.path] = Entry(drawing: drawing, used: self.clock)
                    }
                    // 先让可见图层接住结果，再按LRU限额保留缓存；不会把在途旧结果塞回新一代。
                    arrived(requested)
                    var bytes = self.entries.values.reduce(0) { $0 + $1.bytes }
                    for (path, entry) in self.entries.sorted(by: { $0.value.used < $1.value.used }) where bytes > self.budget {
                        bytes -= entry.bytes
                        self.entries.removeValue(forKey: path)
                    }
                }
            }
        }
    }

    nonisolated private static let renderQueue = DispatchQueue(label: "WindowShade.launchpad-art", qos: .userInitiated)

    nonisolated private static func render(_ apps: [LaunchpadApp], width: CGFloat, scale: CGFloat,
                                           completion: @escaping ([Drawing]) -> Void) {
        renderQueue.async {
            let workers = min(4, apps.count)
            let lock = NSLock()
            var results: [Drawing] = []
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                var batch: [Drawing] = []
                for index in stride(from: worker, to: apps.count, by: workers) {
                    autoreleasepool {
                        let app = apps[index]
                        batch.append(Drawing(path: app.path,
                                             icon: AppCatalog.icon(for: app.path, pixels: Int(ceil(112 * scale))),
                                             label: AppCatalog.label(app.name, width: width, scale: scale)))
                    }
                }
                lock.lock(); results += batch; lock.unlock()
            }
            completion(results)
        }
    }
}
