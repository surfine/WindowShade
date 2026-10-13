// 应用内更新：所有用户看得见的句子（按 docs/copy-guide.md 与 docs/update.md 的“文案”一节）。
// 集中在这里，菜单、设置、更新小窗、欢迎窗口和看护用同一份，不出第二种说法。

import Foundation

enum UpdateCopy {
    // 菜单
    static var checkMenu: String { WSL10n.text("update.checkMenu", zh: "检查更新…") }
    static func updateMenu(_ version: String) -> String { WSL10n.text("update.updateMenu", zh: "更新到 %@…", version) }

    // 更新小窗
    static func windowTitle(_ version: String) -> String { WSL10n.text("update.windowTitle", zh: "WindowShade %@", version) }
    static func currentVersion(_ version: String) -> String { WSL10n.text("update.currentVersion", zh: "你现在用的是 %@。", version) }
    static var reminder: String { WSL10n.text("update.reminder", zh: "更新前，窗口会先恢复原样。") }
    static var fullNotes: String { WSL10n.text("update.fullNotes", zh: "看完整更新记录") }
    static var install: String { WSL10n.text("update.install", zh: "更新并重新打开") }
    static var later: String { WSL10n.text("update.later", zh: "稍后再说") }
    static var skip: String { WSL10n.text("update.skip", zh: "跳过这一版") }
    static var retry: String { WSL10n.text("update.retry", zh: "再试一次") }
    static var ok: String { WSL10n.text("update.ok", zh: "好") }
    static var openDownloadPage: String { WSL10n.text("update.openDownloadPage", zh: "打开下载页") }
    static var feedback: String { WSL10n.text("update.feedback", zh: "反馈问题") }

    // 进行中
    static var checking: String { WSL10n.text("update.checking", zh: "正在检查…") }
    static var downloading: String { WSL10n.text("update.downloading", zh: "正在下载…") }
    static var preparing: String { WSL10n.text("update.preparing", zh: "正在准备…") }
    static var relaunching: String { WSL10n.text("update.relaunching", zh: "正在重新打开…") }

    // 结果与原因
    static var upToDate: String { WSL10n.text("update.upToDate", zh: "已经是最新版本。") }
    static var checkFailed: String { WSL10n.text("update.checkFailed", zh: "没能检查更新，稍后再试。") }
    static func updateFailed(_ version: String) -> String { WSL10n.text("update.updateFailed", zh: "没能更新到 %@，稍后再试。", version) }
    static var lowSpace: String { WSL10n.text("update.lowSpace", zh: "Mac 上的空间不够，没能更新。") }
    static func trialFailed(_ version: String) -> String { WSL10n.text("update.trialFailed", zh: "%@ 在这台 Mac 上没能正常打开，所以没有更新。", version) }
    static func refusedBefore(_ version: String) -> String { WSL10n.text("update.refusedBefore", zh: "%@ 上次在这台 Mac 上没能正常打开。", version) }
    static var manualInstall: String { WSL10n.text("update.manualInstall", zh: "这一版要手动安装。装好后，要重新打开辅助功能和屏幕录制。") }
    static var needsMove: String { WSL10n.text("update.needsMove", zh: "先把 WindowShade 移到“应用程序”文件夹，才能更新。") }
    static var needsAdmin: String { WSL10n.text("update.needsAdmin", zh: "要这台 Mac 的管理员来更新。") }
    static var otherUser: String { WSL10n.text("update.otherUser", zh: "这台 Mac 上还有别人开着 WindowShade，等他退出后再更新。") }
    static func installFailed(to: String, from: String) -> String { WSL10n.text("update.installFailed", zh: "没能更新到 %@，还在用 %@。", to, from) }
    static func restored(to: String, from: String) -> String { WSL10n.text("update.restored", zh: "%@ 没能正常打开，已经换回 %@。", to, from) }
    static func restoreFailed(to: String, from: String) -> String { WSL10n.text("update.restoreFailed", zh: "没能换回 %@，还在用 %@。", from, to) }
    static var unsupportedVolume: String { WSL10n.text("update.unsupportedVolume", zh: "这台 Mac 上没法在菜单里更新 WindowShade。到下载页下载新版，拖进“应用程序”文件夹替换原来那一份。") }

