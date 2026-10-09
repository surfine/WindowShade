import Accelerate
import CoreGraphics
import Foundation
import Metal
import QuartzCore

// 收起／合盖渲染管线（F08）：在飞帧空位、GPU 共享对象只建一次、page 金字塔按帧确认、
// 静图零拷贝纹理与旧路径逐字节一致。需要真实 Metal 设备与 .build/duo-metal/Duo.metallib。

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ message: String) {
  if condition {
    print("ok  \(message)")
  } else {
    failures += 1
    print("FAIL \(message)")
  }
}

final class IdentitySet: @unchecked Sendable {
  private let lock = NSLock()
  private var values = Set<ObjectIdentifier>()
  func insert(_ object: AnyObject) {
    lock.lock()
    values.insert(ObjectIdentifier(object))
    lock.unlock()
  }
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return values.count
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private(set) var value = 0
  private(set) var peak = 0
  func enter() {
    lock.lock()
    value += 1
    peak = max(peak, value)
    lock.unlock()
  }
  func leave() {
    lock.lock()
    value -= 1
    lock.unlock()
  }
  func bump() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }
}

// MARK: - 在飞帧空位

func testSlots() {
  check(FoldFrameSlots.configuredCapacity(environment: [:]) == 1, "默认 1 帧在飞")
  check(
    FoldFrameSlots.configuredCapacity(environment: [FoldFrameSlots.environmentKey: "1"]) == 2,
    "开关打开后 2 帧在飞")
  check(FoldFrameSlots(capacity: 9).capacity == 2, "上限钳到 2")
  check(FoldFrameSlots(capacity: 0).capacity == 1, "下限钳到 1")

  for capacity in [1, 2] {
    let slots = FoldFrameSlots(capacity: capacity)
    var held = 0
    while slots.tryAcquire() { held += 1 }
    check(held == capacity, "容量 \(capacity)：连续拿空位恰好拿到 \(capacity) 个")
    slots.release()
    check(slots.tryAcquire(), "容量 \(capacity)：还一个就能再拿一个")
    check(!slots.tryAcquire(), "容量 \(capacity)：还完之前拿不到第 \(capacity + 1) 个")
    for _ in 0..<capacity { slots.release() }

    // 多线程抢：同时持有的数目绝不超过容量。完成回调在别的线程归还，这里模拟这种交错。
    let inFlight = Counter()
    let skipped = Counter()
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
      for _ in 0..<4000 {
        if slots.tryAcquire() {
          inFlight.enter()
          for _ in 0..<50 { _ = mach_absolute_time() }
          inFlight.leave()
          slots.release()
        } else {
          _ = skipped.bump()
        }
      }
    }
    check(inFlight.peak <= capacity, "容量 \(capacity)：并发峰值 \(inFlight.peak) 不超过容量")
    check(inFlight.peak >= 1, "容量 \(capacity)：确实有帧在飞")
    var after = 0
    while slots.tryAcquire() { after += 1 }
    check(after == capacity, "容量 \(capacity)：抢完后空位全部归还")
    for _ in 0..<after { slots.release() }
  }
}

// MARK: - 只建一次

struct OnceError: Error {}

func testOnce() {
  let once = FoldOnce<NSObject>()
  let made = Counter()
  let identities = IdentitySet()
  DispatchQueue.concurrentPerform(iterations: 32) { _ in
    let value = once.get { () -> NSObject in
      _ = made.bump()
      Thread.sleep(forTimeInterval: 0.002)
      return NSObject()
    }
    identities.insert(value)
  }
  check(made.value == 1, "32 个线程同时取，工厂只调用 1 次（实际 \(made.value)）")
  check(identities.count == 1, "所有线程拿到同一个对象")
  let original = once.current!
  let replaced = once.storeIfEmpty(NSObject())
  check(replaced === original, "已有值时预热结果被丢弃，保留原对象")

  let flaky = FoldOnce<NSObject>()
  var attempts = 0
  let first = try? flaky.get { () throws -> NSObject in
    attempts += 1
    throw OnceError()
  }
  check(first == nil && flaky.current == nil, "创建失败不缓存")
  let second = try? flaky.get { () throws -> NSObject in
    attempts += 1
    return NSObject()
  }
  check(second != nil && attempts == 2, "失败后下次重试成功")
}

