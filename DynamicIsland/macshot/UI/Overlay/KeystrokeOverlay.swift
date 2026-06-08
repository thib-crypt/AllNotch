import Cocoa

/// Helper around the on-screen keystroke display used while recording.
///
/// The visual overlay is driven by the (not-yet-wired) recording pipeline;
/// the only piece the capture overlay needs today is the Input Monitoring
/// permission check that gates a global `CGEvent` tap.
enum KeystrokeOverlay {

    /// Whether the app currently holds Input Monitoring permission, required
    /// to listen for global key events via a CGEvent tap.
    static var hasInputMonitoringPermission: Bool {
        // Returns true only when the user has granted Input Monitoring.
        // Does not prompt — call `requestInputMonitoringPermission()` for that.
        CGPreflightListenEventAccess()
    }

    /// Prompt the user for Input Monitoring permission (one-time system dialog).
    @discardableResult
    static func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }
}