    // 设置
    static var settingsGroup: String { WSL10n.text("update.settingsGroup", zh: "更新") }
    static var autoCheck: String { WSL10n.text("update.autoCheck", zh: "自动检查更新") }
    static var autoCheckDetail: String { WSL10n.text("update.autoCheckDetail", zh: "有新版本时在菜单里告诉你，不会自己装。") }
    /// “上次检查：今天 09:40”。昨天写“昨天 09:40”，更早写“10月3日 09:40”。没检查过时不显示（用 autoCheckDetail）。
    static func lastChecked(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: date)
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = WSL10n.text("update.date.today", zh: "今天")
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            day = WSL10n.text("update.date.yesterday", zh: "昨天")
        } else {
            let parts = calendar.dateComponents([.month, .day], from: date)
            day = WSL10n.text("update.date.short", zh: "%@月%@日", String(parts.month ?? 1), String(parts.day ?? 1))
        }
        return WSL10n.text("update.lastChecked", zh: "上次检查：%@ %@", day, time)
    }
    static var frequency: String { WSL10n.text("update.frequency", zh: "检查频率") }
    static var daily: String { WSL10n.text("update.daily", zh: "每天") }
    static var weekly: String { WSL10n.text("update.weekly", zh: "每周") }
    static func currentVersionRow(_ version: String) -> String { WSL10n.text("update.currentVersionRow", zh: "当前版本 %@", version) }
    static var checkButton: String { WSL10n.text("update.checkButton", zh: "检查更新") }
    static var releaseNotes: String { WSL10n.text("update.releaseNotes", zh: "看更新记录") }
    static func rollback(_ version: String) -> String { WSL10n.text("update.rollback", zh: "回到 %@", version) }
    static var rollbackDetail: String { WSL10n.text("update.rollbackDetail", zh: "新版本用着不对，可以换回刚才那一版。") }

    // 欢迎窗口：放进“应用程序”文件夹
    static var moveTitle: String { WSL10n.text("update.moveTitle", zh: "放进“应用程序”文件夹") }
    static var moveLead: String { WSL10n.text("update.moveLead", zh: "Mac 上的 App 都放在这里。放进去以后，才能在菜单里更新 WindowShade。") }
    static var moveButton: String { WSL10n.text("update.moveButton", zh: "移到“应用程序”") }
    static var moveSkip: String { WSL10n.text("update.moveSkip", zh: "跳过") }
    static func moveReplaces(_ version: String) -> String { WSL10n.text("update.moveReplaces", zh: "“应用程序”里的 WindowShade %@ 会换成这一版。", version) }
    static func moveAlreadyThere(_ version: String) -> String { WSL10n.text("update.moveAlreadyThere", zh: "“应用程序”里已经有 WindowShade %@。", version) }
    static var moveOpenIt: String { WSL10n.text("update.moveOpenIt", zh: "打开它") }
    static var moveFailed: String { WSL10n.text("update.moveFailed", zh: "没能移过去。把 WindowShade 拖进“应用程序”文件夹，再从那里打开它。") }
    static var showInFinder: String { WSL10n.text("update.showInFinder", zh: "在访达中显示") }

    // 欢迎窗口：授权页
    static var standardAccount: String { WSL10n.text("update.standardAccount", zh: "打开这两项时，要输入管理员的名字和密码。") }
    static var permissionsAgainTitle: String { WSL10n.text("update.permissionsAgainTitle", zh: "再打开一次这两项") }
    static var permissionsAgainLead: String { WSL10n.text("update.permissionsAgainLead", zh: "装好新版本后，系统要你重新打开辅助功能和屏幕录制。") }
    static var permissionsStuckHint: String { WSL10n.text("update.permissionsStuckHint", zh: "开关开着却没用？在列表里选中 WindowShade，点“−”删掉，再回来点“去授权”。") }
}

enum UpdateLinks {
    /// “打开下载页”固定打开官网下载处，不用清单里的地址。官网要有 id="download" 的那一块。
    static let downloadPage = URL(string: "https://windowshade.aaronlau.me/#download")!
    static let releaseNotes = URL(string: "https://github.com/surfine/WindowShade/releases")!
    /// “反馈问题”打开 GitHub Issues 的新建页，不附带任何数据。
    static let newIssue = URL(string: "https://github.com/surfine/WindowShade/issues/new")!
    /// 官网连不上时，下次改查 GitHub Release 附件里的同一份清单（清单签了名，放哪里都一样）。
    static let fallbackFeed = "https://github.com/surfine/WindowShade/releases/latest/download/appcast.xml"
}
