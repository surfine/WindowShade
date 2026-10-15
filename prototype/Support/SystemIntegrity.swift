import Darwin

/// 系统完整性保护（SIP）是不是全开着。全开时，跨进程的 SkyLight 窗口改动（私有停车到屏外、调透明度）
/// 会被静默忽略：调用回报成功，窗口一动不动（规格 R9 的追查：本机 172 次停车 0 次生效，csrutil 显示开着）。
/// 读的是 csr_get_active_config（libsystem 导出，csrutil 自己也用它）；读不到时按「全开」算——
/// 那样最多是少试一条本来就大概率无效的路，不会误判成能藏。
enum SystemIntegrity {
    static let fullyEnabled: Bool = {
        typealias ReadConfig = @convention(c) (UnsafeMutablePointer<UInt32>) -> Int32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csr_get_active_config") else { return true }
        var config: UInt32 = 0
        guard unsafeBitCast(symbol, to: ReadConfig.self)(&config) == 0 else { return true }
        return config == 0
    }()
}
