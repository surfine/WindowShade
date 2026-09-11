import Cocoa
import CoreVideo
import QuartzCore
import ScreenCaptureKit
import VideoToolbox

enum EffectColorSpace: String {
  case sRGB, displayP3
  var name: CFString { self == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB }
  var cg: CGColorSpace { CGColorSpace(name: name)! }
  static func display(_ screen: NSScreen?) -> EffectColorSpace {
    screen?.canRepresent(.p3) == true ? .displayP3 : .sRGB
  }
}
struct EffectFrame {
  let buffer: CVPixelBuffer
  let presentationTime: CMTime
  let displayTime: CFTimeInterval?
  let receivedTime: CFTimeInterval
  /// Content bounds normalized into the buffer, after decoding SCK's screen-pixel metadata.
  let contentUV: CGRect
  let scale: CGFloat
  let contentScale: CGFloat
  let colorSpace: EffectColorSpace
  let generation: UInt64
  let id: UInt64

  /// One still image for the existing strip/hover preview, never part of the live render loop.
  /// Reuse the already captured surface instead of starting a second screenshot request.
  func stillImage() -> CGImage? {
    var image: CGImage?
    guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == noErr,
      let image
    else { return nil }
    let rect = CGRect(
      x: contentUV.minX * CGFloat(image.width),
      y: contentUV.minY * CGFloat(image.height), width: contentUV.width * CGFloat(image.width),
      height: contentUV.height * CGFloat(image.height)
    ).integral
      .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return image.cropping(to: rect)
  }
}

/// Capture callbacks only write the locked latest-frame slot. Configuration requests are serialized.
final class EffectFrameSource: NSObject, SCStreamOutput, SCStreamDelegate {
  private let queue = DispatchQueue(label: "WindowShade.effects.frames", qos: .userInteractive)
  private let lock = NSLock()
  private var slot = LatestEffectFrame<EffectFrame>()
  private var stream: SCStream?
  private var sequence: UInt64 = 0
  private var pixels = CGSize.zero
  private var colorSpace: EffectColorSpace = .sRGB
  private var revision: UInt64 = 0
  private var configurationTask: Task<Void, Never>?
  private var heartbeat: CFTimeInterval = 0
  var onStop: ((Error) -> Void)?
  var onContentUnavailable: (() -> Void)?
  func frame() -> EffectFrame? { lock.withLock { slot.value } }
  var lastActivity: CFTimeInterval { lock.withLock { heartbeat } }

  private static func configuration(size: CGSize, fps: Int, color: EffectColorSpace)
    -> SCStreamConfiguration
  {
    let c = SCStreamConfiguration()
    c.width = max(1, Int(size.width.rounded(.up)))
    c.height = max(1, Int(size.height.rounded(.up)))
    c.pixelFormat = kCVPixelFormatType_32BGRA
    c.colorSpaceName = color.name
    c.queueDepth = 3
    c.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
    c.showsCursor = false
    c.capturesAudio = false
    c.scalesToFit = true
    c.ignoreShadowsSingleWindow = true
    c.preservesAspectRatio = true
    return c
  }
  func start(filter: SCContentFilter, size: CGSize, fps: Int = 60, color: EffectColorSpace = .sRGB)
    async throws
  {
    stop()
    let candidate = SCStream(
      filter: filter, configuration: Self.configuration(size: size, fps: fps, color: color),
      delegate: self)
    try candidate.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    let generation = lock.withLock {
      stream = candidate
      pixels = size
      colorSpace = color
      heartbeat = CACurrentMediaTime()
      return slot.generation
    }
    do {
      try await candidate.startCapture()
      guard lock.withLock({ self.slot.accepts(generation) && self.stream === candidate }),
        !Task.isCancelled
      else {
        try? await candidate.stopCapture()
        throw CancellationError()
      }
    } catch {
      lock.withLock {
        if stream === candidate {
          stream = nil
          _ = slot.reset()
        }
      }
      throw error
    }
  }
  func stop() {
    let old = lock.withLock { () -> SCStream? in
      configurationTask?.cancel()
      configurationTask = nil
      _ = slot.reset()
      revision &+= 1
      heartbeat = 0
      let old = stream
      stream = nil
      return old
    }
    if let old { Task { try? await old.stopCapture() } }
  }
  func updateFPS(_ fps: Int) {
    let request = lock.withLock { () -> (SCStream, UInt64, UInt64, CGSize, EffectColorSpace)? in
      guard let stream else { return nil }
      revision &+= 1
      return (stream, slot.generation, revision, pixels, colorSpace)
    }
    guard let (candidate, generation, version, size, color) = request else { return }
    lock.withLock {
      guard slot.accepts(generation), revision == version else { return }
      let previous = configurationTask
      configurationTask = Task { [weak self] in
        await previous?.value
        guard let self, !Task.isCancelled,
          lock.withLock({
            self.slot.accepts(generation) && self.revision == version && self.stream === candidate
          })
        else { return }
        do {
          try await candidate.updateConfiguration(
            Self.configuration(size: size, fps: fps, color: color))
        } catch { fail(candidate, error: error) }
      }
    }
  }
  func waitForFrame(timeout: TimeInterval = 0.6) async -> EffectFrame? {
    let generation = lock.withLock { slot.generation }
    return await EffectFrameAwaiter<EffectFrame>.first(
      timeout: timeout, now: CACurrentMediaTime,
      isCurrent: { self.lock.withLock { self.slot.accepts(generation) } }, latest: { self.frame() },
      pause: { try? await Task.sleep(nanoseconds: 8_000_000) })
  }

