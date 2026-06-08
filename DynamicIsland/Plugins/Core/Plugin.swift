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
import Foundation

/// The minimal core contract every feature-plugin satisfies.
///
/// A plugin describes itself (id, name, icon) and points at the existing
/// `enable*Feature` defaults key that gates it. It opts into surfaces — notch
/// tab, settings, sneak peek, lifecycle — by additionally conforming to the
/// capability protocols in `Plugins/Core/Capabilities/`.
protocol Plugin: AnyObject {
    /// Stable identity, also used as the generic discriminator in
    /// `NotchViews.plugin` and `SneakContentType.plugin`.
    static var id: PluginID { get }

    /// Localized, user-facing name.
    var displayName: String { get }

    /// SF Symbol name.
    var icon: String { get }

    /// Reuses the feature's existing `Defaults.Keys.enable*Feature` toggle,
    /// so there is no preference migration.
    var defaultsEnableKey: Defaults.Key<Bool> { get }
}

extension Plugin {
    /// Instance-side accessor for the static identity.
    var id: PluginID { Self.id }

    /// Current activation state read from the backing defaults key.
    var isEnabled: Bool { Defaults[defaultsEnableKey] }
}
