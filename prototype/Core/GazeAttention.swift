import Foundation

// 注视（决定 75，Aaron 2026-10-31）：「你在看屏幕」，做到 Face ID 注意力感知能做到的最近处。纯逻辑，不碰相机、Vision、钥匙串和界面。
//
// 每一帧（App 从 Vision 的脸部特征点摘出来，见 GazeLandmarks）：
// - 眼睛开度：眼睛轮廓两端（离得最远的两点）连成眼轴，轮廓在垂直方向上的跨度除以眼宽。
// - 瞳孔偏移：瞳孔相对两眼角中点的位移，投到眼轴与它的垂线上，再除以眼宽（u 横、v 竖）。
//   投到眼轴上，所以歪头（roll）不改变它；除以眼宽，所以离屏幕远近不改变它。
// - 特征 = 两眼偏移的平均（u, v）+ 头的朝向（yaw, pitch）。
//
// 校准（录脸时多一步）：你依次看屏幕中间和四个角，每个位置收几帧；按岭回归拟一个仿射映射「特征 → 屏幕上的点」
// （屏幕归一化坐标，原点左上，x 向右、y 向下，四角是 0 和 1）。只存拟出来的系数、开眼参照和残差，跟模板放在钥匙串同一条里。
// 残差大（特征跟着目标走不动，比如瞳孔点抖、光太暗）就不算校准成功，宁可不存。
//
// 锁屏时：两眼都睁开、预测的点落在屏幕里（加一圈余量）、连续够帧数，才是 onScreen；短暂眨眼不打断，
// 闭眼久了是 eyesClosed，落在外面够帧数是 offScreen；没校准、看不到眼睛就是 unknown。只有 onScreen 算注视通过。
// 下面所有数值都是实验参数，未标定，要在真机上量过再定。

/// 一个二维点。注视几何里是画面像素（y 向上）；屏幕点是归一化坐标（原点左上，y 向下）。
struct GazePoint: Equatable, Sendable, Codable {
    var x: Double
    var y: Double

    var isFinite: Bool { x.isFinite && y.isFinite }
}

/// 一张脸做注视要用的几何：眼睛轮廓与瞳孔（画面像素坐标，x 向右、y 向上，横竖同一个尺度）和头的朝向（弧度）。
/// 由 App 在相机队列上从 Vision 结果里摘出来；不含图像，不出内存。
struct GazeLandmarks: Equatable, Sendable {
    var leftEye: [GazePoint]
    var rightEye: [GazePoint]
    var leftPupil: GazePoint?
    var rightPupil: GazePoint?
    var yaw: Double?
    var pitch: Double?
    var roll: Double?
}

/// 一只眼睛：开度（垂直跨度 / 眼宽）和瞳孔偏移（以眼宽为单位）。
struct GazeEye: Equatable, Sendable {
    var openness: Double
    /// 瞳孔点没有或不可信就是 nil。
    var offset: GazePoint?
}

/// 一帧的注视样本。只有数字。
struct GazeSample: Equatable, Sendable {
    var leftOpenness: Double
    var rightOpenness: Double
    /// [u, v, yaw, pitch]；瞳孔或朝向缺一样就是 nil（这时只能判断眼睛睁没睁开）。
    var features: [Double]?

    var minimumOpenness: Double { min(leftOpenness, rightOpenness) }
}

enum GazeFeatures {
    /// 特征维数：u、v、yaw、pitch。
    static let dimension = 4
    /// 眼宽小于这么多像素就不算（脸太远或点退化）。
    static let minimumEyeWidth = 6.0
    /// 瞳孔偏离眼角中点超过这么多个眼宽就当瞳孔点不可信。
    static let maximumPupilOffset = 0.75

