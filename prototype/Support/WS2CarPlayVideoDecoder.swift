import AVFoundation
import CoreMedia
import VideoToolbox
import AppKit

// 接收器视频帧的解码与上屏：avcC/hvcC 记录建格式描述，Annex B 帧转 AVCC 后塞进
// AVSampleBufferDisplayLayer。上游的时间戳恒为 0，这里按"到了就画"处理，不做抖动缓冲。
// 只在主线程使用：层挂在全屏视图上，编解码状态也只在主线程读写。

@MainActor
final class WS2CarPlayVideoDecoder {

    /// 解码失败的最新原因； nil 表示最近一次入队成功或还没入过队。
    private(set) var lastError: String?
    private(set) var configured: Bool = false

    let layer = AVSampleBufferDisplayLayer()

    private var formatDescription: CMVideoFormatDescription?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    /// 用接收器的 VIDEO_CONFIG 建解码格式。换配置先冲掉旧帧。
    func configure(record: [UInt8], codec: WS2CarPlayReceiverWire.VideoCodec, width: Int, height: Int) {
        flush()
        let codecType: CMVideoCodecType = codec == .h265 ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        let atomKey: String = codec == .h265 ? "hvcC" : "avcC"
        let atoms: [String: Data] = [atomKey: Data(record)]
        var format: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: Int32(clamping: width),
            height: Int32(clamping: height),
            extensions: [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms] as CFDictionary,
            formatDescriptionOut: &format)
        guard status == noErr, let format else {
            lastError = "格式描述建立失败（\(status)）"
            configured = false
            return
        }
        formatDescription = format
        lastError = nil
        configured = true
    }

    func flush() {
        layer.flush()
        configured = false
        formatDescription = nil
    }

    /// 入队一帧 Annex B。返回是否真正提交给层（验收里"画出"的口径：提交且层活着）。
    @discardableResult
    func enqueue(annexB: [UInt8]) -> Bool {
        guard configured, let formatDescription else {
            lastError = "还没配置解码格式"
            return false
        }
        guard let block = Self.avccBlockBuffer(fromAnnexB: annexB) else {
            lastError = "Annex B 转换失败"
            return false
        }
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer else {
            lastError = "样例封装失败（\(status)）"
            return false
        }
        // 上游没有可靠时间戳：尽快解码，画不画由层自己按队列决定。
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sampleBuffer)
        lastError = layer.status == .failed ? "解码器错误（\(String(describing: layer.error))）" : nil
        return layer.status != .failed
    }

    // MARK: Annex B → AVCC

    /// 把 `00 00 01` / `00 00 00 01` 起始码的 NAL 序列改写成 4 字节大端长度前缀的块缓冲。
    nonisolated static func avccBlockBuffer(fromAnnexB annexB: [UInt8]) -> CMBlockBuffer? {
        var nals: [ArraySlice<UInt8>] = []
        var index = 0
        while index < annexB.count {
            guard let start = Self.startCodeLength(annexB, at: index) else { index += 1; continue }
            let nalStart = index + start
            var next = nalStart
            while next < annexB.count {
                if Self.startCodeLength(annexB, at: next) != nil { break }
                next += 1
            }
            if next > nalStart { nals.append(annexB[nalStart..<next]) }
            index = next
        }
        guard !nals.isEmpty else { return nil }

        let total = nals.reduce(0) { $0 + 4 + $1.count }
        var bytes = [UInt8]()
        bytes.reserveCapacity(total)
        for nal in nals {
            let length = UInt32(nal.count)
            bytes.append(UInt8(length >> 24 & 0xff))
            bytes.append(UInt8(length >> 16 & 0xff))
            bytes.append(UInt8(length >> 8 & 0xff))
            bytes.append(UInt8(length & 0xff))
            bytes.append(contentsOf: nal)
        }
        var buffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &buffer)
        if status == kCMBlockBufferNoErr, let buffer, bytes.count > 0 {
            status = bytes.withUnsafeBytes { raw in
                CMBlockBufferReplaceDataBytes(
                    with: raw.baseAddress!,
                    blockBuffer: buffer,
                    offsetIntoDestination: 0,
                    dataLength: bytes.count)
            }
        }
        return status == kCMBlockBufferNoErr ? buffer : nil
    }

    /// 返回起始码长度（3 或 4）；不是起始码返回 nil。
    private nonisolated static func startCodeLength(_ bytes: [UInt8], at index: Int) -> Int? {
        guard index + 2 < bytes.count, bytes[index] == 0, bytes[index + 1] == 0 else { return nil }
        if bytes[index + 2] == 1 { return 3 }
        if index + 3 < bytes.count, bytes[index + 2] == 0, bytes[index + 3] == 1 { return 4 }
        return nil
    }
}
