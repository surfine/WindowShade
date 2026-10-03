#!/usr/bin/env python3
"""把登记表里 status=current 的行生成设置页用的 Swift 数据源。

页面和官网都从 tools/privacy/registry.json 生成；生成的文件要提交，tests/run-privacy-page-sync.sh
会重跑一次并比对，防止手改数据源和登记表跑偏。planned 行不上页面。
"""
import argparse
import json
import pathlib

p = argparse.ArgumentParser()
p.add_argument("--registry", default=None)
p.add_argument("--out", required=True)
a = p.parse_args()

root = pathlib.Path(__file__).resolve().parents[2]
registry = pathlib.Path(a.registry) if a.registry else root / "tools/privacy/registry.json"
data = json.loads(registry.read_text())


def swift(_value: str) -> str:
    return '"' + _value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


groups: list[str] = []
for signal in data["signals"]:
    if signal["status"] == "current" and signal["group"] not in groups:
        groups.append(signal["group"])

interfaces: dict[str, list[str]] = {}
for site in data["sites"]:
    interfaces.setdefault(site["signal"], [])
    if site["symbol"] not in interfaces[site["signal"]]:
        interfaces[site["signal"]].append(site["symbol"])

lines = [
    "// 由 tools/privacy/make-privacy-page-source.py 从 tools/privacy/registry.json 生成；不要手改。",
    "// 只有 status=current 的行会出现在设置里；planned 行等对应功能接通再说。",
    "import Foundation",
    "",
    "struct WS2PrivacyRow: Sendable {",
    "    let id: String",
    "    let label: String",
    "    /// public / sensitive / private：private 的值默认不展开。",
    "    let sensitivity: String",
    "    let group: String",
    "    let reads: String",
    "    let purpose: String",
    "    let destination: String",
    "    let activation: String",
    "    let toggle: String",
    "    /// 登记表里这类读取用到的接口名；「显示技术细节」打开后才看得到。",
    "    let interfaces: [String]",
    "}",
    "",
    "enum WS2PrivacyData {",
    "    static let groupOrder: [String] = [" + ", ".join(swift(g) for g in groups) + "]",
    "",
    "    static let rows: [WS2PrivacyRow] = [",
]
for signal in data["signals"]:
    if signal["status"] != "current":
        continue
    lines.append("        WS2PrivacyRow(")
    for key in ("id", "label", "sensitivity", "group", "reads", "purpose", "destination", "activation", "toggle"):
        lines.append(f"            {key}: {swift(signal[key])},")
    symbols = ", ".join(swift(s) for s in sorted(interfaces.get(signal["id"], [])))
    lines.append(f"            interfaces: [{symbols}],")
    lines.append("        ),")
lines += ["    ]", "}", ""]

pathlib.Path(a.out).write_text("\n".join(lines))
print(f"wrote {a.out}: {sum(1 for s in data['signals'] if s['status'] == 'current')} rows in {len(groups)} groups")
