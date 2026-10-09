import Foundation

// 设置里“隐私”一栏的纯逻辑：文案常量、哪些行该出现、一行怎么摆、值怎么写、读取次数。
// 不碰界面，也不读系统状态：现读的值由 WS2PrivacyPane.swift 取了传进来，这里只负责摆放和措辞，
// 所以能脱离整个 App 单独编译和测试（tests/run-privacy-pane-tests.sh）。

/// 页头和页面上固定的几句话。
enum WS2PrivacyCopy {
    static let headerLead = "WindowShade 读到的每一样都列在这里。"
    /// 第二句承诺。要等联网实测（nettop，见设备清单）核过才能说，在那之前保持 false。
    static let showsNetworkPromise = false
    static let networkPromise = "除了检查更新，都不离开这台 Mac。"

    static func headerSubtitle(showingNetworkPromise: Bool = showsNetworkPromise) -> String {
        showingNetworkPromise ? headerLead + networkPromise : headerLead
    }

    static let readAtPrefix = "打开这一页时读的 · "
    static let rereadTitle = "再读一次"
    static let showDetailsTitle = "显示技术细节"
    static let exportTitle = "导出…"
    /// 读不到时写的字，不编一个值。
    static let notRead = "没读到"
    static let planned = "还没读"
    static let granted = "已授权"
    static let needsGrant = "去授权"
    static let showInFinder = "在访达中显示"
    static let destinationGroupTitle = "去了哪里"

    /// 刷脸解锁实验打开后才出现的几行（bluetooth-presence、face-identity、unlock-secret）。
    static let faceUnlockFeature = "face-unlock-experiment"

    static func readAtText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return readAtPrefix + formatter.string(from: date)
    }

    /// 行上副标题后面的标签：要“辅助功能”。
    static func permissionTag(_ permission: String) -> String { "要“\(permission)”" }

    /// “去了哪里”里联网那张卡：写明问谁、不通时问谁、怎么让它不联网。
    static func networkCard(primaryHost: String, fallbackHost: String) -> (lead: String, body: String) {
        ("检查更新会联网。",
         "问 \(primaryHost) 有没有新版本，带上现在的版本号；那里不通时改问 GitHub（\(fallbackHost)）。"
         + "关掉“自动检查更新”，就不会自己联网检查。")
    }

    static let storageCard = (
        lead: "存在这台 Mac 上的：",
        body: "你的设置；收起的窗口的标题和位置（恢复记录），出问题时靠它把窗口找回来；运行记录，出问题时用来查原因。")
}

/// “在访达中显示”要打开的两处：运行记录文件夹和设置文件所在的目录。
enum WS2PrivacyPlaces {
    static func logsDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/WindowShade", isDirectory: true)
    }

    static func preferencesFile(home: URL, bundleID: String) -> URL {
        home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
    }
}

/// 这一页打开时读到的一份快照。整页只用这一份，不边画边读。
struct WS2PrivacySnapshot {
    /// 以行 id 为键的现在的值；读不到的行没有键。
    var values: [String: String] = [:]
    /// 系统授权的状态，键是授权名（辅助功能、屏幕录制）；没有键表示这里查不到。
    var permissions: [String: Bool] = [:]
    /// 现在打开着的、会让 planned 行出现的功能。
    var features: Set<String> = []

    /// 导出用的值：权限类的行写已授权或未授权，和导出一直以来的写法一致。
    func exportValues(rows: [WS2PrivacyRow]) -> [String: String] {
        var result = values
        for row in rows where result[row.id] == nil {
            guard let permission = row.permission, let granted = permissions[permission] else { continue }
            result[row.id] = granted ? WS2PrivacyCopy.granted : "未授权"
        }
        return result
    }
}

enum WS2PrivacyVisibility {
    /// planned 的行默认不显示；写了 appearsWith 的，对应功能打开后才出现。
    static func visibleRows(_ rows: [WS2PrivacyRow], enabledFeatures: Set<String>) -> [WS2PrivacyRow] {
        rows.filter { row in
            if let feature = row.appearsWith { return enabledFeatures.contains(feature) }
            return row.status != "planned"
        }
    }
}

/// 右边那一格：一段文字、已授权标签，或可点的去授权。
enum WS2PrivacyValueDisplay: Equatable {
    case text(String)
    case granted
    case needsGrant
}

struct WS2PrivacyRowPresentation: Equatable {
    let title: String
    let reason: String
    let permissionTag: String?
    let display: WS2PrivacyValueDisplay

    /// 副标题那一行：原因，要授权的话后面跟标签。
    var subtitleLine: String {
        guard let permissionTag else { return reason }
        return reason.isEmpty ? permissionTag : reason + " · " + permissionTag
    }

