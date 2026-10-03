import Foundation

/// Local project/connection binding, NOT a sandbox and NOT an authorization grant.
/// Only the local picker and Runtime may populate identities; never trust a wire-supplied root.
struct WS2OwnedScope: Sendable {
    struct Directory: Hashable, Sendable {
        let canonicalPath: String
        let device: UInt64
        let inode: UInt64
        var isValid: Bool { canonicalPath.hasPrefix("/") && !canonicalPath.utf8.contains(0) && canonicalPath.utf8.count <= 4096 }
    }
    struct Project: Hashable, Sendable {
        let id: UUID
        let root: Directory
    }
    struct Ticket: Hashable, Sendable {
        let boot: UUID
        let connection: UUID
        let project: Project
        let revision: UInt64
    }
    let boot: UUID
    private(set) var revision: UInt64 = 0
    private(set) var project: Project?
    private(set) var active: Ticket?
    private(set) var unlocked = false
    private(set) var enabled = false
    private var exhausted = false
    init(boot: UUID) { self.boot = boot }

    private mutating func advance() -> Bool {
        active = nil
        guard !exhausted, revision < .max else { exhausted = true; return false }
        revision += 1; return true
    }
    @discardableResult mutating func select(_ next: Project) -> Bool {
        guard advance(), next.root.isValid else { project = nil; return false }
        project = next; return true
    }
    mutating func environment(unlocked: Bool, enabled: Bool) {
        guard self.unlocked != unlocked || self.enabled != enabled else { return }
        _ = advance(); self.unlocked = unlocked; self.enabled = enabled
    }
    mutating func invalidate() { _ = advance() }
    mutating func clearProject() { _ = advance(); project = nil }
    mutating func begin(connection: UUID, liveRoot: Directory) -> Ticket? {
        guard advance(), enabled, unlocked, let project, project.root == liveRoot else { return nil }
        let ticket = Ticket(boot: boot, connection: connection, project: project, revision: revision)
        active = ticket; return ticket
    }
    func accepts(_ ticket: Ticket, liveRoot: Directory) -> Bool {
        !exhausted && enabled && unlocked && active == ticket && ticket.boot == boot &&
        ticket.revision == revision && project == ticket.project && liveRoot == ticket.project.root
    }
    /// Call with the session key obtained from the owned backend, not an arbitrary UI label.
    func context(_ ticket: Ticket, session: WS2.SessionKey, liveRoot: Directory) -> WS2.Context? {
        guard accepts(ticket, liveRoot: liveRoot), session.isValid, session.provider == .codex else { return nil }
        return .init(peerID: "local", projectID: ticket.project.id.uuidString, session: session, epoch: ticket.revision)
    }
}
