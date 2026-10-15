import Cocoa
import ImageIO
import Synchronization

/// 正在播放的封面（设计稿《正在播放》工作包 NP-1）。
///
/// 推送流继续带 --no-artwork（一行几百 KB，会顶穿解析器的 64 KB 上限）。曲目换了，这里再用 adapter 的
/// `get` 取一次，只解这一次的封面：
/// - 上限 4 MB（解码后的图片字节），超了当没有；
/// - 立刻缩到 128 × 128（56 点 × 2 倍），顺手算一份封面取色；
/// - 内存里只留最新一张，不落盘，不进日志；换曲、关闭时先丢掉旧的。
///
/// 这一包只做取得与缓存：没有调用方画封面，画面不变。

/// 一张缩好的封面和它的取色结果。像素是 128 × 128 的预乘 RGBA（sRGB），只在内存里。
struct NowPlayingArtworkImage: Sendable, Equatable {
    static let side = 128

    let trackKey: String
    let rgba: Data
    let palette: ArtworkPalette
    /// 64 × 64 取色输入的指纹：同一张封面不重算。
    let fingerprint: UInt64

    /// 给画封面的一方用；不缓存 CGImage，用一次造一次。
    func makeCGImage() -> CGImage? {
        guard rgba.count == Self.side * Self.side * 4,
              let provider = CGDataProvider(data: rgba as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: Self.side, height: Self.side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: Self.side * 4, space: space,
                       bitmapInfo: NowPlayingArtworkDecoder.bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

enum NowPlayingArtworkDecoder {
    nonisolated static let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)
    /// 超过这个像素数的图不解（防解压炸弹）；4 MB 的压缩图正常远小于它。
    nonisolated static let maxSourcePixels = 64_000_000

    /// 图片字节 → 128 × 128 + 取色。解不开、太大、不是图片都返回 nil。可在任意后台队列调用。
    nonisolated static func decode(imageData: Data, trackKey: String) -> NowPlayingArtworkImage? {
        guard !imageData.isEmpty, imageData.count <= NowPlayingArtworkPayload.maxImageBytes,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions),
              CGImageSourceGetCount(source) >= 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maxSourcePixels / height else { return nil }

        // 短边缩到 128、长边按比例（最多 512），再居中裁成正方形。
        let side = NowPlayingArtworkImage.side
        let target = min(512, Int((Double(side) * Double(max(width, height)) / Double(min(width, height))).rounded(.up)))
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(side, target),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              thumbnail.width > 0, thumbnail.height > 0 else { return nil }

        guard let big = draw(thumbnail, side: side, space: space),
              let bigImage = big.makeImage(), let bigPixels = pixels(of: big, side: side),
              let small = draw(bigImage, side: ArtworkPalette.side, space: space),
              let smallPixels = pixels(of: small, side: ArtworkPalette.side) else { return nil }

        let straight = ArtworkPalette.unpremultiplied(smallPixels)
        return NowPlayingArtworkImage(trackKey: trackKey, rgba: Data(bigPixels),
                                      palette: ArtworkPalette.make(rgba: straight),
                                      fingerprint: ArtworkPalette.fingerprint(of: straight))
    }

    /// 把图按“填满”画进 side × side 的正方形，居中裁切。
    private nonisolated static func draw(_ image: CGImage, side: Int, space: CGColorSpace) -> CGContext? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: bitmapInfo.rawValue) else { return nil }
        context.interpolationQuality = .high
        let scale = max(Double(side) / Double(image.width), Double(side) / Double(image.height))
        let width = Double(image.width) * scale
        let height = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2,
                                       width: width, height: height))
        return context
    }

    private nonisolated static func pixels(of context: CGContext, side: Int) -> [UInt8]? {
        guard let base = context.data else { return nil }
        let count = side * side * 4
        return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: count))
    }
}