    static func eye(contour: [GazePoint], pupil: GazePoint?) -> GazeEye? {
        guard contour.count >= 4, contour.allSatisfy(\.isFinite) else { return nil }
        var longest = 0.0
        var a = contour[0], b = contour[0]
        for p in contour { for q in contour {
            let length = hypot(q.x - p.x, q.y - p.y)
            if length > longest { longest = length; a = p; b = q }
        } }
        guard longest >= minimumEyeWidth, longest.isFinite else { return nil }
        // 眼轴从画面左边的眼角指向右边的眼角：两只眼、正反两个方向算出来的号一致。
        if a.x > b.x { swap(&a, &b) }
        let axis = GazePoint(x: (b.x - a.x) / longest, y: (b.y - a.y) / longest)
        let up = GazePoint(x: -axis.y, y: axis.x)
        let centre = GazePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let across = contour.map { ($0.x - centre.x) * up.x + ($0.y - centre.y) * up.y }
        let openness = ((across.max() ?? 0) - (across.min() ?? 0)) / longest
        guard openness.isFinite else { return nil }
        var offset: GazePoint?
        if let pupil, pupil.isFinite {
            let dx = pupil.x - centre.x, dy = pupil.y - centre.y
            let u = (dx * axis.x + dy * axis.y) / longest
            let v = (dx * up.x + dy * up.y) / longest
            if u.isFinite, v.isFinite, abs(u) <= maximumPupilOffset, abs(v) <= maximumPupilOffset {
                offset = GazePoint(x: u, y: v)
            }
        }
        return GazeEye(openness: min(1, max(0, openness)), offset: offset)
    }

    /// 两只眼都要有轮廓才出样本；特征还要两只瞳孔和 yaw、pitch 都在。
    static func sample(_ landmarks: GazeLandmarks) -> GazeSample? {
        guard let left = eye(contour: landmarks.leftEye, pupil: landmarks.leftPupil),
              let right = eye(contour: landmarks.rightEye, pupil: landmarks.rightPupil) else { return nil }
        var features: [Double]?
        if let l = left.offset, let r = right.offset,
           let yaw = landmarks.yaw, let pitch = landmarks.pitch, yaw.isFinite, pitch.isFinite {
            features = [(l.x + r.x) / 2, (l.y + r.y) / 2, yaw, pitch]
        }
        return GazeSample(leftOpenness: left.openness, rightOpenness: right.openness, features: features)
    }
}

/// 校准时看的五个位置。
enum GazeTarget: Int, CaseIterable, Sendable, Equatable {
    case centre, topLeft, topRight, bottomRight, bottomLeft

    /// 屏幕归一化坐标：原点左上，x 向右、y 向下。
    var point: GazePoint {
        switch self {
        case .centre: GazePoint(x: 0.5, y: 0.5)
        case .topLeft: GazePoint(x: 0, y: 0)
        case .topRight: GazePoint(x: 1, y: 0)
        case .bottomRight: GazePoint(x: 1, y: 1)
        case .bottomLeft: GazePoint(x: 0, y: 1)
        }
    }
}

/// 拟好的映射（每个人一份，跟脸的模板存在一起）。只有系数，没有样本、没有图像。
struct GazeCalibration: Equatable, Sendable, Codable {
    static let formatVersion = 1

    var format: Int
    /// 特征标准化：z = (f − mean) / scale。
    var mean: [Double]
    var scale: [Double]
    /// [截距, z0, z1, z2, z3] → 屏幕 x 与 y。
    var weightsX: [Double]
    var weightsY: [Double]
    /// 校准时两眼开度（取小的那只）的中位数；闭眼按它的比例判。
    var openEyeReference: Double
    /// 校准样本上的均方根误差（屏幕归一化单位）。
    var residual: Double

    var isValid: Bool {
        let d = GazeFeatures.dimension
        let all = mean + scale + weightsX + weightsY + [openEyeReference, residual]
        return format == Self.formatVersion && mean.count == d && scale.count == d
            && weightsX.count == d + 1 && weightsY.count == d + 1 && all.allSatisfy(\.isFinite)
            && scale.allSatisfy { $0 > 0 } && openEyeReference > 0 && openEyeReference <= 1
            && residual >= 0 && residual <= GazeCalibrationFit.maximumResidual
    }

