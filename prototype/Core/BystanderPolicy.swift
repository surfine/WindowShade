// WindowShade 2.1 · 有人在看：有人从旁边朝屏幕看，先把私人窗口收进刘海；人走了，慢慢放回来。
// 数字与思路参考 quietglass（MIT）CameraTracking / NearbyPresence / NearbyWarningPolicy，此处为独立 Swift 实现。
// 只看几何：脸框和朝向。不认人，不存图，不解锁。看不到脸是未知，不当成人走了。
import CoreGraphics

/// 一帧里的一张脸。框是归一化坐标（0...1）；朝向读不到就是 nil，nil 不算朝着屏幕。
struct BystanderFace: Sendable, Equatable {
    var box: CGRect
    var yaw: Double?
    var pitch: Double?
}

struct BystanderTuning: Sendable, Equatable {
    /// 前后两帧的框重叠到这个比例，才算同一张脸。
    var matchIoU = 0.25
    /// 一条轨迹这么久没再看到就作废。
    var trackExpiry = 0.65
    /// 朝着屏幕：左右、上下转头都在这个角度（弧度）以内。
    var facingYaw = 0.61
    var facingPitch = 0.52
    /// 旁人连续朝着屏幕这么久才算数。
    var dwell = 0.7
    /// 算数之后最迟这么久要遮上（由帧间隔保证，策略本身当帧就给结论）。
    var coverBudget = 0.35
    /// 连续这么久看得到脸、又没有算数的旁人，才撤遮挡。
    var clearAfter = 1.5
    /// 一帧最多看这么多张脸，代价有上限。
    var maxFaces = 8
    /// 用户亲手放回之后这么久内不再收，免得刚放回又收走。
    var userClearQuiet = 10.0
}

enum BystanderDecision: Sendable, Equatable {
    case none
    /// 现在遮上。
    case cover
    /// 现在撤掉。
    case clear
}

/// 遮得快，放得慢。只有一个人时永远不遮；看不到任何脸时永远不撤。
struct BystanderPolicy: Sendable {
    struct Track: Sendable, Equatable {
        let id: UInt64
        var box: CGRect
        var lastSeen: Double
        /// 作为旁人连续朝着屏幕的起点；断了就是 nil。
        var facingSince: Double?
    }

    let tuning: BystanderTuning
    private(set) var tracks: [Track] = []
    private(set) var ownerID: UInt64?
    private(set) var isCovering = false
    private var nextID: UInt64 = 1
    private var lastFrameAt: Double?
    /// 撤遮挡计时的起点：最后一次看到算数的旁人，或者重新看到脸的那一刻。
    private var clearSince: Double?
    /// 用户亲手撤掉遮挡时正在看的旁人。转开一次再回来才重新算。
    private var dismissed: Set<UInt64> = []
    /// 亲手放回后的安静期截止时刻（和帧同一个时钟）。相机停了也不清。
    private(set) var quietUntil: Double?

    /// 浮点时间比较的余量，免得 0.7 被算成 0.6999999。
    private static let slack = 1e-6

    init(tuning: BystanderTuning = BystanderTuning()) { self.tuning = tuning }

    /// 喂一帧。时间要单调递增，倒退或重复的帧丢掉。
    mutating func observe(_ faces: [BystanderFace], at time: Double) -> BystanderDecision {
        guard time.isFinite else { return .none }
        if let last = lastFrameAt, time <= last { return .none }
        // 中间断了帧：那段时间是未知，撤遮挡要从头计时。
        if let last = lastFrameAt, time - last >= tuning.trackExpiry - Self.slack { clearSince = nil }
        lastFrameAt = time

        tracks.removeAll { time - $0.lastSeen >= tuning.trackExpiry - Self.slack }
        let alive = Set(tracks.map(\.id))
        dismissed.formIntersection(alive)
        if let owner = ownerID, !alive.contains(owner) { ownerID = nil }

        let usable = Array(faces.filter { Self.valid($0.box) }.prefix(tuning.maxFaces))
        let seen = match(usable, at: time)
        chooseOwner()

        for (index, face) in seen {
            if tracks[index].id == ownerID || !facing(face) {
                tracks[index].facingSince = nil
                dismissed.remove(tracks[index].id)
            } else if tracks[index].facingSince == nil {
                tracks[index].facingSince = time
            }
        }
        let quiet = quietUntil.map { time < $0 - Self.slack } ?? false
        let qualifying = !quiet && seen.contains { index, _ in
            let track = tracks[index]
            guard let since = track.facingSince, !dismissed.contains(track.id) else { return false }
            return time - since >= tuning.dwell - Self.slack
        }

        if qualifying {
            clearSince = time
            guard !isCovering else { return .none }
            isCovering = true
            return .cover
        }
        guard isCovering else { return .none }
        // 一张脸都没有：未知，不是人走了。
        guard !usable.isEmpty else { clearSince = nil; return .none }
        let since = clearSince ?? time
        clearSince = since
        guard time - since >= tuning.clearAfter - Self.slack else { return .none }
        isCovering = false
        clearSince = nil
        return .clear
    }

