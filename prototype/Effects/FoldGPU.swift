import Accelerate
import CoreGraphics
import Foundation
import Metal

enum EffectError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    if case .unavailable(let message) = self { return message }
    return nil
  }
}

/// 进程里只建一次的值。第一次取的线程负责创建，同时来取的线程等它建完；建失败不缓存，下次再试。
/// `storeIfEmpty` 给后台预热用：预热不拿着锁做慢活，建完再放进来，已经有值就丢掉自己那份。
final class FoldOnce<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  var current: Value? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func get(_ make: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    if let value { return value }
    let made = try make()
    value = made
    return made
  }

  /// 放进一个在锁外建好的值；已经有值时保留原来的，返回最终生效的那一份。
  @discardableResult
  func storeIfEmpty(_ candidate: Value) -> Value {
    lock.lock()
    defer { lock.unlock() }
    if let value { return value }
    value = candidate
    return candidate
  }
}

/// 收起／合盖渲染的进程级 GPU 共享对象：device、命令队列、着色器库、三条渲染管线。
///
/// 以前每个会话（每次收起、每次合盖）都重新建一遍这些对象，首次收起的主线程要等着色器库载入和三条
/// 管线编译。现在懒加载、只建一次；`scheduleWarmUp` 在启动后几秒于 .utility 队列上用异步编译预热，
/// 预热期间主线程来取时不等预热，自己同步建（两份里只有先放进来的那份会被用到）。
/// 会话结束不释放这些对象；会话自己的纹理缓存、纹理照旧每个会话一份。
final class FoldGPU: @unchecked Sendable {
  struct Objects: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary
    /// duoFragment：离焦光学面。
    let optics: any MTLRenderPipelineState
    /// duoPage：page 金字塔底层。
    let page: any MTLRenderPipelineState
    /// duoComposite：最终合成。
    let composite: any MTLRenderPipelineState
  }

  static let shared = FoldGPU()

  /// 命令队列容量。每个会话最多 2 帧在飞，多个窗口同时收起也远到不了这里；给足余量，
  /// 免得 makeCommandBuffer 在主线程上等队列空位。
  static let queueCapacity = 256

  private let once = FoldOnce<Objects>()
  private let warmLock = NSLock()
  private var warmScheduled = false

  /// 已经建好的共享对象（没建过就是 nil，不会触发创建）。
  var current: Objects? { once.current }

  /// 取共享对象；第一次调用时同步创建。
  func objects() throws -> Objects {
    try once.get { try Self.make(parallelCompile: false) }
  }

  /// 启动后 `delay` 秒在 .utility 队列上预热一次。只排一次，重复调用无效；不轮询、不常驻。
  func scheduleWarmUp(after delay: TimeInterval = 4) {
    warmLock.lock()
    let first = !warmScheduled
    warmScheduled = true
    warmLock.unlock()
    guard first else { return }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in
      warmUpNow()
    }
  }

  /// 在当前线程预热（三条管线并行异步编译后再放进来）。已经建好就什么也不做。
  /// 返回是否由这一次放进了新的共享对象。
  @discardableResult
  func warmUpNow() -> Bool {
    guard once.current == nil, let made = try? Self.make(parallelCompile: true) else { return false }
    let stored = once.storeIfEmpty(made)
    return stored.queue === made.queue
  }

  static func libraryURL() -> URL {
    Bundle.main.url(forResource: "Duo", withExtension: "metallib")
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        ".build/duo-metal/Duo.metallib")
  }

  private static func descriptor(_ library: any MTLLibrary, fragment: String)
    -> MTLRenderPipelineDescriptor
  {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "duoVertex")
    descriptor.fragmentFunction = library.makeFunction(name: fragment)
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    return descriptor
  }

  private static let fragments = ["duoFragment", "duoPage", "duoComposite"]

  private static func make(parallelCompile: Bool) throws -> Objects {
    guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(maxCommandBufferCount: queueCapacity)
    else {
      throw EffectError.unavailable("Metal 不可用")
    }
    let library = try device.makeLibrary(URL: libraryURL())
    let descriptors = fragments.map { descriptor(library, fragment: $0) }
    let pipelines: [any MTLRenderPipelineState]
    if parallelCompile {
      pipelines = try compileInParallel(device: device, descriptors: descriptors)
    } else {
      pipelines = try descriptors.map { try device.makeRenderPipelineState(descriptor: $0) }
    }
    return Objects(
      device: device, queue: queue, library: library, optics: pipelines[0], page: pipelines[1],
      composite: pipelines[2])
  }

  /// 三条管线同时交给编译服务，用完成回调收结果；调用线程（预热时是 .utility）等全部回来。
  private static func compileInParallel(
    device: any MTLDevice, descriptors: [MTLRenderPipelineDescriptor]
  ) throws -> [any MTLRenderPipelineState] {
    final class Results: @unchecked Sendable {
      let lock = NSLock()
      var states: [(any MTLRenderPipelineState)?]
      var error: (any Error)?
      init(count: Int) { states = Array(repeating: nil, count: count) }
    }
    let results = Results(count: descriptors.count)
    let group = DispatchGroup()
    for (index, descriptor) in descriptors.enumerated() {
      group.enter()
      device.makeRenderPipelineState(descriptor: descriptor) { state, error in
        results.lock.lock()
        results.states[index] = state
        if state == nil, results.error == nil {
          results.error = error ?? EffectError.unavailable("渲染管线编译失败")
        }
        results.lock.unlock()
        group.leave()
      }
    }
    group.wait()
    results.lock.lock()
    defer { results.lock.unlock() }
    if let error = results.error { throw error }
    return try results.states.map {
      guard let state = $0 else { throw EffectError.unavailable("渲染管线编译失败") }
      return state
    }
  }
}

