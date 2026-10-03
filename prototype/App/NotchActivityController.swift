import Cocoa
import MapKit

/// Owns the five source lifetimes. The UI never reads devices, runs scripts or calculates routes.
@MainActor
final class NotchActivityController: NSObject, NSSharingServiceDelegate {
    nonisolated static let enabledKey = "Notch.activitiesEnabled"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    var onChange: (([NotchActivity], String?) -> Void)?
    var ws2FocusAction: ((NotchActivityAction) -> Void)?
    func ws2PublishFocus(title: String?, subtitle: String = "", paused: Bool = false, progress: Double? = nil) {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if let title {
            put(id: "ws2.focus", kind: .focus, title: title, subtitle: subtitle, symbol: "timer", progress: progress, paused: paused)
        } else if let old = store.activities.first(where: { $0.id == "ws2.focus" }) {
            store.end(id: old.id, generation: old.generation, now: ProcessInfo.processInfo.systemUptime)
        }
        publish()
    }
    private(set) var store = NotchActivityStore()
    private let sources = NotchActivitySources()
    private var generation: UInt64 = 0
    private var running = false
    private var expiry: Timer?
    private var operationEpoch = 0
    private var choosingFiles = false
    private var sharing: NSSharingService?
    private var routeTask: Task<Void, Never>?
    private var routeEpoch = 0
    private var routeItems: [MKMapItem] = []
    private var observers: [NSObjectProtocol] = []
    private var lastVisible: [NotchActivity] = []
    private var lastSelection: String?
    private var suspensions: Set<String> = []
    private var suspended: Bool { !suspensions.isEmpty }

