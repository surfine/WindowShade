import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A local configuration boundary, NOT an OS sandbox. User-selected code still runs as this user.
/// Do not call prepare until the user explicitly consents to running that executable.
struct WS2LocalLaunchProfile: Sendable {
    enum Failure: Error { case unsafePath, configurationChanged, externalConfiguration, executableChanged }
    struct FileIdentity: Equatable, Sendable {
        let path:String;let device:UInt64;let inode:UInt64;let size:UInt64;let modified:Date
    }
    let project:WS2OwnedScope.Project
    let executable:URL
    let executableIdentity:FileIdentity
    let root:URL
    let environment:[String:String]
    private let configURL:URL
    static let config = """
    # WindowShade owned local query profile v1; do not silently overwrite edits.
    approval_policy = "on-request"
    approvals_reviewer = "user"
    sandbox_mode = "read-only"
    model_provider = "openai"
    cli_auth_credentials_store = "file"
    web_search = "disabled"
    check_for_update_on_startup = false
    [features]
    shell_tool = false
    unified_exec = false
    shell_snapshot = false
    [mcp_servers]
    [plugins]
    [hooks]
    """ + "\n"
    static func prepare(projectURL:URL,projectID:UUID,executableURL:URL,root:URL) throws -> Self {
        let project=WS2OwnedScope.Project(id:projectID,root:try WS2ProjectDirectory.read(projectURL))
        let executable=executableURL.resolvingSymlinksInPath().standardizedFileURL
        let identity=try identify(executable)
        guard FileManager.default.isExecutableFile(atPath:executable.path) else { throw Failure.unsafePath }
        try rejectExternalConfiguration(project.root)
        guard root.isFileURL,root.path.hasPrefix("/"),!root.path.utf8.contains(0) else { throw Failure.unsafePath }
        // The caller supplies the app's own storage root. Existing objects must belong to this UID.
        try privateDirectory(root)
        let home=root.appendingPathComponent("home",isDirectory:true)
        let codex=root.appendingPathComponent("codex",isDirectory:true)
        let tmp=root.appendingPathComponent("tmp",isDirectory:true)
        for dir in [home,codex,tmp] { try privateDirectory(dir) }
        let configURL=codex.appendingPathComponent("config.toml")
        let expected=Data(config.utf8)
        if !FileManager.default.fileExists(atPath:configURL.path) {
            let fd=configURL.path.withCString { open($0,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,mode_t(0o600)) }
            guard fd >= 0 else { throw Failure.unsafePath }
            defer { _=close(fd) }
            try expected.withUnsafeBytes { bytes in
                var offset=0
                while offset<bytes.count {
                    let n=write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                    if n<0 && errno==EINTR { continue }
                    guard n>0 else { throw Failure.unsafePath };offset += n
                }
            }
            guard fsync(fd)==0 else { throw Failure.unsafePath }
        }
        let env=["HOME":home.path,"CODEX_HOME":codex.path,"TMPDIR":tmp.path,
                 "PATH":"/usr/bin:/bin:/usr/sbin:/sbin","LANG":"en_US.UTF-8","LC_ALL":"en_US.UTF-8"]
        let result=Self(project:project,executable:executable,executableIdentity:identity,
                        root:root,environment:env,configURL:configURL)
        try result.revalidate();return result
    }
    func revalidate() throws {
        guard try WS2ProjectDirectory.read(URL(fileURLWithPath:project.root.canonicalPath))==project.root else { throw Failure.unsafePath }
        guard try Self.identify(executable)==executableIdentity else { throw Failure.executableChanged }
        try Self.rejectExternalConfiguration(project.root)
        let a=try FileManager.default.attributesOfItem(atPath:configURL.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (a[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (a[.size] as? NSNumber)?.intValue == Self.config.utf8.count,
              try Data(contentsOf:configURL)==Data(Self.config.utf8) else { throw Failure.configurationChanged }
    }
    private static func identify(_ url:URL) throws -> FileIdentity {
        let a=try FileManager.default.attributesOfItem(atPath:url.path)
        guard a[.type] as? FileAttributeType == .typeRegular,
              let device=a[.systemNumber] as? NSNumber,let inode=a[.systemFileNumber] as? NSNumber,
              let size=a[.size] as? NSNumber,let modified=a[.modificationDate] as? Date else { throw Failure.unsafePath }
        return .init(path:url.path,device:device.uint64Value,inode:inode.uint64Value,size:size.uint64Value,modified:modified)
    }
    private static func privateDirectory(_ url:URL) throws {
        let fm=FileManager.default
        if !fm.fileExists(atPath:url.path) {
            try fm.createDirectory(at:url,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        }
        let a=try fm.attributesOfItem(atPath:url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (a[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else { throw Failure.unsafePath }
    }
    private static func rejectExternalConfiguration(_ project:WS2OwnedScope.Directory) throws {
        let fm=FileManager.default
        var directory=URL(fileURLWithPath:project.canonicalPath,isDirectory:true)
        // Conservative initial profile: no project/ancestor execution configuration or plugin roots.
        // AGENTS.md remains an instruction file, not a permission grant; it is not silently removed.
        while true {
            for name in [".codex",".agents"] {
                if (try? fm.attributesOfItem(atPath:directory.appendingPathComponent(name).path)) != nil { throw Failure.externalConfiguration }
            }
            let parent=directory.deletingLastPathComponent();if parent.path==directory.path { break };directory=parent
        }
        for path in ["/etc/codex/config.toml","/etc/codex/requirements.toml","/etc/codex/managed_config.toml"] {
            if fm.fileExists(atPath:path) { throw Failure.externalConfiguration }
        }
    }
    /// This checks the server's effective projection. It does not prove that an executable is benign.
    static func admitsEffectiveConfig(_ response:WireJSON) -> Bool {
        guard let c=response["config"],case .object = c,
              c["sandbox_mode"]?.text=="read-only",c["approval_policy"]?.text=="on-request",
              c["approvals_reviewer"]?.text=="user",c["model_provider"]?.text=="openai",
              c["web_search"]?.text=="disabled" else { return false }
        for key in ["mcp_servers","plugins","hooks"] {
            if let value=c[key],value != .null,value != .object([:]) { return false }
        }
        for key in ["shell_tool","unified_exec","shell_snapshot"] {
            guard c["features"]?[key] == .bool(false) else { return false }
        }
        return true
    }
}
