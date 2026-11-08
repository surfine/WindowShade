// 系统灵動岛的能力判断：纯映射表 + 本机真实读数（本机不是岛机就应该是 0/absent）。
import Foundation

@MainActor
func runTests() {
    var failures = 0
    func check(_ ok: Bool, _ name: String) {
        if !ok { failures += 1; print("FAIL \(name)") }
    }
    typealias S = SystemIsland

    // 真值表：原始读数 × 复核开关。开关只认明确的 on/off；写错的照样听系统的。
    let cases: [(raw: Int, override: String?, want: S.Answer)] = [
        (1, nil, .present), (1, "on", .present), (1, "off", .absent), (1, "auto", .present),
        (0, nil, .absent), (0, "on", .present), (0, "off", .absent), (0, "  OFF ", .absent),
        (-1, nil, .unknown), (-1, "on", .present), (-1, "off", .absent), (-1, "garbage", .unknown),
        (1, "true", .present), (0, "0", .absent), (-1, "1", .present), (-1, "", .unknown),
    ]
    for c in cases {
        check(S.resolve(raw: c.raw, override: c.override) == c.want,
              "resolve raw=\(c.raw) override=\(c.override ?? "nil") want=\(c.want.rawValue)")
    }

    // 未知不等于有岛：没有明确证据时绝不抢顶部。
    check(!S.resolve(raw: -1, override: nil).rawValue.isEmpty, "unknown 有值")
    check(S.resolve(raw: -1, override: nil) != .present, "问不到时不当作有岛")

    // 顶部归谁：只有“机器有岛 + 这块屏是内建屏”才让给系统；外接屏、旧刘海机照旧。
    check(S.slotKind(systemIsland: true, builtIn: true, hasNotch: true) == .systemIsland, "岛机内建屏（有刘海）让位")
    check(S.slotKind(systemIsland: true, builtIn: true, hasNotch: false) == .systemIsland, "岛机内建屏（无刘海）也让位")
    check(S.slotKind(systemIsland: true, builtIn: false, hasNotch: false) == .virtual, "岛机外接屏仍是隐形刘海")
    check(S.slotKind(systemIsland: true, builtIn: false, hasNotch: true) == .notch, "岛机外接屏（带刘海）照旧")
    check(S.slotKind(systemIsland: false, builtIn: true, hasNotch: true) == .notch, "旧刘海机照旧")
    check(S.slotKind(systemIsland: false, builtIn: true, hasNotch: false) == .virtual, "没有刘海也没有岛：隐形刘海")
    check(S.slotKind(systemIsland: true, builtIn: true, hasNotch: true) != .virtual, "岛机不落回隐形刘海")

    // 本机读数：MobileGestalt 必须答得上话（0 或 1）。答不上来（-1）说明 dlsym 出了问题，要红。
    check(S.raw == 0 || S.raw == 1, "本机 MobileGestalt 答得上话（raw=\(S.raw)）")
    // 读数与结论一致：0 不让位；1 让位（除非复核开关把结论改掉）。旧刘海机与 PROLED 机都能跑。
    let override = UserDefaults.standard.string(forKey: S.Override.key)
    check(S.present == (S.resolve(raw: S.raw, override: override) == .present),
          "present 与 raw/开关一致（raw=\(S.raw)、override=\(override ?? "nil")）")
    if S.raw == 0 { check(!S.present, "raw=0 不让位") }
    if S.raw == 1, override == nil { check(S.present, "raw=1 且没有开关 → 让位") }

    if failures == 0 { print("PASS system-island") } else { print("FAILED \(failures)"); exit(1) }
}

@main struct Runner { @MainActor static func main() { runTests() } }
