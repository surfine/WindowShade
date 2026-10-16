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
assert 'completeFold(success: true, transaction:' in native, 'Verified native collapse must name its installed transaction'
assert 'bindFoldWaiters(id: id, tokens: completionTokens, transaction:' in native, 'Native waiter binding must precede completion'
exit_code = (root / 'prototype/App/FoldExit.swift').read_text()
sync = exit_code.split('func unshadeReturningElement(', 1)[1].split('@discardableResult', 1)[0]
assert 'interceptRestore(' not in sync, 'Synchronous callers must never acquire async restore semantics'
assert 'cancelForSynchronousRestore' in sync
controller = (root / 'prototype/Effects/DuoController.swift').read_text()
assert 'EffectSecurityBoundary.isLocked' in controller
suspend = controller.split('private func suspend()', 1)[1].split('private func resume()', 1)[0]
assert 'windowEffects.cancelAll()' in suspend and 'sensor.stop()' in suspend
assert 'excludingWindows: excluded' in controller
# 规格 R29: without Screen Recording the cover can never get a frame. The fold must not start an
# async job (and a doomed system-wide window enumeration) that delays the real fold and re-reads the frame later.
effects = (root / 'prototype/Effects/WindowFoldEffects.swift').read_text()
prepare_fold = effects.split('private func prepareFold(', 1)[1].split('private func background(', 1)[0]
assert 'hasScreenRecordingPermission()' in prepare_fold, 'prepareFold must check Screen Recording'
assert prepare_fold.index('hasScreenRecordingPermission()') < prepare_fold.index('jobs[id] = job'), 'Screen Recording check must precede the fold job'
assert prepare_fold.index('hasScreenRecordingPermission()') < prepare_fold.index('ShareableContentCache.shared.content('), 'Screen Recording check must precede the window enumeration'
menu = (root / 'prototype/App/MenuBarController.swift').read_text()
settings = (root / 'prototype/Effects/DuoSettingsWindow.swift').read_text()
sections = (root / 'prototype/App/SettingsSections.swift').read_text()
assert 'struct MenuState' in menu
for title in ['屏幕开合角度：', '当前窗口', '设置…']:
    assert title in menu, f'menu state entry missing: {title}'
# 1.0.17：欢迎窗口的入口从卷帘页的「专注与输入」搬到 高级 → 关于（那一块随预览旗标藏起来）。
assert '"settings.about.welcome.name"' in settings and 'owner?.showWelcomeGuide()' in settings, 'welcome must remain reachable from settings'
for title in ['启用桌面开合效果', '启用窗口卷帘动画', '预览桌面效果…', '停止所有效果']:
    assert title not in menu, f'redundant menu entry still present: {title}'
assert 'showDuoSettings(section: .effects)' in settings
for section in ['效果', '卷帘', '隐私', '高级']:
    assert section in sections, f'unified settings section missing: {section}'
assert '打开诊断日志' in settings
print('PASS: recovery intent precedes hiding, animation follows verification, synchronous restore contract, session teardown, capture exclusion and the no-Screen-Recording fold bypass are wired')
