#!/usr/bin/env python3
"""把目录里的简体源句转成台湾用语的繁体（zh-Hant）列。

用法：
    python3 tools/localize/zh-hant.py            # 写入 prototype/Resources/Localizable.xcstrings
    python3 tools/localize/zh-hant.py --audit    # 只报告：转换结果里还剩哪些大陆用词

流程：每条 zh-Hans → OpenCC `s2twp`（简体→繁体 + 台湾用词）→ 套本文件的台湾专名表
（Apple 台湾官方用词与我们自己的产品词，OpenCC 不认识或译错的那批）→ 写 zh-Hant 列。

前置：opencc CLI（brew install opencc）。
新增文案入库后重跑本脚本即可，不用手改 xcstrings 的 zh-Hant 列。
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOG = os.path.join(ROOT, "prototype", "Resources", "Localizable.xcstrings")

# 台湾专名表：OpenCC s2twp 的输出 → 台湾实际用词。
# 分三类：① Apple 台湾官方界面术语（OpenCC 不认识或给的是大陆式译法）；
# ② Mac 通用部件的台湾叫法；③ 我们自己的产品词在台湾的写法。
# 顺序无关（按 needle 长度从长到短替换），但同一处多次命中时以更长的为准。
#
# 带 `SKIP:` 注释的条目不参与盲替换——对应 taiwan.md 转换器的 `auto_convert: false`：
# 「这个说法该换成台湾用词」和「能不能对全文做字符串替换」是两件事，中国侧那个词
# 若在台湾另有正当用法，替换会改坏正确文字（他们的例子：挺胸→蠻胸、力挺→力蠻）。
# 我们的文案是自家写的，风险低，但单字／通用词的全局替换同样危险，一律标 SKIP，
# 要用时人工决定。方法出处见 docs/research/taiwan-terminology-converter.md。
TAIWAN_TERMS = [
    # ① Apple 台湾官方术语
    ("排程中心", "指揮中心"),        # Mission Control
    ("選單欄", "選單列"),            # menu bar
    ("標題欄", "標題列"),            # title bar（台湾 Apple 用「列」）
    ("狀態欄", "狀態列"),
    ("全屏", "全螢幕"),
    ("畫中畫", "子母畫面"),          # Picture in Picture
    ("輔助功能", "輔助使用"),        # Accessibility
    ("快捷鍵", "快速鍵"),            # keyboard shortcut
    ("雙擊", "按兩下"),
    ("三擊", "按三下"),
    ("單擊", "按一下"),
    ("拖動", "拖移"),
    ("拖拽", "拖移"),
    ("訪問", "存取"),
    ("鎖屏", "鎖定畫面"),            # lock screen
    ("塊屏", "塊螢幕"),              # 「这块屏」= this display
    ("內建屏", "內建螢幕"),
    ("會話", "工作階段"),            # session
    ("主屏幕", "主畫面"),            # home screen（台湾叫主畫面）
    ("外設", "周邊裝置"),            # peripheral
    ("許可權", "權限"),              # OpenCC 的错译：permission → 權限
    ("訪達", "Finder"),              # Finder 在台湾不译
    ("這臺", "這台"),                # 台湾 Apple 写「台」（台灣/這台 Mac）
    ("臺", "台"),                    # 其余「臺」同此（啟動台已单独处理）
    ("配置", "設定"),                # configuration → 設定（台湾）
    ("手柄", "手把"),                # game controller（台湾叫手把）
    ("搖桿", "搖桿"),                # 台湾也用「搖桿」，保留
    ("在Finder中顯示", "在 Finder 中顯示"),
    ("映象", "鏡像"),                # mirror（OpenCC 给了「映象」，那是 image）
    ("反饋", "回饋"),
    ("認證", "驗證"),                # authentication
    ("應用程序", "應用程式"),
    ("硬盤", "硬碟"),
    ("優盤", "隨身碟"),
    ("打印機", "印表機"),
    ("鼠標", "滑鼠"),                # 兜底，正常 OpenCC 已换
    ("隱私", "隱私權"),              # 台湾系统设置的页面名（隱私權與安全性）
    ("隔空投送", "AirDrop"),         # 台湾不译这个名字
    ("隔空播放", "AirPlay"),
    ("負一屏", "主畫面最左邊那一頁"),
    ("分屏", "分割畫面"),            # Split View 的台湾叫法
    # SKIP：单字「屏」的全局替换风险最高——「屏蔽」「屏東」（地名）「屏風」都不该动。
    # 现在的文案里没有这些词，所以这条仍然生效；文案一旦出现，先加进 FALSE_POSITIVES。
    ("屏", "螢幕"),                  # 其余单字「屏」都是"屏幕"义（半屏/这块屏/锁屏已先处理）
    # ② Mac 部件
    ("窗口", "視窗"),
    ("程序塢", "Dock"),
    ("程式塢", "Dock"),
    ("廢紙簍", "垃圾桶"),
    ("觸摸板", "觸控板"),
    ("妙控鼠標", "巧控滑鼠"),
    ("妙控滑鼠", "巧控滑鼠"),
    ("妙控鍵盤", "巧控鍵盤"),
    ("妙控板", "巧控板"),
    # ③ 产品词
    ("劉海", "瀏海"),                # notch（头发那个词，台湾 Apple 也用它指刘海）
    ("啟動臺", "啟動台"),            # Launchpad
    ("魔法平鋪", "魔法並排"),
    ("捲簾條", "捲簾條"),            # 确认写法（OpenCC 已对）
    # ④ 2026-10-14 复核（对照 taiwan.md 的 2057 条词对做覆盖核对，见
    # docs/research/taiwan-terminology-converter.md）：我们文案里还残留的大陆腔。
    # 每条都按台湾 Apple 的官方写法定；他们的表里写法更口语或与 Apple 不一致的，
    # 记在 §「有意保留」里不改（恢复/解鎖/藍牙/日誌/重置/標籤頁/進度條/一鍵…）。
    ("滾動", "捲動"),                # scroll（Apple 台湾：捲動）
    ("斷開", "中斷連線"),            # disconnect（Apple 台湾：中斷連線）
    ("居中", "置中"),                # center（台湾：置中）
    ("區域網", "區域網路"),          # LAN（台湾：區域網路）
    ("只讀", "唯讀"),                # read-only（Apple 台湾：唯讀）
    ("發送", "傳送"),                # send（Apple 台湾：傳送）
    ("超時", "逾時"),                # timeout（Apple 台湾：逾時）
    ("攝像頭", "網路攝影機"),        # camera（Apple 台湾：網路攝影機）
    ("賬戶", "帳戶"),                # account（台湾写「帳」，不是「賬」）
    ("賬號", "帳號"),
    ("退出登入", "登出"),            # sign out（台湾：登出）
    ("彈窗", "彈出視窗"),            # dialog/pop-up（Apple 台湾：彈出式視窗）
    ("回車", "Return"),              # 键盘键名跟我们的 Esc 一致，用英文键名
    ("Return只", "Return 只"),        # 键名与汉字之间留一个空格（与「按 Esc」一致）
    ("Return開始", "Return 開始"),
    ("演示", "示範"),                # demo（台湾：示範）
    ("詳情", "詳細資訊"),            # details（Apple 台湾：詳細資訊）
    ("匹配", "對應"),                # match（台湾：對應／相符）
    ("推送", "推播"),                # push notification（台湾：推播）
    ("音箱", "揚聲器"),              # speaker（Apple 台湾：揚聲器）
    ("回收站", "資源回收筒"),        # recycle bin（台湾：資源回收筒）
    ("鉤子", "掛勾"),                # hook（台湾：掛勾）
    ("連續互通", "接續互通"),        # Continuity（Apple 台湾官方：接續互通）
    ("替換", "取代"),                # replace（台湾：取代）
    ("普通話", "國語"),              # Mandarin（台湾：國語）
    ("令牌", "權杖"),                # token（台湾：權杖）
]

# 盲替换的保护清单：出现这些片段时整段绕开，不做词表替换。
# 对应 taiwan.md 的 `false_positives`——「含 china 字串但其实是台湾合法写法」。
# 我们目前为空：文案是自家写的，未出现这类词；新增文案时按需补。
FALSE_POSITIVES = [
    # 已确认的一例：台湾也把 documentation 叫「文件」——我们的
    # privacy.group.用了系统没公开的方法的.subtitle 就是「Apple 沒寫進文件」。
    # 词表里没有「文件 → 檔案」这条规则（OpenCC 只把「文档」给成「文件」），
    # 这里留档，防止将来有人加这条规则时改坏它。
    "沒寫進文件",
    # "屏東",   # 地名（含「屏」）
    # "屏蔽",   # 动词
    # "質量",   # 物理量，台湾也用「質量」
]

# 审计用：出现即说明这条还没换成台湾说法（排除我们有意保留的写法）。
# 后一半取自 taiwan.md 的常见对照（当核对清单用，没有搬他们的数据）。
AUDIT_WORDS = [
    "窗口", "選單欄", "默認", "設置", "快捷鍵", "單擊", "雙擊", "全屏",
    "畫中畫", "妙控", "隱私(?!權)", "輔助功能", "鼠標", "軟件", "網絡", "信息",
    "文件夾", "打印", "磁盤", "視頻", "屏幕", "優盤",
    "打車", "博客", "博主", "質量", "算法", "數組", "文件(?!架)",
]


# 标了 SKIP 的词（对应 taiwan.md 的 auto_convert: false）：留在表里做文档，不参与替换。
SKIPPED: set[str] = set()


def convert(texts):
    """批量走 opencc s2twp；用哨兵保住换行。"""
    sentinel = "\x00"
    lines = [t.replace("\r\n", "\n").replace("\n", sentinel) for t in texts]
    with tempfile.NamedTemporaryFile("w+", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(lines))
        path = handle.name
    try:
        out = subprocess.run(["opencc", "-c", "s2twp", "-i", path],
                             capture_output=True, text=True, check=True).stdout
    finally:
        os.unlink(path)
    result = out.split("\n")
    if result and result[-1] == "":
        result.pop()
    if len(result) != len(texts):
        raise SystemExit(f"opencc 行数不匹配：{len(result)} != {len(texts)}")
    return [r.replace(sentinel, "\n") for r in result]


def apply_terms(text):
    """词表替换：长度降序（长的先换，避免被短的先截走）；命中的词写成 SKIP 就跳过。

    带 `SKIP:` 的条目按 taiwan.md 的 `auto_convert: false` 语义处理：仍留在表里当文档，
    但不参与替换。FALSE_POSITIVES 里的片段先摘出去，换完再放回来。
    """
    protected = []
    for index, fragment in enumerate(FALSE_POSITIVES):
        marker = f"\u0001{index}\u0001"
        if fragment in text:
            text = text.replace(fragment, marker)
            protected.append((marker, fragment))
    for source, target in sorted(TAIWAN_TERMS, key=lambda pair: -len(pair[0])):
        if source == target or source in SKIPPED:
            continue
        text = text.replace(source, target)
    for marker, fragment in protected:
        text = text.replace(marker, fragment)
    return text


def convert_to_traditional(texts):
    """整条流水线：OpenCC s2twp + 台湾专名表。别的脚本（short-hant.py）也用它。"""
    return [apply_terms(t) for t in convert(texts)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", action="store_true", help="只报告残留大陆用词，不写文件")
    args = parser.parse_args()

    data = json.load(open(CATALOG, encoding="utf-8"))
    strings = data["strings"]
    keys = [k for k, entry in strings.items() if "zh-Hans" in entry.get("localizations", {})]
    sources = [strings[k]["localizations"]["zh-Hans"]["stringUnit"]["value"] for k in keys]

    converted = [apply_terms(t) for t in convert(sources)]

    if args.audit:
        hits = {}
        known = 0
        for key, text in zip(keys, converted):
            # 命中 FALSE_POSITIVES 的算「已确认不动」，不报成待查。
            if any(fragment in text for fragment in FALSE_POSITIVES):
                known += 1
                continue
            for word in AUDIT_WORDS:
                if re.search(word, text):
                    hits.setdefault(word, []).append((key, text))
        for word, items in sorted(hits.items(), key=lambda kv: -len(kv[1])):
            print(f"{word}: {len(items)} 处")
            for key, text in items[:3]:
                print(f"    {key}: {text}")
        todo = {k for v in hits.values() for k, _ in v}
        print(f"\n合计 {len(keys)} 条；{known} 条命中保护清单（已确认不动）；待查 {len(todo)} 条")
        return

    for key, value in zip(keys, converted):
        localizations = strings[key]["localizations"]
        localizations["zh-Hant"] = {"stringUnit": {"state": "translated", "value": value}}
    json.dump(data, open(CATALOG, "w", encoding="utf-8"), ensure_ascii=False, indent=2,
              separators=(",", " : "))
    print(f"写入 zh-Hant：{len(keys)} 条", file=sys.stderr)


if __name__ == "__main__":
    main()
