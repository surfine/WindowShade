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
  func save(_ entries: [[String: Any]]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let data = try PropertyListSerialization.data(
      fromPropertyList: entries, format: .binary, options: 0)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    try file.synchronize()
  }
}
