// 只认本应用留下、所属进程已经结束的侧拉记录；不扫描或移动用户任意离屏窗口。
import Cocoa
import ApplicationServices
import Darwin

@MainActor
enum SlideOverRecovery {
    private static var directory: URL { DurableShadeJournal.application.url.deletingLastPathComponent() }
    private static var journal: DurableShadeJournal {
        DurableShadeJournal(url: directory.appendingPathComponent("SlideOver-\(getpid()).plist"))
    }

    static func record(id: CGWindowID, pid: pid_t, frame: CGRect) -> Bool {
        guard let launched = processBirth(pid), let ownerLaunched = processBirth(getpid()) else { return false }
        do {
            var entries = (try journal.load()) ?? []
            entries.removeAll { ($0["id"] as? Int) == Int(id) }
            entries.append(["id": Int(id), "pid": Int(pid), "launched": launched,
                "owner": Int(getpid()), "ownerLaunched": ownerLaunched,
                "x": Double(frame.minX), "y": Double(frame.minY),
                "w": Double(frame.width), "h": Double(frame.height)])
            try journal.save(entries)
            return true
        } catch { wlog("slide-over: recovery record failed \(error)"); return false }
    }

    nonisolated static func processBirth(_ pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    static func clear(id: CGWindowID) { clear(id: Int(id), from: journal) }
    private static func clear(id: Int, from stored: DurableShadeJournal) {
        guard let entries = try? stored.load() else { return }
        try? stored.save(entries.filter { ($0["id"] as? Int) != id })
    }
    static func clamped(_ frame: CGRect) -> CGRect {
        let screen = NSScreen.screens.first { frame.intersects($0.visibleFrame) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return frame }
        return CGRect(x: min(max(frame.minX, area.minX + 10), max(area.minX + 10, area.maxX - frame.width - 10)),
                      y: min(max(frame.minY, area.minY + 10), max(area.minY + 10, area.maxY - frame.height - 10)),
                      width: frame.width, height: frame.height)
    }

    static func recoverAbandoned(directoryOverride: URL? = nil) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directoryOverride ?? directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix("SlideOver-") && url.pathExtension == "plist" {
            let stored = DurableShadeJournal(url: url)
            guard let entries = try? stored.load() else { continue }
            for entry in entries {
            guard
                  let owner = entry["owner"] as? Int, let ownerTime = entry["ownerLaunched"] as? String,
                  let pid = entry["pid"] as? Int, let id = entry["id"] as? Int,
                  let launched = entry["launched"] as? String,
                  let x = entry["x"] as? Double, let y = entry["y"] as? Double,
                  let w = entry["w"] as? Double, let h = entry["h"] as? Double,
                  x.isFinite, y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0,
                  owner > 0, owner <= Int(Int32.max), pid > 0, pid <= Int(Int32.max), id > 0, id <= Int(UInt32.max)
            else { continue }
            if processBirth(pid_t(owner)) == ownerTime { continue }
            guard processBirth(pid_t(pid)) == launched,
                  let info = cgWindowInfo(CGWindowID(id)), (info[kCGWindowOwnerPID as String] as? Int) == pid
            else { clear(id: id, from: stored); continue }
            // WindowServer 的位置在 AX 移动成功后仍可能短暂滞后，不能据此丢掉恢复记录。
            let baseline = coordinateBaselineY()
            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            let destination = clamped(cocoaFrame(fromAXPosition: CGPoint(x: x, y: y), size: CGSize(width: w, height: h)))
            let target = axPosition(fromCocoaFrame: destination)
            DispatchQueue.global(qos: .userInitiated).async {
                guard processBirth(pid_t(pid)) == launched,
                      let window = appWindows(pid: pid_t(pid)).first(where: { windowID(of: $0) == CGWindowID(id) }),
                      let position = axPosition(window), let size = axSize(window) else { return }
                let current = CGRect(x: position.x, y: baseline - position.y - size.height, width: size.width, height: size.height)
                if visibleFrames.contains(where: { current.intersection($0).width > 64 }) {
                    DispatchQueue.main.async { clear(id: id, from: stored) }
                    return
                }
                guard processBirth(pid_t(pid)) == launched else { return }
                setAXPosition(window, target)
                if let observed = axPosition(window), hypot(observed.x - target.x, observed.y - target.y) < 8 {
                    DispatchQueue.main.async { clear(id: id, from: stored) }
                }
            }
            }
        }
    }
}
