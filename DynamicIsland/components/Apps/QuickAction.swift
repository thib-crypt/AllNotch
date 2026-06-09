/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

/// The customizable quick actions that live in the right cluster of the open
/// notch header. Each has a *stable* identity (used as the ordering key in
/// `Defaults[.notchQuickActionsOrder]`) and renders identically in the header
/// and — when it overflows — in the Apps grid's "Quick Actions" section.
///
/// Status indicators (recording / Do Not Disturb) and the battery view are
/// intentionally *not* quick actions: they are anchored to the far right and
/// never overflow (spec §3).
enum QuickActionKind: String, CaseIterable, Identifiable {
    case mirror
    case clipboard
    case colorPicker
    case timer
    case screenshot
    case settings

    var id: String { "action-\(rawValue)" }

    var icon: String {
        switch self {
        case .mirror:      return "web.camera"
        case .clipboard:   return "doc.on.clipboard"
        case .colorPicker: return "eyedropper"
        case .timer:       return "timer"
        case .screenshot:  return "camera.viewfinder"
        case .settings:    return "gear"
        }
    }

    var label: String {
        switch self {
        case .mirror:      return String(localized: "Mirror")
        case .clipboard:   return String(localized: "Clipboard")
        case .colorPicker: return String(localized: "Color Picker")
        case .timer:       return String(localized: "Timer")
        case .screenshot:  return String(localized: "Screenshot")
        case .settings:    return String(localized: "Settings")
        }
    }

    /// Whether the action is currently available (its backing feature/icon
    /// toggle is on). Mirrors the gating previously inlined in the header.
    var isAvailable: Bool {
        switch self {
        case .mirror:
            return Defaults[.showMirror]
        case .clipboard:
            return Defaults[.enableClipboardManager]
                && Defaults[.showClipboardIcon]
                && Defaults[.clipboardDisplayMode] != .separateTab
        case .colorPicker:
            return Defaults[.enableColorPickerFeature] && Defaults[.showColorPickerIcon]
        case .timer:
            return Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .popover
        case .screenshot:
            return Defaults[.enableScreenshotFeature]
        case .settings:
            return Defaults[.settingsIconInNotch]
        }
    }
}
