"""Supplement behavioral tests with checks on integration boundaries in the legacy app."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
shade = (root / 'prototype/App/ShadeController.swift').read_text()
transaction = shade.split('func installOverlay(', 1)[1].split('func installInteractiveNativeCollapse', 1)[0]
assert transaction.index('recordShadeRecoveryIntent(') < transaction.index('let hide = hideWindow(')
assert transaction.index('let hideVerifiedNow = hideTookEffect(') < transaction.index('didVerifyFold(')
assert transaction.index('guard intentWritten else') < transaction.index('to: .folded'), 'Failed durable intent must still be able to transition capturing -> failed'
sync_finish = shade.split('if !handedToAsyncCapture {', 1)[1].split('guard let pos =', 1)[0]
assert 'success: true' not in sync_finish, 'Returning from shade does not prove hiding completed'
native = shade.split('func installInteractiveNativeCollapse', 1)[1].split('if mode == .interactiveNative', 1)[0]
assert 'completeFold(success: true)' in native, 'Verified native collapse must complete explicitly'
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
settings = (root / 'prototype/Effects/DuoSettingsWindow.swift').read_text()
assert 'struct MenuState' in menu
for title in ['屏幕开合角度：', '当前窗口', '使用说明…', '设置…']:
    assert title in menu, f'menu state entry missing: {title}'
for title in ['启用桌面开合效果', '启用窗口卷帘动画', '预览桌面效果…', '停止所有效果']:
    assert title not in menu, f'redundant menu entry still present: {title}'
assert 'showDuoSettings(section: .effects)' in settings
for section in ['效果', '卷帘', '权限与启动', '高级']:
    assert section in settings, f'unified settings section missing: {section}'
assert '打开诊断日志' in settings
print('PASS: recovery intent precedes hiding, animation follows verification, synchronous restore contract, session teardown and capture exclusion are wired')