    override init() {
        super.init()
        sources.onSnapshot = { [weak self] items in self?.receive(items) }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "sleep"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "sleep"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume(reason) }
            })
        }
        for (name, lock) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if lock { self?.suspend("lock") } else { self?.resume("lock") } }
            })
        }
    }

    func configure() {
        guard Self.isEnabled, !suspended else { stop(); return }
        guard !running else { return }
        running = true
        sources.start()
        expiry = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.prune(now: ProcessInfo.processInfo.systemUptime); self?.publish() }
        }
        if let expiry { RunLoop.main.add(expiry, forMode: .common) }
    }

    private func suspend(_ reason: String) { suspensions.insert(reason); stop() }
    private func resume(_ reason: String) { suspensions.remove(reason); configure() }
    private func stop() {
        running = false; operationEpoch += 1; choosingFiles = false
        sources.stop()
        expiry?.invalidate(); expiry = nil
        routeEpoch += 1; routeTask?.cancel(); routeTask = nil; routeItems = []
        sharing?.delegate = nil; sharing = nil
        store = NotchActivityStore()
        publish()
    }

    func select(_ id: String) { if store.select(id: id) { publish() } }
    func move(_ delta: Int) { store.moveSelection(by: delta); publish() }

    private func receive(_ items: [NotchSourceSnapshot]) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for kind in [NotchActivityKind.music, .airPods, .recording] {
            let id = "source.\(kind.rawValue)"
            if let item = items.first(where: { $0.kind == kind }) {
                put(id: id, kind: kind, title: item.title, subtitle: item.subtitle, symbol: item.symbol,
                    progress: item.progress, paused: item.isPaused, detail: item.detail, now: now)
            } else if let old = store.activities.first(where: { $0.id == id }) {
                store.end(id: id, generation: old.generation, now: now)
            }
        }
        publish()
    }

    private func put(id: String, kind: NotchActivityKind, title: String, subtitle: String,
                     symbol: String, progress: Double? = nil, paused: Bool = false, detail: String = "",
                     expires: Double? = nil, now: Double = ProcessInfo.processInfo.systemUptime) {
        let old = store.activities.first { $0.id == id }
        if old == nil { generation += 1 }
        store.upsert(NotchActivity(id: id, generation: old?.generation ?? generation, kind: kind,
                                  title: title, subtitle: subtitle, symbol: symbol,
                                  startedAt: old?.startedAt ?? now, updatedAt: now, expiresAt: expires,
                                  progress: progress, isPaused: paused, detail: detail), now: now)
    }

    private func publish() {
        if store.selected == nil, let first = store.visible.first { store.select(id: first.id) }
        let visible = store.visible
        // A poll with unchanged metadata does not cause a compositor transaction.
        func equivalent(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
            a.id == b.id && a.generation == b.generation && a.title == b.title && a.subtitle == b.subtitle
                && a.symbol == b.symbol && a.progress == b.progress && a.isPaused == b.isPaused && a.detail == b.detail
        }
        guard lastVisible.count != visible.count || !zip(lastVisible, visible).allSatisfy({ equivalent($0, $1) })
                || lastSelection != store.selectedID else { return }
        lastVisible = visible; lastSelection = store.selectedID
        onChange?(visible, store.selectedID)
    }

    func perform(_ action: NotchActivityAction) {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if store.selected?.kind == .focus && [.open, .end, .focusTogglePause, .focusSkip].contains(action) {
            ws2FocusAction?(action); return
        }
        switch action {
        case .focusOpen: ws2FocusAction?(.focusOpen)
        case .focusTogglePause, .focusSkip: return
        case .enableMusic: sources.enableMusic()
        case .playPause: sources.musicCommand(.playPause)
        case .previous: sources.musicCommand(.previous)
        case .next: sources.musicCommand(.next)
        case .airDrop: chooseFiles()
        case .route: chooseRoute()
        case .voiceMemos: openApp("com.apple.VoiceMemos")
        case .end:
            guard let selected = store.selected, selected.kind == .route else { return }
            routeEpoch += 1; routeTask?.cancel(); routeTask = nil; routeItems = []
            store.end(id: selected.id, generation: selected.generation, now: ProcessInfo.processInfo.systemUptime)
            publish()
        case .open:
            guard let selected = store.selected else { return }
            switch selected.kind {
            case .focus: return
            case .music: openApp(selected.detail)
            case .recording: openApp("com.apple.VoiceMemos")
            case .route: if !routeItems.isEmpty { MKMapItem.openMaps(with: routeItems, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) }
            case .airPods: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            case .airDrop:
                let app = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
                NSWorkspace.shared.openApplication(at: app, configuration: .init())
            }
        }
    }

    private func openApp(_ id: String) {
        guard ["com.apple.Music", "com.spotify.client", "com.apple.VoiceMemos"].contains(id),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func chooseFiles() {
        guard sharing == nil, !choosingFiles else { return }
        choosingFiles = true
        let epoch = operationEpoch
        let picker = NSOpenPanel()
        picker.title = "隔空投送"; picker.prompt = "选择文件"
        picker.allowsMultipleSelection = true; picker.canChooseDirectories = true
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, self.operationEpoch == epoch else { return }
                self.choosingFiles = false
                guard response == .OK, self.running, !picker.urls.isEmpty else { return }
                guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: picker.urls) else {
                    self.put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送", subtitle: "隔空投送暂时不可用",
                             symbol: "airdrop", expires: ProcessInfo.processInfo.systemUptime + 6)
                    self.publish(); return
                }
                self.sharing = service; service.delegate = self
                self.put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送",
                         subtitle: "\(picker.urls.count) 个文件", symbol: "airdrop", detail: "在隔空投送中选择接收设备")
                self.publish()
                service.perform(withItems: picker.urls)
            }
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharing === sharingService else { return }
        finishShare("分享完成")
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard sharing === sharingService else { return }
        finishShare((error as NSError).code == NSUserCancelledError ? "已取消" : "没能完成分享")
    }
    private func finishShare(_ text: String) {
        put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送", subtitle: text,
            symbol: text == "分享完成" ? "checkmark.circle.fill" : "airdrop", expires: ProcessInfo.processInfo.systemUptime + 4)
        sharing?.delegate = nil; sharing = nil; publish()
    }

    private func chooseRoute() {
        let epoch = operationEpoch
        let dialog = NSAlert()
        dialog.messageText = "查看路线"
        dialog.informativeText = "输入出发地和目的地。"
        dialog.addButton(withTitle: "查找路线"); dialog.addButton(withTitle: "取消")
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 66))
        let start = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 26))
        let end = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        start.placeholderString = "出发地"; end.placeholderString = "目的地"
        form.addSubview(start); form.addSubview(end); dialog.accessoryView = form
        // Native modal panels keep the event loop running; no synchronous route I/O here.
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let from = start.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = end.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, running, operationEpoch == epoch else { return }
        calculateRoute(from: from, to: to)
    }

    private func calculateRoute(from: String, to: String) {
        routeEpoch += 1
        let epoch = routeEpoch
        routeTask?.cancel(); routeItems = []
        put(id: "owned.route", kind: .route, title: to, subtitle: "正在查找路线", symbol: "map.fill")
        publish()
        routeTask = Task { [weak self] in
            do {
                let first = MKLocalSearch.Request(); first.naturalLanguageQuery = from
                let second = MKLocalSearch.Request(); second.naturalLanguageQuery = to
                let source = try await MKLocalSearch(request: first).start()
                try Task.checkCancellation()
                let destination = try await MKLocalSearch(request: second).start()
                try Task.checkCancellation()
                guard let a = source.mapItems.first, let b = destination.mapItems.first else { throw CocoaError(.fileReadUnknown) }
                let request = MKDirections.Request(); request.source = a; request.destination = b; request.transportType = .automobile
                let directions = try await MKDirections(request: request).calculate()
                try Task.checkCancellation()
                guard let self, self.running, self.routeEpoch == epoch, let route = directions.routes.first else { return }
                self.routeItems = [a, b]
                let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
                let distance = String(format: "%.1f 公里", route.distance / 1000)
                self.put(id: "owned.route", kind: .route, title: b.name ?? to,
                         subtitle: "预计 \(minutes) 分钟 · \(distance)", symbol: "car.fill", detail: "在地图中打开路线")
                self.publish()
            } catch {
                guard let self, self.running, self.routeEpoch == epoch, !Task.isCancelled else { return }
                self.put(id: "owned.route", kind: .route, title: to, subtitle: "没能找到路线", symbol: "map.fill",
                         expires: ProcessInfo.processInfo.systemUptime + 6)
                self.publish()
            }
        }
    }
}
