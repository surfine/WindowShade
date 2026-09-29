// 应用内更新：所有用户看得见的句子（按 docs/copy-guide.md 与 docs/update.md 的“文案”一节）。
// 集中在这里，菜单、设置、更新小窗、欢迎窗口和看护用同一份，不出第二种说法。

import Foundation

enum UpdateCopy {
    // 菜单
    static let checkMenu = "检查更新…"
    static func updateMenu(_ version: String) -> String { "更新到 \(version)…" }

    // 更新小窗
    static func windowTitle(_ version: String) -> String { "WindowShade \(version)" }
    static func currentVersion(_ version: String) -> String { "你现在用的是 \(version)。" }
    static let reminder = "更新前，窗口会先恢复原样。"
    static let fullNotes = "看完整更新记录"
    static let install = "更新并重新打开"
    static let later = "稍后再说"
    static let skip = "跳过这一版"
    static let retry = "再试一次"
    static let ok = "好"
    static let openDownloadPage = "打开下载页"
    static let feedback = "反馈问题"

    // 进行中
    static let checking = "正在检查…"
    static let downloading = "正在下载…"
    static let preparing = "正在准备…"
    static let relaunching = "正在重新打开…"

    // 结果与原因
    static let upToDate = "已经是最新版本。"
    static let checkFailed = "没能检查更新，稍后再试。"
    static func updateFailed(_ version: String) -> String { "没能更新到 \(version)，稍后再试。" }
    static let lowSpace = "Mac 上的空间不够，没能更新。"
    static func trialFailed(_ version: String) -> String { "\(version) 在这台 Mac 上没能正常打开，所以没有更新。" }
    static func refusedBefore(_ version: String) -> String { "\(version) 上次在这台 Mac 上没能正常打开。" }
    static let manualInstall = "这一版要手动安装。装好后，要重新打开辅助功能和屏幕录制。"
    static let needsMove = "先把 WindowShade 移到“应用程序”文件夹，才能更新。"
    static let needsAdmin = "要这台 Mac 的管理员来更新。"
    static let otherUser = "这台 Mac 上还有别人开着 WindowShade，等他退出后再更新。"
    static func installFailed(to: String, from: String) -> String { "没能更新到 \(to)，还在用 \(from)。" }
    static func restored(to: String, from: String) -> String { "\(to) 没能正常打开，已经换回 \(from)。" }
    static func restoreFailed(to: String, from: String) -> String { "没能换回 \(from)，还在用 \(to)。" }
    static let unsupportedVolume = "这台 Mac 上没法在菜单里更新 WindowShade。到下载页下载新版，拖进“应用程序”文件夹替换原来那一份。"

    // 设置
    static let settingsGroup = "更新"
    static let autoCheck = "自动检查更新"
    static let autoCheckDetail = "有新版本时在菜单里告诉你，不会自己装。"
    static let frequency = "检查频率"
    static let daily = "每天"
    static let weekly = "每周"
    static func currentVersionRow(_ version: String) -> String { "当前版本 \(version)" }
    static let checkButton = "检查更新"
    static let releaseNotes = "看更新记录"
    static func rollback(_ version: String) -> String { "回到 \(version)" }
    static let rollbackDetail = "新版本用着不对，可以换回刚才那一版。"

    // 欢迎窗口：放进“应用程序”文件夹
    static let moveTitle = "放进“应用程序”文件夹"
    static let moveLead = "Mac 上的 App 都放在这里。放进去以后，才能在菜单里更新 WindowShade。"
    static let moveButton = "移到“应用程序”"
    static let moveSkip = "跳过"
    static func moveReplaces(_ version: String) -> String { "“应用程序”里的 WindowShade \(version) 会换成这一版。" }
    static func moveAlreadyThere(_ version: String) -> String { "“应用程序”里已经有 WindowShade \(version)。" }
    static let moveOpenIt = "打开它"
    static let moveFailed = "没能移过去。把 WindowShade 拖进“应用程序”文件夹，再从那里打开它。"
    static let showInFinder = "在访达中显示"

    // 欢迎窗口：授权页
    static let standardAccount = "打开这两项时，要输入管理员的名字和密码。"
    static let permissionsAgainTitle = "再打开一次这两项"
    static let permissionsAgainLead = "装好新版本后，系统要你重新打开辅助功能和屏幕录制。"
    static let permissionsStuckHint = "开关开着却没用？在列表里选中 WindowShade，点“−”删掉，再回来点“去授权”。"
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
