// FS-03：文件拖近刘海。三格 / 五格判定、松在刘海那一条上 = 暂存、灰格原因、几何、从文件架拖出来不出小岛。
import AppKit
import Foundation

@main
struct FileDragSensorTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ c: Bool, _ m: String) {
        if c { print("ok   \(m)") } else { failures += 1; print("FAIL \(m)") }
    }

    static func item(_ types: String..., folder: Bool = false) -> FileDragKind.Item {
        FileDragKind.Item(types: Set(types), isFolder: folder)
    }

    static func main() {
        classification()
        plan()
        geometry()
        MainActor.assumeIsolated { pasteboard() }
        if failures > 0 { print("\(failures) 项失败"); exit(1) }
        print("全部通过")
    }

    static func classification() {
        let file = item("public.file-url", "public.utf8-plain-text")
        expect(FileDragKind.classify([file]) == .files(count: 1, hasFolder: false), "文件和文字混着拖：只收文件")
        expect(FileDragKind.classify([file, file, file]) == .files(count: 3, hasFolder: false), "三个文件")
        expect(FileDragKind.classify([file, item("public.file-url", folder: true)]) == .files(count: 2, hasFolder: true), "里面有文件夹")
        expect(FileDragKind.classify([item("public.tiff", "public.url")]) == .image, "网页上的图：有图片数据就是图片，不是链接")
        expect(FileDragKind.classify([item("public.url", "public.utf8-plain-text")]) == .link, "网址是链接")
        expect(FileDragKind.classify([item("public.utf8-plain-text")]) == .text, "只有文字")
        expect(FileDragKind.classify([item("com.apple.pasteboard.promised-file-url")]) == .files(count: 1, hasFolder: false), "只给承诺文件：按文件")
        expect(FileDragKind.classify([item("com.example.private")]) == nil, "认不出的类型不出小岛")
        expect(FileDragKind.classify([]) == nil, "空的不出小岛")
        let own = item("public.file-url", FileDragKind.fileShelfSourceType)
        expect(FileDragKind.classify([own]) == nil, "从文件架拖出来的东西经过刘海不出落点小岛")
        expect(FileDragKind.classify([own, file]) == nil, "混着从文件架拖出来的也不出")

        expect(FileDragKind.files(count: 3, hasFolder: false).holdingLabel == "3 个", "左耳：3 个")
        expect(FileDragKind.files(count: 1, hasFolder: true).holdingLabel == "文件夹", "左耳：文件夹")
        expect(FileDragKind.files(count: 1, hasFolder: false).holdingLabel == "文件", "左耳：一个文件")
        expect([FileDragKind.text, .image, .link].map(\.holdingLabel) == ["文字", "图片", "链接"], "左耳：文字、图片、链接")
    }

    static func plan() {
        let env = FileDropEnvironment()
        let files = FileDragKind.files(count: 3, hasFolder: false)
        // 三格：暂存 / 隔空投送 / 用 App 打开。
        expect(FileDropCell.allCases.map(\.title) == ["暂存", "隔空投送", "用 App 打开"], "文件是三格")
        expect(FileDropCell.allCases.allSatisfy { FileDropPlan.state(of: $0, kind: files, env: env).enabled }, "文件三格都能用")

        // 灰格和原因。
        var full = env; full.shelfFull = true
        expect(FileDropPlan.state(of: .stage, kind: files, env: full) == FileDropCellState(enabled: false, reason: "文件架满了"), "满了：暂存灰着，文件架满了")
        var noAir = env; noAir.airDropAvailable = false
        expect(FileDropPlan.state(of: .airDrop, kind: files, env: noAir) == FileDropCellState(enabled: false, reason: "隔空投送没开"), "隔空投送没开")
        expect(FileDropPlan.state(of: .openWith, kind: .text, env: env) == FileDropCellState(enabled: false, reason: "文字挑不了 App"), "文字挑不了 App")
        expect(!FileDropPlan.state(of: .openWith, kind: .image, env: env).enabled, "图片也挑不了 App")
        expect(FileDropPlan.state(of: .openWith, kind: .link, env: env).enabled, "链接能用 App 打开（只亮浏览器）")
        var off = env; off.shelfEnabled = false
        expect(!FileDropPlan.state(of: .stage, kind: files, env: off).enabled, "文件架没开：暂存灰着")
        var busy = env; busy.airDropBusy = true
        expect(FileDropPlan.state(of: .airDrop, kind: files, env: busy).reason == "正在隔空投送", "上一次隔空投送还没完")

        // 松手。
        expect(FileDropPlan.release(at: .cell(.stage), kind: files, env: env) == .stage, "松在暂存格：暂存")
        expect(FileDropPlan.release(at: .cell(.airDrop), kind: files, env: env) == .airDrop, "松在隔空投送格：隔空投送")
        expect(FileDropPlan.release(at: .cell(.openWith), kind: files, env: env) == .openWith, "松在用 App 打开格：用 App 打开")
        expect(FileDropPlan.release(at: .strip, kind: files, env: env) == .stage, "松在刘海那一条上 = 暂存")
        expect(FileDropPlan.release(at: .strip, kind: .text, env: env) == .stage, "文字松在刘海那一条上也是暂存")
        expect(FileDropPlan.release(at: .strip, kind: files, env: full) == .nothing, "文件架满了：刘海那一条上松手什么都不做")
        expect(FileDropPlan.release(at: .cell(.stage), kind: files, env: full) == .nothing, "灰格上松手什么都不做")
        expect(FileDropPlan.release(at: .cell(.openWith), kind: .text, env: env) == .nothing, "文字松在用 App 打开：什么都不做")
        expect(FileDropPlan.release(at: .margin, kind: files, env: env) == .nothing, "松在格子外的边距：什么都不做")
        expect(FileDropPlan.release(at: .outside, kind: files, env: env) == .nothing, "松在岛外：什么都不做")

        // 右耳。
        expect(FileDropPlan.rightEar(at: .cell(.stage), kind: files, env: env) == nil, "做得了：右耳空着")
        expect(FileDropPlan.rightEar(at: .cell(.stage), kind: files, env: full) == "文件架满了", "右耳说文件架满了")
        expect(FileDropPlan.rightEar(at: .strip, kind: files, env: full) == "文件架满了", "刘海那一条上也说为什么")
        expect(FileDropPlan.rightEar(at: .cell(.openWith), kind: .text, env: env) == "文字挑不了 App", "右耳说文字挑不了 App")
        expect(FileDropPlan.rightEar(at: .outside, kind: files, env: full) == nil, "岛外右耳空着")
    }

    static func geometry() {
        let screenTop: CGFloat = 900, midX: CGFloat = 756
        expect(FileDropGeometry.shouldShow(pointer: CGPoint(x: midX, y: screenTop - 59), screenTop: screenTop, notchMidX: midX), "离顶 59 点：垂下")
        expect(!FileDropGeometry.shouldShow(pointer: CGPoint(x: midX, y: screenTop - 61), screenTop: screenTop, notchMidX: midX), "离顶 61 点：不垂")
        expect(FileDropGeometry.shouldShow(pointer: CGPoint(x: midX + 194, y: screenTop - 10), screenTop: screenTop, notchMidX: midX), "横向 ±194 以内：垂下")
        expect(!FileDropGeometry.shouldShow(pointer: CGPoint(x: midX - 195, y: screenTop - 10), screenTop: screenTop, notchMidX: midX), "横向超过 194：不垂")

        let island = FileDropGeometry.island(notchMidX: midX, screenTop: screenTop)
        expect(island.size == CGSize(width: 340, height: 84) && island.maxY == screenTop && island.midX == midX, "340 × 84，顶边贴屏幕顶，横向居中")
        let cells = FileDropGeometry.cellRects(in: island)
        expect(cells.count == 3 && cells.allSatisfy { $0.size == CGSize(width: 100.7, height: 34.5) }, "格 100.7 × 34.5")
        expect(abs((cells[1].minX - cells[0].maxX) - 6) < 0.001 && abs((cells[2].minX - cells[1].maxX) - 6) < 0.001, "格间 6")
        expect(cells[0].minY == island.minY + 10, "底边距 10")
        expect(abs(cells[0].minX - island.minX - (island.maxX - cells[2].maxX)) < 0.001, "三格左右对称")

        func hit(_ x: CGFloat, _ y: CGFloat) -> FileDropHit { FileDropGeometry.hit(CGPoint(x: x, y: y), island: island) }
        expect(hit(cells[0].midX, cells[0].midY) == .cell(.stage), "指在第一格：暂存")
        expect(hit(cells[1].midX, cells[1].midY) == .cell(.airDrop), "指在第二格：隔空投送")
        expect(hit(cells[2].midX, cells[2].midY) == .cell(.openWith), "指在第三格：用 App 打开")
        expect(hit((cells[0].maxX + cells[1].minX) / 2 + 1, cells[0].midY) == .cell(.airDrop), "格间的缝算挨着的那一格")
        expect(hit(island.midX, island.maxY - 10) == .strip, "刘海那一条上")
        expect(hit(cells[1].midX, cells[0].maxY + 1) == .strip, "格子上沿以上都是那一条")
        expect(hit(island.minX + 3, cells[0].midY) == .margin, "格子左边的边距")
        expect(hit(cells[1].midX, island.minY + 3) == .margin, "格子下面的边距")
        expect(hit(island.midX, island.minY - 1) == .outside && hit(island.maxX + 5, island.midY) == .outside, "岛外")

        expect(FileDropGeometry.shouldKeep(pointer: CGPoint(x: island.midX, y: island.minY - 23), island: island), "出岛外不到 24 点还留着")
        expect(!FileDropGeometry.shouldKeep(pointer: CGPoint(x: island.midX, y: island.minY - 25), island: island), "出岛外 24 点就收")
    }

    @MainActor
    static func pasteboard() {
        func board(_ build: (NSPasteboardItem) -> Void) -> NSPasteboard {
            let pb = NSPasteboard.withUniqueName()
            pb.clearContents()
            let it = NSPasteboardItem()
            build(it)
            pb.writeObjects([it])
            return pb
        }
        let fileBoard = board { $0.setString("file:///tmp/a.txt", forType: .fileURL) }
        expect(FileDragSensor.kind(of: fileBoard) == .files(count: 1, hasFolder: false), "拖动剪贴板里一个文件")
        let folderBoard = board { $0.setString("file:///tmp/dir/", forType: .fileURL) }
        expect(FileDragSensor.kind(of: folderBoard) == .files(count: 1, hasFolder: true), "路径以斜杠结尾是文件夹")
        let textBoard = board { $0.setString("你好", forType: .string) }
        expect(FileDragSensor.kind(of: textBoard) == .text, "拖动剪贴板里一段文字")
        let own = board {
            $0.setString("file:///tmp/a.txt", forType: .fileURL)
            $0.setData(Data([1]), forType: NSPasteboard.PasteboardType(FileDragKind.fileShelfSourceType))
        }
        expect(FileDragSensor.kind(of: own) == nil, "带文件架记号的拖动不出小岛")
        if case .text(let text)? = FileDropPayload.read(textBoard, kind: .text) { expect(text == "你好", "松手后才读文字") } else { expect(false, "松手后才读文字") }
        if case .files(let urls)? = FileDropPayload.read(fileBoard, kind: .files(count: 1, hasFolder: false)) {
            expect(urls.map(\.path) == ["/tmp/a.txt"], "松手后才读文件路径")
        } else { expect(false, "松手后才读文件路径") }
    }
}