// MARK: - page 金字塔按帧确认

func key(_ version: UInt64) -> FoldPageKey {
  FoldPageKey(
    sourceVersion: version, sourceWidth: 100, sourceHeight: 100, pixelFormatRawValue: 80,
    colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1), pageWidth: 100,
    pageHeight: 100)
}

func testPageSubmissions() {
  var pages = FoldPageSubmissions()
  let a = key(1)
  let b = key(2)
  check(pages.needsRebuild(for: a), "没有已证实的金字塔时必须重建")
  pages.submitted(rebuild: a)
  check(pages.needsRebuild(for: a), "第一份还在飞、没被证实：第二帧仍要自己重建")
  pages.submitted(rebuild: a)
  pages.completed(rebuilt: a, success: true)
  check(!pages.needsRebuild(for: a), "已证实且在飞的只有同键重建：静态源不再重建")
  pages.completed(rebuilt: a, success: true)
  check(!pages.needsRebuild(for: a), "全部完成后静态源不重建")
  pages.completed(rebuilt: nil, success: true)
  check(pages.state.key == a, "没重建的帧完成不改已证实的键")

  // 换源：B 在飞时，回到 A 的帧不能沿用旧确认（B 会先改写同一张 page 纹理）。
  pages.submitted(rebuild: b)
  check(pages.needsRebuild(for: a), "别的键在飞：即使已证实 A，也要重建")
  check(pages.needsRebuild(for: b), "B 还没被证实：要 B 也得重建")
  pages.completed(rebuilt: b, success: true)
  check(pages.state.key == b && !pages.needsRebuild(for: b), "B 完成后只确认 B")

  // 按完成顺序确认：A、B 先后在飞，各自只确认自己的键。
  pages.submitted(rebuild: a)
  pages.submitted(rebuild: b)
  pages.completed(rebuilt: a, success: true)
  check(pages.state.key == a, "先完成的 A 只确认 A")
  check(pages.needsRebuild(for: a), "B 还在飞：A 不能被沿用")
  pages.completed(rebuilt: b, success: true)
  check(pages.state.key == b && pages.inFlight.isEmpty, "后完成的 B 确认 B，在飞清空")

  // 失败：作废，下一帧必定重建。
  pages.submitted(rebuild: b)
  pages.completed(rebuilt: b, success: false)
  check(pages.state.key == nil && pages.needsRebuild(for: b), "失败后作废，下一帧重建")
  pages.submitted(rebuild: b)
  pages.completed(rebuilt: nil, success: false)
  check(pages.state.key == nil, "没重建的帧失败也作废")
  pages.invalidate()
  check(pages.inFlight.isEmpty && pages.state.key == nil, "会话作废清空一切")
}

// MARK: - GPU 共享对象

func testSharedGPU() {
  let cold = FoldGPU()
  let started = CACurrentMediaTime()
  guard let first = try? cold.objects() else {
    check(false, "FoldGPU 能在本机建出共享对象（需要 .build/duo-metal/Duo.metallib）")
    return
  }
  let createMs = (CACurrentMediaTime() - started) * 1000
  let again = CACurrentMediaTime()
  let second = try! cold.objects()
  let cachedMs = (CACurrentMediaTime() - again) * 1000
  check(first.queue === second.queue && first.library === second.library, "第二次取拿到同一个队列和库")
  check(
    first.optics === second.optics && first.page === second.page
      && first.composite === second.composite, "三条管线只建一次")
  check(!cold.warmUpNow(), "已经建好时预热什么也不做")
  check((try! cold.objects()).queue === first.queue, "预热之后对象不变")
  print(String(format: "info 首次同步创建 %.1fms，之后取 %.3fms", createMs, cachedMs))

  let warmed = FoldGPU()
  let warmStart = CACurrentMediaTime()
  check(warmed.warmUpNow(), "预热放进了共享对象")
  let warmMs = (CACurrentMediaTime() - warmStart) * 1000
  let afterWarm = CACurrentMediaTime()
  let objects = try! warmed.objects()
  let afterWarmMs = (CACurrentMediaTime() - afterWarm) * 1000
  check(objects.queue === warmed.current?.queue, "预热后主线程取到的就是预热那一份")
  check(!warmed.warmUpNow(), "第二次预热不再建")
  print(String(format: "info 预热（并行异步编译）%.1fms，预热后首取 %.3fms", warmMs, afterWarmMs))

  // 同时来取：只有一份生效。
  let racing = FoldGPU()
  let queues = IdentitySet()
  DispatchQueue.concurrentPerform(iterations: 6) { index in
    if index % 2 == 0 { racing.warmUpNow() }
    let value = try! racing.objects()
    queues.insert(value.queue)
  }
  check(queues.count == 1, "预热与同步取同时发生，所有调用方拿到同一份共享对象")
}

