#!/usr/bin/env python3
"""把登记表生成设置页用的 Swift 数据源。

页面从 tools/privacy/registry.json 生成；生成的文件要提交，tests/run-privacy-page-sync.sh
会重跑一次并比对，防止手改数据源和登记表跑偏。
current 行用现有快照。planned 行默认不显示；行上写了 appears_with 的，对应功能打开后才出现，
出现时值固定显示「还没读」。

生成时顺带守住用户看得到的文字：每一行都要有 combined（合起来能看出什么）和 subtitle（一行原因）；
不许出现内部代号（P1、A2a、IPC、L1、Sparkle……）和「待验证」这类自认没核过的句子。
违反就非零退出，页面和登记表一起红。
"""
import argparse
import json
import pathlib
import re
import sys

p = argparse.ArgumentParser()
p.add_argument("--registry", default=None)
p.add_argument("--out", required=True)
a = p.parse_args()

root = pathlib.Path(__file__).resolve().parents[2]
registry = pathlib.Path(a.registry) if a.registry else root / "tools/privacy/registry.json"
data = json.loads(registry.read_text())


def localized(prefix: str, field: str, zh: str, en: str | None) -> str:
    """有条目级英文（signal["en"][field]）就走 WSL10n 出当前语言；没有就照旧出中文常量。
    中文仍是语义身份（目录键里的 zh），英文是显示译文。"""
    if en:
        key = f"privacy.{prefix}.{field}"
        return f'WSL10n.text({swift(key)}, zh: {swift(zh)})'
    return swift(zh)


def swift(_value: str) -> str:
    return '"' + _value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


TEXT_FIELDS = ("label", "subtitle", "reads", "purpose", "destination", "activation", "toggle", "combined")
FORBIDDEN = re.compile(r"\b(P\d|A2[ab]|IPC|L1|Sparkle)\b|待验证|待核|待P\d|磁盘行为待")

declared = [g["title"] for g in data["groups"]]
problems: list[str] = []
for signal in data["signals"]:
    if not signal.get("combined"):
        problems.append(f'{signal["id"]}: 缺 combined（合起来能看出什么）')
    if not signal.get("subtitle"):
        problems.append(f'{signal["id"]}: 缺 subtitle（一行原因）')
    if signal["group"] not in declared:
        problems.append(f'{signal["id"]}: group「{signal["group"]}」没有在 groups 里声明')
    for key in TEXT_FIELDS:
        value = signal.get(key) or ""
        if FORBIDDEN.search(value):
            problems.append(f'{signal["id"]}.{key}: 含内部代号或「待验证」类句子：{value}')
for group in data["groups"]:
    for key in ("title", "subtitle"):
        if FORBIDDEN.search(group[key]):
            problems.append(f'groups.{group["title"]}.{key}: 含内部代号')
if problems:
    print("FAIL privacy-page-source:", file=sys.stderr)
    for line in problems:
        print("  " + line, file=sys.stderr)
    sys.exit(1)

interfaces: dict[str, list[str]] = {}
for site in data["sites"]:
    interfaces.setdefault(site["signal"], [])
    if site["symbol"] not in interfaces[site["signal"]]:
        interfaces[site["signal"]].append(site["symbol"])

lines = [
    "// 由 tools/privacy/make-privacy-page-source.py 从 tools/privacy/registry.json 生成；不要手改。",
    "// current 行显示现有快照。planned 行默认不显示；写了 appearsWith 的，对应功能打开后才出现，值固定为「还没读」。",
    "import Foundation",
    "",
    "struct WS2PrivacyRow: Sendable {",
    "    let id: String",
    "    let label: String",
    "    /// public / sensitive / private：private 的值导出时不带原值。",
    "    let sensitivity: String",
    "    let group: String",
    "    let reads: String",
    "    let purpose: String",
    "    let destination: String",
    "    let activation: String",
    "    let toggle: String",
    "    /// current 或 planned。planned 的值固定是「还没读」。",
    "    let status: String",
    "    /// 「合起来能看出什么」：这一项和别的项合起来，别人可能推出什么。",
    "    let combined: String?",
    "    /// 登记表里这类读取用到的接口名；「显示技术细节」打开后才看得到。",
    "    let interfaces: [String]",
    "    /// 行上那一句原因（一行，最多十几个字）。",
    "    var subtitle: String = \"\"",
    "    /// 要用到的系统授权，例如「辅助功能」；没有就是 nil。",
    "    var permission: String? = nil",
    "    /// 展开后放哪个开关（页面按这个名字找原来的那一个设置）；没有就是 nil。",
    "    var switchID: String? = nil",
    "    /// 对应功能打开后这一行才出现（planned 行默认不显示）；没有就是 nil。",
    "    var appearsWith: String? = nil",
    "}",
    "",
    "/// 一组的标题和副标题。",
    "struct WS2PrivacyGroup: Sendable {",
    "    let title: String",
    "    let subtitle: String",
    "}",
    "",
    "enum WS2PrivacyData {",
    "    static let groups: [WS2PrivacyGroup] = [",
]
for group in data["groups"]:
    gen = group.get("en", {})
    lines.append('        WS2PrivacyGroup(title: '
                 + localized("group." + group["title"], "title", group["title"], gen.get("title"))
                 + ', subtitle: '
                 + localized("group." + group["title"], "subtitle", group["subtitle"], gen.get("subtitle"))
                 + '),')
lines += [
    "    ]",
    "",
    "    static let groupOrder: [String] = [" + ", ".join(swift(g) for g in declared) + "]",
    "",
    "    static let rows: [WS2PrivacyRow] = [",
]
for signal in data["signals"]:
    lines.append("        WS2PrivacyRow(")
    sen = signal.get("en", {})
    # 字段顺序与提交件逐字节一致（tests/run-privacy-page-sync.sh 会比对）；只把文本字段接到目录。
    for key in ("id", "label", "sensitivity", "group", "reads", "purpose", "destination", "activation", "toggle", "status"):
        if key in TEXT_FIELDS:
            lines.append(f"            {key}: {localized(signal['id'], key, signal[key], sen.get(key))},")
        else:
            lines.append(f"            {key}: {swift(signal[key])},")
    lines.append(f"            combined: {localized(signal['id'], 'combined', signal['combined'], sen.get('combined'))},")
    symbols = ", ".join(swift(s) for s in sorted(interfaces.get(signal["id"], [])))
    lines.append(f"            interfaces: [{symbols}],")
    lines.append(f"            subtitle: {localized(signal['id'], 'subtitle', signal['subtitle'], sen.get('subtitle'))},")
    if signal.get("permission"):
        lines.append(f"            permission: {swift(signal['permission'])},")
    if signal.get("switch"):
        lines.append(f"            switchID: {swift(signal['switch'])},")
    if signal.get("appears_with"):
        lines.append(f"            appearsWith: {swift(signal['appears_with'])},")
    lines.append("        ),")
lines += ["    ]", "}", ""]

pathlib.Path(a.out).write_text("\n".join(lines))
current = sum(1 for s in data["signals"] if s["status"] == "current")
planned = sum(1 for s in data["signals"] if s["status"] == "planned")
print(f"wrote {a.out}: {current} current, {planned} planned, {len(declared)} groups")
