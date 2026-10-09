import Foundation

/// Atomic local recovery record. The injected URL lets tests exercise write failures and restart recovery.
struct DurableShadeJournal {
  let url: URL
  static var application: DurableShadeJournal {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return DurableShadeJournal(
      url: base.appendingPathComponent("WindowShade/RecoveryJournal.plist"))
  }
  func load() throws -> [[String: Any]]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard
      let entries = try PropertyListSerialization.propertyList(from: data, format: nil)
        as? [[String: Any]]
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return entries
  }
  /// 失败注入点，只给测试用：模拟改权限失败。
  var setPermissions: (@Sendable (URL) throws -> Void)?

  func save(_ entries: [[String: Any]]) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let data = try PropertyListSerialization.data(
      fromPropertyList: entries, format: .binary, options: 0)
    // 同目录临时文件 → 完整落盘 → 改名 → 再落盘目录；崩在任何一步，正式文件要么是旧的要么是新的。
    let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    let fd = open(temp.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    var renamed = false
    defer {
      if !renamed { unlink(temp.path) }
    }
    do {
      try data.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
          if n < 0 {
            if errno == EINTR { continue }
            throw CocoaError(.fileWriteUnknown)
          }
          offset += n
        }
      }
      if fcntl(fd, F_FULLFSYNC) != 0, fsync(fd) != 0 { throw CocoaError(.fileWriteUnknown) }
    } catch {
      close(fd)
      throw error
    }
    close(fd)
    // 权限在创建时已是 0600；这里只是补一刀，失败不算保存失败。
    if let setPermissions {
      try? setPermissions(temp)
    } else {
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
    }
    guard rename(temp.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    renamed = true
    let dirFD = open(directory.path, O_RDONLY)
    if dirFD >= 0 {
      _ = fsync(dirFD)
      close(dirFD)
    }
  }
}
