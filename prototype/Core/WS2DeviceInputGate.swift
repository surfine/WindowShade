// Original per-attachment admission. Vendor/product names are NOT cryptographic identity.
import Foundation
struct WS2DeviceInputGate: Sendable {
    enum Domain: Sendable { case desktop, conductor, review }
    enum Outcome: Equatable, Sendable { case ignored, began(UInt64), ended(UInt64), cancelled(UInt64) }
    private(set) var attachment: UUID?
    private(set) var enabled = false
    private var neutralSeen = Set<String>()
    private var down: [String:UInt64] = [:]
    private var serial: UInt64 = 0
    private var sequence: UInt64?
    private var currentDomain: Domain?
    private var time = WS2.TimeGate()
    mutating func connect(_ id: UUID) { attachment = id; enabled = false; neutralSeen.removeAll(); down.removeAll(); sequence = nil; time = .init(); currentDomain = nil }
    mutating func enable(_ id: UUID) -> Bool {
        guard attachment == id else { return false }
        enabled = true; neutralSeen.removeAll(); down.removeAll(); currentDomain = nil; return true
    }
    mutating func suspend() -> [UInt64] {
        enabled = false; neutralSeen.removeAll(); let active = down.values.sorted(); down.removeAll(); return active
    }
    mutating func disconnect() -> [UInt64] { let ids = suspend(); attachment = nil; currentDomain = nil; return ids }
    // The bridge MUST deliver these cancellations before publishing a new UI domain.
    mutating func changeDomain(to domain: Domain) -> [UInt64] {
        guard currentDomain != domain else { return [] }
        let active = down.values.sorted(); down.removeAll(); neutralSeen.removeAll(); currentDomain = domain
        return active
    }
    // Each control must be observed UP after enable; a held button cannot become a new approval.
    mutating func button(attachment id: UUID, name: String, pressed: Bool, sequence: UInt64,
                         at now: WS2.Instant, unlocked: Bool, domain: Domain) -> Outcome {
        guard attachment == id, enabled else { return .ignored }
        if let currentDomain, currentDomain != domain { _ = suspend(); return .ignored }
        if currentDomain == nil { currentDomain = domain }
        guard unlocked, time.accept(now), self.sequence.map({ sequence > $0 }) ?? true else {
            _ = suspend(); return .ignored
        }
        self.sequence = sequence
        guard !name.isEmpty, name.utf8.count <= 64 else { _ = suspend(); return .ignored }
        if !pressed {
            neutralSeen.insert(name)
            if let n = down.removeValue(forKey: name) { return .ended(n) }; return .ignored
        }
        guard domain != .review, neutralSeen.contains(name), down[name] == nil, down.count < 32, serial < .max else { return .ignored }
        serial += 1; down[name] = serial; return .began(serial)
    }
}
/// Exact, admitted attachment + public HID usage only. Unknown usages are not consumed.
struct WS2HIDButtonMap: Sendable {
    struct Identity: Equatable, Sendable { let registryID: UInt64; let vendor: Int; let product: Int }
    let identity: Identity
    func button(from actual: Identity, page: Int, usage: Int, value: Int) -> (WS2.Button, Bool)? {
        guard actual == identity, value == 0 || value == 1 else { return nil }
        let b: WS2.Button
        switch (page,usage) {
        case (0x0C,0x42): b = .up; case (0x0C,0x43): b = .down
        case (0x0C,0x44): b = .left; case (0x0C,0x45): b = .right
        case (0x0C,0x80): b = .select; case (0x01,0x86): b = .back
        case (0x0C,0x60): b = .tv; case (0x0C,0xCD): b = .playPause
        case (0x0C,0xE2): b = .mute; case (0x0C,0xE9): b = .volumeUp
        case (0x0C,0xEA): b = .volumeDown; case (0x0C,0x04): b = .side
        default: return nil
        }
        return (b,value == 1)
    }
}
