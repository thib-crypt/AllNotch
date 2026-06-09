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

import Foundation

/// Stable, typed identity for a plugin (avoids magic strings scattered around).
///
/// Public because it appears in the `public enum NotchViews.plugin(_:)` case.
public struct PluginID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}

extension PluginID {
    /// Screenshot / macshot capture feature (pilot plugin).
    static let screenshot = PluginID("screenshot")

    /// To-do list feature (notch tab + settings).
    static let todo = PluginID("todo")

    /// Color picker feature (settings only; surfaced via the header button).
    static let colorPicker = PluginID("colorPicker")

    /// AI agents feature (notch tab + settings + bridge lifecycle).
    static let agents = PluginID("agents")

    /// Weather conditions and forecast feature.
    static let weather = PluginID("weather")
}