    /// 特征 → 屏幕上的点；特征不对或校准无效就是 nil。
    func predict(_ features: [Double]) -> GazePoint? {
        guard isValid, features.count == GazeFeatures.dimension, features.allSatisfy(\.isFinite) else { return nil }
        var x = weightsX[0], y = weightsY[0]
        for i in 0..<GazeFeatures.dimension {
            let z = (features[i] - mean[i]) / scale[i]
            x += weightsX[i + 1] * z
            y += weightsY[i + 1] * z
        }
        let point = GazePoint(x: x, y: y)
        return point.isFinite ? point : nil
    }

    /// Touch ID 确认的那一组里，校准这一段的规范字节（字段顺序固定，大端位型）。改动要升 formatVersion。
    var canonicalBytes: [UInt8] {
        var bytes = Array("WindowShade.GazeCalibration\0".utf8)
        func put(_ value: UInt64) { withUnsafeBytes(of: value.bigEndian) { bytes += $0 } }
        func put(_ values: [Double]) {
            put(UInt64(values.count))
            for value in values { put(value.bitPattern) }
        }
        put(UInt64(format))
        put(mean); put(scale); put(weightsX); put(weightsY)
        put(openEyeReference.bitPattern); put(residual.bitPattern)
        return bytes
    }
}

enum GazeCalibrationFit {
    /// 岭回归的惩罚（按样本数缩放，截距不罚）。
    static let ridge = 0.05
    /// 校准样本上的均方根误差超过这个（屏幕归一化单位）就不算校准成功。
    /// 退化成常数（特征不跟着目标走）时误差约 0.36，所以它也挡住「怎么看都在屏幕中间」。
    static let maximumResidual = 0.15
    /// 每个位置至少要这么多帧。
    static let minimumSamplesPerTarget = 3
    /// 标准差小于这个的特征当常数（标准化时不放大噪声）。
    static let minimumScale = 1e-4

    enum Failure: Error, Equatable, Sendable {
        case notEnoughSamples
        case singular
        case residualTooLarge
    }

    struct Sample: Equatable, Sendable {
        var target: GazeTarget
        var features: [Double]
        var openness: Double
    }

    static func fit(_ samples: [Sample]) -> Result<GazeCalibration, Failure> {
        let d = GazeFeatures.dimension
        let usable = samples.filter { $0.features.count == d && $0.features.allSatisfy(\.isFinite) && $0.openness.isFinite }
        for target in GazeTarget.allCases where usable.filter({ $0.target == target }).count < minimumSamplesPerTarget {
            return .failure(.notEnoughSamples)
        }
        let n = Double(usable.count)
        var mean = [Double](repeating: 0, count: d), scale = [Double](repeating: 0, count: d)
        for s in usable { for i in 0..<d { mean[i] += s.features[i] / n } }
        for s in usable { for i in 0..<d { scale[i] += pow(s.features[i] - mean[i], 2) / n } }
        scale = scale.map { max(sqrt($0), minimumScale) }
        let rows = usable.map { s in [1.0] + (0..<d).map { (s.features[$0] - mean[$0]) / scale[$0] } }
        let k = d + 1
        var normal = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var rhsX = [Double](repeating: 0, count: k), rhsY = [Double](repeating: 0, count: k)
        for (row, s) in zip(rows, usable) {
            for i in 0..<k {
                for j in 0..<k { normal[i][j] += row[i] * row[j] }
                rhsX[i] += row[i] * s.target.point.x
                rhsY[i] += row[i] * s.target.point.y
            }
        }
        for i in 1..<k { normal[i][i] += ridge * n }
        guard let wx = solve(normal, rhsX), let wy = solve(normal, rhsY) else { return .failure(.singular) }
        var squared = 0.0
        for (row, s) in zip(rows, usable) {
            let px = zip(row, wx).reduce(0) { $0 + $1.0 * $1.1 }
            let py = zip(row, wy).reduce(0) { $0 + $1.0 * $1.1 }
            squared += pow(px - s.target.point.x, 2) + pow(py - s.target.point.y, 2)
        }
        let residual = sqrt(squared / n)
        guard residual.isFinite, residual <= maximumResidual else { return .failure(.residualTooLarge) }
        let opens = usable.map(\.openness).sorted()
        let reference = opens[opens.count / 2]
        let calibration = GazeCalibration(format: GazeCalibration.formatVersion, mean: mean, scale: scale,
                                          weightsX: wx, weightsY: wy, openEyeReference: reference, residual: residual)
        return calibration.isValid ? .success(calibration) : .failure(.singular)
    }

