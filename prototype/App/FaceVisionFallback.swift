import CoreVideo
import Foundation
import Vision

/// 相机路径的固定调校值（PERF-07）。数字放这里，测试与真机 runbook 引用同一份。
enum FaceCameraTuning {
    /// 要求相机提供的源帧率。脸部姿势与睁眼程度不需要更高；与下方 Vision 最小间隔一致，
    /// 让相机不要产出我们注定丢掉、还要花钱解码的帧。
    static let targetSourceFPS: Double = 8
    /// Vision 一次请求的用时预算（毫秒）：超过就记一笔，供资格测试与真机对照。
    static let visionBudgetMs: Double = 60
    /// 连续几次 Vision 失败才算一次会话级异常。
    static let consecutiveFailureLimit = 3
}

/// 像素格式偏好（PERF-07）。只改相机路径，其它采集路径不受影响。
enum FaceCameraPixelFormat {
    static let biPlanarVideoRange = UInt32(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    static let biPlanarFullRange = UInt32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    static let bgra = UInt32(kCVPixelFormatType_32BGRA)

    /// 依 `availableVideoPixelFormatTypes` 挑一个：原生双平面 YUV 优先，其次 BGRA。
    /// 都不在支援清单里就回 nil——不硬塞一个相机不认的格式。
    /// `forced` 是真机对照用的覆写（`WINDOWSHADE_CAMERA_PIXEL_FORMAT`），只认这三个值。
    static func preferred(from available: [UInt32], forced: String? = nil) -> UInt32? {
        if let forced, let value = named(forced) {
            return available.contains(value) ? value : nil
        }
        for candidate in [biPlanarVideoRange, biPlanarFullRange, bgra] where available.contains(candidate) {
            return candidate
        }
        return nil
    }

    /// 四字码 → 名字，只用于日志与报表，不参与判断。
    static func name(_ format: UInt32) -> String {
        switch format {
        case biPlanarVideoRange: return "420v"
        case biPlanarFullRange: return "420f"
        case bgra: return "BGRA"
        default: return Self.fourCC(format)
        }
    }

    private static func named(_ text: String) -> UInt32? {
        switch text.lowercased() {
        case "420v", "biplanar-video", "yuv": return biPlanarVideoRange
        case "420f", "biplanar-full": return biPlanarFullRange
        case "bgra", "bgra8", "rgb": return bgra
        default: return nil
        }
    }

    private static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        let text = String(bytes: bytes, encoding: .ascii) ?? ""
        return text.allSatisfy { $0.isLetter || $0.isNumber } ? text : String(format: "0x%08X", value)
    }
}

/// Vision 失败的类别（PERF-07）：先只记类别，不做重试也不退路，等连续失败成立再动作。
enum FaceVisionFailureCategory: Int, Sendable, Equatable {
    case unknown = 0
    case cancelled = 1
    case invalidInput = 2
    case unsupportedCompute = 3
    case resources = 4
    case io = 5
    case internalFailure = 6
    case timeout = 7

    static func of(_ error: Error) -> FaceVisionFailureCategory {
        let nsError = error as NSError
        guard nsError.domain == VNErrorDomain, let code = VNErrorCode(rawValue: nsError.code) else {
            return .unknown
        }
        switch code {
        case .requestCancelled: return .cancelled
        case .invalidImage, .invalidFormat, .invalidOption, .missingOption, .invalidArgument,
            .invalidOperation, .invalidModel:
            return .invalidInput
        case .unsupportedComputeStage, .unsupportedComputeDevice, .notImplemented,
            .unsupportedRequest, .unsupportedRevision:
            return .unsupportedCompute
        case .outOfMemory, .dataUnavailable: return .resources
        case .ioError: return .io
        case .internalError, .operationFailed, .outOfBoundsError, .unknownError:
            return .internalFailure
        case .timeout, .timeStampNotFound: return .timeout
        default: return .unknown
        }
    }
}

/// Vision 连续失败的会话级退路（PERF-07）。纯状态机：把判断从回调里拿出来，可以单独测。
///
/// 规则：先记类别；连续 `consecutiveFailureLimit` 次失败时退回系统预设计算装置（整个会话只退一次，
/// 因为钉神经引擎只是加速，不是唯一可行路径）；退回之后仍连续失败，就判定这条源不可用，
/// 让上层停源并报错——不做无限重试。
struct FaceVisionFallbackPolicy {
    enum Decision: Equatable {
        case keepRunning
        case fallBackToDefault
        case stopUnavailable
    }

    private(set) var consecutiveFailures = 0
    private(set) var lastFailureCategory: FaceVisionFailureCategory?
    /// 已经退回系统预设几次（上限 1）。
    private(set) var fallbacks = 0
    /// 是否还在用系统预设计算装置。
    private(set) var usesDefaultComputeDevice = false
    private(set) var unavailable = false

    /// 记一次失败并给出该做什么。
    mutating func recordFailure(_ category: FaceVisionFailureCategory) -> Decision {
        lastFailureCategory = category
        consecutiveFailures += 1
        guard consecutiveFailures >= FaceCameraTuning.consecutiveFailureLimit else {
            return .keepRunning
        }
        if fallbacks == 0 {
            fallbacks = 1
            usesDefaultComputeDevice = true
            consecutiveFailures = 0
            return .fallBackToDefault
        }
        unavailable = true
        return .stopUnavailable
    }

    /// 一次成功：连续计数归零，类别清掉（退路状态保留，它是会话级的）。
    mutating func recordSuccess() {
        consecutiveFailures = 0
        lastFailureCategory = nil
    }
}

/// 相机一次会话实际选中的配置与代价（PERF-07）。不含硬件名、不含图像内容。
struct FaceCameraReport: Sendable, Equatable {
    var activeFormatWidth = 0
    var activeFormatHeight = 0
    var activeFormatMinFPS: Double = 0
    var activeFormatMaxFPS: Double = 0
    /// 实际要求相机给的源帧率（已夹进 activeFormat 支援范围）。
    var requestedSourceFPS: Double = 0
    /// 实际拿到的像素格式四字码。
    var pixelFormat: UInt32 = 0
    /// 是否钉在神经引擎上（退回系统预设后为 false）。
    var pinsNeuralEngine = false
}
