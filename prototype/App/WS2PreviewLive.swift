import Foundation

/// 读出现在哪些 WindowShade 2 开关已经开着（只读各自原来的键，不改任何东西）。
@MainActor
extension WS2Preview {
  static var isOn: Bool { isOn(in: .standard) }

  static var live: Live {
    let store = UserDefaults.standard
    let input = WS2InputPreferences.load(from: store)
    var live = Live()
    live.pointer = input.smooth != nil || input.mouseInvert || input.trackpadInvert || input.fine || input.sideButtons
      || input.threeFinger || input.fourFinger
    live.remote = input.remoteMode || !WS2GamepadDesktopControl.enabledKeys.isEmpty
    live.conductor = (input.remoteMode && WS2ConductorSettings.flag(WS2ConductorSettings.enabledKey, in: store))
      || WS2ConductorSettings.flag(WS2ConductorSettings.codingSessionsKey, in: store)
    live.middleFold = input.middleFold
    live.carPlay = CarPlaySurfaceController.isEnabled
    return live
  }

  /// 侧栏这次放的页（按旗标和已经开着的开关算）。
  static var sections: [WindowShadeSettingsSection] { visibleSections(previewOn: isOn, live: live) }
}
