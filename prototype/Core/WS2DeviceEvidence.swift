// WindowShade 2.1 · 蓝牙观察的证据等级。
// 名字相符、读到回应、RSSI、靠近、安全测距，各自只说明自己那一层。
// 只有登记时绑定的秘密核对通过，才进入设备因素。本类型不产生解锁许可。
import Foundation

struct WS2DeviceObservation: Equatable, Sendable, Codable {
    var sawNamedAdvertisement: Bool?
    var receivedResponse: Bool?
    var rssiNear: Bool?
    var enrolledIdentityVerified: Bool?
    var nearByLocalCalibration: Bool?
    var secureRangingVerified: Bool?

    init(
        sawNamedAdvertisement: Bool? = nil,
        receivedResponse: Bool? = nil,
        rssiNear: Bool? = nil,
        enrolledIdentityVerified: Bool? = nil,
        nearByLocalCalibration: Bool? = nil,
        secureRangingVerified: Bool? = nil
    ) {
        self.sawNamedAdvertisement = sawNamedAdvertisement
        self.receivedResponse = receivedResponse
        self.rssiNear = rssiNear
        self.enrolledIdentityVerified = enrolledIdentityVerified
        self.nearByLocalCalibration = nearByLocalCalibration
        self.secureRangingVerified = secureRangingVerified
    }
}

struct WS2DeviceEvidence: Equatable, Sendable {
    enum Fact: Equatable, Sendable {
        case unknown, no, yes
    }

    var sawNamedAdvertisement: Fact
    var receivedResponse: Fact
    var rssi: Fact
    var enrolledIdentity: Fact
    var nearByCalibration: Fact
    var secureRanging: Fact

    /// 设备因素只看登记身份。名字、读到、RSSI、靠近都不能把它填成通过。
    var deviceFactor: Fact { enrolledIdentity }

    /// 分级结果永远不许可自动解锁。
    var unlockPermitted: Bool { false }

    static func grade(_ observation: WS2DeviceObservation) -> WS2DeviceEvidence {
        WS2DeviceEvidence(
            sawNamedAdvertisement: fact(observation.sawNamedAdvertisement),
            receivedResponse: fact(observation.receivedResponse),
            rssi: fact(observation.rssiNear),
            enrolledIdentity: fact(observation.enrolledIdentityVerified),
            nearByCalibration: fact(observation.nearByLocalCalibration),
            secureRanging: fact(observation.secureRangingVerified)
        )
    }

    private static func fact(_ value: Bool?) -> Fact {
        switch value {
        case nil: return .unknown
        case false?: return .no
        case true?: return .yes
        }
    }
}

/// Connection-local transport observations. CoreBluetooth does not expose a cryptographic
/// peer identity proof here; even encrypted characteristic access cannot become a factor.
struct WS2DeviceEvidenceSession: Sendable {
    enum Level: Int, Codable, Sendable { case seen, connected, protectedAccess }
    enum End: String, Codable, Sendable { case disconnected, revoked, sleeping, radioOff, cancelled }
    struct Lease: Equatable, Sendable { let device: UUID; let generation: UUID }
    struct Receipt: Equatable, Sendable {
        let lease: Lease
        let level: Level
        let sampledAt: Double
        let expiresAt: Double
        var authenticatedIdentity: Bool { false }
    }
    private(set) var active: Lease?
    private(set) var receipt: Receipt?
    private(set) var ended: End?
    private var lastTime: Double?

    mutating func begin(device: UUID, now: Double) -> Lease? {
        active = nil; receipt = nil; lastTime = nil; ended = nil
        guard now.isFinite, now >= 0 else { return nil }
        let lease = Lease(device: device, generation: UUID())
        active = lease; lastTime = now
        return lease
    }
    @discardableResult
    mutating func observe(_ level: Level, lease: Lease, now: Double, validFor: Double = 5) -> Bool {
        guard active == lease, now.isFinite, validFor.isFinite, validFor > 0,
              now >= (lastTime ?? now), (now + validFor).isFinite else { return false }
        lastTime = now
        // Keep the level tied to this sample, never refresh stronger old evidence with a weak event.
        receipt = Receipt(lease: lease, level: level, sampledAt: now, expiresAt: now + validFor)
        return true
    }
    func current(now: Double) -> Receipt? {
        guard now.isFinite, let receipt, receipt.lease == active,
              now >= receipt.sampledAt, now < receipt.expiresAt else { return nil }
        return receipt
    }
    mutating func end(_ reason: End, lease: Lease) {
        guard active == lease else { return }
        active = nil; receipt = nil; lastTime = nil; ended = reason
    }
}
