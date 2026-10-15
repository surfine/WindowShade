import Foundation

// 隐私一栏的纯逻辑：读取次数、哪些行出现、一行怎么摆、值怎么写、文案里不许出现的字样，
// 以及启动时一次性清理旧的 /tmp/windowshade.log。界面本身由 SettingsNavigationTests 看。
@main
struct PrivacyPaneTests {
  @MainActor
  static func main() throws {
    readSessionTests()
    visibilityTests()
    presentationTests()
    formatTests()
    copyTests()
    registryTextTests()
    noPollingTests()
    try legacyLogTests()
    print("PASS privacy-pane: read session, visibility, presentation, values, copy, no polling, legacy log cleanup")
  }

  // MARK: 读取次数

  @MainActor
  static func readSessionTests() {
    var ticks = 0
    let session = WS2PrivacyReadSession(clock: {
      ticks += 1
      return Date(timeIntervalSince1970: Double(ticks) * 60)
    })
    var reads: [Date] = []
    session.onRead = { reads.append($0) }
    precondition(session.readCount == 0, "还没出现就不读")
    session.open()
    precondition(session.readCount == 1, "页面出现时读一次")
    session.open()
    session.open()
    precondition(session.readCount == 1, "同一次出现里反复布局不重读")
    session.reread()
    precondition(session.readCount == 2, "按“再读一次”再读一次")
    precondition(reads.count == 2 && session.lastReadAt == reads.last, "每次读取都带上读取的时间")
    session.close()
    session.reread()
    precondition(session.readCount == 2, "页面关了不再读")
    session.open()
    precondition(session.readCount == 3, "下一次出现再读一次")
  }

  // MARK: 哪些行出现

  static func visibilityTests() {
    let rows = WS2PrivacyData.rows
    let planned = rows.filter { $0.status == "planned" }
    precondition(!planned.isEmpty, "登记表里有 planned 行才有东西可测")

    let hidden = WS2PrivacyVisibility.visibleRows(rows, enabledFeatures: [])
    precondition(hidden.allSatisfy { $0.status != "planned" }, "planned 行默认隐藏")
    precondition(hidden.count == rows.filter { $0.status != "planned" && $0.appearsWith == nil }.count)

    let faceRows: Set<String> = ["bluetooth-presence", "face-identity", "face-quality", "unlock-secret"]
    let withFace = WS2PrivacyVisibility.visibleRows(rows, enabledFeatures: [WS2PrivacyCopy.faceUnlockFeature])
    let added = Set(withFace.map(\.id)).subtracting(hidden.map(\.id))
    precondition(added == faceRows, "刷脸解锁实验打开后，只多出这四行：\(added)")
    for row in withFace where faceRows.contains(row.id) {
      precondition(row.status == "planned", "这四行在登记表里仍是 planned，出现时值固定「还没读」")
    }
    let other = WS2PrivacyVisibility.visibleRows(rows, enabledFeatures: ["不存在的功能"])
    precondition(other.map(\.id) == hidden.map(\.id), "别的功能名不会让它们出现")

    let titles = Set(WS2PrivacyData.groups.map(\.title))
    precondition(withFace.allSatisfy { titles.contains($0.group) }, "每一行都属于已声明的组")
    precondition(WS2PrivacyData.groups.map(\.title) == ["不用问就能读的", "你同意后才读的", "用了系统没公开的方法的", "去了哪里"])
    precondition(Array(WS2PrivacyData.groups.map(\.subtitle).prefix(3))
      == ["系统给每个 App 都开着", "系统会先问你", "Apple 没写进文档，系统更新后可能失效"])
    precondition(WS2PrivacyData.groups.last?.title == WS2PrivacyCopy.destinationGroupTitle)
  }

  // MARK: 一行怎么摆

