// 旁人一瞥的纯逻辑。不开相机，只喂脸框和朝向。
import CoreGraphics
import Foundation

@main
struct BystanderPolicyTests {
    nonisolated(unsafe) static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    /// 本人：画面中间的大脸。
    static let owner = BystanderFace(box: CGRect(x: 0.35, y: 0.3, width: 0.3, height: 0.4), yaw: 0, pitch: 0)
    /// 旁人：右上角的小脸，朝着屏幕。
    static func bystander(yaw: Double = 0.2, pitch: Double = 0.1) -> BystanderFace {
        BystanderFace(box: CGRect(x: 0.75, y: 0.6, width: 0.12, height: 0.16), yaw: yaw, pitch: pitch)
    }

    static let step = 0.05

    /// 从 start 起每 step 秒喂一帧，直到 end（含）。返回第一次出现的 cover / clear 时刻。
    @discardableResult
    static func run(_ policy: inout BystanderPolicy, from start: Double, to end: Double,
                    faces: [BystanderFace]) -> (cover: Double?, clear: Double?) {
        var cover: Double?, clear: Double?
        var i = 0
        while start + Double(i) * step <= end + 1e-9 {
            let t = start + Double(i) * step
            switch policy.observe(faces, at: t) {
            case .cover: if cover == nil { cover = t }
            case .clear: if clear == nil { clear = t }
            case .none: break
            }
            i += 1
        }
        return (cover, clear)
    }

    static func main() {
        singleOwnerNeverCovers()
        dwellBoundary()
        lookingAwayNeverCounts()
        unknownPoseNeverCounts()
        coverPersistsWhileFacesVanish()
        clearsAfterBystanderLeaves()
        trackingSurvivesSmallMotion()
        farFaceIsNewTrack()
        trackExpiry()
        ownerIsCentredLargest()
        selfDuplicateCannotQualify()
        userClearWaitsForLookAway()
        gapRestartsClearTimer()
        if failures == 0 { print("PASS bystander-policy") }
        else { print("FAIL bystander-policy \(failures)") }
        exit(failures == 0 ? 0 : 1)
    }

    static func singleOwnerNeverCovers() {
        var policy = BystanderPolicy()
        let result = run(&policy, from: 0, to: 10, faces: [owner])
        expect(result.cover == nil && !policy.isCovering, "只有本人看着屏幕，十秒都不遮")
        // 换一个不居中的单人，也一样。
        var other = BystanderPolicy()
        let side = run(&other, from: 0, to: 5, faces: [bystander()])
        expect(side.cover == nil, "画面里只有一张脸，哪怕在角落，也不遮")
    }

    static func dwellBoundary() {
        var short = BystanderPolicy()
        run(&short, from: 0, to: 1, faces: [owner])
        let brief = run(&short, from: 1.05, to: 1.65, faces: [owner, bystander()])
        expect(brief.cover == nil, "旁人朝着屏幕 0.6 秒，不遮")
        // 0.6 秒后转开，再看也要重新数。
        run(&short, from: 1.7, to: 1.8, faces: [owner, bystander(yaw: 1.2)])
        let again = run(&short, from: 1.85, to: 2.45, faces: [owner, bystander()])
        expect(again.cover == nil, "转开一下再看 0.6 秒，仍不遮")

        var long = BystanderPolicy()
        run(&long, from: 0, to: 1, faces: [owner])
        let result = run(&long, from: 1.05, to: 1.8, faces: [owner, bystander()])
        expect(result.cover != nil, "旁人朝着屏幕 0.75 秒，遮上")
        if let cover = result.cover {
            let tuning = BystanderTuning()
            expect(cover - 1.05 >= tuning.dwell - 1e-9, "不早于 0.7 秒")
            expect(cover - 1.05 <= tuning.dwell + tuning.coverBudget, "算数后 0.35 秒内遮上")
        }
    }

    static func lookingAwayNeverCounts() {
        var policy = BystanderPolicy()
        let sideways = run(&policy, from: 0, to: 5, faces: [owner, bystander(yaw: 0.9)])
        expect(sideways.cover == nil, "旁人侧着脸，不算")
        let down = run(&policy, from: 5.05, to: 10, faces: [owner, bystander(yaw: 0, pitch: -0.7)])
        expect(down.cover == nil, "旁人低着头，不算")
        expect(!policy.isCovering, "看别处的旁人一直不触发")
    }

    static func unknownPoseNeverCounts() {
        var policy = BystanderPolicy()
        let face = BystanderFace(box: bystander().box, yaw: nil, pitch: nil)
        let result = run(&policy, from: 0, to: 3, faces: [owner, face])
        expect(result.cover == nil, "读不到朝向，不当成朝着屏幕")
    }