  static func contentUV(_ raw: Any?, scaleFactor: CGFloat, buffer: CVPixelBuffer) -> CGRect {
    let bounds = CGRect(
      x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    let rect: CGRect?
    if let value = raw as? CGRect {
      rect = value
    } else if let dict = raw as? [String: Any] {
      rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
    } else {
      rect = nil
    }
    guard let rect, !rect.isEmpty, scaleFactor.isFinite, scaleFactor > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    // SCStream.h: contentRect is in surface points; scaleFactor converts points to pixels.
    // contentScale already affected the surface layout and must not be applied again.
    let pixels = CGRect(
      x: rect.minX * scaleFactor, y: rect.minY * scaleFactor, width: rect.width * scaleFactor,
      height: rect.height * scaleFactor
    ).intersection(bounds)
    guard !pixels.isNull, !pixels.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
    return CGRect(
      x: pixels.minX / bounds.width, y: pixels.minY / bounds.height,
      width: pixels.width / bounds.width, height: pixels.height / bounds.height)
  }
  func stream(
    _ candidate: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .screen, sample.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]],
      let info = attachments.first, let raw = info[.status] as? Int,
      let status = SCFrameStatus(rawValue: raw)
    else { return }
    var unavailable: UInt64?
    lock.withLock {
      guard stream === candidate else { return }
      let now = CACurrentMediaTime()
      heartbeat = now
      if status == .blank || status == .suspended || status == .stopped {
        slot.receive(.unavailable, token: slot.generation, frame: nil)
        unavailable = slot.generation
        return
      }
      guard status == .complete, let buffer = sample.imageBuffer else { return }
      let scale = (info[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
      let contentScale = (info[.contentScale] as? NSNumber)?.doubleValue ?? 1
      sequence &+= 1
      let ticks = (info[.displayTime] as? NSNumber)?.uint64Value
      let displaySeconds = ticks.map { Double($0) * Self.hostTickSeconds }
      let frame = EffectFrame(
        buffer: buffer, presentationTime: CMSampleBufferGetPresentationTimeStamp(sample),
        displayTime: displaySeconds, receivedTime: now,
        contentUV: Self.contentUV(info[.contentRect], scaleFactor: scale, buffer: buffer),
        scale: scale, contentScale: contentScale, colorSpace: colorSpace,
        generation: slot.generation, id: sequence)
      slot.receive(.complete, token: slot.generation, frame: frame)
    }
    if let generation = unavailable {
      DispatchQueue.main.async { [weak self] in
        guard let self,
          lock.withLock({ self.slot.accepts(generation) && self.stream === candidate })
        else { return }
        onContentUnavailable?()
      }
    }
  }
  private static let hostTickSeconds: Double = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return Double(info.numer) / Double(info.denom) / 1_000_000_000
  }()
  private func fail(_ candidate: SCStream, error: Error) {
    let token = lock.withLock { () -> UInt64? in
      guard stream === candidate else { return nil }
      stream = nil
      return slot.reset()
    }
    if let token {
      DispatchQueue.main.async { [weak self] in
        guard let self, lock.withLock({ self.slot.accepts(token) }) else { return }
        onStop?(error)
      }
    }
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) { fail(stream, error: error) }
}
