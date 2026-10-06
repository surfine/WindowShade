import Cocoa
import CoreVideo
import Accelerate
import MetalKit

/// Main-thread presentation. Capture buffers are retained through GPU completion, one submission at a time.
@MainActor final class FoldRenderer: NSObject, MTKViewDelegate {
  struct Parameters: Equatable {
    var progress: Float = 0
    var titleFraction: Float = 0
    var windowMode = false
    var opacity: Float = 1
    var motionX: Float = 0
    var motionY: Float = 0
    var preset: DuoPreset = .shade
  }
  let view: MTKView
  private(set) var revision: UInt64 = 0
  var parameters = Parameters() {
    didSet {
      if oldValue != parameters {
        revision &+= 1
        dirty = true
      }
    }
  }
  private let queue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let pagePipeline: MTLRenderPipelineState
  private let compositePipeline: MTLRenderPipelineState
  private var opticalSurface: MTLTexture?
  private var pageTexture: MTLTexture?
  private var cache: CVMetalTextureCache?
  private var frame: EffectFrame?
  private var imageTexture: MTLTexture?
  private var background: MTLTexture
  private let transparentBackground: MTLTexture
  private var backgroundImage: CGImage?
  private var colorSpace: EffectColorSpace = .sRGB
  // PERF-05：图像准备（vImage 颜色转换 + 纹理创建）不在主线程做。有界 worker：一次一个任务、
  // 每个目标至多一个待替换请求；完成时主线程只验证代际再换入，过期结果丢弃。
  private let prepQueue = DispatchQueue(label: "WindowShade.fold-prep", qos: .userInitiated)
  private let imageCache = FoldImageCache<MTLTexture>(capacity: 4)
  private var prepPolicy = FoldPrepPolicy()
  private var pendingPrimary: PrepRequest?
  private var pendingBackground: PrepRequest?
  private var prepRunning = false

  /// 交给 worker 的一次图像准备。只在主线程创建，worker 只读，所以标注 Sendable。
  private struct PrepRequest: @unchecked Sendable {
    let image: CGImage
    let colorSpace: CGColorSpace
    let device: MTLDevice
    let target: FoldPrepPolicy.Target
    let generation: UInt64
    let key: FoldImageCache<MTLTexture>.Key
  }

  private var dirty = true
  private var busy = false
  private var cleared = false
  private var epoch = EffectEpoch()
  /// 静图换入序号（PERF-06）：换一张位图就是一次新的源版本，page 金字塔必须跟着重建。
  private var stillVersion: UInt64 = 0
  /// page 金字塔的重建依据与「已被 GPU 证实」的上一份键。只由源内容与采样范围决定，
  /// 呈现参数变了不会让它重建。
  private var pageState = FoldPagePyramidState()
  private var pendingPageKey: FoldPageKey?
  private var latencies: [Double] = []
  private var gpuTimes: [Double] = []
  private var intervals: [Double] = []
  private var lastPresentedTime: CFTimeInterval?
  private var measuredFrame: UInt64?
  private(set) var presentedCount = 0
  private(set) var skippedBusy = 0
  var onFrameReady: (() -> Void)?
  var onPresented: ((UInt64) -> Void)?
  var onFailure: ((Error) -> Void)?
  var onReadback: ((CGImage) -> Void)? { didSet { view.framebufferOnly = onReadback == nil } }

