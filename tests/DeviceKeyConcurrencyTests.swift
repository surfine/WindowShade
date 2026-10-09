// S06：设备密钥并发创建只留一把；进程内换回不卡主线程、只许一份。
// 编译：tests/run-device-key-concurrency-tests.sh（真的 DeviceAuthorizationKey.swift，
// 加上从 App/UpdaterLaunch.swift 原样截出来的 InProcessRestore 一段）。不碰 Secure Enclave、不碰真实更新状态。
import CryptoKit
import Foundation

@main
struct DeviceKeyConcurrencyTests {
  nonisolated(unsafe) static var failures = 0

  static func check(_ condition: Bool, _ name: String) {
    if condition { print("ok   \(name)") } else { print("FAIL \(name)"); failures += 1 }
  }

  static func main() {
    concurrentPrepareMakesOneKey()
    halfWrittenKeyIsRebuilt()
    failedCreationLeavesNothing()
    restoreDoesNotBlockMain()
    restoreSuccessDoesNotResumeLaunch()
    if failures > 0 { print("\(failures) failure(s)"); exit(1) }
    print("all device-key / restore checks passed")
  }

  static func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("ws-device-key-\(UUID().uuidString)", isDirectory: true)
  }

  /// 软件密钥替身：blob 就是私钥原文，便于检查磁盘上的公钥和私钥是不是一对。
  final class FakeMaker: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func make() throws -> DeviceKeyMaterial {
      lock.withLock { count += 1 }
      usleep(20_000)  // 拉宽竞态窗口
      let key = P256.Signing.PrivateKey()
      return DeviceKeyMaterial(blob: key.rawRepresentation, publicKey: key.publicKey, biometryState: Data([1, 2, 3]))
    }
  }

  final class Box: @unchecked Sendable {
    private var events: [String] = []
    private let lock = NSLock()
    func add(_ e: String) { lock.withLock { events.append(e) } }
    var snapshot: [String] { lock.withLock { events } }
  }

  static func concurrentPrepareMakesOneKey() {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let maker = FakeMaker()
    let key = DeviceAuthorizationKey(directory: dir, makeKey: maker.make)
    let results = Box()
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
      let pub = try? key.prepare()
      results.add(pub?.rawRepresentation.base64EncodedString() ?? "")
    }
    let got = results.snapshot
    check(got.count == 8 && Set(got).count == 1 && !got[0].isEmpty, "8 个并发 prepare() 拿到同一把公钥")
    check(maker.calls == 1, "只建了一次密钥（实际 \(maker.calls) 次）")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()) ?? []
    check(names == ["device-key.v1", "device-key.v1.biometry", "device-key.v1.pub"], "磁盘上只有一对密钥：\(names)")
    if let blob = try? Data(contentsOf: dir.appendingPathComponent("device-key.v1")),
      let pub = try? Data(contentsOf: dir.appendingPathComponent("device-key.v1.pub")),
      let priv = try? P256.Signing.PrivateKey(rawRepresentation: blob)
    {
      check(priv.publicKey.rawRepresentation == pub && pub.base64EncodedString() == got.first, "磁盘上的公钥和私钥是一对")
    } else {
      check(false, "读得回磁盘上的密钥")
    }
    let reread = DeviceAuthorizationKey(directory: dir, makeKey: maker.make)
    check(reread.publicKey?.rawRepresentation.base64EncodedString() == got.first && maker.calls == 1, "重新打开读到同一把，不重建")
  }

  /// 公钥最后写、作为提交标记：只有私钥没有公钥的半成品当作没有密钥，整把重建。
  static func halfWrittenKeyIsRebuilt() {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? Data([9, 9, 9]).write(to: dir.appendingPathComponent("device-key.v1"))
    let maker = FakeMaker()
    let key = DeviceAuthorizationKey(directory: dir, makeKey: maker.make)
    check(key.publicKey == nil, "没有公钥文件就算没有密钥")
    let pub = try? key.prepare()
    let blob = try? Data(contentsOf: dir.appendingPathComponent("device-key.v1"))
    let matches = blob.flatMap { try? P256.Signing.PrivateKey(rawRepresentation: $0) }?.publicKey.rawRepresentation
    check(pub != nil && maker.calls == 1 && matches == pub?.rawRepresentation, "半成品被整把重建，公私钥配对")
  }

  static func failedCreationLeavesNothing() {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    struct Nope: Error {}
    let key = DeviceAuthorizationKey(directory: dir, makeKey: { throw Nope() })
    check((try? key.prepare()) == nil, "建钥失败时 prepare() 抛错")
    check(!FileManager.default.fileExists(atPath: dir.path), "建钥失败不留文件")
  }

  /// 跑主 RunLoop 直到条件成立或超时。
  static func spin(until done: () -> Bool, timeout: TimeInterval) {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
  }

  static func restoreDoesNotBlockMain() {
    let runner = InProcessRestore()
    let box = Box()
    struct Broken: Error {}
    let began = Date()
    let started = runner.start(
      work: { Thread.sleep(forTimeInterval: 5); throw Broken() },
      succeeded: { box.add("succeeded") },
      failed: { _ in box.add("failed main=\(Thread.isMainThread) suspended=\(runner.isSuspended)") })
    let elapsed = Date().timeIntervalSince(began)
    check(started, "换回开跑")
    check(elapsed < 0.05, String(format: "主线程 %.1f ms 内返回（要求 50 ms）", elapsed * 1000))
    check(runner.isSuspended, "换回期间启动挂起")
    let second = runner.start(work: { box.add("second ran") }, succeeded: {}, failed: { _ in })
    check(!second, "同一时间只许一份在跑")
    let deferred = MainActor.assumeIsolated {
      runner.deferLaunch { box.add("resumed suspended=\(runner.isSuspended)") }
    }
    check(deferred, "挂起期间启动被推迟")
    spin(until: { box.snapshot.count >= 2 }, timeout: 8)
    check(
      box.snapshot == ["failed main=true suspended=true", "resumed suspended=false"],
      "失败：先在主线程收尾，再清标志、补跑启动：\(box.snapshot)")
    let third = runner.start(work: {}, succeeded: {}, failed: { _ in })
    check(third, "上一份结束后可以再开")
    spin(until: { !runner.isSuspended }, timeout: 2)
  }

  static func restoreSuccessDoesNotResumeLaunch() {
    let runner = InProcessRestore()
    let box = Box()
    _ = runner.start(
      work: { Thread.sleep(forTimeInterval: 0.1) }, succeeded: { box.add("succeeded") }, failed: { _ in box.add("failed") })
    _ = MainActor.assumeIsolated { runner.deferLaunch { box.add("resumed") } }
    spin(until: { !runner.isSuspended }, timeout: 3)
    check(box.snapshot == ["succeeded"], "成功：走成功回调（产品里退出），不补跑启动：\(box.snapshot)")
    let after = MainActor.assumeIsolated { runner.deferLaunch {} }
    check(!after, "换回结束后启动不再推迟")
  }
}