    /// 用户亲手放回了。正在看的旁人先不再触发，直到他转开过一次；
    /// 另外从 time（缺省用最后一帧的时刻）起安静 `userClearQuiet` 秒，谁来看都先不收。
    mutating func userCleared(at time: Double? = nil) {
        isCovering = false
        clearSince = nil
        if let start = time ?? lastFrameAt, start.isFinite { quietUntil = start + tuning.userClearQuiet }
        for track in tracks where track.facingSince != nil && track.id != ownerID {
            dismissed.insert(track.id)
        }
    }

    /// 相机停了：轨迹全部作废。收起状态和安静期不动，停了不等于人走了。
    mutating func forgetTracks() {
        tracks.removeAll()
        ownerID = nil
        lastFrameAt = nil
        clearSince = nil
        dismissed.removeAll()
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let overlap = a.intersection(b)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return 0 }
        let inter = Double(overlap.width * overlap.height)
        let union = Double(a.width * a.height + b.width * b.height) - inter
        return union > 0 ? inter / union : 0
    }

    // MARK: - 内部

    private static func valid(_ box: CGRect) -> Bool {
        box.origin.x.isFinite && box.origin.y.isFinite && box.width.isFinite && box.height.isFinite
            && box.width > 0 && box.height > 0
    }

    private func facing(_ face: BystanderFace) -> Bool {
        guard let yaw = face.yaw, let pitch = face.pitch, yaw.isFinite, pitch.isFinite else { return false }
        return abs(yaw) < tuning.facingYaw && abs(pitch) < tuning.facingPitch
    }

    /// 按重叠从大到小贪心配对；配不上的脸开新轨迹。返回这一帧看到的轨迹下标和对应的脸。
    private mutating func match(_ faces: [BystanderFace], at time: Double) -> [(Int, BystanderFace)] {
        var pairs: [(iou: Double, track: Int, face: Int)] = []
        for (t, track) in tracks.enumerated() {
            for (f, face) in faces.enumerated() {
                let value = Self.iou(track.box, face.box)
                if value >= tuning.matchIoU { pairs.append((value, t, f)) }
            }
        }
        pairs.sort { $0.iou != $1.iou ? $0.iou > $1.iou : ($0.track, $0.face) < ($1.track, $1.face) }
        var usedTracks = Set<Int>(), usedFaces = Set<Int>()
        var seen: [(Int, BystanderFace)] = []
        for pair in pairs where !usedTracks.contains(pair.track) && !usedFaces.contains(pair.face) {
            usedTracks.insert(pair.track); usedFaces.insert(pair.face)
            tracks[pair.track].box = faces[pair.face].box
            tracks[pair.track].lastSeen = time
            seen.append((pair.track, faces[pair.face]))
        }
        for (f, face) in faces.enumerated() where !usedFaces.contains(f) {
            tracks.append(Track(id: nextID, box: face.box, lastSeen: time, facingSince: nil))
            nextID &+= 1
            seen.append((tracks.count - 1, face))
        }
        return seen
    }

    /// 只有一条活着的轨迹，它就是本人；多条时沿用原来的本人，原来的没了再挑居中且最大的那张。
    private mutating func chooseOwner() {
        if tracks.count == 1 { ownerID = tracks[0].id; return }
        guard !tracks.isEmpty else { return }
        if let owner = ownerID, tracks.contains(where: { $0.id == owner }) { return }
        ownerID = tracks.max { Self.ownerScore($0.box) < Self.ownerScore($1.box) }?.id
    }

    /// 面积乘居中程度：离画面中心越远越打折，最远打五折。
    static func ownerScore(_ box: CGRect) -> Double {
        let dx = Double(box.midX) - 0.5, dy = Double(box.midY) - 0.5
        let off = min(1, (dx * dx + dy * dy).squareRoot() / 0.5)
        return Double(box.width * box.height) * (1 - 0.5 * off)
    }
}

// MARK: - 什么时候开相机

