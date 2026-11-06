import Foundation
import Synchronization

/// 声音比对在 App 里的装配：模型（随包的 `SpeakerEmbedding.mlmodelc`）、钥匙串里的登记、念短语那一侧。
/// 包里没有模型（build.sh 没找到 WindowShade-models）时 `isModelBundled` 为 false，验证器永远报用不了——失败即关，
/// 麦克风不开，行为跟没有这个功能一样。
final class LazySpeakerVerifier: SpeakerVerifier, @unchecked Sendable {
    /// Mutex 不能复制，后台任务要拿的是这个盒子的引用。
    private final class Loaded: Sendable {
        let verifier = Mutex<CoreMLSpeakerVerifier?>(nil)
        let embedder = Mutex<CoreMLSpeakerEmbedder?>(nil)
    }
    private let loaded = Loaded()

    /// 模型在后台线程加载（第一次可能要几秒编译到神经引擎）；没加载完之前一律报用不了。
    init(modelURL: URL?, store: any SpeakerTemplateStoring) {
        guard let modelURL else { return }
        let loaded = self.loaded
        Task.detached(priority: .utility) {
            guard let embedder = CoreMLSpeakerEmbedder(compiledModelURL: modelURL) else { return }
            loaded.embedder.withLock { $0 = embedder }
            let verifier = CoreMLSpeakerVerifier(embedder: embedder, store: store)
            loaded.verifier.withLock { $0 = verifier }
        }
    }

    private var current: CoreMLSpeakerVerifier? { loaded.verifier.withLock { $0 } }
    var embedder: CoreMLSpeakerEmbedder? { loaded.embedder.withLock { $0 } }
    var isAvailable: Bool { current?.isAvailable ?? false }
    var isEnrolled: Bool { current?.isEnrolled ?? false }
    func refresh() { current?.refresh() }
    func verify(sample: [Float], purpose: VoiceprintPurpose) -> SpeakerVerdict {
        current?.verify(sample: sample, purpose: purpose) ?? .unavailable
    }
}

@MainActor final class SpeakerVoiceKit {
    static let shared = SpeakerVoiceKit()

    /// Intel 版不带声纹（PlatformSupport）：没有模型就是“不可用”，验证器失败即关，不加载模型、不开麦克风。
    static var modelURL: URL? {
        guard PlatformSupport.voiceprint else { return nil }
        return Bundle.main.url(forResource: "SpeakerEmbedding", withExtension: "mlmodelc")
    }
    static var isModelBundled: Bool { modelURL != nil }

    let store = VoiceprintKeychainStore()
    let verifier: LazySpeakerVerifier
    let capture = SpeechVoiceprintCapture()
    private var enrolment: VoiceprintEnrolment?

    private init() { verifier = LazySpeakerVerifier(modelURL: Self.modelURL, store: store) }

    var isEnrolled: Bool { verifier.isEnrolled }

    func startEnrolment(_ update: @escaping @MainActor (VoiceprintEnrolment.Update) -> Void) {
        enrolment?.cancel()
        let session = VoiceprintEnrolment(kit: self)
        enrolment = session
        session.start { [weak self] event in
            if case .finished = event { self?.enrolment = nil }
            if case .failed = event { self?.enrolment = nil }
            update(event)
        }
    }

    func cancelEnrolment() { enrolment?.cancel(); enrolment = nil }
    var isEnrolling: Bool { enrolment != nil }

    @discardableResult func deleteEnrolment() -> Bool {
        let ok = store.delete()
        verifier.refresh()
        return ok
    }
}

/// 登记三句：每句换一个随机短语；字对不上或声音不够就让你重念那一句，三句够像才存。只存特征数字。
@MainActor final class VoiceprintEnrolment {
    enum Failure: Equatable { case noModel, permission, storeUnavailable, cancelled }
    enum Update: Equatable {
        case prompt(step: Int, phrase: String)
        case retry(SpeakerEnrolment.Rejection, step: Int, phrase: String)
        case finished
        case failed(Failure)
    }

    private unowned let kit: SpeakerVoiceKit
    private var progress: SpeakerEnrolment?
    private var onUpdate: (@MainActor (Update) -> Void)?
    private var step = 1
    private var generator = SystemRandomNumberGenerator()
    private var cancelled = false
    /// 每句最多等这么久。
    static let window: Double = 10

    init(kit: SpeakerVoiceKit) { self.kit = kit }

    func start(_ update: @escaping @MainActor (Update) -> Void) {
        onUpdate = update
        guard SpeakerVoiceKit.isModelBundled, let embedder = kit.verifier.embedder else { finish(.failed(.noModel)); return }
        progress = SpeakerEnrolment(embedder: embedder)
        switch SpeechVoiceprintCapture.availability {
        case .ready: nextPhrase(retry: nil)
        case .notDetermined:
            SpeechVoiceprintCapture.requestPermissions { [weak self] granted in
                guard let self, !self.cancelled else { return }
                if granted, SpeechVoiceprintCapture.availability == .ready { self.nextPhrase(retry: nil) }
                else { self.finish(.failed(.permission)) }
            }
        case .denied, .onDeviceUnavailable: finish(.failed(.permission))
        }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        kit.capture.cancel()
        onUpdate = nil
    }

    private var phrase = ""

    private func nextPhrase(retry: SpeakerEnrolment.Rejection?) {
        guard !cancelled else { return }
        if retry == nil || phrase.isEmpty {
            phrase = VoiceprintPhrase.make(english: WSL10n.language == .en, using: &generator)
        }
        onUpdate?(retry.map { .retry($0, step: step, phrase: phrase) } ?? .prompt(step: step, phrase: phrase))
        let expected = phrase
        let deadline = Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000 + Self.window
        kit.capture.capture(phrase: expected, until: deadline) { [weak self] heard, sample in
            guard let self, !self.cancelled, var progress = self.progress else { return }
            let result = progress.add(expected: expected, heard: heard, sample: sample ?? [])
            self.progress = progress
            switch result {
            case .accepted:
                self.step += 1
                self.phrase = ""
                self.nextPhrase(retry: nil)
            case .complete(let template):
                if self.kit.store.write(template) {
                    self.kit.verifier.refresh()
                    self.finish(.finished)
                } else {
                    self.finish(.failed(.storeUnavailable))
                }
            case .rejected(let reason):
                self.nextPhrase(retry: reason)
            }
        }
    }

    private func finish(_ event: Update) {
        let callback = onUpdate
        onUpdate = nil
        progress = nil
        cancelled = true
        callback?(event)
    }
}
