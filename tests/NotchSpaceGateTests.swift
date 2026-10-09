// 刘海让开原生全屏 / 调度中心：真值表、桌面类型解析、几何只平移（纯逻辑，外加注入读数的重算）。
import Foundation
import CoreGraphics

@MainActor
func runTests() {
    var failures = 0
    func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL \(name)") }
    }
    typealias G = NotchSpaceGate
    let facts: [NotchSpaceFact] = [.yes, .no, .unknown]

    // 真值表：全屏 × 调度中心 × 层级。只有“确定是”才让开，未知不让开，第 1 层永远不让开。
    for fs in facts { for mc in facts { for auth in [false, true] {
        let expected = !auth && (fs == .yes || mc == .yes)
        check(G.yields(fullScreen: fs, missionControl: mc, authorizationLayer: auth) == expected,
              "truth fs=\(fs) mc=\(mc) auth=\(auth)")
    } } }
    check(!G.yields(fullScreen: .unknown, missionControl: .unknown, authorizationLayer: false), "unknown does not yield")

    // 桌面类型解析
    let uuidA = "AAAA", uuidB = "BBBB"
    let two: [[String: Any]] = [
        ["Display Identifier": uuidA, "Current Space": ["type": 0]],
        ["Display Identifier": uuidB, "Current Space": ["type": 4]],
    ]
    check(G.currentSpaceType(in: two, displayUUID: "bbbb") == 4, "match by uuid, case-insensitive")
    check(G.currentSpaceType(in: two, displayUUID: uuidA) == 0, "match first display")
    check(G.currentSpaceType(in: two, displayUUID: "ZZZZ") == nil, "two displays, no match -> nil")
    check(G.currentSpaceType(in: two, displayUUID: nil) == nil, "two displays, no uuid -> nil")
    let one: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["type": 4]]]
    check(G.currentSpaceType(in: one, displayUUID: "whatever") == 4, "single display fallback")
    let shared: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["type": 0]],
                                   ["Display Identifier": "x", "Current Space": ["type": 4]]]
    check(G.currentSpaceType(in: shared, displayUUID: nil) == 0, "Main entry when spaces shared")
    check(G.currentSpaceType(in: [["Display Identifier": uuidA]], displayUUID: uuidA) == nil, "missing Current Space -> nil")
    check(G.fact(forSpaceType: 4) == .yes && G.fact(forSpaceType: 0) == .no && G.fact(forSpaceType: nil) == .unknown,
          "space type to fact")

    // 几何：碰角只平移，宽高不变；已在屏内不动；比屏还大不动。
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let inside = CGRect(x: 600, y: 900, width: 200, height: 60)
    check(G.translatedInside(inside, screen: screen) == inside, "inside unchanged")
    let overTop = CGRect(x: 600, y: 940, width: 200, height: 60)
    let movedTop = G.translatedInside(overTop, screen: screen)
    check(movedTop.size == overTop.size && movedTop.maxY == screen.maxY && movedTop.minX == overTop.minX, "top overflow translates")
    let corner = CGRect(x: -12, y: 950, width: 200, height: 60)
    let movedCorner = G.translatedInside(corner, screen: screen)
    check(movedCorner.size == corner.size && movedCorner.minX == 0 && movedCorner.maxY == screen.maxY, "corner translates only")
    let huge = CGRect(x: 0, y: 0, width: 2000, height: 100)
    check(G.translatedInside(huge, screen: screen) == huge, "bigger than screen unchanged")

    // 重算：只在变化时通知；读不到当未知不让开；调度中心让所有屏让开。
    var type: Int? = 4
    var focused: (display: CGDirectDisplayID?, fact: NotchSpaceFact) = (nil, .unknown)
    var mission: NotchSpaceFact = .no
    var calls = 0
    let gate = NotchSpaceGate(sources: .init(
        spaceType: { _ in type }, focusedWindow: { focused }, missionControl: { mission }, displays: { [1, 2] }))
    gate.onChange = { _ in calls += 1 }
    check(gate.recompute() == [1, 2] && calls == 1, "fullscreen on both")
    gate.recompute()
    check(calls == 1, "no change, no notify")
    type = 0
    check(gate.recompute().isEmpty && calls == 2, "exit fullscreen clears")
    type = nil
    check(gate.recompute().isEmpty, "unreadable space + unknown fallback -> not yielding")
    focused = (2, .yes)
    check(gate.recompute() == [2], "AX fallback applies to its own display only")
    focused = (2, .no)
    check(gate.recompute().isEmpty, "AX fallback says not fullscreen")
    mission = .yes
    check(gate.recompute() == [1, 2], "mission control yields everywhere")
    mission = .unknown
    check(gate.recompute().isEmpty, "mission control unknown -> not yielding")

    if failures == 0 { print("NotchSpaceGateTests: all passed") } else { print("NotchSpaceGateTests: \(failures) failed"); exit(1) }
}

@main struct Runner { @MainActor static func main() { runTests() } }
