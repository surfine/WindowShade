import Foundation

/// 下载卡的来源：盯着“下载”文件夹里的临时文件。默认关；用户打开后才会第一次读这个文件夹
/// （macOS 会在那时问一次文件夹权限）。靠目录变化的系统通知触发，没有轮询；关掉或休眠就拆掉。
@MainActor
final class DownloadActivitySource {
    nonisolated static let enabledKey = "Notch.activities.downloadsEnabled"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var onChange: ((DownloadUpdate) -> Void)?
    private let queue = DispatchQueue(label: "com.windowshade.activities.downloads", qos: .utility)
    private var watcher: DispatchSourceFileSystemObject?
    private var tracker = DownloadTracker()
    private var epoch = 0
    private var scanQueued = false
    private var scanning = false
    private var scanAgain = false

    func start() {
        guard watcher == nil, Self.isEnabled,
              let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let path = folder.path
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        epoch += 1
        tracker = DownloadTracker()
        // 只关心目录里多了、少了、改名了；文件越写越大不会触发。
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.queueScan(path: path) } }
        }
        source.setCancelHandler { close(fd) }
        watcher = source
        source.resume()
        queueScan(path: path)
    }

    func stop() {
        epoch += 1
        watcher?.cancel(); watcher = nil
        scanQueued = false; scanAgain = false
        tracker = DownloadTracker()
    }

    /// 浏览器改名、删除常常连着来几下，合并成一次读。
    private func queueScan(path: String) {
        guard watcher != nil, !scanQueued else { return }
        scanQueued = true
        let token = epoch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.epoch == token else { return }
                self.scanQueued = false
                self.scan(path: path)
            }
        }
    }

    private func scan(path: String) {
        guard watcher != nil else { return }
        guard !scanning else { scanAgain = true; return }
        scanning = true
        let token = epoch
        queue.async { [weak self] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            // 只有临时文件才取修改时间，别的文件一概不碰。
            let entries = names.map { name -> DownloadFileEntry in
                guard DownloadTempName.finalName(of: name) != nil else { return DownloadFileEntry(name: name, modifiedAt: nil) }
                let date = (try? FileManager.default.attributesOfItem(atPath: path + "/" + name))?[.modificationDate] as? Date
                return DownloadFileEntry(name: name, modifiedAt: date?.timeIntervalSince1970)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scanning = false
                    guard self.epoch == token, self.watcher != nil else { return }
                    let update = self.tracker.update(entries, now: Date().timeIntervalSince1970)
                    self.onChange?(update)
                    if self.scanAgain { self.scanAgain = false; self.queueScan(path: path) }
                }
            }
        }
    }
}