// MARK: - 静图纹理与旧路径逐字节一致

/// 旧实现（F08 之前 FoldRenderer.makeTexture），原样保留做基准。
enum Legacy {
  static func makeTexture(
    image: CGImage, colorSpace space: CGColorSpace, device: MTLDevice, allowVImage: Bool = true
  ) throws -> MTLTexture {
    let width = image.width
    let height = image.height
    let bitmap =
      CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    if allowVImage, let converted = convert(image, to: space, bitmap: CGBitmapInfo(rawValue: bitmap)) {
      defer { converted.free() }
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = .shaderRead
      let texture = device.makeTexture(descriptor: descriptor)!
      texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: converted.data,
        bytesPerRow: converted.rowBytes)
      return texture
    }
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: space, bitmapInfo: bitmap)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    let texture = device.makeTexture(descriptor: descriptor)!
    texture.replace(
      region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: context.data!,
      bytesPerRow: width * 4)
    return texture
  }
  static func convert(_ image: CGImage, to space: CGColorSpace, bitmap: CGBitmapInfo)
    -> vImage_Buffer?
  {
    guard let source = vImage_CGImageFormat(cgImage: image),
      let target = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space, bitmapInfo: bitmap),
      let converter = try? vImageConverter.make(sourceFormat: source, destinationFormat: target),
      let input = try? vImage_Buffer(cgImage: image, format: source)
    else { return nil }
    defer { input.free() }
    guard var output = try? vImage_Buffer(width: image.width, height: image.height, bitsPerPixel: 32)
    else { return nil }
    do {
      try converter.convert(source: input, destination: &output)
    } catch {
      output.free()
      return nil
    }
    return output
  }
}