/// 同一会话同时在 GPU 上飞的帧数上限，最多 2，和 `CAMetalLayer.maximumDrawableCount = 2` 一致。
/// 主线程不等：拿不到空位就跳过这次呈现（计入 busySkipped）。空位在 GPU 完成回调线程上直接归还，
/// 不经过主线程。完成回调要强持有它：DispatchSemaphore 在计数没还齐时被释放会直接崩。
///
/// 默认 1 帧在飞（与原来的 busy 标志同样的上限，只是归还不再绕主线程）。只有两块 drawable 时，
/// 一块挂在屏上、一块在飞，第二帧会在主线程的 `currentDrawable` 上等到上一帧上屏——原来是跳过，
/// 现在会变成主线程卡住。所以 2 帧在飞先由 `WINDOWSHADE_FOLD_TWO_IN_FLIGHT=1` 打开，配合
/// `WINDOWSHADE_DUO_DIAGNOSTICS=1` 的 fps／gpuToBusyP95ms／busySkipped 实测后再定默认值。
final class FoldFrameSlots: @unchecked Sendable {
  static let maximumCapacity = 2
  static let environmentKey = "WINDOWSHADE_FOLD_TWO_IN_FLIGHT"

  static func configuredCapacity(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    environment[environmentKey] == "1" ? maximumCapacity : 1
  }

  let capacity: Int
  private let semaphore: DispatchSemaphore

  init(capacity: Int = FoldFrameSlots.configuredCapacity()) {
    self.capacity = min(Self.maximumCapacity, max(1, capacity))
    semaphore = DispatchSemaphore(value: self.capacity)
  }

  /// 立即返回：拿到空位为 true。
  func tryAcquire() -> Bool { semaphore.wait(timeout: .now()) == .success }

  func release() { semaphore.signal() }
}

/// page 金字塔在「两帧在飞」下的确认账。
///
/// 每一帧只确认自己那一帧重建的键（完成回调按 GPU 真正完成的顺序到达）。跳过重建的条件是：
/// 已被 GPU 证实的键就是这一帧要的键，且还在飞的重建全是同一个键。在飞的重建若是别的键，
/// 它会先于这一帧改写同一张 page 纹理（同一命令队列按提交顺序执行），所以这一帧必须自己重建。
/// 同键的在飞重建写的是已被证实的同一份内容，不会让静态源每帧都重建（两帧在飞时最多多建一次）。
struct FoldPageSubmissions {
  private(set) var state = FoldPagePyramidState()
  /// 还在飞的重建，按提交顺序。
  private(set) var inFlight: [FoldPageKey] = []

  func needsRebuild(for key: FoldPageKey) -> Bool {
    state.needsRebuild(for: key) || inFlight.contains { $0 != key }
  }

  /// 这一帧编码了 page 重建。
  mutating func submitted(rebuild key: FoldPageKey) { inFlight.append(key) }

  /// 一帧在 GPU 上结束。`rebuilt` 是这一帧自己重建的键（没重建就是 nil）。
  mutating func completed(rebuilt key: FoldPageKey?, success: Bool) {
    if let key, let index = inFlight.firstIndex(of: key) { inFlight.remove(at: index) }
    guard success else {
      // 这一帧没成：page 可能没画完，作废，下一帧重建。
      state.invalidate()
      return
    }
    if let key { state.confirm(key) }
  }

  mutating func invalidate() {
    state.invalidate()
    inFlight.removeAll()
  }
}

/// 静图纹理（收起动画的窗口背景、展开用的静止画面）。
///
/// 色彩空间转换的结果直接写进一块页对齐的共享 MTLBuffer，再用 `makeTexture(descriptor:offset:bytesPerRow:)`
/// 把它当纹理用，省掉 `replace` 那一遍整图拷贝。源图本来就是目标色彩空间、目标像素格式时，逐行拷贝，
/// 不走 vImage。输出逐像素与旧路径（vImage 转换或 CGContext 重画 + replace）一致，见 FoldRendererPipelineTests。
enum FoldStillTexture {
  static let bitmapInfo = CGBitmapInfo(
    rawValue: CGBitmapInfo.byteOrder32Little.rawValue
      | CGImageAlphaInfo.premultipliedFirst.rawValue)

