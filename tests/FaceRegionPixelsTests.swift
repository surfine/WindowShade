// 刷脸实验的画质采样（App/FaceObservationSource.swift 的 FaceRegionPixels）：只测有行为风险的——
// Vision 框原点在左下、像素缓冲区第 0 行在上，取反了就会量错半张脸；YUV 换 RGB 的量程；
// 矩形检测节拍与 Core 的 RectangleCadence 一致。合成像素缓冲区，不开相机、不跑 Vision。
import CoreVideo
import Foundation

@main
struct FaceRegionPixelsTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func stats(_ rgb: [UInt8]?) -> FaceCaptureSampling.Stats? {
    rgb.flatMap { FaceCaptureSampling.stats(pixels: $0, bytesPerPixel: 3, redIndex: 0, greenIndex: 1, blueIndex: 2) }
  }

  /// 上半白、下半黑（第 0 行在上）。
  static func bgra(width: Int = 64, height: Int = 48) -> CVPixelBuffer {
    var made: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &made)
    let buffer = made!
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
      for x in 0..<width {
        let value: UInt8 = y < height / 2 ? 255 : 0
        let offset = y * stride + x * 4
        base[offset] = value; base[offset + 1] = value; base[offset + 2] = value; base[offset + 3] = 255
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
  }

  /// 双平面 YUV：上半 Y=top、下半 Y=bottom，色度全是 (cb, cr)。
  static func yuv(_ format: OSType, top: UInt8, bottom: UInt8, cb: UInt8 = 128, cr: UInt8 = 128,
                  width: Int = 64, height: Int = 48) -> CVPixelBuffer {
    var made: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, format, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &made)
    let buffer = made!
    CVPixelBufferLockBaseAddress(buffer, [])
    let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
    let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    for y in 0..<height { for x in 0..<width { luma[y * lumaStride + x] = y < height / 2 ? top : bottom } }
    let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
    let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
    for y in 0..<CVPixelBufferGetHeightOfPlane(buffer, 1) {
      for x in 0..<CVPixelBufferGetWidthOfPlane(buffer, 1) {
        chroma[y * chromaStride + x * 2] = cb; chroma[y * chromaStride + x * 2 + 1] = cr
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
  }

  static let upper = CGRect(x: 0.25, y: 0.55, width: 0.5, height: 0.4)  // Vision：y 大 = 画面上方
  static let lower = CGRect(x: 0.25, y: 0.05, width: 0.5, height: 0.4)

  static func main() {
    expect(FaceIdentityAnalysis.rectangleInterval == RectangleCadence.interval,
           "the capture queue runs rectangle detection on the same cadence as the veto cue expects (every 3 frames)")

    let white = bgra()
    let up = stats(FaceRegionPixels.rgbSamples(white, box: upper))
    let down = stats(FaceRegionPixels.rgbSamples(white, box: lower))
    expect(up.map { $0.brightness > 0.99 && $0.glareRatio > 0.99 } == true,
           "BGRA: a box in the upper half (Vision origin bottom-left) samples the top rows")
    expect(down.map { $0.brightness < 0.01 && $0.glareRatio == 0 } == true, "BGRA: a box in the lower half samples the bottom rows")
    expect(FaceRegionPixels.rgbSamples(white, box: lower)?.count == FaceIdentityAnalysis.samplingGrid
             * FaceIdentityAnalysis.samplingGrid * 3, "a fixed 32×32 grid, 3 bytes a pixel")

    let video = yuv(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, top: 235, bottom: 16)
    expect(stats(FaceRegionPixels.rgbSamples(video, box: upper)).map { $0.brightness > 0.99 && $0.glareRatio > 0.99 } == true
             && stats(FaceRegionPixels.rgbSamples(video, box: lower)).map { $0.brightness < 0.01 } == true,
           "420v: video-range white (235) and black (16) map to full white and black")
    let full = yuv(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, top: 128, bottom: 128)
    let gray = FaceRegionPixels.rgbSamples(full, box: upper) ?? []
    expect(!gray.isEmpty && gray.allSatisfy { $0 == 128 }, "420f: neutral chroma stays gray")
    let (r, g, b) = FaceRegionPixels.rgb(y: 128, cb: 128, cr: 200, fullRange: true, bt709: false)
    expect(r > 200 && g < 128 && b == 128, "BT.601: Cr pushes red up and green down")

    expect(FaceRegionPixels.rgbSamples(white, box: CGRect(x: 2, y: 2, width: 0.2, height: 0.2)) == nil
             && FaceRegionPixels.rgbSamples(white, box: CGRect(x: 0.1, y: .nan, width: 0.2, height: 0.2)) == nil,
           "a box outside the frame or with NaN gives nothing")

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("FaceRegionPixelsTests: all checks passed; no camera or Vision was run")
  }
}
