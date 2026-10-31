import Accelerate
import Foundation

/// 说话人模型的前端：Kaldi 风格的 80 维 log-mel fbank，参数跟 WeSpeaker 推理一致
/// （25 ms 帧 / 10 ms 移、去直流、0.97 预加重、非周期 Hamming、512 点 FFT、功率谱、20 Hz–8 kHz 的 Kaldi mel 滤波、
/// log(max(能量, 1.19e-7))、不加抖动、波形按 int16 量级）。再对整段做 CMN（减去每一维的均值）。
/// 对照来源：tools/speaker-model/convert.py（torchaudio.compliance.kaldi.fbank）；参考值在 tests/fixtures/speaker-fbank-reference.json。
/// 纯计算：输入的声音只活在这次调用里，不存、不写日志。
enum SpeakerFbank {
    static let sampleRate = 16_000
    static let frameLength = 400
    static let frameShift = 160
    static let fftSize = 512
    static let melBins = 80
    /// Core ML 模型的固定窗口：300 帧 = 25 ms + 299 × 10 ms ≈ 3.015 s。
    static let modelFrames = 300

    static func frameCount(samples: Int) -> Int {
        samples < frameLength ? 0 : 1 + (samples - frameLength) / frameShift
    }

    private struct Tables: Sendable {
        let window: [Float]
        /// 每个 mel 通道：第一个有权重的 FFT 点（0…255）和权重。
        let bankStart: [Int]
        let bankWeights: [[Float]]
    }

    private static let tables: Tables = {
        let window = (0..<frameLength).map { Float(0.54 - 0.46 * cos(2 * Double.pi * Double($0) / Double(frameLength - 1))) }
        func mel(_ hz: Double) -> Double { 1127.0 * log(1.0 + hz / 700.0) }
        let nyquist = Double(sampleRate) / 2
        let melLow = mel(20), melHigh = mel(nyquist)
        let delta = (melHigh - melLow) / Double(melBins + 1)
        let binWidth = Double(sampleRate) / Double(fftSize)
        var starts: [Int] = [], weights: [[Float]] = []
        for bin in 0..<melBins {
            let left = melLow + Double(bin) * delta
            let center = melLow + Double(bin + 1) * delta
            let right = melLow + Double(bin + 2) * delta
            var first = -1
            var row: [Float] = []
            for k in 0..<(fftSize / 2) {  // 0…255；奈奎斯特点权重恒为 0
                let m = mel(binWidth * Double(k))
                let up = (m - left) / (center - left)
                let down = (right - m) / (right - center)
                let w = max(0, min(up, down))
                if w > 0 {
                    if first < 0 { first = k }
                    row.append(Float(w))
                } else if first >= 0 {
                    break
                }
            }
            starts.append(max(first, 0))
            weights.append(row)
        }
        return Tables(window: window, bankStart: starts, bankWeights: weights)
    }()