    /// - Parameters:
    ///   - value: 这一行现读到的值；没有就是 nil。
    ///   - hasValueSource: 这一行有没有能现读的值。有来源却没读到写「没读到」；根本没有来源就什么也不写，不编。
    ///   - permissionGranted: 这一行要的系统授权现在给没给；查不到就是 nil。
    static func make(row: WS2PrivacyRow, value: String?, hasValueSource: Bool,
                     permissionGranted: Bool?) -> WS2PrivacyRowPresentation {
        let tag = row.permission.map(WS2PrivacyCopy.permissionTag)
        let display: WS2PrivacyValueDisplay
        if row.status == "planned" {
            display = .text(WS2PrivacyCopy.planned)
        } else if permissionGranted == false {
            display = .needsGrant
        } else if let value {
            display = .text(value)
        } else if permissionGranted == true {
            display = .granted
        } else {
            display = .text(hasValueSource ? WS2PrivacyCopy.notRead : "")
        }
        return WS2PrivacyRowPresentation(title: row.label, reason: row.subtitle, permissionTag: tag, display: display)
    }
}

/// 值的措辞。输入都是已经读到的事实，这里只决定怎么写。
enum WS2PrivacyFormat {
    static func screen(count: Int, thisScreenHasNotch: Bool?) -> String? {
        guard let thisScreenHasNotch else { return nil }
        let notch = thisScreenHasNotch ? "有刘海" : "没有刘海"
        return count > 1 ? "\(count) 块屏 · 这块\(notch)" : "这块屏\(notch)"
    }

    static func hinge(desktopEnabled: Bool, angle: Double?) -> String {
        guard desktopEnabled else { return "关着" }
        guard let angle, angle.isFinite else { return WS2PrivacyCopy.notRead }
        return "\(Int(angle.rounded()))°"
    }

    static func onOff(_ on: Bool) -> String { on ? "开着" : "关着" }

    /// 相机：“有人在看时收起私人窗口”开着时，解锁期间会用相机；其余时候没在用。
    static func camera(bystanderEnabled: Bool) -> String {
        bystanderEnabled ? "解锁时在用" : "没在用"
    }

    static func music(activitiesEnabled: Bool, paused: Bool?) -> String {
        guard activitiesEnabled else { return "关着" }
        guard let paused else { return "没在放" }
        return paused ? "音乐 · 暂停" : "音乐 · 播放中"
    }

    static func recording(activitiesEnabled: Bool, title: String?) -> String {
        guard activitiesEnabled else { return "关着" }
        return title ?? "没有 App 在录音"
    }

    /// 配件电量：先排配件，再排这台 Mac；最多写两个，其余写“等 N 个”。耳机另有自己的活动，不在这里。
    static func battery(book: DeviceBatteryBook, now: Double) -> String {
        let main = book.rows(now: now).filter { $0.component == .main }
        let listed: [(name: String, isMac: Bool, row: BatterySourceRow)] = main.compactMap { row in
            guard book.connected.contains(row.deviceID), let device = book.devices[row.deviceID],
                  device.kind != .headphones else { return nil }
            return (device.displayName, device.kind == .mac, row)
        }.sorted { lhs, rhs in
            if lhs.isMac != rhs.isMac { return !lhs.isMac }
            return lhs.name == rhs.name ? lhs.row.deviceID < rhs.row.deviceID : lhs.name < rhs.name
        }
        guard !listed.isEmpty else { return "没有连着的配件" }
        func text(_ item: (name: String, isMac: Bool, row: BatterySourceRow)) -> String {
            if item.row.presence == .connected, let percent = item.row.percent { return "\(item.name) \(percent)%" }
            return "\(item.name) \(DeviceBatteryCopy.percentUnavailable)"
        }
        let shown = listed.prefix(2).map(text).joined(separator: "、")
        let rest = listed.count - 2
        return rest > 0 ? "\(shown) 等 \(listed.count) 个" : shown
    }
}

/// 一次“打开这一页”的读取账：打开时读一次，按“再读一次”再读一次，页面关了就不再读。
/// 没有定时器，也不轮询：除了这两个入口，没有任何地方会触发读取。
@MainActor
final class WS2PrivacyReadSession {
    private(set) var readCount = 0
    private(set) var lastReadAt: Date?
    private(set) var isOpen = false
    /// 每次读取时调用，参数是读取的时间。
    var onRead: (@MainActor (Date) -> Void)?
    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    /// 页面出现。已经打开着就什么也不做（同一次出现里反复布局不会重读）。
    func open() {
        guard !isOpen else { return }
        isOpen = true
        performRead()
    }

    /// “再读一次”。页面关着时不读。
    func reread() {
        guard isOpen else { return }
        performRead()
    }

    /// 页面关了或离开：之后不再读，直到下一次出现。
    func close() {
        isOpen = false
    }

    private func performRead() {
        readCount += 1
        let date = clock()
        lastReadAt = date
        onRead?(date)
    }
}
