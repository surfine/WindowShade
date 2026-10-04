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
