import CoreVideo
import Foundation
import Vision

/// PERF-07：相机路径的像素格式偏好、Vision 失败类别与连续失败的会话级退路。
/// 硬条件：格式只在相机支援清单里挑（不硬塞）；失败先记类别；退路整个会话只有一次；
/// 退路后仍失败就判定不可用，不做无限重试。
@main struct FaceVisionFallbackTests {
    static func main() {
        pixelFormatTests()
        failureCategoryTests()
        fallbackPolicyTests()
        print(
            "PASS: camera pixel format preference, Vision failure categories and one-shot ANE fallback")
    }

    static func pixelFormatTests() {
        let yuv = FaceCameraPixelFormat.biPlanarVideoRange
        let yuvFull = FaceCameraPixelFormat.biPlanarFullRange
        let bgra = FaceCameraPixelFormat.bgra

        precondition(
            FaceCameraPixelFormat.preferred(from: [bgra, yuv, yuvFull]) == yuv,
            "支援清单里有原生双平面 YUV 就优先它，不用多一次转换")
        precondition(
            FaceCameraPixelFormat.preferred(from: [bgra, yuvFull]) == yuvFull,
            "只有 full-range 双平面就用它")
        precondition(
            FaceCameraPixelFormat.preferred(from: [bgra]) == bgra, "只剩 BGRA 就用 BGRA")
        precondition(
            FaceCameraPixelFormat.preferred(from: []) == nil, "相机一个都不支援时不能硬塞格式")
        precondition(
            FaceCameraPixelFormat.preferred(from: [0x1122_3344]) == nil,
            "清单里只有认不出的格式就当没有可用格式")

        // 真机对照用的覆写：只在相机真的支援时才生效。
        precondition(
            FaceCameraPixelFormat.preferred(from: [bgra], forced: "bgra") == bgra)
        precondition(
            FaceCameraPixelFormat.preferred(from: [yuv], forced: "bgra") == nil,
            "覆写指定的格式相机不支援就不设，而不是设一个它不认的值")
        precondition(
            FaceCameraPixelFormat.preferred(from: [yuv, yuvFull, bgra], forced: "420F") == yuvFull,
            "覆写不分大小写")

        precondition(FaceCameraPixelFormat.name(yuv) == "420v")
        precondition(FaceCameraPixelFormat.name(yuvFull) == "420f")
        precondition(FaceCameraPixelFormat.name(bgra) == "BGRA")
        precondition(!FaceCameraPixelFormat.name(0x0000_0000).isEmpty, "认不出的格式也要有可读名")
    }

    static func failureCategoryTests() {
        func category(_ code: VNErrorCode) -> FaceVisionFailureCategory {
            FaceVisionFailureCategory.of(
                NSError(domain: VNErrorDomain, code: code.rawValue))
        }
        precondition(category(.requestCancelled) == .cancelled)
        precondition(category(.invalidImage) == .invalidInput)
        precondition(category(.invalidOption) == .invalidInput)
        precondition(category(.unsupportedComputeDevice) == .unsupportedCompute)
        precondition(category(.outOfMemory) == .resources)
        precondition(category(.ioError) == .io)
        precondition(category(.internalError) == .internalFailure)
        precondition(category(.timeout) == .timeout)
        precondition(
            FaceVisionFailureCategory.of(
                NSError(domain: "com.example.notvision", code: 3)) == .unknown,
            "不是 Vision 的错就记 unknown，不硬套一个类别")
    }

    static func fallbackPolicyTests() {
        var policy = FaceVisionFallbackPolicy()
        precondition(policy.fallbacks == 0)
        precondition(!policy.usesDefaultComputeDevice)

        // 前两次失败只是记类别，不动任何东西。
        for _ in 0..<(FaceCameraTuning.consecutiveFailureLimit - 1) {
            precondition(policy.recordFailure(.internalFailure) == .keepRunning)
        }
        precondition(policy.lastFailureCategory == .internalFailure, "先记类别")
        precondition(policy.fallbacks == 0, "还没到阈值不该退路")
        precondition(!policy.usesDefaultComputeDevice)

        // 第 N 次连续失败：退回系统预设，整个会话只有一次。
        precondition(policy.recordFailure(.internalFailure) == .fallBackToDefault)
        precondition(policy.fallbacks == 1)
        precondition(policy.usesDefaultComputeDevice)
        precondition(policy.consecutiveFailures == 0, "退路后连续计数重新开始")
        precondition(!policy.unavailable)

        // 退路后用着系统预设，再有零散成功也不退回钉神经引擎。
        policy.recordSuccess()
        precondition(policy.usesDefaultComputeDevice, "退路是会话级的，一次成功不该收回")
        precondition(policy.lastFailureCategory == nil, "成功一次就把类别清掉")

        // 退路后仍连续失败：判定不可用，不再退路、不再重试。
        for _ in 0..<(FaceCameraTuning.consecutiveFailureLimit - 1) {
            precondition(policy.recordFailure(.unsupportedCompute) == .keepRunning)
        }
        precondition(policy.recordFailure(.unsupportedCompute) == .stopUnavailable)
        precondition(policy.unavailable)
        precondition(policy.fallbacks == 1, "退路不会来第二次")
        precondition(
            policy.recordFailure(.unsupportedCompute) == .stopUnavailable,
            "已经判定不可用之后仍然只能停源")

        // 中途成功一次会把连续计数打断：不到阈值不该退路。
        var interrupted = FaceVisionFallbackPolicy()
        for _ in 0..<(FaceCameraTuning.consecutiveFailureLimit - 1) {
            precondition(interrupted.recordFailure(.io) == .keepRunning)
            interrupted.recordSuccess()
        }
        precondition(interrupted.fallbacks == 0, "失败不连续就不算会话级异常")
        precondition(!interrupted.usesDefaultComputeDevice)
    }
}
