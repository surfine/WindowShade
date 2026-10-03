import Foundation

/// A fresh local filesystem observation. It cannot close a later path-replacement race.
enum WS2ProjectDirectory {
    enum Failure: Error { case notAbsoluteFileURL, notDirectory, missingIdentity }
    static func read(_ url: URL) throws -> WS2OwnedScope.Directory {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else { throw Failure.notAbsoluteFileURL }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.notDirectory }
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { throw Failure.missingIdentity }
        let identity = WS2OwnedScope.Directory(canonicalPath: resolved.path, device: device.uint64Value, inode: inode.uint64Value)
        guard identity.isValid else { throw Failure.missingIdentity }
        return identity
    }
    /// Boundary-aware advisory containment only; the CLI sandbox must enforce actual access.
    static func contains(canonicalRoot root: String, canonicalCandidate candidate: String) -> Bool {
        guard root.hasPrefix("/"), candidate.hasPrefix("/"), !root.utf8.contains(0), !candidate.utf8.contains(0),
              !root.split(separator: "/").contains(".."), !candidate.split(separator: "/").contains("..") else { return false }
        let r = root == "/" ? "/" : root.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Preserve an absolute root; trailing separators do not broaden /repo to /repo-old.
        let normalized = root == "/" ? "/" : "/" + r
        return normalized == "/" || candidate == normalized || candidate.hasPrefix(normalized + "/")
    }
}
