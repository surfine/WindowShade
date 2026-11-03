// 独立蓝牙配件探针（macOS 原生诊断）。
//
// **不是主 App 的一部分**：单独编译、单独运行，只回答一个问题——
// 这台机器的已配对蓝牙设备里，有多少「音频/视频大类」设备当前处于连接状态。
//
// 用法（都经 tools/accessory-probe/run.sh）：
//   run.sh                等价 --summary，只打印计数
//   run.sh --summary      只打印计数：已配对 / 已连接 / 连接中的音视频设备
//   run.sh --list         逐个列出用户可读名称与是否连接、是否音视频大类
//   run.sh --help | -h    用法
//
// 刻意约束（怕读者误解这份输出的含义）：
// - 只用 Foundation + 官方 IOBluetoothDevice.pairedDevices()，不扫蓝牙、不连接/断开、
//   不请求 RSSI、不碰 UI、不碰 AirTag 相关 API；
// - --summary 只输出计数，**绝不**输出任何设备名称、地址或身份信息；
// - --list 会输出名称（缺名写 unnamed），但**绝不**输出设备地址；
// - 这里的计数**不是**「人在场」「已解锁」之类的认证证明；
// - 配对列表不可用时报告「查询不可用/未知」并退出 1，**不**当成 0 台。

import Foundation
import IOBluetooth

// MARK: - 参数解析

private enum Mode {
    case summary
    case list
    case help
}

private func parseArguments() -> (mode: Mode?, error: String?) {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty { return (.summary, nil) }
    if args.count > 1 { return (nil, "参数过多：只接受 0 或 1 个参数") }
    switch args[0] {
    case "--summary": return (.summary, nil)
    case "--list": return (.list, nil)
    case "--help", "-h": return (.help, nil)
    default: return (nil, "未知参数：\(args[0])")
    }
}

private let usage = """
accessory-probe —— 已配对蓝牙配件计数探针（本机诊断，非主 App）

用法：
  run.sh                等价 --summary，只打印计数
  run.sh --summary      只打印计数：已配对 / 已连接 / 连接中的音视频设备
  run.sh --list         逐个列出名称（缺名写 unnamed）与是否连接、是否音视频大类
  run.sh --help, -h     显示本帮助

说明：
  * --summary 只输出计数，绝不输出名称、地址或身份信息；
  * --list 输出名称但绝不输出设备地址；
  * 这些计数不是认证证明，不能用来断言「人在场」或「已解锁」；
  * 不支持 AirTag / 查找网络相关查询；不扫描、不连接、不断开、不请求 RSSI。

退出码：0 成功；1 参数非法或设备查询不可用。
"""

// MARK: - 名称转义

/// 把名称里的换行与其它控制字符压成一行，保证每条输出只占一行。
private func escapeToSingleLine(_ raw: String) -> String {
    var out = ""
    for scalar in raw.unicodeScalars {
        switch scalar {
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x2028 || scalar.value == 0x2029 {
                out += String(format: "\\u%04X", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    let trimmed = out.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "unnamed" : trimmed
}

/// 官方 API 返回的蓝牙「大类」编码：0x04 = 音频/视频。
private func isAudioVideoMajor(_ device: IOBluetoothDevice) -> Bool {
    return Int(device.deviceClassMajor) == 4
}

// MARK: - 主流程

private func run() -> Int32 {
    switch parseArguments() {
    case (_, let error?):
        FileHandle.standardError.write(Data(("accessory-probe: \(error)\n\n\(usage)\n").utf8))
        return 1
    case (.help?, _):
        print(usage)
        return 0
    case (.summary?, _), (.list?, _):
        break
    default:
        break
    }
    let mode = parseArguments().mode ?? .summary

    // 唯一可信来源：官方配对列表。返回 nil 就是查询不可用，不当作 0 台。
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
        FileHandle.standardError.write(Data("配件查询不可用：pairedDevices() 返回未知结果。\n".utf8))
        return 1
    }

    let paired = devices.count
    let connected = devices.filter { $0.isConnected() }
    let connectedAudioVideo = connected.filter { isAudioVideoMajor($0) }

    if mode == .summary {
        // 只输出计数，绝不输出名称 / 地址 / 身份信息。
        print("已配对设备数: \(paired)")
        print("已连接设备数: \(connected.count)")
        print("连接中的音频/视频设备数: \(connectedAudioVideo.count)")
        return 0
    }

    print("已配对设备: \(paired)（下面仅列名称与状态，不输出地址）")
    if devices.isEmpty {
        print("（没有已配对设备）")
    }
    for device in devices {
        let name = escapeToSingleLine(device.name ?? "")
        let connectedText = device.isConnected() ? "yes" : "no"
        let classText = isAudioVideoMajor(device) ? "音频/视频" : "其它"
        print("- \(name) | connected: \(connectedText) | 大类: \(classText)")
    }
    return 0
}

exit(run())