func pixels(_ texture: MTLTexture) -> [UInt8] {
  var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
  bytes.withUnsafeMutableBytes {
    texture.getBytes(
      $0.baseAddress!, bytesPerRow: texture.width * 4,
      from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
  }
  return bytes
}

/// 伪随机但可复现的像素；预乘格式保证颜色不超过 alpha。
func makeImage(
  width: Int, height: Int, space: CGColorSpace, bitsPerComponent: Int = 8, components: Int = 4,
  bitmapInfo: CGBitmapInfo, premultiplied: Bool, opaque: Bool = false
) -> CGImage {
  let bytesPerPixel = bitsPerComponent / 8 * components
  let rowBytes = width * bytesPerPixel + 24  // 故意留行尾空隙
  var data = [UInt8](repeating: 0, count: rowBytes * height)
  var seed: UInt32 = 0x9E37_79B9
  func next() -> UInt8 {
    seed ^= seed << 13
    seed ^= seed >> 17
    seed ^= seed << 5
    return UInt8(truncatingIfNeeded: seed)
  }
  let alphaIndex: Int? = {
    guard components == 4 else { return nil }
    switch bitmapInfo.intersection(.alphaInfoMask).rawValue {
    case CGImageAlphaInfo.premultipliedFirst.rawValue, CGImageAlphaInfo.first.rawValue,
      CGImageAlphaInfo.noneSkipFirst.rawValue:
      return bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little ? 3 : 0
    default:
      return bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little ? 0 : 3
    }
  }()
  for y in 0..<height {
    for x in 0..<width {
      let base = y * rowBytes + x * bytesPerPixel
      if bitsPerComponent == 8 {
        let alpha: UInt8 = opaque ? 255 : (x + y) % 7 == 0 ? 0 : max(1, next())
        for c in 0..<components {
          let index = base + c
          if c == alphaIndex {
            data[index] = alpha
          } else {
            let value = UInt8(truncatingIfNeeded: (x * 3 + y * 5 + c * 40)) &+ next() / 4
            data[index] = premultiplied ? UInt8(Int(value) * Int(alpha) / 255) : value
          }
        }
      } else {
        // 16 位（主机字节序），预乘 last。
        let alpha = UInt16(opaque ? 65535 : Int(next()) * 257)
        for c in 0..<components {
          let v: UInt16 =
            c == 3 ? alpha : UInt16(Int(UInt16(next()) * 257) * Int(alpha) / 65535)
          data[base + c * 2] = UInt8(v & 0xFF)
          data[base + c * 2 + 1] = UInt8(v >> 8)
        }
      }
    }
  }
  let provider = CGDataProvider(data: Data(data) as CFData)!
  return CGImage(
    width: width, height: height, bitsPerComponent: bitsPerComponent,
    bitsPerPixel: bitsPerComponent * components, bytesPerRow: rowBytes, space: space,
    bitmapInfo: bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false,
    intent: .defaultIntent)!
}

func testStillTextures(device: MTLDevice) {
  let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
  let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
  let generic = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
  let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
  let bgra = FoldStillTexture.bitmapInfo
  let rgbaLast = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
  let rgbaUnpremul = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
  let skipFirst = CGBitmapInfo(
    rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
  let rgba16 = CGBitmapInfo(
    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)

  struct Case {
    let name: String
    let image: CGImage
    let target: CGColorSpace
    let expected: FoldStillTexture.Path
  }
  let cases = [
    Case(
      name: "BGRA sRGB→sRGB 333×77（同空间直接拷贝）",
      image: makeImage(width: 333, height: 77, space: srgb, bitmapInfo: bgra, premultiplied: true),
      target: srgb, expected: .copied),
    Case(
      name: "BGRA P3→P3 1×1（同空间直接拷贝）",
      image: makeImage(width: 1, height: 1, space: p3, bitmapInfo: bgra, premultiplied: true),
      target: p3, expected: .copied),
    Case(
      name: "BGRA sRGB→P3 333×77",
      image: makeImage(width: 333, height: 77, space: srgb, bitmapInfo: bgra, premultiplied: true),
      target: p3, expected: .converted),
    Case(
      name: "RGBA 预乘 sRGB→sRGB 640×480（只换像素格式）",
      image: makeImage(
        width: 640, height: 480, space: srgb, bitmapInfo: rgbaLast, premultiplied: true),
      target: srgb, expected: .converted),
    Case(
      name: "RGBA 非预乘 P3→sRGB 257×129",
      image: makeImage(
        width: 257, height: 129, space: p3, bitmapInfo: rgbaUnpremul, premultiplied: false),
      target: srgb, expected: .converted),
    Case(
      name: "BGRX 线性 RGB→P3 64×64",
      image: makeImage(
        width: 64, height: 64, space: generic, bitmapInfo: skipFirst, premultiplied: false,
        opaque: true),
      target: p3, expected: .converted),
    Case(
      name: "RGBA 16 位 sRGB→P3 97×33",
      image: makeImage(
        width: 97, height: 33, space: srgb, bitsPerComponent: 16, bitmapInfo: rgba16,
        premultiplied: true),
      target: p3, expected: .converted),
    Case(
      name: "灰度 8 位→sRGB 101×10",
      image: makeImage(
        width: 101, height: 10, space: gray, components: 1,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), premultiplied: false,
        opaque: true),
      target: srgb, expected: .converted),
  ]
  for item in cases {
    do {
      let legacy = pixels(try Legacy.makeTexture(image: item.image, colorSpace: item.target, device: device))
      let made = try FoldStillTexture.makeReporting(
        image: item.image, colorSpace: item.target, device: device)
      let current = pixels(made.texture)
      let mismatched = zip(legacy, current).filter { $0 != $1 }.count
      check(made.path == item.expected, "\(item.name)：走 \(made.path)（预期 \(item.expected)）")
      check(
        mismatched == 0 && legacy.count == current.count,
        "\(item.name)：与旧路径逐字节一致（\(legacy.count) 字节，差 \(mismatched)）")
      check(made.texture.buffer != nil && made.texture.bufferBytesPerRow % max(1, device.minimumLinearTextureAlignment(for: .bgra8Unorm)) == 0,
        "\(item.name)：纹理直接建在共享 buffer 上，行宽按线性纹理对齐")
      if let buffer = made.texture.buffer {
        check(buffer.length % Int(getpagesize()) == 0, "\(item.name)：buffer 长度页对齐")
      }

      // 画法兜底（vImage 换不了时）也要和旧画法一致。
      let legacyDrawn = pixels(
        try Legacy.makeTexture(
          image: item.image, colorSpace: item.target, device: device, allowVImage: false))
      let drawn = pixels(
        try FoldStillTexture.make(
          image: item.image, colorSpace: item.target, device: device, strategy: .drawOnly))
      let drawMismatch = zip(legacyDrawn, drawn).filter { $0 != $1 }.count
      check(drawMismatch == 0, "\(item.name)：画法兜底与旧画法逐字节一致（差 \(drawMismatch)）")
    } catch {
      check(false, "\(item.name)：\(error)")
    }
  }

  let layout = FoldStillTexture.layout(width: 333, height: 77, rowAlignment: 256, pageSize: 16384)
  check(layout.rowBytes == 1536 && layout.length == 16384 * 8, "行宽与总长对齐计算")
  check(
    !FoldStillTexture.matchesTarget(
      makeImage(width: 4, height: 4, space: srgb, bitmapInfo: bgra, premultiplied: true),
      colorSpace: p3), "色彩空间不同不走直接拷贝")
}

func benchmarkStill(device: MTLDevice) {
  // 5K 屏上的一张大窗口背景。
  let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
  let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
  let image = makeImage(
    width: 4800, height: 2600, space: srgb, bitmapInfo: FoldStillTexture.bitmapInfo,
    premultiplied: true)
  func time(_ body: () throws -> MTLTexture) -> Double {
    var samples: [Double] = []
    for _ in 0..<5 {
      let start = CACurrentMediaTime()
      _ = try? body()
      samples.append((CACurrentMediaTime() - start) * 1000)
    }
    return samples.sorted()[samples.count / 2]
  }
  let legacyConvert = time { try Legacy.makeTexture(image: image, colorSpace: p3, device: device) }
  let newConvert = time { try FoldStillTexture.make(image: image, colorSpace: p3, device: device) }
  let legacySame = time { try Legacy.makeTexture(image: image, colorSpace: srgb, device: device) }
  let newSame = time { try FoldStillTexture.make(image: image, colorSpace: srgb, device: device) }
  print(
    String(
      format:
        "info 4800×2600 静图准备中位数：换空间 旧 %.1fms → 新 %.1fms；同空间 旧 %.1fms → 新 %.1fms",
      legacyConvert, newConvert, legacySame, newSame))
}

@main struct FoldRendererPipelineTests {
  static func main() {
    testSlots()
    testOnce()
    testPageSubmissions()
    testSharedGPU()
    if let device = MTLCreateSystemDefaultDevice() {
      testStillTextures(device: device)
      if ProcessInfo.processInfo.environment["FOLD_BENCH"] != "0" { benchmarkStill(device: device) }
    } else {
      check(false, "本机有 Metal 设备")
    }
    if failures > 0 {
      print("\(failures) 项失败")
      exit(1)
    }
    print("全部通过")
  }
}
