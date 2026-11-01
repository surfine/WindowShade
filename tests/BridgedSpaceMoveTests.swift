import Cocoa

// 私有跨桌面移动：只验证“找不到就不装”的路径。真正移动窗口要在真机/虚拟机上跑。

@main
struct BridgedSpaceMoveTests {
    static func main() {
        // 不存在的映像、不存在的符号：必须返回 nil，而不是越界读
        precondition(BridgedSpaceMove.findLocalSymbol(image: "/nonexistent/SkyLight", name: "nope") == nil)

        // 没有 initWithWindows:spaceID: 的类不能当成可初始化
        precondition(BridgedSpaceMove.canInitialize(NSObject.self) == false)

        // 可用性查询本身不该崩；结果取决于当前系统
        _ = BridgedSpaceMove.isAvailable

        print("BridgedSpaceMoveTests ok")
    }
}
