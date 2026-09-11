"""Supplement behavioral tests with checks on integration boundaries in the legacy app."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
shade = (root / 'prototype/App/ShadeController.swift').read_text()
transaction = shade.split('func installOverlay(', 1)[1].split('func installInteractiveNativeCollapse', 1)[0]
assert transaction.index('recordShadeRecoveryIntent(') < transaction.index('let hide = hideWindow(')
assert transaction.index('let hideVerifiedNow = hideTookEffect(') < transaction.index('didVerifyFold(')
exit_code = (root / 'prototype/App/FoldExit.swift').read_text()
sync = exit_code.split('func unshadeReturningElement(', 1)[1].split('@discardableResult', 1)[0]
assert 'interceptRestore(' not in sync, 'Synchronous callers must never acquire async restore semantics'
assert 'cancelForSynchronousRestore' in sync
controller = (root / 'prototype/Effects/DuoController.swift').read_text()
assert 'EffectSecurityBoundary.isLocked' in controller
suspend = controller.split('private func suspend()', 1)[1].split('private func resume()', 1)[0]
assert 'windowEffects.cancelAll()' in suspend and 'sensor.stop()' in suspend
assert 'excludingWindows: excluded' in controller
menu = (root / 'prototype/App/MenuBarController.swift').read_text()
for title in ['铰链角度：', '启用桌面开合效果', '启用窗口卷帘动画', '预览桌面效果…', '停止所有效果']:
    assert title in menu, f'menu state entry missing: {title}'
assert 'duoController.settings.desktopEnabled.toggle()' in menu
assert 'duoController.settings.windowsEnabled.toggle()' in menu
assert 'beginMenuPreview()' in menu
print('PASS: recovery intent precedes hiding, animation follows verification, synchronous restore contract, session teardown and capture exclusion are wired')
