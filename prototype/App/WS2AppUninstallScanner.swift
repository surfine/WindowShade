import Foundation

// 卸载计划的真实文件系统适配与执行器。只读扫描；删除唯一出口是移废纸篓（可找回），
// 逐条执行、单条失败不中断，失败清单如实交回界面。

struct WS2AppUninstallRealFS: WS2AppUninstallFileSystem {
    private var fm: FileManager { FileManager.default }

    func isDirectory(_ path: String) -> Bool {
        var flag: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &flag) else { return false }
        return flag.boolValue
    }

    func fileExists(_ path: String) -> Bool { fm.fileExists(atPath: path) }

    func namesInDirectory(_ path: String) -> [String] {
        (try? fm.contentsOfDirectory(atPath: path)) ?? []
    }

    func dataOfFile(_ path: String) -> Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }

    /// 文件 = 实际字节；目录 = 递归枚举求和（符号链接不跟进，避免循环与越界）。
    func bytes(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey],
                                             options: [.skipsPackageDescendants], errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

enum WS2AppUninstallTrash {

    struct Outcome: Sendable {
        var trashed: [String]
        var failures: [String]
    }

    /// 逐条移废纸篓（可找回）。单条失败记录后继续，不中断整批。
    static func trash(_ paths: [String]) -> Outcome {
        let fm = FileManager.default
        var outcome = Outcome(trashed: [], failures: [])
        for path in paths {
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                outcome.trashed.append(path)
            } catch {
                outcome.failures.append(path)
            }
        }
        return outcome
    }
}
