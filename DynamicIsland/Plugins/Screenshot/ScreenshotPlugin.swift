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

/// Pilot plugin: screen capture (macshot).
///
/// Declares only the surfaces it uses — settings + lifecycle. It does **not**
/// conform to `NotchTabProviding`: capture has no full-panel notch tab, and a
/// plugin only declares what it actually offers.
final class ScreenshotPlugin: Plugin, SettingsProviding, PluginLifecycle {
    static let id = PluginID.screenshot

    var displayName: String { String(localized: "Capture") }
    var icon: String { "camera.viewfinder" }
    var defaultsEnableKey: Defaults.Key<Bool> { .enableScreenshotFeature }

    // MARK: SettingsProviding

    var settingsGroup: PluginSettingsGroup { .utilities }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(CaptureSettingsView())
    }

    // MARK: PluginLifecycle

    @MainActor func activate() {
        // Warm the capture path so the first screenshot is fast. The menu-bar
        // entry (`ScreenCaptureMenuButton`) and shortcuts are gated directly on
        // `enableScreenshotFeature`, so they appear/disappear with this toggle.
        MacshotManager.shared.prewarmCapturePath()
    }

    @MainActor func deactivate() {
        // Capture is on-demand; there is no persistent background service to
        // tear down. The menu-bar entry hides itself via the defaults toggle.
    }
}
