import Cocoa
import CoreVideo
import MetalKit

/// Main-thread presentation. Capture buffers are retained through GPU completion, one submission at a time.
final class FoldRenderer: NSObject, MTKViewDelegate {
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
  private var dirty = true
  private var busy = false
  private var cleared = false
  private var epoch = EffectEpoch()
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
  func setFrame(_ next: EffectFrame) {
    guard !cleared, frame?.id != next.id || frame?.generation != next.generation else { return }
    if frame?.generation != next.generation { measuredFrame = nil }
    setColorSpace(next.colorSpace)
    frame = next
    imageTexture = nil
    dirty = true
  }
  func setImage(_ image: CGImage, color: EffectColorSpace? = nil) throws {
    guard !cleared, let device = view.device else { return }
    setColorSpace(color ?? (image.colorSpace?.name == CGColorSpace.displayP3 ? .displayP3 : .sRGB))
    imageTexture = try texture(from: image, device: device)
    frame = nil
    dirty = true
  }
  func setBackground(_ image: CGImage) throws {
    guard !cleared, let device = view.device else { return }
    backgroundImage = image
    background = try texture(from: image, device: device)
    dirty = true
  }
  private func setColorSpace(_ value: EffectColorSpace) {
    guard colorSpace != value else { return }
    colorSpace = value
    view.colorspace = value.cg
    if let backgroundImage, let device = view.device,
      let converted = try? texture(from: backgroundImage, device: device)
    {
      background = converted
    }
  }
  private func texture(from image: CGImage, device: MTLDevice) throws -> MTLTexture {
    let width = image.width
    let height = image.height
    let bitmap =
      CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: colorSpace.cg, bitmapInfo: bitmap),
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
    _ = epoch.advance()
    frame = nil
    imageTexture = nil
    backgroundImage = nil
    background = transparentBackground
    opticalSurface = nil
    pageTexture = nil
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
  func metrics() -> String {
    func p95(_ values: [Double]) -> Double {
      let a = values.sorted()
      return a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * 0.95))]
    }
    let fps = intervals.isEmpty ? 0 : Double(intervals.count) / intervals.reduce(0, +)
    return String(
      format:
        "presented=%d fps=%.1f captureToPresentP95=%.1fms gpuP95=%.1fms busySkipped=%d latencySamples=%d",
      presentedCount, fps, p95(latencies), p95(gpuTimes), skippedBusy, latencies.count)
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
    if parameters.progress > 0 || hasMotion {
      // The page pyramid carries the defocus: one base level plus generated mips, so the
      // wide part of the blur is a filtered fetch instead of a disk of taps.
      let pageWidth = max(1, Int((Double(source.width) * Double(rect.width)).rounded()))
      let pageHeight = max(1, Int((Double(source.height) * Double(rect.height)).rounded()))
      if pageTexture?.width != pageWidth || pageTexture?.height != pageHeight {
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
    let retainedWrapper = wrapped
    let output = readback
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
        if let frame = retainedFrame, measuredFrame != frame.id {
          measuredFrame = frame.id
          let origin = frame.displayTime ?? frame.presentationTime.seconds
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
      withExtendedLifetime((retainedFrame, retainedWrapper, source, opticalSurface)) {}
      let gpu = (result.gpuEndTime - result.gpuStartTime) * 1000
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        busy = false
        guard epoch.accepts(token), !cleared else { return }
        guard result.status == .completed else {
          onFailure?(result.error ?? EffectError.unavailable("GPU 呈现失败"))
          return
        }
        append(gpu, to: &gpuTimes)
        onFrameReady?()
        if let output,
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