    /// 高斯消元（部分主元）。主元太小当奇异。
    static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        guard matrix.count == n, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var a = matrix, b = rhs
        for column in 0..<n {
            guard let pivot = (column..<n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }),
                  abs(a[pivot][column]) > 1e-12 else { return nil }
            a.swapAt(column, pivot); b.swapAt(column, pivot)
            for row in (column + 1)..<n where row < n {
                let factor = a[row][column] / a[column][column]
                for j in column..<n { a[row][j] -= factor * a[column][j] }
                b[row] -= factor * b[column]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for j in (row + 1)..<n where j < n { sum -= a[row][j] * x[j] }
            x[row] = sum / a[row][row]
        }
        return x.allSatisfy(\.isFinite) ? x : nil
    }
}

/// 录脸里的校准那一步：依次给五个位置，每个位置先等你把眼睛移过去，再收几帧。
struct GazeCalibrationFlow: Equatable, Sendable {
    struct Tuning: Equatable, Sendable {
        /// 换到新位置后先等这么久再收（眼睛移过去、稳住）。
        var settleSeconds = 0.8
        /// 每个位置收这么多帧。
        var samplesPerTarget = 5
        /// 一个位置这么久还没收够，这次校准就不成（录脸照旧，只是不存新的校准）。
        var targetTimeout = 6.0
        /// 两眼开度低于这个的帧不收（眨眼、眯眼）。
        var minimumOpenness = 0.12
    }

    /// 给界面看的一步。
    struct Step: Equatable, Sendable {
        var target: GazeTarget
        /// 第几个位置（0 起）。
        var index: Int
        var count: Int
        /// 已经在收这一处的帧（过了等待时间）。
        var collecting: Bool
    }

    enum Outcome: Equatable, Sendable {
        case fitted(GazeCalibration)
        case failed(Failure)
    }

    enum Failure: Equatable, Sendable {
        case timedOut
        case fit(GazeCalibrationFit.Failure)
    }

    let tuning: Tuning
    private(set) var index = 0
    private(set) var shownAt: Double
    private(set) var outcome: Outcome?
    private var collectedHere = 0
    private var samples: [GazeCalibrationFit.Sample] = []

    init(startedAt: Double, tuning: Tuning = Tuning()) {
        self.tuning = tuning
        shownAt = startedAt.isFinite ? startedAt : 0
    }

    var step: Step? {
        guard outcome == nil, GazeTarget.allCases.indices.contains(index) else { return nil }
        return Step(target: GazeTarget.allCases[index], index: index, count: GazeTarget.allCases.count,
                    collecting: false)
    }

    /// 和 step 一样，另按时间说这一处是不是已经在收。
    func step(at time: Double) -> Step? {
        guard var step else { return nil }
        step.collecting = time.isFinite && time - shownAt >= tuning.settleSeconds
        return step
    }

    /// 一帧。`faceCount` 不是 1、样本没有特征、眼睛没睁开的帧都不收（也不算失败）；只有超时才失败。
    mutating func receive(_ sample: GazeSample?, faceCount: Int, at time: Double) {
        guard outcome == nil, time.isFinite else { return }
        if time - shownAt > tuning.targetTimeout { outcome = .failed(.timedOut); return }
        guard time - shownAt >= tuning.settleSeconds, faceCount == 1, let sample, let features = sample.features,
              sample.minimumOpenness >= tuning.minimumOpenness else { return }
        samples.append(.init(target: GazeTarget.allCases[index], features: features, openness: sample.minimumOpenness))
        collectedHere += 1
        guard collectedHere >= max(1, tuning.samplesPerTarget) else { return }
        index += 1
        collectedHere = 0
        shownAt = time
        guard index >= GazeTarget.allCases.count else { return }
        switch GazeCalibrationFit.fit(samples) {
        case .success(let calibration): outcome = .fitted(calibration)
        case .failure(let failure): outcome = .failed(.fit(failure))
        }
        samples = []
    }
}

