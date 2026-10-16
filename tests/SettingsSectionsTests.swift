import Foundation

// 设置侧栏（1.0.17 精简）：预览旗标关着时 8 页、顺序固定；已经开着的 WindowShade 2 开关保住它那一页；
// 行号在 visibleCases 里查；1.0.16 存下的「上次看的页」编号还原到同一页（手势页加进来之后不再错一位）。
@main
struct SettingsSectionsTests {
  static func main() {
    typealias S = WindowShadeSettingsSection
    let off = WS2Preview.visibleSections(previewOn: false, live: .none)
    precondition(off == [.effects, .shade, .notch, .gesture, .browser, .shortcuts, .permissions, .advanced],
                 "旗标关：8 页，效果、卷帘、刘海、手势、窗口浏览、快捷键、隐私、高级；实际 \(off)")
    let on = WS2Preview.visibleSections(previewOn: true, live: .none)
    precondition(on == off + [.pointer, .remote, .conductor], "旗标开：WindowShade 2 三页接在后面；实际 \(on)")

    // 已经开着的开关：对应那一页照样在，其余照样藏。
    var remoteOn = WS2Preview.Live.none
    remoteOn.remote = true
    precondition(WS2Preview.visibleSections(previewOn: false, live: remoteOn) == off + [.remote])
    var conductorOn = WS2Preview.Live.none
    conductorOn.conductor = true
    let withConductor = WS2Preview.visibleSections(previewOn: false, live: conductorOn)
    precondition(withConductor == off + [.conductor])
    var pointerOn = WS2Preview.Live.none
    pointerOn.pointer = true
    precondition(WS2Preview.visibleSections(previewOn: false, live: pointerOn) == off + [.pointer])
    // 中键和 CarPlay 只管页内的行，不带出整页。
    var rowsOnly = WS2Preview.Live.none
    rowsOnly.middleFold = true
    rowsOnly.carPlay = true
    precondition(WS2Preview.visibleSections(previewOn: false, live: rowsOnly) == off)
    precondition(WS2Preview.shows(previewOn: false, alreadyOn: true) && WS2Preview.shows(previewOn: true, alreadyOn: false)
                 && !WS2Preview.shows(previewOn: false, alreadyOn: false))
    precondition(rowsOnly.readsSomething && remoteOn.readsSomething && conductorOn.readsSomething && !pointerOn.readsSomething,
                 "隐私页的 WindowShade 2 行：遥控、指挥／编程会话、CarPlay 开着就列出来；只改了滚动不算")

    // 行号 ↔ 分节：在这次的可见列表里查，不拿 rawValue 当行号。
    for (row, section) in off.enumerated() {
      precondition(S.section(atRow: row, in: off) == section)
      precondition(S.row(of: section, in: off) == row)
    }
    precondition(S.row(of: .conductor, in: withConductor) == 8, "藏了中间两页之后，指挥模式在第 9 行")
    precondition(S.row(of: .remote, in: withConductor) == nil, "藏着的页没有行")
    precondition(S.section(atRow: off.count, in: off) == nil && S.section(atRow: -1, in: off) == nil)
    precondition(S.row(of: .browser, in: off) == 4, "窗口浏览前面多了刘海和手势两页")

    // 上次看的页：1.0.16 存的编号（0 效果 … 8 指挥模式）还原到同一页。
    let suite = "WindowShade.SettingsSectionsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let shipped: [(Int, S)] = [(0, .effects), (1, .shade), (2, .browser), (3, .shortcuts), (4, .permissions),
                               (5, .advanced), (6, .pointer), (7, .remote), (8, .conductor)]
    for (stored, section) in shipped {
      defaults.set(stored, forKey: "WindowShade.Settings.LastViewedSection")
      precondition(S.lastViewed(in: defaults) == section, "1.0.16 存的 \(stored) 应还原成 \(section)，实际 \(S.lastViewed(in: defaults))")
    }
    for section in S.allCases {
      section.remember(in: defaults)
      precondition(S.lastViewed(in: defaults) == section)
    }
    precondition(Set(S.allCases.map(\.rawValue)).count == S.allCases.count, "存档编号不能重复")
    // 被藏的页不还原：回到卷帘；没藏就原样。
    precondition(S.restored(lastViewed: .remote, visible: off) == .shade)
    precondition(S.restored(lastViewed: .remote, visible: off + [.remote]) == .remote)
    precondition(S.restored(lastViewed: .notch, visible: off) == .notch)
    print("PASS settings-sections: 旗标关 8 页、开着的开关保住它那一页、行号查可见列表、1.0.16 存档编号还原")
  }
}