  static func presentationTests() {
    func row(_ id: String) -> WS2PrivacyRow {
      guard let row = WS2PrivacyData.rows.first(where: { $0.id == id }) else { preconditionFailure("缺 \(id)") }
      return row
    }
    let ax = row("window-ax")
    precondition(ax.permission == "辅助功能")
    let denied = WS2PrivacyRowPresentation.make(row: ax, value: nil, hasValueSource: false, permissionGranted: false)
    precondition(denied.display == .needsGrant, "没授权写去授权")
    precondition(denied.permissionTag == "要“辅助功能”")
    precondition(denied.subtitleLine == "找到、移动和恢复窗口 · 要“辅助功能”", denied.subtitleLine)
    let granted = WS2PrivacyRowPresentation.make(row: ax, value: nil, hasValueSource: false, permissionGranted: true)
    precondition(granted.display == .granted, "已授权且没有别的值，写已授权")

    let battery = row("battery")
    let withValue = WS2PrivacyRowPresentation.make(row: battery, value: "妙控鼠标 82%", hasValueSource: true, permissionGranted: nil)
    precondition(withValue.display == .text("妙控鼠标 82%") && withValue.permissionTag == nil)
    let failed = WS2PrivacyRowPresentation.make(row: battery, value: nil, hasValueSource: true, permissionGranted: nil)
    precondition(failed.display == .text("没读到"), "有来源却没读到，写没读到")
    let noSource = WS2PrivacyRowPresentation.make(row: row("notch-private"), value: nil, hasValueSource: false, permissionGranted: nil)
    precondition(noSource.display == .text(""), "根本没有来源的行什么也不写，不编")

    let cameraRow = row("camera-frame")
    let camera = WS2PrivacyRowPresentation.make(row: cameraRow, value: "没在用", hasValueSource: true, permissionGranted: nil)
    precondition(camera.display == .text("没在用") && camera.permissionTag == "要“摄像头”")

    let plannedRow = row("agent-voice-proof")
    let planned = WS2PrivacyRowPresentation.make(row: plannedRow, value: "不该出现", hasValueSource: true, permissionGranted: false)
    precondition(planned.display == .text("还没读"), "planned 行值固定还没读")

    // 能关的行：开关绑定哪个原设置，登记表里写明。
    let switches = Dictionary(uniqueKeysWithValues: WS2PrivacyData.rows.compactMap { r in r.switchID.map { (r.id, $0) } })
    precondition(switches["recording-app"] == "activities" && switches["music"] == "activities")
    precondition(switches["hinge"] == "desktop" && switches["tilt"] == "desktop")
    precondition(switches["login-item"] == "login" && switches["update"] == "autoUpdate")
    precondition(switches["download-files"] == "downloads")

    var snapshot = WS2PrivacySnapshot()
    snapshot.permissions["辅助功能"] = true
    snapshot.permissions["屏幕录制"] = false
    snapshot.values["battery"] = "妙控鼠标 82%"
    let exported = snapshot.exportValues(rows: WS2PrivacyData.rows)
    precondition(exported["window-ax"] == "已授权" && exported["window-image"] == "未授权", "导出里权限类的行写已授权或未授权")
    precondition(exported["battery"] == "妙控鼠标 82%")
  }

  // MARK: 值怎么写

  static func formatTests() {
    precondition(WS2PrivacyFormat.hinge(desktopEnabled: true, angle: 111.6) == "112°")
    precondition(WS2PrivacyFormat.hinge(desktopEnabled: true, angle: nil) == "没读到")
    precondition(WS2PrivacyFormat.hinge(desktopEnabled: true, angle: .nan) == "没读到")
    precondition(WS2PrivacyFormat.hinge(desktopEnabled: false, angle: 90) == "关着")
    precondition(WS2PrivacyFormat.screen(count: 1, thisScreenHasNotch: true) == "这块屏有刘海")
    precondition(WS2PrivacyFormat.screen(count: 1, thisScreenHasNotch: false) == "这块屏没有刘海")
    precondition(WS2PrivacyFormat.screen(count: 2, thisScreenHasNotch: true) == "2 块屏 · 这块有刘海")
    precondition(WS2PrivacyFormat.screen(count: 1, thisScreenHasNotch: nil) == nil, "不知道就不写")
    precondition(WS2PrivacyFormat.camera(bystanderEnabled: false) == "没在用")
    precondition(WS2PrivacyFormat.music(activitiesEnabled: true, paused: true) == "音乐 · 暂停")
    precondition(WS2PrivacyFormat.music(activitiesEnabled: true, paused: false) == "音乐 · 播放中")
    precondition(WS2PrivacyFormat.music(activitiesEnabled: true, paused: nil) == "没在放")
    precondition(WS2PrivacyFormat.music(activitiesEnabled: false, paused: nil) == "关着")
    precondition(WS2PrivacyFormat.recording(activitiesEnabled: true, title: nil) == "没有 App 在录音")
    precondition(WS2PrivacyFormat.recording(activitiesEnabled: true, title: "语音备忘录") == "语音备忘录")

    func reading(_ id: String, _ percent: Int?, at time: Double) -> BatteryReading {
      BatteryReading(deviceID: id, component: .main, provider: "test", providerEpoch: 1, percent: percent,
                     charging: .unknown, sourceObservedAt: nil, receivedAt: time)
    }
    let mouse = DeviceIdentity(id: "hid.bt:aa", displayName: "妙控鼠标", kind: .mouse)
    let keyboard = DeviceIdentity(id: "hid.bt:bb", displayName: "妙控键盘", kind: .keyboard)
    let mac = DeviceIdentity(id: "mac.internal", displayName: "这台 Mac", kind: .mac)
    let pods = DeviceIdentity(id: "bt:pods", displayName: "AirPods", kind: .headphones)

    var book = DeviceBatteryBook()
    precondition(WS2PrivacyFormat.battery(book: book, now: 100) == "没有连着的配件")
    _ = book.connect(mouse, at: 100, initialSnapshot: true)
    _ = book.record(reading(mouse.id, 82, at: 100), now: 100)
    precondition(WS2PrivacyFormat.battery(book: book, now: 101) == "妙控鼠标 82%", "写原值，不写“读取设备信息”")

    _ = book.connect(pods, at: 100, initialSnapshot: true)
    precondition(WS2PrivacyFormat.battery(book: book, now: 101) == "妙控鼠标 82%", "耳机另有自己的活动，不在这一行")

    _ = book.connect(mac, at: 100, initialSnapshot: true)
    _ = book.record(reading(mac.id, 55, at: 100), now: 100)
    precondition(WS2PrivacyFormat.battery(book: book, now: 101) == "妙控鼠标 82%、这台 Mac 55%", "配件在前，这台 Mac 在后")

    _ = book.connect(keyboard, at: 100, initialSnapshot: true)
    _ = book.record(reading(keyboard.id, 70, at: 100), now: 100)
    precondition(WS2PrivacyFormat.battery(book: book, now: 101) == "妙控键盘 70%、妙控鼠标 82% 等 3 个")

    precondition(WS2PrivacyFormat.battery(book: book, now: 100 + DeviceBatteryBook.freshFor + 60)
      == "妙控键盘 电量暂时读不到、妙控鼠标 电量暂时读不到 等 3 个", "读数太旧不当现在的值写")
    _ = book.disconnect(mouse.id)
    _ = book.disconnect(keyboard.id)
    precondition(WS2PrivacyFormat.battery(book: book, now: 101) == "这台 Mac 55%")
  }