    /// `pcm`：16 kHz 单声道，[-1, 1]。返回按行排开的 帧数 × 80（没做 CMN）。不够一帧返回空。
    static func logMel(pcm: [Float]) -> [Float] {
        let frames = frameCount(samples: pcm.count)
        guard frames > 0, pcm.allSatisfy(\.isFinite) else { return [] }
        let t = tables
        let log2n = vDSP_Length(9)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var out = [Float](repeating: 0, count: frames * melBins)
        var frame = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var power = [Float](repeating: 0, count: fftSize / 2)
        let epsilon = Float.ulpOfOne  // 1.1920929e-07，跟 torchaudio 的 EPSILON 一样
        let scale: Float = 32768
        for f in 0..<frames {
            let start = f * frameShift
            for i in 0..<frameLength { frame[i] = pcm[start + i] * scale }
            for i in frameLength..<fftSize { frame[i] = 0 }
            // 去直流
            var mean: Float = 0
            frame.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress!, 1, &mean, vDSP_Length(frameLength)) }
            var negMean = -mean
            frame.withUnsafeMutableBufferPointer { vDSP_vsadd($0.baseAddress!, 1, &negMean, $0.baseAddress!, 1, vDSP_Length(frameLength)) }
            // 预加重 0.97；第一个样本跟自己（replicate 边界）
            var previous = frame[0]
            for i in 0..<frameLength {
                let current = frame[i]
                frame[i] = current - 0.97 * previous
                previous = current
            }
            // 加窗
            for i in 0..<frameLength { frame[i] *= t.window[i] }
            // 实数 FFT（vDSP 打包格式，输出是 2 倍的 DFT）
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                }
            }
            let dc = real[0] / 2
            power[0] = dc * dc
            for k in 1..<(fftSize / 2) { power[k] = (real[k] * real[k] + imag[k] * imag[k]) / 4 }
            let base = f * melBins
            for bin in 0..<melBins {
                let weights = t.bankWeights[bin], first = t.bankStart[bin]
                var energy: Float = 0
                for (j, w) in weights.enumerated() { energy += w * power[first + j] }
                out[base + bin] = log(max(energy, epsilon))
            }
        }
        return out
    }

    /// 整段减去每一维的均值（CMN）。
    static func cmn(_ features: [Float], frames: Int) -> [Float] {
        guard frames > 0, features.count == frames * melBins else { return features }
        var sums = [Float](repeating: 0, count: melBins)
        for f in 0..<frames { for b in 0..<melBins { sums[b] += features[f * melBins + b] } }
        var out = features
        for b in 0..<melBins { sums[b] /= Float(frames) }
        for f in 0..<frames { for b in 0..<melBins { out[f * melBins + b] -= sums[b] } }
        return out
    }

    /// 切成模型要的 300 帧窗口：不够 300 帧就把整段特征循环铺满（均值与方差大致不变），够了就滑动（步长 150 帧，
    /// 最后一个对齐到结尾），最多 `maxWindows` 个。每个窗口 300 × 80 个 Float，按行排。
    static func windows(cmnFeatures: [Float], frames: Int, maxWindows: Int = 6) -> [[Float]] {
        guard frames > 0, cmnFeatures.count == frames * melBins else { return [] }
        if frames < modelFrames {
            var tiled = [Float](); tiled.reserveCapacity(modelFrames * melBins)
            for i in 0..<modelFrames { tiled.append(contentsOf: cmnFeatures[(i % frames) * melBins..<((i % frames) + 1) * melBins]) }
            return [tiled]
        }
        var starts = Array(stride(from: 0, through: frames - modelFrames, by: 150))
        if let last = starts.last, last != frames - modelFrames { starts.append(frames - modelFrames) }
        if starts.count > maxWindows {
            let step = Double(starts.count - 1) / Double(maxWindows - 1)
            starts = (0..<maxWindows).map { starts[Int((Double($0) * step).rounded())] }
        }
        return starts.map { Array(cmnFeatures[$0 * melBins..<($0 + modelFrames) * melBins]) }
    }
}

/// 去掉头尾的静音（按 20 ms 帧的 RMS）。不是说话检测，只是别让大段静音稀释特征。
enum SpeakerSpeechTrim {
    /// 保留从第一个到最后一个够响的帧（前后各留 100 ms）。全是静音返回空。
    static func trim(_ pcm: [Float]) -> [Float] {
        let hop = 320
        guard pcm.count >= hop, pcm.allSatisfy(\.isFinite) else { return [] }
        let count = pcm.count / hop
        var rms = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var value: Float = 0
            pcm.withUnsafeBufferPointer { vDSP_rmsqv($0.baseAddress! + i * hop, 1, &value, vDSP_Length(hop)) }
            rms[i] = value
        }
        let sorted = rms.sorted()
        let loud = sorted[min(count - 1, Int(Double(count) * 0.9))]
        let threshold = max(0.002, loud * 0.1)
        guard let first = rms.firstIndex(where: { $0 >= threshold }), let last = rms.lastIndex(where: { $0 >= threshold }) else { return [] }
        let pad = 5
        let lower = max(0, first - pad), upper = min(count, last + 1 + pad)
        return Array(pcm[(lower * hop)..<(upper * hop)])
    }
}