  struct Layout: Equatable {
    let rowBytes: Int
    let length: Int
  }

  /// 测试用：强制走某条路径。正式调用一律 `.automatic`。
  enum Strategy {
    case automatic
    case vImageOnly
    case drawOnly
  }

  enum Path: Equatable {
    case copied
    case converted
    case drawn
  }

  static func align(_ value: Int, to alignment: Int) -> Int {
    let a = max(1, alignment)
    return (value + a - 1) / a * a
  }

  /// 每行按线性纹理对齐，总长按页对齐。
  static func layout(width: Int, height: Int, rowAlignment: Int, pageSize: Int) -> Layout {
    let rowBytes = align(max(1, width) * 4, to: rowAlignment)
    return Layout(rowBytes: rowBytes, length: align(rowBytes * max(1, height), to: pageSize))
  }

  /// 源图是否已经是目标格式：8 位、32 位像素、BGRA 预乘、小端，色彩空间相同，没有 decode 数组。
  static func matchesTarget(_ image: CGImage, colorSpace space: CGColorSpace) -> Bool {
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32, !image.isMask,
      image.decode == nil, image.alphaInfo == .premultipliedFirst,
      image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little,
      !image.bitmapInfo.contains(.floatComponents),
      let source = image.colorSpace, source == space
    else { return false }
    return true
  }

  static func make(
    image: CGImage, colorSpace space: CGColorSpace, device: any MTLDevice,
    strategy: Strategy = .automatic
  ) throws -> any MTLTexture {
    try makeReporting(image: image, colorSpace: space, device: device, strategy: strategy).texture
  }

  static func makeReporting(
    image: CGImage, colorSpace space: CGColorSpace, device: any MTLDevice,
    strategy: Strategy = .automatic
  ) throws -> (texture: any MTLTexture, path: Path) {
    let width = image.width
    let height = image.height
    let layout = layout(
      width: width, height: height,
      rowAlignment: device.minimumLinearTextureAlignment(for: .bgra8Unorm),
      pageSize: Int(getpagesize()))
    guard let buffer = device.makeBuffer(length: layout.length, options: .storageModeShared) else {
      throw EffectError.unavailable("图像纹理分配失败")
    }
    let base = buffer.contents()
    let path: Path
    if strategy == .automatic, matchesTarget(image, colorSpace: space),
      copyRows(image, into: base, rowBytes: layout.rowBytes)
    {
      path = .copied
    } else if strategy != .drawOnly,
      convert(image, to: space, into: base, rowBytes: layout.rowBytes)
    {
      path = .converted
    } else {
      // 换不了（少见的格式）再走原来的画法，直接画进这块内存。
      memset(base, 0, layout.length)
      guard
        let context = CGContext(
          data: base, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: layout.rowBytes, space: space, bitmapInfo: bitmapInfo.rawValue)
      else { throw EffectError.unavailable("图像转换失败") }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      path = .drawn
    }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    descriptor.storageMode = .shared
    guard
      let texture = buffer.makeTexture(
        descriptor: descriptor, offset: 0, bytesPerRow: layout.rowBytes)
    else {
      throw EffectError.unavailable("图像纹理分配失败")
    }
    return (texture, path)
  }

  /// 同色彩空间、同像素格式：逐行拷贝源像素。拿不到源数据时返回 false，由调用方换路径。
  private static func copyRows(_ image: CGImage, into base: UnsafeMutableRawPointer, rowBytes: Int)
    -> Bool
  {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
      return false
    }
    let width = image.width
    let height = image.height
    let sourceRow = image.bytesPerRow
    guard sourceRow >= width * 4, CFDataGetLength(data) >= sourceRow * (height - 1) + width * 4
    else { return false }
    for row in 0..<height {
      memcpy(base + row * rowBytes, bytes + row * sourceRow, width * 4)
    }
    return true
  }

  /// vImage 换色彩空间（会用上所有核心）。实测 5K 屏上 4800×2600 的窗口背景，从显示器的色彩空间换到
  /// Display P3，CGContext 画一遍要 650ms，vImage 30ms。目标就是共享 buffer 本身。
  private static func convert(
    _ image: CGImage, to space: CGColorSpace, into base: UnsafeMutableRawPointer, rowBytes: Int
  ) -> Bool {
    guard let source = vImage_CGImageFormat(cgImage: image),
      let target = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space, bitmapInfo: bitmapInfo),
      let converter = try? vImageConverter.make(sourceFormat: source, destinationFormat: target),
      let input = try? vImage_Buffer(cgImage: image, format: source)
    else { return false }
    defer { input.free() }
    var output = vImage_Buffer(
      data: base, height: vImagePixelCount(image.height), width: vImagePixelCount(image.width),
      rowBytes: rowBytes)
    do {
      try converter.convert(source: input, destination: &output)
    } catch {
      return false
    }
    return true
  }
}
