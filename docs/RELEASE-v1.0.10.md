# WindowShade v1.0.10

## Highlights

- Duo desktop open/close effect with ScreenCaptureKit and Metal rendering.
- Window fold/unfold animation with live frames, title-bar anchoring, reverse transitions, and verified recovery.
- Bendy-style status menu with lid angle, desktop toggle, window-animation toggle, live preview, and stop-all-effects action.
- Durable restore journal and recovery handling for failed hides, closed windows, display changes, and stale capture sessions.
- Duo settings window with calibration, presets, trigger angle, live preview, pause, and Screen Recording permission guidance.

## Validation

- Swift type check and signed arm64 stage build passed on macOS 26.5 / Mac17,4.
- Core, frame metadata, recovery, native window fixture, edge-window, and shader parity tests passed.
- The release bundle is signed with the existing Apple Development identity to preserve local TCC authorization.

## Scope

- macOS 14+.
- Lock-screen effects, helper agents, SIP changes, and HDR-specific paths are not included.
- First launch still requires Accessibility and Screen Recording permissions for the relevant features.
