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

import SwiftUI

/// A plugin that contributes a section to the Settings sidebar.
///
/// Settings entries are always reachable (regardless of activation state) so the
/// user can find the feature's enable toggle, which conventionally lives inside
/// the settings view itself.
protocol SettingsProviding: Plugin {
    var settingsGroup: PluginSettingsGroup { get }
    @MainActor func makeSettingsView() -> AnyView
}