    static func coverPersistsWhileFacesVanish() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 0.5, faces: [owner])
        let covered = run(&policy, from: 0.55, to: 1.5, faces: [owner, bystander()])
        expect(covered.cover != nil, "先遮上")
        let empty = run(&policy, from: 1.55, to: 20, faces: [])
        expect(empty.clear == nil && policy.isCovering, "一张脸都看不到，二十秒也不撤")
    }

    static func clearsAfterBystanderLeaves() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 0.5, faces: [owner])
        run(&policy, from: 0.55, to: 1.5, faces: [owner, bystander()])
        expect(policy.isCovering, "旁人看了，遮上")
        // 旁人最后一次算数在 1.5；之后只剩本人。
        let early = run(&policy, from: 1.55, to: 2.95, faces: [owner])
        expect(early.clear == nil && policy.isCovering, "旁人离开 1.4 秒，还遮着")
        let late = run(&policy, from: 3.0, to: 3.1, faces: [owner])
        expect(late.clear != nil && !policy.isCovering, "旁人离开 1.5 秒，本人还在，撤掉")
        if let clear = late.clear { expect(abs(clear - 3.0) < 1e-6, "正好在 1.5 秒撤") }
    }

    static func trackingSurvivesSmallMotion() {
        var policy = BystanderPolicy()
        var box = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
        _ = policy.observe([BystanderFace(box: box, yaw: 0, pitch: 0)], at: 0)
        let first = policy.tracks.first?.id
        for i in 1...20 {
            box = box.offsetBy(dx: 0.02, dy: -0.01)
            _ = policy.observe([BystanderFace(box: box, yaw: 0, pitch: 0)], at: Double(i) * step)
        }
        expect(policy.tracks.count == 1 && policy.tracks.first?.id == first, "每帧小幅移动，始终是同一条轨迹")
        let a = CGRect(x: 0, y: 0, width: 1, height: 1), b = CGRect(x: 0.5, y: 0, width: 1, height: 1)
        expect(abs(BystanderPolicy.iou(a, b) - 1.0 / 3.0) < 1e-9, "重叠一半的两个框，IoU 是 1/3")
    }

    static func farFaceIsNewTrack() {
        var policy = BystanderPolicy()
        _ = policy.observe([owner], at: 0)
        let first = policy.tracks.first?.id
        let far = BystanderFace(box: CGRect(x: 0.02, y: 0.02, width: 0.12, height: 0.16), yaw: 0, pitch: 0)
        _ = policy.observe([owner, far], at: step)
        expect(policy.tracks.count == 2, "远处出现的脸，开一条新轨迹")
        expect(policy.ownerID == first, "原来的本人仍是本人")
        // 框挪得太远（IoU 低于 0.25）也算新轨迹。
        var jump = BystanderPolicy()
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        _ = jump.observe([BystanderFace(box: box, yaw: 0, pitch: 0)], at: 0)
        _ = jump.observe([BystanderFace(box: box.offsetBy(dx: 0.15, dy: 0), yaw: 0, pitch: 0)], at: step)
        expect(jump.tracks.count == 2, "重叠不到 0.25，算另一张脸")
    }

    static func trackExpiry() {
        var policy = BystanderPolicy()
        _ = policy.observe([owner, bystander()], at: 0)
        expect(policy.tracks.count == 2, "两条轨迹")
        _ = policy.observe([owner], at: 0.64)
        expect(policy.tracks.count == 2, "0.64 秒没看到，轨迹还在")
        _ = policy.observe([owner], at: 0.66)
        expect(policy.tracks.count == 1, "0.65 秒没看到，轨迹作废")
        // 回来的旁人是新轨迹，朝向计时从头来。
        _ = policy.observe([owner, bystander()], at: 0.7)
        let returned = policy.tracks.first { $0.id != policy.ownerID }
        expect(returned?.facingSince == 0.7, "回来的旁人从头计时")
    }

    static func ownerIsCentredLargest() {
        var policy = BystanderPolicy()
        let centred = BystanderFace(box: CGRect(x: 0.35, y: 0.3, width: 0.25, height: 0.3), yaw: 0, pitch: 0)
        // 角落里同样大的脸，居中打折后输。
        let corner = BystanderFace(box: CGRect(x: 0.0, y: 0.7, width: 0.25, height: 0.3), yaw: 0, pitch: 0)
        _ = policy.observe([corner, centred], at: 0)
        let ownerBox = policy.tracks.first { $0.id == policy.ownerID }?.box
        expect(ownerBox == centred.box, "两张同样大的脸，居中的是本人")
        let result = run(&policy, from: step, to: 1.5, faces: [corner, centred])
        expect(result.cover != nil, "角落那张朝着屏幕够久，遮上")
    }

    static func selfDuplicateCannotQualify() {
        // 本人猛地一动，框跳开成新轨迹；旧轨迹 0.65 秒作废后新轨迹就是唯一的本人，来不及凑够 0.7 秒。
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 1, faces: [owner])
        let moved = BystanderFace(box: owner.box.offsetBy(dx: 0.25, dy: 0), yaw: 0, pitch: 0)
        let result = run(&policy, from: 1.05, to: 4, faces: [moved])
        expect(result.cover == nil, "本人自己挪位置，不会被当成旁人")
    }

    static func userClearWaitsForLookAway() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 0.5, faces: [owner])
        run(&policy, from: 0.55, to: 1.5, faces: [owner, bystander()])
        policy.userCleared()
        // 安静期（10 秒）过了，同一个人一直看着也还是不收：要等他转开过一次。
        let still = run(&policy, from: 1.55, to: 14, faces: [owner, bystander()])
        expect(still.cover == nil, "亲手撤掉后，同一个人一直看着也不再遮")
        run(&policy, from: 14.05, to: 14.2, faces: [owner, bystander(yaw: 1.0)])
        let again = run(&policy, from: 14.25, to: 15.2, faces: [owner, bystander()])
        expect(again.cover != nil, "转开一次再看够久，重新遮上")
    }

    static func gapRestartsClearTimer() {
        var policy = BystanderPolicy()
        run(&policy, from: 0, to: 0.5, faces: [owner])
        run(&policy, from: 0.55, to: 1.5, faces: [owner])
        run(&policy, from: 1.55, to: 2.5, faces: [owner, bystander()])
        expect(policy.isCovering, "遮上")
        // 相机十秒没有帧，回来只看到本人：从回来那一刻重新数 1.5 秒。
        let back = run(&policy, from: 12.5, to: 13.95, faces: [owner])
        expect(back.clear == nil, "断帧那段不算人走了")
        let done = run(&policy, from: 14.0, to: 14.1, faces: [owner])
        expect(done.clear != nil, "回来后连续看到本人 1.5 秒，撤掉")
    }
}
