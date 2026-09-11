import Cocoa
import ImageIO

/// Exercises the actual compiled shader with synthetic content only. Does not capture the desktop.
final class EffectRenderProbe {
  private var renderer: FoldRenderer?
  private var panel: EffectPanel?
  private var index = 0
  private let output: URL
  private var firstOpenPixels: Data?

  init(output: URL) { self.output = output }

  func run() {
    do {
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      let renderer = try FoldRenderer(size: CGSize(width: 800, height: 500))
      self.renderer = renderer
      let panel = EffectPanel(frame: NSRect(x: 50, y: 50, width: 800, height: 500), desktop: false)
      self.panel = panel
      panel.contentView = renderer.view
      let image = NSImage(size: CGSize(width: 800, height: 500))
      image.lockFocus()
      NSColor.white.setFill()
      NSRect(x: 0, y: 0, width: 800, height: 500).fill()
      NSColor.systemBlue.setFill()
      NSRect(x: 0, y: 450, width: 800, height: 50).fill()
      for row in 0..<8 {
        ("WindowShade 0123456789 — Row \(row)" as NSString).draw(
          at: CGPoint(x: 40, y: 40 + row * 50),
          withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
            .foregroundColor: NSColor.black,
          ])
      }
      image.unlockFocus()
      guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw EffectError.unavailable("test image")
      }
      try renderer.setImage(cg)
      renderer.onReadback = { [weak self] in self?.received($0) }
      panel.orderFrontRegardless()
      next()
      DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        fputs("FAIL: GPU readback timed out\n", stderr)
        exit(1)
      }
    } catch {
      fputs("FAIL: \(error)\n", stderr)
      exit(1)
    }
  }

  private func next() {
    guard let renderer else { return }
    let p = Float(index % 5) / 4
    renderer.parameters = .init(progress: p, titleFraction: 0.1, windowMode: index >= 5)
    renderer.render()
  }

  private func received(_ image: CGImage) {
    let url = output.appendingPathComponent("\(index>=5 ? "window" : "desktop")-\(index%5).png")
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    if index == 0 { firstOpenPixels = image.dataProvider?.data as Data? }
    if index == 5 {
      guard firstOpenPixels == image.dataProvider?.data as Data? else {
        fputs("FAIL: open desktop and window outputs differ\n", stderr)
        exit(1)
      }
    }
    print("render: \(url.lastPathComponent) \(image.width)x\(image.height)")
    index += 1
    if index == 10 {
      print("PASS: 10 GPU outputs, five positions in each mode; open endpoints match")
      panel?.orderOut(nil)
      renderer?.clear()
      fflush(stdout)
      NSApp.terminate(nil)
    } else {
      DispatchQueue.main.async { [weak self] in self?.next() }
    }
  }
}
