// S05：子进程回收、journal 先落盘后改名、SPU 加速度计 Open 失败不 abort。
import Foundation
import IOKit.hid

nonisolated(unsafe) var failures = 0
func check(_ ok: Bool, _ name: String) {
  if ok { print("PASS \(name)") } else { print("FAIL \(name)"); failures += 1 }
}

func threadCount() -> Int {
  var list: thread_act_array_t?
  var count: mach_msg_type_number_t = 0
  guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS else { return -1 }
  if let list {
    vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                  vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
  }
  return Int(count)
}

func childCount() -> Int {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
  p.arguments = ["-P", String(getpid())]
  let pipe = Pipe()
  p.standardOutput = pipe
  try? p.run()
  p.waitUntilExit()
  let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
  return s.split(separator: "\n").count
}

@main enum ProcessFileHygiene {
  static func main() {
  setvbuf(stdout, nil, _IOLBF, 0)
  // MARK: 1. profiler 超时回收
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("s05-\(getpid())")
  try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  let script = dir.appendingPathComponent("stubborn.sh")
  try! "#!/bin/bash\ntrap '' TERM\nwhile true; do sleep 1; done\n".write(to: script, atomically: true, encoding: .utf8)
  chmod(script.path, 0o755)

  _ = AirPodsBatterySource.runProcess(path: script.path, arguments: [], timeout: 0.3)  // 预热
  let baseThreads = threadCount()
  let baseChildren = childCount()
  var allNil = true
  let start = Date()
  for _ in 0..<20 {
    if AirPodsBatterySource.runProcess(path: script.path, arguments: [], timeout: 0.2) != nil { allNil = false }
  }
  usleep(300_000)
  check(allNil, "忽略 TERM 的子进程超时都返回 nil")
  check(Date().timeIntervalSince(start) < 120, "20 次在合理时间内结束")
  check(childCount() <= baseChildren, "子进程数不增长 (\(baseChildren) -> \(childCount()))")
  check(threadCount() <= baseThreads + 2, "线程数不增长 (\(baseThreads) -> \(threadCount()))")
  let ok = AirPodsBatterySource.runProcess(path: "/bin/echo", arguments: ["hi"], timeout: 5)
  check(ok.flatMap { String(data: $0, encoding: .utf8) } == "hi\n", "正常子进程照常返回输出")

  // MARK: 2. journal
  var journal = DurableShadeJournal(url: dir.appendingPathComponent("sub/journal.plist"))
  try! journal.save([["id": 1]])
  journal.setPermissions = { _ in throw CocoaError(.fileWriteNoPermission) }
  do {
    try journal.save([["id": 2]])
    check((try? journal.load())??.first?["id"] as? Int == 2, "改权限失败也读回新条目")
  } catch {
    check(false, "改权限失败不应让 save 抛错: \(error)")
  }
  let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: journal.url.deletingLastPathComponent().path)) ?? []
  check(leftovers == ["journal.plist"], "没有残留临时文件 \(leftovers)")
  let attrs = (try? FileManager.default.attributesOfItem(atPath: journal.url.path)) ?? [:]
  check((attrs[.posixPermissions] as? Int) == 0o600, "正式文件权限 0600")
  // 目标是目录 → rename 失败，临时文件被清理。
  let blocked = DurableShadeJournal(url: dir.appendingPathComponent("blockdir"))
  try! FileManager.default.createDirectory(at: blocked.url, withIntermediateDirectories: true)
  check((try? blocked.save([["id": 3]])) == nil, "改名失败如实抛错")
  check(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).allSatisfy { !$0.hasSuffix(".tmp") },
        "改名失败后清掉临时文件")

  // MARK: 3. SPU 加速度计：Open 必失败
  let spu = AppleSPUAccelerometer(openManager: { _ in kIOReturnNotPermitted }, wakeDriver: { true })
  for _ in 0..<50 {
    spu.start()
    usleep(5_000)
    spu.stop()
  }
  RunLoop.main.run(until: Date().addingTimeInterval(0.5))
  check(true, "Open 失败的 manager 反复 start/stop 没有 abort")

  try? FileManager.default.removeItem(at: dir)
  print(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
  exit(failures == 0 ? 0 : 1)

  }
}
