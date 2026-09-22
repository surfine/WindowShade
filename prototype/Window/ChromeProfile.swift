// 窗口外框画像：Adobe 工作区识别、标准标题栏裁切高度、画像缓存与解析。

import Cocoa

func adobeChromeProfile(for win: AXUIElement,
                        pid: pid_t,
                        title: String? = nil,
                        size: CGSize? = nil) -> AdobeChromeProfile {
    guard isAdobeApp(pid: pid) else { return .none }

    let bundle = appBundleID(pid: pid).lowercased()
    let appName = appDisplayName(pid: pid).lowercased()
    let windowTitle = (title ?? axTitle(win)).lowercased()
    let subrole = axSubrole(win)?.lowercased() ?? ""
    let size = size ?? axSize(win) ?? .zero
    let hasToolbar = firstToolbar(win) != nil
    let hasDocumentishTitle = windowTitle.contains(".psd") ||
        windowTitle.contains(".psb") ||
        windowTitle.contains(".ai") ||
        windowTitle.contains(".ait") ||
        windowTitle.contains(".indd") ||
        windowTitle.contains(".indl") ||
        windowTitle.contains(".pdf") ||
        windowTitle.contains(".aep") ||
        windowTitle.contains(".aet") ||
        windowTitle.contains(".prproj") ||
        windowTitle.contains(".sesx") ||
        windowTitle.contains(".fla")

    let isProductionWorkspace =
        bundle.contains("aftereffects") ||
        bundle.contains("premiere") ||
        bundle.contains("audition") ||
        bundle.contains("mediaencoder") ||
        bundle.contains("animate") ||
        appName.contains("after effects") ||
        appName.contains("premiere") ||
        appName.contains("audition") ||
        appName.contains("media encoder") ||
        appName.contains("animate")

    let isDesignDocumentApp =
        bundle.contains("photoshop") ||
        bundle.contains("illustrator") ||
        bundle.contains("indesign") ||
        appName.contains("photoshop") ||
        appName.contains("illustrator") ||
        appName.contains("indesign")

    // AE/Premiere 的工作区标题总带产品名前缀（"Adobe After Effects 2026 - …"），
    // 独立面板则是 "Effect Controls" / "Timeline: …" 这类裸面板名。
    let titleLooksLikeWorkspace = windowTitle.contains("adobe") || windowTitle.contains(appName)

    // Adobe panels are usually small floating windows owned by the workspace.
    // Default to ignoring them so WindowShade does not fight Adobe's panel/layout system.
    // 注意：AE/Premiere 连主工作区的 subrole 都标成 floating（AX 树非标准），
    // 生产线 app 的工作区窗口（标题带产品名，或带 .aep/.prproj 等工程后缀）
    // 不得落进面板分支，否则整个 app 无法折叠（实测 2026-07）。
    if subrole.contains("floating") && !hasDocumentishTitle &&
        !(isProductionWorkspace && titleLooksLikeWorkspace) {
        return AdobeChromeProfile(kind: .floatingPanel,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: false,
                                  reason: "floating-subrole")
    }
    if !hasDocumentishTitle && size.width > 0 && size.height > 0 &&
        (size.width < 520 || size.height < 260) &&
        (windowTitle.contains("panel") ||
         windowTitle.contains("properties") ||
         windowTitle.contains("effects") ||
         windowTitle.contains("color") ||
         windowTitle.contains("layers") ||
         windowTitle.contains("timeline")) {
        return AdobeChromeProfile(kind: .floatingPanel,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: false,
                                  reason: "panel-like-title")
    }

    // 主屏/欢迎窗口（标题就是产品名、无文稿、无工具栏）：内容紧贴系统标题栏，
    // 没有标签条/工作区 chrome 可保留。按标准标题栏高度裁切——84pt 的文档框
    // 高度在 PS 2026 主屏会把 Ps 头部内容条拼进卷帘条（"灰标题栏+深色头部条"
    // 两截拼接，实测 2026-07）。文档窗口标题都带文件名/缩放比等后缀，不会误中。
    let titleIsBareProductName = windowTitle.isEmpty || windowTitle == appName
    if titleIsBareProductName && !hasDocumentishTitle && !hasToolbar {
        return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                                  preservedChromeHeight: titleBarHeight,
                                  hitChromeHeight: titleBarHeight,
                                  canShade: true,
                                  reason: "home-screen")
    }

    if isProductionWorkspace {
        // AE / Premiere 用实测的专属裁切高度；其余生产线 app（Audition 等）
        // 未实测，沿用通用值。hit 高度与裁切一致：可见 chrome 即双击折叠带。
        let isPremiere = bundle.contains("premiere") || appName.contains("premiere")
        let isAfterEffects = bundle.contains("aftereffects") || appName.contains("after effects")
        let base: CGFloat = isPremiere ? premiereWorkspaceChromeHeight
            : (isAfterEffects ? afterEffectsWorkspaceChromeHeight : adobeApplicationFrameChromeHeight)
        let h = min(max(base, titleBarHeight), max(titleBarHeight, size.height))
        return AdobeChromeProfile(kind: .applicationFrame,
                                  preservedChromeHeight: h,
                                  hitChromeHeight: h,
                                  canShade: true,
                                  reason: "production-workspace")
    }

    if isDesignDocumentApp {
        if subrole.contains("standard") && hasDocumentishTitle && !hasToolbar {
            let h = min(max(adobeFloatingDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
            return AdobeChromeProfile(kind: .floatingDocumentWindow,
                                      preservedChromeHeight: h,
                                      hitChromeHeight: h,
                                      canShade: true,
                                      reason: "floating-document-title")
        }

        let h = min(max(adobeTabbedDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
        return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                                  preservedChromeHeight: h,
                                  hitChromeHeight: h,
                                  canShade: true,
                                  reason: "design-tabbed-frame")
    }

    let h = min(max(adobeTabbedDocumentChromeHeight, titleBarHeight), max(titleBarHeight, size.height))
    return AdobeChromeProfile(kind: .tabbedDocumentFrame,
                              preservedChromeHeight: h,
                              hitChromeHeight: h,
                              canShade: true,
                              reason: "generic-adobe-frame")
}

func standardTitleBarCropHeight(of win: AXUIElement,
                                winTop: CGFloat,
                                winSize: CGSize,
                                trafficPaddedHeight: CGFloat? = nil) -> CGFloat {
    let padded = trafficPaddedHeight ?? trafficLightPaddedHeight(of: win, winTop: winTop) ?? titleBarHeight
    return min(max(titleBarHeight, padded), min(winSize.height, standardTitleBarMaxCropHeight))
}

func windowLooksToolbarlessStandardTitleBar(_ win: AXUIElement,
                                            winTop: CGFloat,
                                            winSize: CGSize,
                                            pid: pid_t,
                                            hasToolbar: Bool? = nil,
                                            trafficLightHeight precomputedTrafficH: CGFloat? = nil,
                                            adobeProfile: AdobeChromeProfile? = nil,
                                            trafficLights: ProxyTrafficLightConfiguration? = nil) -> Bool {
    let hasToolbar = hasToolbar ?? (firstToolbar(win) != nil)
    guard !hasToolbar else { return false }
    guard !needsControlPaddedChrome(pid: pid) else { return false }

    let adobeProfile = adobeProfile ?? adobeChromeProfile(for: win, pid: pid, size: winSize)
    guard adobeProfile.kind == .none else { return false }

    let trafficLights = trafficLights ?? proxyTrafficLightConfiguration(of: win, pid: pid)
    guard trafficLights.style != .quickLook else { return false }

    guard let trafficH = precomputedTrafficH ?? trafficLightHeight(of: win, winTop: winTop),
          trafficH > 0,
          trafficH <= 40 else { return false }
    return true
}

// 折叠/双击热路径的 chrome profile 缓存：同一窗口在短 TTL 内反复折叠，或双击
// 判定的第一下/第二下，都会重复执行同一批昂贵 AX IPC（firstToolbar、交通灯高度、
// 深度 6 的整棵 AX 子树控件扫描）。以「窗口 ID + AX 元素身份 + 窗口尺寸」为
// 失效条件：ID 被复用、元素被重建、窗口被拖拽改尺寸都立即重算。
// 只能在主线程访问（事件 tap 回调、shade、双击判定全部在主线程执行）。
final class ChromeProfileCache {
    static let shared = ChromeProfileCache()

    private struct Entry {
        let element: AXUIElement
        let profile: WindowChromeProfile
        let size: CGSize
        let resolvedAt: CFAbsoluteTime
    }

    private var entries: [CGWindowID: Entry] = [:]
    private let ttl: TimeInterval = 2.0
    private let sizeTolerance: CGFloat = 0.5
    private let maxEntries = 64

    func profile(id: CGWindowID, win: AXUIElement, pos: CGPoint, size: CGSize,
                 pid: pid_t, title: String) -> WindowChromeProfile {
        if let entry = entries[id], isFresh(entry, id: id, win: win, size: size) {
            return entry.profile
        }
        let resolved = resolveWindowChromeProfileUncached(win: win, id: id, pos: pos,
                                                          size: size, pid: pid, title: title,
                                                          localChromeHeight: localWindowChromeHeight(id: id, pid: pid))
        entries[id] = Entry(element: win, profile: resolved, size: size,
                            resolvedAt: CFAbsoluteTimeGetCurrent())
        pruneIfNeeded()
        return resolved
    }

    // 双击判定只需要标题栏命中高度：profile 新鲜时直接返回，第二次点击不必再
    // 付一次完整的 chrome 解析。
    // 并发预热。外框解析全是只读 AX 调用（工具栏探测、红绿灯几何、标题栏高度），
    // 各窗口之间互不相干，实测每个窗口约 70ms、批量折叠时是最大的一块。
    // 先在后台并发把 profile 算好，再回到主线程一次性写入——entries 本身没有锁，
    // 仍然保持只在主线程读写这一点不变。
    @discardableResult
    func prewarm(
        _ requests: [(id: CGWindowID, win: AXUIElement, pos: CGPoint,
                      size: CGSize, pid: pid_t, title: String)]
    ) -> [CGWindowID: WindowChromeProfile] {
        guard requests.count > 1 else { return [:] }
        var resolved = [WindowChromeProfile?](repeating: nil, count: requests.count)
        // Snapshot AppKit geometry before entering the concurrent AX reads.
        let localHeights = requests.map { localWindowChromeHeight(id: $0.id, pid: $0.pid) }
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: requests.count) { index in
            let request = requests[index]
            let profile = resolveWindowChromeProfileUncached(
                win: request.win, id: request.id, pos: request.pos,
                size: request.size, pid: request.pid, title: request.title,
                localChromeHeight: localHeights[index])
            lock.lock()
            resolved[index] = profile
            lock.unlock()
        }
        let now = CFAbsoluteTimeGetCurrent()
        var warmed: [CGWindowID: WindowChromeProfile] = [:]
        for (index, request) in requests.enumerated() {
            guard let profile = resolved[index] else { continue }
            entries[request.id] = Entry(element: request.win, profile: profile,
                                        size: request.size, resolvedAt: now)
            warmed[request.id] = profile
        }
        pruneIfNeeded()
        return warmed
    }

    func cachedHitBarHeight(id: CGWindowID, win: AXUIElement, size: CGSize) -> CGFloat? {
        guard let entry = entries[id], isFresh(entry, id: id, win: win, size: size) else { return nil }
        return entry.profile.hitBarHeight
    }

    private func isFresh(_ entry: Entry, id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {
        CFAbsoluteTimeGetCurrent() - entry.resolvedAt < ttl
            && CFEqual(win, entry.element)
            && abs(size.width - entry.size.width) <= sizeTolerance
            && abs(size.height - entry.size.height) <= sizeTolerance
    }

    private func pruneIfNeeded() {
        guard entries.count > maxEntries else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // 先按 TTL 清掉过期项；仍超限（短时间大量不同窗口）就丢最旧的一个。
        entries = entries.filter { now - $0.value.resolvedAt < ttl }
        while entries.count > maxEntries {
            guard let oldest = entries.min(by: { $0.value.resolvedAt < $1.value.resolvedAt }) else { break }
            entries.removeValue(forKey: oldest.key)
        }
    }
}

func resolveWindowChromeProfile(win: AXUIElement, id: CGWindowID,
                                pos: CGPoint,
                                size: CGSize,
                                pid: pid_t,
                                title: String) -> WindowChromeProfile {
    ChromeProfileCache.shared.profile(id: id, win: win, pos: pos, size: size, pid: pid, title: title)
}

private func localWindowChromeHeight(id: CGWindowID, pid: pid_t) -> CGFloat? {
    dispatchPrecondition(condition: .onQueue(.main))
    guard pid == ProcessInfo.processInfo.processIdentifier,
          let window = NSApp.windows.first(where: { $0.windowNumber == Int(id) }),
          window.styleMask.contains(.titled) else { return nil }
    // AX can omit our own toolbar and traffic lights. AppKit provides the
    // actual unobscured content boundary, including a unified toolbar.
    let content = window.convertToScreen(window.contentLayoutRect)
    return max(0, window.frame.maxY - content.maxY)
}

private func resolveWindowChromeProfileUncached(win: AXUIElement,
                                                id: CGWindowID,
                                                pos: CGPoint,
                                                size: CGSize,
                                                pid: pid_t,
                                                title: String,
                                                localChromeHeight: CGFloat? = nil) -> WindowChromeProfile {
    let hasToolbar = firstToolbar(win) != nil
    let trafficH = trafficLightHeight(of: win, winTop: pos.y)
    let adobeProfile = adobeChromeProfile(for: win, pid: pid, title: title, size: size)
    let trafficLights = proxyTrafficLightConfiguration(of: win, pid: pid)
    let preciseChrome = needsControlPaddedChrome(pid: pid)
    let toolbarlessStandardTitleBar = windowLooksToolbarlessStandardTitleBar(
        win,
        winTop: pos.y,
        winSize: size,
        pid: pid,
        hasToolbar: hasToolbar,
        trafficLightHeight: trafficH,
        adobeProfile: adobeProfile,
        trafficLights: trafficLights
    )
    let standardTitleBarOnly = localChromeHeight == nil &&
        (usesStandardTitleBarOnly(pid: pid) || toolbarlessStandardTitleBar)
    let hasContentBelowTitleBar = !standardTitleBarOnly && size.width > 0 &&
        hasContentControlsBelowTitleBar(win, winTop: pos.y, winSize: size, titleBarBottom: trafficH)
    let standardCropH = standardTitleBarCropHeight(of: win, winTop: pos.y, winSize: size)
    let axBarH = localChromeHeight ?? (standardTitleBarOnly
        ? standardCropH
        : chromeHeight(of: win, winTop: pos.y, winSize: size, pid: pid))
    let hitBarH = localChromeHeight ?? (standardTitleBarOnly
        ? standardCropH
        : titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid))

    return WindowChromeProfile(hasToolbar: hasToolbar,
                               trafficLightHeight: trafficH,
                               adobeProfile: adobeProfile,
                               trafficLights: trafficLights,
                               preciseChrome: preciseChrome,
                               toolbarlessStandardTitleBar: toolbarlessStandardTitleBar,
                               standardTitleBarOnly: standardTitleBarOnly,
                               hasContentBelowTitleBar: hasContentBelowTitleBar,
                               standardCropHeight: standardCropH,
                               axBarHeight: axBarH,
                               hitBarHeight: hitBarH)
}
