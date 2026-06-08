import Foundation

/// Lightweight localization helper used throughout the macshot module.
/// Mirrors the upstream `L("…")` free function so ported sources compile unchanged.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
