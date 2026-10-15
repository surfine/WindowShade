import os

// 面向系统的诊断走统一日志（规格 N2）：`log stream --predicate 'subsystem == "com.windowshade.prototype"'`
// 就能看到启动、权限变化、事件通道体检与睡醒恢复，不用翻文件。文件日志（wlog）照旧保留，探针读它。
// 这里只写我们自己的固定标签、计数和 build 号，没有窗口标题、文件名这类用户数据，所以标成 .public；
// 以后往这里加用户数据，一律用默认的 <private>，并对照 docs/privacy-page.md 登记。
enum SystemLog {
    static let subsystem = "com.windowshade.prototype"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let input = Logger(subsystem: subsystem, category: "input")
}