  // MARK: 文案

  static func copyTests() {
    precondition(WS2PrivacyCopy.headerSubtitle(showingNetworkPromise: false)
      == "WindowShade 读到的每一样都列在这里。不收集使用数据，也不做任何统计或上报。")
    precondition(WS2PrivacyCopy.showsNetworkPromise == false, "联网实测之前，“不离开这台 Mac”不上页头")
    precondition(WS2PrivacyCopy.headerSubtitle() == WS2PrivacyCopy.headerLead + WS2PrivacyCopy.noReporting)
    precondition(WS2PrivacyCopy.headerSubtitle(showingNetworkPromise: true)
      == "WindowShade 读到的每一样都列在这里。不收集使用数据，也不做任何统计或上报。除了检查更新，都不离开这台 Mac。")
    precondition(WS2PrivacyCopy.joinSentences(["Listed here.", "No analytics."]) == "Listed here. No analytics.",
                 "英文句子之间留一个空格")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 10, minute: 2))!
    precondition(WS2PrivacyCopy.readAtText(date, timeZone: calendar.timeZone) == "打开这一页时读的 · 10:02")

    let card = WS2PrivacyCopy.networkCard(primaryHost: "windowshade.aaronlau.me", fallbackHost: "github.com")
    precondition(card.body.contains("windowshade.aaronlau.me") && card.body.contains("GitHub"))
    precondition(card.body.contains("关掉“自动检查更新”"))
    precondition(!card.lead.contains("只有"), "联网实测之前不写“只有”")

    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    precondition(WS2PrivacyPlaces.logsDirectory(home: home).path == "/Users/someone/Library/Logs/WindowShade")
    precondition(WS2PrivacyPlaces.preferencesFile(home: home, bundleID: "me.example.app").path
      == "/Users/someone/Library/Preferences/me.example.app.plist")
  }

  /// 登记表生成的、给用户看的字：不许有内部代号，也不许有“待验证”这类自认没核过的句子。
  static func registryTextTests() {
    let forbidden = try! NSRegularExpression(pattern: #"\b(P\d|A2[ab]|IPC|L1|Sparkle)\b|待验证|待核|磁盘行为待"#)
    var texts: [(String, String)] = []
    for row in WS2PrivacyData.rows {
      for (key, value) in [("label", row.label), ("subtitle", row.subtitle), ("reads", row.reads),
                           ("purpose", row.purpose), ("destination", row.destination),
                           ("activation", row.activation), ("toggle", row.toggle), ("combined", row.combined ?? "")] {
        texts.append(("\(row.id).\(key)", value))
      }
      precondition(row.combined?.isEmpty == false, "\(row.id) 缺 combined")
      precondition(!row.subtitle.isEmpty, "\(row.id) 缺一行原因")
      precondition(row.subtitle.count <= 16, "\(row.id) 副标题太长：\(row.subtitle)")
    }
    for group in WS2PrivacyData.groups { texts.append(("group.\(group.title)", group.title + group.subtitle)) }
    for (name, text) in texts {
      let range = NSRange(text.startIndex..., in: text)
      precondition(forbidden.firstMatch(in: text, range: range) == nil, "\(name) 含内部代号或自认没核过的句子：\(text)")
    }
    // 词表：不再出现旧叫法。
    let joined = texts.map(\.1).joined(separator: "\n")
    for old in ["有人偷看时收起", "指挥控制", "自动锁屏"] {
      precondition(!joined.contains(old), "旧叫法没改：\(old)")
    }
    precondition(joined.contains("指挥模式") && joined.contains("离开就锁"))
  }

  /// 页面没有定时器、不轮询：读取只有“出现”和“再读一次”两个入口。
  static func noPollingTests() {
    let path = "prototype/App/WS2PrivacyPane.swift"
    guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
      preconditionFailure("读不到 \(path)；请在仓库根目录运行")
    }
    for token in ["Timer", "scheduledTimer", "DispatchSource", "asyncAfter", "CADisplayLink", "Task.sleep"] {
      precondition(!source.contains(token), "隐私页不该有定时读取：\(token)")
    }
    precondition(source.contains("session.open()") && source.contains("session.reread()") && source.contains("session.close()"))
  }

  // MARK: 旧日志清理

  static func legacyLogTests() throws {
    let manager = FileManager.default
    let base = manager.temporaryDirectory.appendingPathComponent("ws-legacy-log-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: base) }
    let directory = base.path
    let name = "windowshade.log"
    let file = base.appendingPathComponent(name)
    let me = getuid()

    precondition(LegacyLogCleanup.remove(directory: directory, fileName: name, uid: me) == .absent, "没有旧文件就什么也不做")
    precondition(LegacyLogCleanup.remove(directory: directory + "/不存在", fileName: name, uid: me) == .absent)

    try Data("old".utf8).write(to: file)
    precondition(LegacyLogCleanup.remove(directory: directory, fileName: name, uid: me) == .removed)
    precondition(!manager.fileExists(atPath: file.path), "普通文件删掉")

    // 符号链接：拒绝，链接和目标都留着。
    let target = base.appendingPathComponent("target.txt")
    try Data("keep".utf8).write(to: target)
    try manager.createSymbolicLink(at: file, withDestinationURL: target)
    let refusedLink = LegacyLogCleanup.remove(directory: directory, fileName: name, uid: me)
    precondition(refusedLink == .refused("不是普通文件"), "符号链接不删：\(refusedLink)")
    precondition(manager.fileExists(atPath: target.path), "链接指向的文件不能被删")
    precondition((try? manager.destinationOfSymbolicLink(atPath: file.path)) != nil, "链接本身也留着")
    try manager.removeItem(at: file)

    // 不属于当前用户：拒绝。
    try Data("old".utf8).write(to: file)
    let refusedOwner = LegacyLogCleanup.remove(directory: directory, fileName: name, uid: me &+ 1)
    precondition(refusedOwner == .refused("不属于当前用户"), "别人的文件不删：\(refusedOwner)")
    precondition(manager.fileExists(atPath: file.path))
    try manager.removeItem(at: file)

    // 目录：拒绝。
    try manager.createDirectory(at: file, withIntermediateDirectories: false)
    precondition(LegacyLogCleanup.remove(directory: directory, fileName: name, uid: me) == .refused("不是普通文件"))
    try manager.removeItem(at: file)

    // 上一级目录本身是符号链接（/tmp 就是）：照常处理最后的文件名。
    let linkedDirectory = base.appendingPathComponent("linked", isDirectory: true)
    try manager.createSymbolicLink(at: linkedDirectory, withDestinationURL: base)
    try Data("old".utf8).write(to: file)
    precondition(LegacyLogCleanup.remove(directory: linkedDirectory.path, fileName: name, uid: me) == .removed)

    // 只做一次：第一次处理并记下，之后哪怕文件又出现也不再动。
    let suite = "WindowShade.PrivacyPaneTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try Data("old".utf8).write(to: file)
    precondition(LegacyLogCleanup.runOnce(directory: directory, fileName: name, defaults: defaults, uid: me) == .removed)
    try Data("again".utf8).write(to: file)
    precondition(LegacyLogCleanup.runOnce(directory: directory, fileName: name, defaults: defaults, uid: me) == .alreadyDone)
    precondition(manager.fileExists(atPath: file.path), "第二次不再动")

    // 被拒绝的那一次也算做过，不会反复尝试。
    try manager.removeItem(at: file)
    try manager.createSymbolicLink(at: file, withDestinationURL: target)
    let other = UserDefaults(suiteName: suite + ".b")!
    defer { other.removePersistentDomain(forName: suite + ".b") }
    precondition(LegacyLogCleanup.runOnce(directory: directory, fileName: name, defaults: other, uid: me) == .refused("不是普通文件"))
    precondition(LegacyLogCleanup.runOnce(directory: directory, fileName: name, defaults: other, uid: me) == .alreadyDone)
  }
}
