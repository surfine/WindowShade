#!/bin/bash
# 1-1：音量、亮度提示只在真的按了键时开口（纯逻辑：按键解析、窗口、让开、退回老做法）。
# LV1：拦键判定表（NotchLevelSuppression）、步长/落格/到头/符号分档（NotchLevelStep）、键盘灯键与修饰键。
# LV2：拦键与写回（NotchLevelControl）：能写才吞、写失败补发、未核对版本只旁听、松开跟着按下吞。
# LV4：全屏出两耳走判定表、输出设备分类、设置行三态（纯逻辑）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/notch-level-tests

# 每个测试各自带 @main，所以分开编、分开跑。
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchLevelGate.swift tests/NotchLevelGateTests.swift \
  -o .build/notch-level-tests/level
.build/notch-level-tests/level

swiftc -swift-version 6 -parse-as-library prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelSuppression.swift \
  tests/NotchLevelSuppressionTests.swift -o .build/notch-level-tests/suppression
.build/notch-level-tests/suppression

swiftc -swift-version 6 -parse-as-library prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelStep.swift \
  prototype/Core/FlickMotion.swift tests/NotchLevelStepTests.swift -o .build/notch-level-tests/step
.build/notch-level-tests/step

# LV2：拦键与写回（可替换的写入端口；不碰真机、不装监听）。
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library -D NOTCH_LEVEL_HOST_TESTING \
  prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelSuppression.swift prototype/Core/NotchLevelStep.swift \
  prototype/Core/FlickMotion.swift prototype/App/NotchLevelControl.swift tests/NotchLevelControlTests.swift \
  -o .build/notch-level-tests/control
.build/notch-level-tests/control
# LV3：两耳的几何、符号分档与设备符号、读屏那一句、全屏可见性判定。
swiftc -swift-version 6 -parse-as-library prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelStep.swift \
  prototype/Core/NotchLevelSuppression.swift prototype/Core/NotchLevelEars.swift prototype/Core/FlickMotion.swift \
  tests/NotchLevelEarsTests.swift -o .build/notch-level-tests/ears
.build/notch-level-tests/ears
# LV4：门闸接判定表（全屏可见才出两耳）、输出设备分类、设置那一行的三种副标题与“允许…”的等待。
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library \
  prototype/Core/NotchLevelGate.swift prototype/Core/NotchLevelStep.swift prototype/Core/NotchLevelSuppression.swift \
  prototype/Core/NotchLevelEars.swift prototype/Core/NotchLevelOutput.swift prototype/Core/NotchLevelScreen.swift \
  prototype/Core/NotchLevelSetting.swift prototype/Core/ReleaseDefaults.swift prototype/Core/FlickMotion.swift tests/NotchLevelLV4Tests.swift \
  -o .build/notch-level-tests/lv4
.build/notch-level-tests/lv4
