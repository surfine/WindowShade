// 画质门（Core/FaceCaptureQuality.swift）：门槛、提示优先级与回滞、反光锁存、非法输入、采样。
import Foundation

@main
struct FaceCaptureQualityTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func good(_ edit: (inout FaceQualitySample) -> Void = { _ in }) -> FaceQualitySample {
    var s = FaceQualitySample(faceCount: 1, faceWidth: 0.3, yaw: 0, pitch: 0, eyeOpenness: 0.3,
                              captureQuality: 0.6, brightness: 0.5, glareRatio: 0, centerOffset: 0.05, motion: 0.01)
    edit(&s)
    return s
  }

  static func main() {
    let scan = FaceQualityGate(mode: .scan)
    let enroll = FaceQualityGate(mode: .enrollment)

    expect(scan.rawHint(for: good()) == nil && enroll.rawHint(for: good()) == nil, "a good frame passes both modes")
    expect(scan.rawHint(for: good { $0.faceWidth = 0.17 }) == .moveCloser, "face narrower than 0.18 is too far")
    expect(scan.rawHint(for: good { $0.faceWidth = 0.9 }) == nil, "scan has no upper width limit")
    expect(enroll.rawHint(for: good { $0.faceWidth = 0.7 }) == .moveBack, "enrollment caps width at 0.6")
    expect(enroll.rawHint(for: good { $0.faceCount = 2 }) == .onlyOneFace, "enrollment wants exactly one face")
    expect(scan.rawHint(for: good { $0.faceCount = 2 }) == nil, "scan takes the largest face, crowd is fine")
    expect(scan.rawHint(for: good { $0.faceCount = 0 }) == .lookAtCamera, "no face asks to look at the camera")
    expect(scan.rawHint(for: good { $0.yaw = 0.51 }) == .lookAtCamera && scan.rawHint(for: good { $0.pitch = -0.6 }) == .lookAtCamera,
           "scan pose limit is 0.5 rad on yaw and pitch")
    expect(scan.rawHint(for: good { $0.yaw = 0.3 }) == nil && enroll.rawHint(for: good { $0.yaw = 0.3 }) == .lookAtCamera,
           "enrollment wants a frontal face (0.14 rad)")
    expect(enroll.rawHint(for: good { $0.eyeOpenness = 0.1 }) == .lookAtCamera && enroll.rawHint(for: good { $0.eyeOpenness = 0.7 }) == .lookAtCamera,
           "enrollment eyes must be open 0.14...0.6")
    expect(scan.rawHint(for: good { $0.eyeOpenness = 0.01 }) == nil, "scan ignores eye openness")
    expect(scan.rawHint(for: good { $0.centerOffset = 0.5 }) == .centerFace, "off-center face")
    expect(scan.rawHint(for: good { $0.brightness = 0.05 }) == .tooDark && scan.rawHint(for: good { $0.brightness = 0.97 }) == .tooBright,
           "brightness window both ends")
    expect(scan.rawHint(for: good { $0.captureQuality = 0.1 }) == .holdStill, "blurry with normal light asks to hold still")
    expect(scan.rawHint(for: good { $0.captureQuality = 0.1; $0.brightness = 0.05 }) == .tooDark, "blurry because dark says dark")
    expect(scan.rawHint(for: good { $0.motion = 0.2 }) == .holdStill, "shake asks to hold still")
    expect(scan.rawHint(for: good { $0.captureQuality = nil; $0.brightness = nil; $0.motion = nil; $0.centerOffset = nil }) == nil,
           "missing optional measurements do not block")

    // 一次只给一条，按优先级
    let everything = good { $0.faceCount = 2; $0.faceWidth = 0.1; $0.yaw = 1; $0.brightness = 0.01; $0.motion = 1 }
    expect(enroll.rawHint(for: everything) == .onlyOneFace, "many faces outrank everything")
    expect(enroll.rawHint(for: good { $0.faceWidth = 0.1; $0.yaw = 1; $0.brightness = 0.01 }) == .moveCloser, "distance outranks pose and light")
    expect(scan.rawHint(for: good { $0.yaw = 1; $0.brightness = 0.01; $0.motion = 1 }) == .lookAtCamera, "pose outranks light and shake")
    expect(scan.rawHint(for: good { $0.brightness = 0.01; $0.motion = 1 }) == .tooDark, "light outranks shake")
    expect(Array(FaceQualityHint.allCases.prefix(2)) == [.onlyOneFace, .moveCloser], "declaration order is the priority order")

    // NaN 与越界
    expect(scan.rawHint(for: good { $0.faceWidth = .nan }) == .moveCloser, "NaN width is unusable")
    expect(scan.rawHint(for: good { $0.yaw = .nan }) == .lookAtCamera && scan.rawHint(for: good { $0.pitch = .infinity }) == .lookAtCamera, "non-finite pose fails")
    expect(scan.rawHint(for: good { $0.captureQuality = .nan }) != nil, "NaN quality fails")
    expect(scan.rawHint(for: good { $0.brightness = .nan }) == .tooDark, "NaN brightness fails as dark")
    expect(scan.rawHint(for: good { $0.motion = .nan }) == .holdStill && scan.rawHint(for: good { $0.centerOffset = .nan }) == .centerFace, "NaN motion and offset fail")
    expect(scan.rawHint(for: good { $0.faceCount = -1 }) == .lookAtCamera, "negative face count is no face")
    var nanGate = FaceQualityGate(mode: .scan)
    expect(!nanGate.evaluate(good { $0.glareRatio = .nan }, at: 0).glareVeto, "NaN glare never vetoes")

    // 回滞：新结论持续 0.6 s 才换
    do {
      var g = FaceQualityGate(mode: .scan)
      let dark = good { $0.brightness = 0.05 }
      expect(g.evaluate(dark, at: 0).hint == nil, "a new hint waits before showing")
      expect(g.evaluate(dark, at: 0.59).hint == nil, "still waiting at 0.59 s")
      expect(g.evaluate(dark, at: 0.6).hint == .tooDark, "shown at 0.6 s")
      let shaky = good { $0.motion = 0.5 }
      expect(g.evaluate(shaky, at: 1.0).hint == .tooDark, "a different conclusion does not swap at once")
      expect(g.evaluate(dark, at: 1.2).hint == .tooDark, "flicker back resets the pending change")
      expect(g.evaluate(shaky, at: 1.3).hint == .tooDark && g.evaluate(shaky, at: 1.89).hint == .tooDark, "pending restarts from the flicker")
      expect(g.evaluate(shaky, at: 1.95).hint == .holdStill, "swapped after holding 0.6 s")
      let ok = g.evaluate(good(), at: 2.0)
      expect(ok.passed && ok.hint == nil, "passing clears the hint at once")
    }

    // 录脸要连续 0.5 s
    do {
      var g = FaceQualityGate(mode: .enrollment)
      expect(!g.evaluate(good(), at: 0).passed && !g.evaluate(good(), at: 0.49).passed, "enrollment needs 0.5 s of good frames")
      expect(g.evaluate(good(), at: 0.5).passed, "passes at 0.5 s")
      expect(!g.evaluate(good { $0.faceCount = 2 }, at: 0.6).passed, "a bad frame breaks the run")
      expect(!g.evaluate(good(), at: 0.7).passed && !g.evaluate(good(), at: 1.19).passed && g.evaluate(good(), at: 1.2).passed, "the run restarts from zero")
      var s = FaceQualityGate(mode: .scan)
      expect(s.evaluate(good(), at: 5).passed, "scan passes on the first good frame")
    }

    // 反光：连续 3 帧才否决，锁存，不算画质提示
    do {
      var g = FaceQualityGate(mode: .scan)
      let glare = good { $0.glareRatio = 0.04 }
      expect(!g.evaluate(glare, at: 0).glareVeto && !g.evaluate(glare, at: 0.1).glareVeto, "two glare frames are not enough")
      expect(g.evaluate(glare, at: 0.2).glareVeto, "three in a row veto")
      let after = g.evaluate(good(), at: 0.3)
      expect(after.glareVeto && after.passed && after.hint == nil, "veto latches and is not a quality hint")
      var h = FaceQualityGate(mode: .scan)
      _ = h.evaluate(glare, at: 0); _ = h.evaluate(glare, at: 0.1)
      _ = h.evaluate(good { $0.glareRatio = 0.039 }, at: 0.2)
      expect(!h.evaluate(glare, at: 0.3).glareVeto && !h.evaluate(glare, at: 0.4).glareVeto, "a clean frame breaks the streak")
      expect(h.evaluate(glare, at: 0.5).glareVeto, "a new streak of three vetoes")
      h.reset()
      expect(!h.evaluate(good(), at: 1).glareVeto, "reset clears the latch")
    }

    // 起点建议
    expect(FaceQualityTuning.recommendedMinimumQuality(fromEnrollment: [0.9, 0.5, 0.7, 0.6, 0.8]) == 0.5, "20th percentile of five samples")
    expect(FaceQualityTuning.recommendedMinimumQuality(fromEnrollment: [.nan, 2, -1]) == nil, "no valid samples, no suggestion")
    expect(FaceQualityTuning.recommendedMinimumQuality(fromEnrollment: [0.4]) == 0.4, "single sample")
    expect(!FaceQualityTuning.scan.calibrated, "numbers are marked uncalibrated")

    // 采样
    do {
      let white = [UInt8](repeating: 255, count: 16)
      expect(FaceCaptureSampling.stats(pixels: white) == .init(brightness: 1, glareRatio: 1), "all-white crop")
      let black = [UInt8](repeating: 0, count: 16)
      expect(FaceCaptureSampling.stats(pixels: black) == .init(brightness: 0, glareRatio: 0), "all-black crop")
      // BGRA：1 个近白、1 个肤色（R=200 G=150 B=120）
      let mixed: [UInt8] = [255, 255, 255, 255, 120, 150, 200, 255]
      let stats = FaceCaptureSampling.stats(pixels: mixed)
      expect(stats?.glareRatio == 0.5 && abs((stats?.brightness ?? 0) - (1 + (0.299 * 200 + 0.587 * 150 + 0.114 * 120) / 255) / 2) < 1e-9,
             "skin tone is not glare; mean luma is Rec.601")
      let gray: [UInt8] = [210, 205, 208, 255]
      expect(FaceCaptureSampling.stats(pixels: gray)?.glareRatio == 1, "bright near-gray counts as glare")
      let dimGray: [UInt8] = [120, 120, 120, 255]
      expect(FaceCaptureSampling.stats(pixels: dimGray)?.glareRatio == 0, "dim gray does not")
      expect(FaceCaptureSampling.stats(pixels: []) == nil && FaceCaptureSampling.stats(pixels: [1, 2]) == nil, "empty or partial pixel is nil")
      expect(FaceCaptureSampling.stats(pixels: white, stride: 0) == nil && FaceCaptureSampling.stats(pixels: white, redIndex: 4) == nil, "bad parameters are nil")
      expect(FaceCaptureSampling.stats(pixels: mixed, stride: 2)?.glareRatio == 1, "stride samples every other pixel")
      expect(FaceCaptureSampling.stats(pixels: [10, 20, 30, 40, 50, 60], bytesPerPixel: 3, redIndex: 0, greenIndex: 1, blueIndex: 2) != nil, "RGB 3-byte layout")
    }

    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("FaceCaptureQualityTests passed (gate only, never unlock)")
  }
}
