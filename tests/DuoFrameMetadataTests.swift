import Cocoa
import CoreVideo

@main struct FrameMetadataTests {
  static func main() {
    var buffer: CVPixelBuffer?
    precondition(
      CVPixelBufferCreate(nil, 2560, 1660, kCVPixelFormatType_32BGRA, nil, &buffer)
        == kCVReturnSuccess)
    let surface = buffer!
    func uv(_ rect: CGRect, _ scale: CGFloat) -> CGRect {
      EffectFrameSource.contentUV(
        rect.dictionaryRepresentation, scaleFactor: scale, buffer: surface)
    }
    precondition(
      uv(CGRect(x: 0, y: 0, width: 1280, height: 830), 2) == CGRect(x: 0, y: 0, width: 1, height: 1)
    )
    precondition(
      uv(CGRect(x: 0, y: 0, width: 2560, height: 1660), 1)
        == CGRect(x: 0, y: 0, width: 1, height: 1))
    precondition(
      uv(CGRect(x: 320, y: 83, width: 640, height: 664), 2)
        == CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8))
    precondition(
      uv(CGRect(x: -5, y: -5, width: 2600, height: 1700), 1)
        == CGRect(x: 0, y: 0, width: 1, height: 1))
    precondition(
      EffectFrameSource.contentUV(nil, scaleFactor: 2, buffer: surface)
        == CGRect(x: 0, y: 0, width: 1, height: 1))
    print("PASS: SCK surface points × Retina scale, 1x/2x, padded content and clipped bounds")
    let frame = EffectFrame(buffer: surface, presentationTime: .zero, displayTime: nil,
      receivedTime: 0, contentUV: CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8),
      scale: 2, contentScale: 0.75, colorSpace: .sRGB, generation: 1, id: 1)
    let still = frame.stillImage()
    precondition(still?.width == 1280 && still?.height == 1328)
    print("PASS: existing capture produces a cropped still preview without another capture")
  }
}