/// 换曲时取一次封面，只留最新一张。没有调用方就什么都不做（`trackChanged` 不被调用）。
@MainActor
final class NowPlayingArtwork {
    /// 换曲后等一下再起 get：连点下一首时只取最后一首。
    nonisolated static let settleDelay: TimeInterval = 0.35
    /// get 子进程最长等多久。
    nonisolated static let fetchTimeout: TimeInterval = 4

    /// 当前这首的封面；还没取到、取不到、超 4 MB 都是 nil。
    private(set) var latest: NowPlayingArtworkImage?
    var onChange: ((NowPlayingArtworkImage?) -> Void)?

    private var generation = 0
    private var currentKey: String?

    /// 推送流给出新现状时调用。曲目没变（暂停、继续、进度）什么都不做；换曲先丢掉旧封面。
    func trackChanged(to info: NowPlayingInfo?) {
        guard let info else { clear(); return }
        let key = info.artworkTrackKey
        guard key != currentKey else { return }
        currentKey = key
        generation += 1
        let token = generation
        dropLatest()
        guard NowPlayingStream.isEnabled else { return }
        let timer = Timer(timeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFetch(for: info, token: token) }
        }
        timer.tolerance = Self.settleDelay / 2
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 关掉、锁屏、播放器退出时调用：丢掉封面，在途的结果作废。
    func clear() {
        generation += 1
        currentKey = nil
        dropLatest()
    }

    private func dropLatest() {
        guard latest != nil else { return }
        latest = nil
        onChange?(nil)
    }

    private func startFetch(for info: NowPlayingInfo, token: Int) {
        guard token == generation, NowPlayingStream.isEnabled, let adapter = NowPlayingStream.locateAdapter() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = Self.fetch(adapter: adapter, expecting: info)
            DispatchQueue.main.async { self?.finish(image, token: token) }
        }
    }

    private func finish(_ image: NowPlayingArtworkImage?, token: Int) {
        guard token == generation, let image else { return }
        latest = image
        onChange?(image)
    }

    /// 起一次 `get`，读到封面就解。阻塞调用，只在后台队列用。读超过上限就掐掉子进程。
    nonisolated static func fetch(adapter: NowPlayingStream.Adapter, expecting info: NowPlayingInfo) -> NowPlayingArtworkImage? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [adapter.script.path, adapter.framework.path, "get", "--micros"]
        let out = Pipe()
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        let collector = ArtworkOutputCollector(limit: NowPlayingArtworkPayload.maxOutputBytes)
        let finished = DispatchSemaphore(value: 0)
        let handle = out.fileHandleForReading
        handle.readabilityHandler = { reader in
            let chunk = reader.availableData
            if chunk.isEmpty {
                reader.readabilityHandler = nil
                finished.signal()
            } else if !collector.append(chunk) {
                reader.readabilityHandler = nil
                finished.signal()
            }
        }
        do { try task.run() } catch {
            handle.readabilityHandler = nil
            return nil
        }
        _ = finished.wait(timeout: .now() + fetchTimeout)
        handle.readabilityHandler = nil
        if task.isRunning { task.terminate() }

        guard let data = collector.result(),
              let payload = NowPlayingArtworkPayload.parse(data), payload.matches(info) else { return nil }
        return NowPlayingArtworkDecoder.decode(imageData: payload.imageData, trackKey: info.artworkTrackKey)
    }
}

/// 子进程输出的有上限收集器。readabilityHandler 在系统后台队列串行调用；锁只为满足 Sendable。
// 规格 M3：数据与超限标记进 Mutex，去掉 @unchecked Sendable。
private final class ArtworkOutputCollector: Sendable {
    private struct State {
        var data = Data()
        var overflow = false
    }
    private let state = Mutex(State())
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    /// 还能继续收返回 true；超限返回 false（之后 `result()` 为 nil）。
    func append(_ chunk: Data) -> Bool {
        state.withLock { s in
            guard !s.overflow else { return false }
            if s.data.count + chunk.count > limit {
                s.overflow = true
                s.data = Data()
                return false
            }
            s.data.append(chunk)
            return true
        }
    }

    func result() -> Data? {
        state.withLock { $0.overflow ? nil : $0.data }
    }
}
