import Foundation

/// Explicit, process-wide knobs for the isolated receiver.  They are selected before
/// the first frame and are never read from an environment variable or changed live.
/// These values describe wire variants; none of them changes the production channel.
struct RemoteProbeConfiguration: Equatable {
    enum ReplyPolicy: String { case current, upstreamReference = "upstream-reference" }
    enum PairingEnvelope: String {
        case `default`
        case type1

        var pairingType: UInt64? { self == .type1 ? 1 : nil }
    }
    enum IdentifierRepresentation: String {
        case compact
        case hyphenated
    }
    enum M6Metadata: String {
        case none
        case probeLabel = "probe-label"

        var value: Data? { get throws {
            switch self {
            case .none: return nil
            // This is a descriptive test label only.  It is inside M6 AEAD but is not an
            // account, device, or authorization claim.
            case .probeLabel: return try WS2OPACK.encode(.dictionary(["name": .string("WindowShade Remote Probe"), "model": .string("AppleTV6,2")]))
            }
        } }
    }

    let replyPolicy: ReplyPolicy
    let pairingEnvelope: PairingEnvelope
    let identifierRepresentation: IdentifierRepresentation
    let m6Metadata: M6Metadata

    static let `default` = RemoteProbeConfiguration(replyPolicy: .current,
        pairingEnvelope: .default, identifierRepresentation: .compact, m6Metadata: .none)

    var summary: [String: String] {
        ["replyPolicy": replyPolicy.rawValue,
         "pairingEnvelope": pairingEnvelope.rawValue,
         "identifierRepresentation": identifierRepresentation.rawValue,
         "m6Metadata": m6Metadata.rawValue]
    }

    static func parse(_ args: ArraySlice<String>) throws -> RemoteProbeConfiguration {
        var replyPolicy: ReplyPolicy = .current
        var pairingEnvelope: PairingEnvelope = .default
        var identifierRepresentation: IdentifierRepresentation = .compact
        var m6Metadata: M6Metadata = .none
        var seen = Set<String>()
        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            guard seen.insert(flag).inserted else { throw Failure.malformed(flag) }
            guard let value = iterator.next() else { throw Failure.malformed(flag) }
            switch flag {
            case "--reply-policy": guard let parsed = ReplyPolicy(rawValue: value) else { throw Failure.malformed(value) }; replyPolicy = parsed
            case "--pairing-envelope": guard let parsed = PairingEnvelope(rawValue: value) else { throw Failure.malformed(value) }; pairingEnvelope = parsed
            case "--identifier-form": guard let parsed = IdentifierRepresentation(rawValue: value) else { throw Failure.malformed(value) }; identifierRepresentation = parsed
            case "--m6-metadata": guard let parsed = M6Metadata(rawValue: value) else { throw Failure.malformed(value) }; m6Metadata = parsed
            default: throw Failure.malformed(flag)
            }
        }
        return RemoteProbeConfiguration(replyPolicy: replyPolicy, pairingEnvelope: pairingEnvelope,
            identifierRepresentation: identifierRepresentation, m6Metadata: m6Metadata)
    }

    enum Failure: Error { case malformed(String) }
}