/// 有人在看这一路什么时候开相机。纯判断：空闲秒数由调用方读好了给。
/// 只在键盘鼠标停手满 `idleThreshold` 秒后才开，一有输入就关；名单为空、没授权、锁屏、睡眠、切走用户都不开。
enum BystanderCameraGate {
    /// 停手多久才开相机（秒）。
    static let idleThreshold = 30.0
    /// 等停手时，最短隔多久再看一次（秒）：离门槛很近时不连着排很多次。
    static let minimumWait = 1.0

    struct Facts: Sendable, Equatable {
        /// 设置开着（或开发者用环境变量指定了镜头）。
        var enabled: Bool
        /// 私人 App 名单里至少有一个。
        var hasPrivateApps: Bool
        var cameraAuthorized: Bool
        var unlocked: Bool
        /// 睡眠、屏幕睡了、切到别的用户。
        var suspended: Bool
        /// 距最后一次键盘鼠标输入多少秒。
        var idleSeconds: Double
    }

    enum Verdict: Sendable, Equatable {
        /// 不开，也不用等。
        case off
        /// 先不开；过这么多秒再看一次停手够不够。
        case waitForIdle(Double)
        /// 开着。
        case run
    }

    static func verdict(_ facts: Facts) -> Verdict {
        guard facts.enabled, facts.hasPrivateApps, facts.cameraAuthorized,
              facts.unlocked, !facts.suspended else { return .off }
        // 读不到或读成负数：当成刚有输入。
        let idle = facts.idleSeconds.isFinite ? max(0, facts.idleSeconds) : 0
        if idle >= idleThreshold { return .run }
        return .waitForIdle(max(minimumWait, idleThreshold - idle))
    }
}

// MARK: - 收了哪些窗口

/// 有人在看时收进刘海的窗口账本：只放回自己收的；用户自己收的、已经放回的、换了进程的都不碰。
struct BystanderTuckLedger: Sendable {
    struct Candidate: Sendable, Equatable {
        var id: CGWindowID
        var pid: Int32
        var bundleID: String?
    }

    struct Entry: Sendable, Equatable {
        var id: CGWindowID
        var pid: Int32
    }

    /// 按收起的顺序。
    private(set) var owned: [Entry] = []

    var isEmpty: Bool { owned.isEmpty }

    /// 这一批里该收的：私人 App 的、还没被我们收过的，同一扇只收一次。
    func toTuck(_ candidates: [Candidate], isPrivate: (String?) -> Bool) -> [Candidate] {
        var seen = Set(owned.map(\.id))
        var result: [Candidate] = []
        for candidate in candidates where isPrivate(candidate.bundleID) && seen.insert(candidate.id).inserted {
            result.append(candidate)
        }
        return result
    }

    mutating func recordTucked(_ candidate: Candidate) {
        guard !owned.contains(where: { $0.id == candidate.id }) else { return }
        owned.append(Entry(id: candidate.id, pid: candidate.pid))
    }

    /// 要放回的：还收在刘海里、而且还是原来那个进程的。账本清空。
    /// tuckedPID：刘海里这扇窗口属于哪个进程，不在刘海里就是 nil。
    mutating func takeReleases(tuckedPID: (CGWindowID) -> Int32?) -> [CGWindowID] {
        let release = owned.filter { tuckedPID($0.id) == $0.pid }.map(\.id)
        owned.removeAll()
        return release
    }
}

/// 设置里“有人在看时收起私人窗口”这一行：名单为空时灰着，提示先去选 App。
enum BystanderTuckRow {
    static let titleZh = "有人在看时收起私人窗口"
    static let subtitleZh = "只在解锁时用相机，不留任何画面"
    static let emptySubtitleZh = "先在私人 App 里选几个"

    /// 显示走目录：zh 是语义身份。
    static var title: String { WSL10n.text("settings.bystander.title", zh: titleZh) }
    static var subtitle: String { WSL10n.text("settings.bystander.subtitle", zh: subtitleZh) }
    static var emptySubtitle: String { WSL10n.text("settings.bystander.empty", zh: emptySubtitleZh) }

    static func state(listEmpty: Bool) -> (enabled: Bool, subtitle: String) {
        listEmpty ? (false, emptySubtitle) : (true, subtitle)
    }

    /// 设置页那一行实际画什么。开关开着时副标题始终讲开关本身；名单为空的提醒只放在 tooltip，不和“开着”矛盾。
    /// 开着的永远可以关掉。
    static func presentation(isOn: Bool, listEmpty: Bool) -> (enabled: Bool, subtitle: String, toolTip: String?) {
        if !listEmpty { return (true, subtitle, nil) }
        if isOn { return (true, subtitle, emptySubtitle) }
        return (false, emptySubtitle, nil)
    }
}
