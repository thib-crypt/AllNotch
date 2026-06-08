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

/// Color picker feature, migrated to the plugin architecture.
///
/// Settings-only — like the Screenshot pilot. The picker has no full-panel notch
/// tab: it surfaces through the header eyedropper button as a floating panel or
/// popover (`colorPickerDisplayMode`), and its global shortcut is registered at
/// app launch. So it declares `SettingsProviding` only.
final class ColorPickerPlugin: Plugin, SettingsProviding {
    static let id = PluginID.colorPicker

    var displayName: String { String(localized: "Color Picker") }
    var icon: String { "eyedropper" }
    var defaultsEnableKey: Defaults.Key<Bool> { .enableColorPickerFeature }

    // MARK: SettingsProviding

    var settingsGroup: PluginSettingsGroup { .utilities }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(ColorPickerSettings())
    }
}
