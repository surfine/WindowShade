#!/usr/bin/env python3
"""第26批组合 QA 入口：把两个已有 QA enum（隐私组合、动效接力）去掉 @main，
由新 @main 在自己的 NSApp.run 里顺序调度；输出互不覆盖（page/ 与 motion/）。
记录组合前源文件身份与生成入口身份，供证据绑定。"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / "tools/design-qa"
PRIVACY = QA / "PrivacyPageCompositionPreview.swift"
MOTION = QA / "NotchRetargetPreview.swift"
ENTRY = QA / "Batch26CombinedEntry.swift"
MANIFEST = QA / "Batch26CombinedEntry.inputs.json"

DISPATCHER = '''
/// 第26批组合入口：新 @main 自有 NSApp.run，顺序调度隐私组合与动效接力两个套件；
/// 输出互不覆盖（page/ 静帧与登记表、motion/ 接力记录）。由 make-batch26-entry.py 生成。
@main enum Batch26CombinedEntry {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        guard Thread.isMainThread, NSApp.delegate == nil else { fatalError("own main-thread entry only") }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        Task { @MainActor in
            do {
                try await PrivacyPageCompositionPreview.run(out.appendingPathComponent("page"))
                try await NotchRetargetPreview.run(out.appendingPathComponent("motion"))
                exit(0)
            } catch { print("FAILED combined entry: \\(error)"); exit(1) }
        }
        NSApp.run()
    }
}
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strip_main(text: str, name: str) -> str:
    if text.count("@main ") != 1:
        raise SystemExit(f"expect exactly one @main in {name}, got {text.count('@main ')}")
    return text.replace("@main ", "", 1)


def main() -> None:
    combined = strip_main(PRIVACY.read_text(), PRIVACY.name) + "\n" + \
        strip_main(MOTION.read_text(), MOTION.name) + DISPATCHER
    ENTRY.write_text(combined)
    manifest = {
        "inputs": {str(p.relative_to(ROOT)): sha256(p) for p in (PRIVACY, MOTION, Path(__file__))},
        "entry": {str(ENTRY.relative_to(ROOT)): sha256(ENTRY)},
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps(manifest, indent=2, sort_keys=True))
    print(f"wrote {ENTRY}", file=sys.stderr)


if __name__ == "__main__":
    main()