/// 锁屏时的注视判定（带回滞）。每一次认你（每一轮相机）新建一个。
struct GazeAttention: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case unknown, onScreen, offScreen, eyesClosed
    }

    struct Tuning: Equatable, Sendable {
        /// 预测点落在 [−enterMargin, 1 + enterMargin] 里才开始算「在看」。
        var enterMargin = 0.10
        /// 已经在看时，落在 [−exitMargin, 1 + exitMargin] 里都还算（回滞）。
        var exitMargin = 0.20
        /// 连续这么多帧在看才是 onScreen（识别时每秒 10 帧，约 0.4 秒）。
        var requiredOnScreenFrames = 4
        /// 连续这么多帧落在外面才是 offScreen。
        var offScreenFrames = 3
        /// 闭眼不超过这么多帧当眨眼：不打断、也不计入。
        var blinkToleranceFrames = 3
        /// 两眼开度（取小的那只）低于 校准时开眼参照 × 这个比例 就算闭着。
        var closedRatio = 0.5
        /// 不管参照多少，低于这个一律算闭着。
        var closedFloor = 0.06
        /// 连续这么多帧看不到眼睛（没脸、没特征点）就回到 unknown。
        var missingFramesToReset = 3
    }

    let calibration: GazeCalibration?
    let tuning: Tuning
    private(set) var state: State = .unknown
    private var onRun = 0
    private var offRun = 0
    private var closedRun = 0
    private var missingRun = 0

    init(calibration: GazeCalibration?, tuning: Tuning = Tuning()) {
        self.calibration = calibration.flatMap { $0.isValid ? $0 : nil }
        self.tuning = tuning
    }

    var isCalibrated: Bool { calibration != nil }

    /// 预测点在不在屏幕（加余量）里。
    static func inside(_ point: GazePoint, margin: Double) -> Bool {
        point.isFinite && point.x >= -margin && point.x <= 1 + margin && point.y >= -margin && point.y <= 1 + margin
    }

    @discardableResult
    mutating func receive(_ sample: GazeSample?) -> State {
        guard let calibration else { state = .unknown; return state }
        guard let sample, sample.leftOpenness.isFinite, sample.rightOpenness.isFinite else { return missing() }
        let closedBelow = max(tuning.closedFloor, calibration.openEyeReference * tuning.closedRatio)
        if sample.minimumOpenness < closedBelow {
            missingRun = 0
            closedRun += 1
            if closedRun > max(0, tuning.blinkToleranceFrames) {
                state = .eyesClosed
                onRun = 0; offRun = 0
            }
            return state
        }
        closedRun = 0
        guard let features = sample.features, let point = calibration.predict(features) else { return missing() }
        missingRun = 0
        if state == .onScreen {
            if Self.inside(point, margin: tuning.exitMargin) { offRun = 0 }
            else {
                offRun += 1
                if offRun >= max(1, tuning.offScreenFrames) { state = .offScreen; onRun = 0 }
            }
            return state
        }
        if Self.inside(point, margin: tuning.enterMargin) {
            offRun = 0
            onRun += 1
            if onRun >= max(1, tuning.requiredOnScreenFrames) { state = .onScreen }
        } else {
            onRun = 0
            offRun += 1
            if offRun >= max(1, tuning.offScreenFrames) { state = .offScreen }
        }
        return state
    }

    private mutating func missing() -> State {
        missingRun += 1
        if missingRun >= max(1, tuning.missingFramesToReset) {
            state = .unknown
            onRun = 0; offRun = 0; closedRun = 0
        }
        return state
    }
}
