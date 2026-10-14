#!/bin/bash
# 刘海文案本地化：键齐全（缺键就失败）、中文默认不变、英文译文完整；第27批起全目录逐键走 WSL10n。
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/check-localizable.py
OUT=.build/localization-tests
rm -rf "$OUT"
mkdir -p "$OUT"
xcrun xcstringstool compile prototype/Resources/Localizable.xcstrings -o "$OUT/strings"
swiftc -parse-as-library prototype/Core/WSL10n.swift prototype/Core/SwitcherOrigin.swift prototype/Core/GestureCoach.swift \
  prototype/Core/HabitRules.swift prototype/Core/WS2SilentCopy.swift tests/LocalizationTests.swift -o "$OUT/localization"
"$OUT/localization" "$OUT/strings/en.lproj" "$OUT/strings/zh-Hant.lproj"
# 界面语言（第27批）：解析规则、偏好存取、立即生效；只碰测试专属 suite。
swiftc -parse-as-library prototype/Core/WSL10n.swift prototype/Core/InterfaceLanguage.swift \
  tests/InterfaceLanguageTests.swift -o "$OUT/language"
"$OUT/language"