  init(size: CGSize) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw EffectError.unavailable("Metal 不可用")
    }
    self.queue = queue
    let url =
      Bundle.main.url(forResource: "Duo", withExtension: "metallib")
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(
        ".build/duo-metal/Duo.metallib")
    let library = try device.makeLibrary(URL: url)
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "duoVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "duoFragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    descriptor.fragmentFunction = library.makeFunction(name: "duoPage")
    pagePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    descriptor.fragmentFunction = library.makeFunction(name: "duoComposite")
    compositePipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let transparent = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
    guard let texture = device.makeTexture(descriptor: transparent) else {
      throw EffectError.unavailable("纹理分配失败")
    }
    var zero: UInt32 = 0
    texture.replace(
      region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)
    background = texture
    transparentBackground = texture
    view = MTKView(frame: CGRect(origin: .zero, size: size), device: device)
    super.init()
    guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess else {
      throw EffectError.unavailable("纹理缓存分配失败")
    }
    view.colorPixelFormat = .bgra8Unorm
    view.colorspace = colorSpace.cg
    view.clearColor = MTLClearColorMake(0, 0, 0, 0)
    view.layer?.isOpaque = false
    view.framebufferOnly = true
    view.isPaused = true
    view.enableSetNeedsDisplay = false
    view.delegate = self
    view.autoresizingMask = [.width, .height]
    (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
  }
  /// 当前画面的一张静止图（合上动画播完时留着，屏再亮时直接拿它开始展开，不用等新截图）。
  var currentStill: CGImage? { frame?.stillImage() }
  func setFrame(_ next: EffectFrame) {
    guard !cleared, frame?.id != next.id || frame?.generation != next.generation else { return }
    if frame?.generation != next.generation { measuredFrame = nil }
    setColorSpace(next.colorSpace)
    frame = next
    imageTexture = nil
    revision &+= 1
    dirty = true
  }
  func setImage(_ image: CGImage, color: EffectColorSpace? = nil) throws {
    guard !cleared, let device = view.device else { return }
    let space = color ?? (image.colorSpace?.name == CGColorSpace.displayP3 ? .displayP3 : .sRGB)
    setColorSpace(space)
    frame = nil
    prepare(image: image, colorSpace: space, device: device, target: .primary)
  }
  func setBackground(_ image: CGImage) throws {
    guard !cleared, let device = view.device else { return }
    backgroundImage = image
    prepare(image: image, colorSpace: colorSpace, device: device, target: .background)
  }
  private func setColorSpace(_ value: EffectColorSpace) {
    guard colorSpace != value else { return }
    colorSpace = value
    view.colorspace = value.cg
    if let backgroundImage, let device = view.device {
      prepare(image: backgroundImage, colorSpace: value, device: device, target: .background)
    }
  }

  /// 图像准备入口：命中缓存就同步换入（只是一次字典查找），否则交给有界 worker。
  private func prepare(
    image: CGImage, colorSpace space: EffectColorSpace, device: MTLDevice,
    target: FoldPrepPolicy.Target
  ) {
    guard !cleared else { return }
    let key = FoldImageCache<MTLTexture>.Key(
      source: ObjectIdentifier(image), colorSpace: space.rawValue, width: image.width,
      height: image.height)
    if let cached = imageCache.value(for: key) {
      // 换入缓存结果也算一次新请求：作废还在飞的旧结果。
      _ = prepPolicy.supersede(target)
      apply(texture: cached, target: target)
      return
    }
    let generation = prepPolicy.supersede(target)
    let request = PrepRequest(
      image: image, colorSpace: space.cg, device: device, target: target,
      generation: generation, key: key)
    switch target {
    case .primary: pendingPrimary = request
    case .background: pendingBackground = request
    }
    drainPrepIfNeeded()
  }

  private func drainPrepIfNeeded() {
    guard !prepRunning, !cleared else { return }
    let request: PrepRequest
    if let next = pendingPrimary {
      request = next
      pendingPrimary = nil
    } else if let next = pendingBackground {
      request = next
      pendingBackground = nil
    } else {
      return
    }
    prepRunning = true
    // worker 上只做纯准备：不碰 AppKit、不碰主线程状态。
    prepQueue.async { [weak self] in
      let result: Result<MTLTexture, Error>
      do {
        result = .success(
          try Self.makeTexture(
            image: request.image, colorSpace: request.colorSpace, device: request.device))
      } catch {
        result = .failure(error)
      }
      DispatchQueue.main.async { [weak self] in
        self?.finishPrep(request, result)
      }
    }
  }

  private func finishPrep(_ request: PrepRequest, _ result: Result<MTLTexture, Error>) {
    prepRunning = false
    switch result {
    case .success(let texture):
      imageCache.store(texture, for: request.key)
      if !cleared, prepPolicy.isCurrent(request.target, request.generation) {
        apply(texture: texture, target: request.target)
      }
    case .failure(let error):
      if !cleared, prepPolicy.isCurrent(request.target, request.generation) {
        onFailure?(error)
      }
    }
    drainPrepIfNeeded()
  }

  /// 换入完成的资源并请求一次呈现；键里不含帧号，同一张静图不会被反复重建。
  private func apply(texture: MTLTexture, target: FoldPrepPolicy.Target) {
    switch target {
    case .primary:
      imageTexture = texture
      // 换了一张静图：新的源版本，page 金字塔那一份立刻作废。
      stillVersion &+= 1
    case .background: background = texture
    }
    revision &+= 1
    dirty = true
    render()
  }

  /// 当前源画面的版本号：实时帧按「代际 + 帧号」，静图按换入序号。
  private func currentSourceVersion() -> UInt64 {
    if let frame {
      return FoldPageKey.liveSourceVersion(
        frameGeneration: frame.generation, frameID: frame.id)
    }
    return FoldPageKey.stillSourceVersion(swapCount: stillVersion)
  }

  private nonisolated static func makeTexture(
    image: CGImage, colorSpace space: CGColorSpace, device: MTLDevice
  ) throws -> MTLTexture {
    let width = image.width
    let height = image.height
    let bitmap =
      CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    // 先用 vImage 换色彩空间：它会用上所有核心。实测 5K 屏上 4800×2600 的窗口背景，从显示器的色彩空间
    // 换到 Display P3，CGContext 画一遍要 650ms（单线程，收起动画开头主线程卡住的就是这里），vImage 30ms，
    // 抽样逐字节一致。换不了（少见的格式）再走原来的画法。
    if let converted = Self.convert(image, to: space, bitmap: CGBitmapInfo(rawValue: bitmap)) {
      defer { converted.free() }
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
      descriptor.usage = .shaderRead
      guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw EffectError.unavailable("图像纹理分配失败")
      }
      texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: converted.data,
        bytesPerRow: converted.rowBytes)
      return texture
    }
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: bitmap),
      let data = context.data
    else { throw EffectError.unavailable("图像转换失败") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw EffectError.unavailable("图像纹理分配失败")
    }
    texture.replace(
      region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: data,
      bytesPerRow: width * 4)
    return texture
  }
  private nonisolated static func convert(_ image: CGImage, to space: CGColorSpace, bitmap: CGBitmapInfo) -> vImage_Buffer? {
    guard let source = vImage_CGImageFormat(cgImage: image),
      let target = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space, bitmapInfo: bitmap),
      let converter = try? vImageConverter.make(sourceFormat: source, destinationFormat: target),
      let input = try? vImage_Buffer(cgImage: image, format: source)
    else { return nil }
    defer { input.free() }
    guard var output = try? vImage_Buffer(width: image.width, height: image.height, bitsPerPixel: 32) else {
      return nil
    }
    do {
      try converter.convert(source: input, destination: &output)
    } catch {
      output.free()
      return nil
    }
    return output
  }
  func invalidate() { if !cleared { dirty = true } }
  func render() {
    guard !cleared, dirty else { return }
    if busy {
      skippedBusy += 1
      return
    }
    view.draw()
  }
  func clear() {
    guard !cleared else { return }
    cleared = true
    revision &+= 1
    _ = epoch.advance()
    frame = nil
    imageTexture = nil
    backgroundImage = nil
    background = transparentBackground
    opticalSurface = nil
    pageTexture = nil
    // 作废还在飞或排队的图像准备，并清掉有界缓存。
    pendingPrimary = nil
    pendingBackground = nil
    prepPolicy.reset()
    imageCache.removeAll()
    // page 金字塔：纹理没了，键也一起作废。
    pageState.invalidate()
    pendingPageKey = nil
    dirty = false
    view.isHidden = true
    onFrameReady = nil
    onPresented = nil
    onFailure = nil
    onReadback = nil
    if let cache { CVMetalTextureCacheFlush(cache, 0) }
  }
  private func append(_ value: Double, to values: inout [Double]) {
    values.append(value)
    if values.count > 1800 { values.removeFirst(values.count - 1800) }
  }
  /// 结构化数值字段（PERF-11）：给自动比较与资格门槛用，不再只有一行字符串。
  func metricFields() -> [String: Double] {
    func p95(_ values: [Double]) -> Double {
      let a = values.sorted()
      return a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * 0.95))]
    }
    let fps = intervals.isEmpty ? 0 : Double(intervals.count) / intervals.reduce(0, +)
    return [
      "presentedCount": Double(presentedCount),
      "fps": fps,
      "captureToPresentP95ms": p95(latencies),
      "gpuP95ms": p95(gpuTimes),
      "busySkipped": Double(skippedBusy),
      "latencySamples": Double(latencies.count),
    ]
  }
  func metrics() -> String {
    let fields = metricFields()
    return String(
      format:
        "presented=%d fps=%.1f captureToPresentP95=%.1fms gpuP95=%.1fms busySkipped=%d latencySamples=%d",
      Int(fields["presentedCount"] ?? 0), fields["fps"] ?? 0,
      fields["captureToPresentP95ms"] ?? 0, fields["gpuP95ms"] ?? 0,
      Int(fields["busySkipped"] ?? 0), Int(fields["latencySamples"] ?? 0))
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { dirty = true }
  func draw(in view: MTKView) {
    guard !cleared, dirty, !busy, let device = view.device else { return }
    var wrapped: CVMetalTexture?
    var source = imageTexture
    if let frame, let cache {
      guard
        CVMetalTextureCacheCreateTextureFromImage(
          nil, cache, frame.buffer, nil, .bgra8Unorm,
          CVPixelBufferGetWidth(frame.buffer), CVPixelBufferGetHeight(frame.buffer), 0, &wrapped)
          == kCVReturnSuccess,
        let wrapped
      else {
        onFailure?(EffectError.unavailable("捕获纹理不可用"))
        return
      }
      source = CVMetalTextureGetTexture(wrapped)
    }
    guard let source, let pass = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let command = queue.makeCommandBuffer()
    else { return }
    let o = parameters.preset.optics
    let rect = frame?.contentUV ?? CGRect(x: 0, y: 0, width: 1, height: 1)
    var uniforms = [
      SIMD4<Float>(
        parameters.progress, parameters.titleFraction, parameters.windowMode ? 1 : 0,
        parameters.opacity),
      SIMD4<Float>(o.focal, o.defocus, o.dim, o.baseBlur),
      SIMD4<Float>(o.angle, parameters.motionX, parameters.motionY, 0),
      SIMD4<Float>(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
      SIMD4<Float>(Float(drawable.texture.width), Float(drawable.texture.height), 0, 0),
    ]
    // Bound only the expensive optical surface; capture, title bars and final output stay native.
    let opticalWidth = min(960, drawable.texture.width)
    let opticalHeight = max(
      1,
      Int(
        (Double(opticalWidth) * Double(drawable.texture.height) / Double(drawable.texture.width))
          .rounded()))
    if opticalSurface?.width != opticalWidth || opticalSurface?.height != opticalHeight {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: opticalWidth, height: opticalHeight, mipmapped: false)
      descriptor.storageMode = .private
      descriptor.usage = [.renderTarget, .shaderRead]
      opticalSurface = device.makeTexture(descriptor: descriptor)
    }
    guard let opticalSurface else {
      onFailure?(EffectError.unavailable("光学纹理分配失败"))
      return
    }
    let hasMotion = hypot(parameters.motionX, parameters.motionY) > 0.0001
    pendingPageKey = nil
    if parameters.progress > 0 || hasMotion {
      // The page pyramid carries the defocus: one base level plus generated mips, so the
      // wide part of the blur is a filtered fetch instead of a disk of taps.
      // PERF-06：page 与 mipmap 只在源内容或采样范围真的变了时才重建。progress／标题比例／
      // 透明度只影响呈现，不进键——静态源播一整段动画也只建一次。清晰标题与终点仍从原始
      // source 采样，行为不变。
      let pageWidth = max(1, Int((Double(source.width) * Double(rect.width)).rounded()))
      let pageHeight = max(1, Int((Double(source.height) * Double(rect.height)).rounded()))
      if pageTexture == nil || pageTexture?.width != pageWidth || pageTexture?.height != pageHeight {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: .bgra8Unorm, width: pageWidth, height: pageHeight, mipmapped: true)
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        pageTexture = device.makeTexture(descriptor: descriptor)
      }
      guard let pageTexture else {
        onFailure?(EffectError.unavailable("光学纹理分配失败"))
        return
      }
      let pageKey = FoldPageKey(
        sourceVersion: currentSourceVersion(), sourceWidth: source.width,
        sourceHeight: source.height, pixelFormatRawValue: source.pixelFormat.rawValue,
        colorSpace: colorSpace.rawValue, content: rect, pageWidth: pageWidth,
        pageHeight: pageHeight)
      // 源画面没变就跳过 page 通道与 generateMipmaps，直接把上一份金字塔交给光学通道。
      if pageState.needsRebuild(for: pageKey) {
        let pagePass = MTLRenderPassDescriptor()
        pagePass.colorAttachments[0].texture = pageTexture
        pagePass.colorAttachments[0].level = 0
        pagePass.colorAttachments[0].loadAction = .dontCare
        pagePass.colorAttachments[0].storeAction = .store
        guard let pageEncoder = command.makeRenderCommandEncoder(descriptor: pagePass) else {
          return
        }
        pageEncoder.setRenderPipelineState(pagePipeline)
        pageEncoder.setFragmentTexture(source, index: 0)
        pageEncoder.setFragmentBytes(
          &uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
        pageEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        pageEncoder.endEncoding()
        if let blit = command.makeBlitCommandEncoder() {
          blit.generateMipmaps(for: pageTexture)
          blit.endEncoding()
        }
        // GPU 真的完成这一帧后才作数（见完成回调）。
        pendingPageKey = pageKey
      }
      let opticalPass = MTLRenderPassDescriptor()
      opticalPass.colorAttachments[0].texture = opticalSurface
      opticalPass.colorAttachments[0].loadAction = .dontCare
      opticalPass.colorAttachments[0].storeAction = .store
      guard let opticalEncoder = command.makeRenderCommandEncoder(descriptor: opticalPass) else {
        return
      }
      opticalEncoder.setRenderPipelineState(pipeline)
      opticalEncoder.setFragmentTexture(source, index: 0)
      opticalEncoder.setFragmentTexture(background, index: 1)
      opticalEncoder.setFragmentTexture(pageTexture, index: 2)
      opticalEncoder.setFragmentBytes(
        &uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
      opticalEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      opticalEncoder.endEncoding()
    }
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
    encoder.setRenderPipelineState(compositePipeline)
    encoder.setFragmentTexture(source, index: 0)
    encoder.setFragmentTexture(background, index: 1)
    encoder.setFragmentTexture(opticalSurface, index: 2)
    encoder.setFragmentBytes(
      &uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    var readback: MTLBuffer?
    let rowBytes = ((drawable.texture.width * 4 + 255) / 256) * 256
    if onReadback != nil,
      let buffer = device.makeBuffer(
        length: rowBytes * drawable.texture.height, options: .storageModeShared),
      let blit = command.makeBlitCommandEncoder()
    {
      blit.copy(
        from: drawable.texture, sourceSlice: 0, sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceSize: MTLSize(
          width: drawable.texture.width, height: drawable.texture.height, depth: 1), to: buffer,
        destinationOffset: 0,
        destinationBytesPerRow: rowBytes,
        destinationBytesPerImage: rowBytes * drawable.texture.height)
      blit.endEncoding()
      readback = buffer
    }
    let token = epoch.value
    let revision = self.revision
    let retainedFrame = frame
    let frameTiming = frame.map { (id: $0.id, origin: $0.displayTime ?? $0.presentationTime.seconds) }
    let gpu = FoldGPUInFlight(wrapper: wrapped, source: source, opticalSurface: opticalSurface,
                              readback: readback)
    let space = colorSpace
    let size = (drawable.texture.width, drawable.texture.height)
    // Presentation time is separate from GPU completion, and counted once per fresh captured frame.
    drawable.addPresentedHandler { [weak self] presented in
      let time = presented.presentedTime
      DispatchQueue.main.async { [weak self] in
        guard let self, epoch.accepts(token), !cleared, time > 0 else { return }
        presentedCount += 1
        if let previous = lastPresentedTime, time > previous {
          append(time - previous, to: &intervals)
        }
        lastPresentedTime = time
        if let frame = frameTiming, measuredFrame != frame.id {
          measuredFrame = frame.id
          let origin = frame.origin
          if origin.isFinite, origin > 0, time >= origin {
            append((time - origin) * 1000, to: &latencies)
          }
        }
        onPresented?(revision)
      }
    }
    command.present(drawable)
    busy = true
    dirty = false
    command.addCompletedHandler { [weak self] result in
      withExtendedLifetime((retainedFrame, gpu)) {}
      let gpuMilliseconds = (result.gpuEndTime - result.gpuStartTime) * 1000
      let completed = result.status == .completed
      let failure = result.error
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        busy = false
        guard epoch.accepts(token), !cleared else { return }
        guard completed else {
          // 这一帧没成：page 金字塔可能没画完，作废它，下一帧重建，绝不拿它去离焦。
          pendingPageKey = nil
          pageState.invalidate()
          onFailure?(failure ?? EffectError.unavailable("GPU 呈现失败"))
          return
        }
        // page 渲染和消费它的光学通道在同一个命令缓冲里；到这里才证实金字塔可用。
        if let promoted = pendingPageKey {
          pageState.confirm(promoted)
          pendingPageKey = nil
        }
        append(gpuMilliseconds, to: &gpuTimes)
        onFrameReady?()
        // The first command may complete while the panel is still transparent.
        // onFrameReady can then invalidate the view, but a paused MTKView is not
        // guaranteed to receive a display-link tick before the presentation
        // deadline. Submit the newly dirty frame from the completion callback,
        // after busy is cleared, so visibility is proven by a real drawable.
        if dirty { render() }
        if let output = gpu.readback,
          let provider = CGDataProvider(
            data: Data(bytes: output.contents(), count: output.length) as CFData),
          let image = CGImage(
            width: size.0, height: size.1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: space.cg,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
              .byteOrder32Little),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        {
          onReadback?(image)
        }
      }
    }
    command.commit()
  }
}
enum EffectError: LocalizedError {
  case unavailable(String)
  var errorDescription: String? {
    if case .unavailable(let message) = self { return message }
    return nil
  }
}

/// 一帧在 GPU 做完之前必须活着的资源。编码完成后谁都不再改它们：GPU 完成回调只负责持有到结束，
/// 主队列只读一次 readback。Metal 资源对象本身可以跨线程持有（编码器不在这里）。
private struct FoldGPUInFlight: @unchecked Sendable {
  let wrapper: CVMetalTexture?
  let source: any MTLTexture
  let opticalSurface: any MTLTexture
  let readback: (any MTLBuffer)?
}
