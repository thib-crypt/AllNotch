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

/// Data describing a plugin's notch tab (no logic).
struct TabDescriptor {
    var label: String
    var icon: String
    var accentColor: Color?

    init(label: String, icon: String, accentColor: Color? = nil) {
        self.label = label
        self.icon = icon
        self.accentColor = accentColor
    }
}

/// Sidebar group a plugin's settings section belongs to.
///
/// Raw values mirror `SettingsView`'s private `SettingsTabGroup`, so a plugin's
/// group maps onto an existing settings section by raw value.
enum PluginSettingsGroup: String, CaseIterable {
    case core
    case mediaAndDisplay
    case system
    case productivity
    case utilities
    case developer
    case integrations
    case info
}

/// A notch-closed contribution a plugin pushes through `PluginHost.surface(_:from:)`.
///
/// The `token` distinguishes different sneak kinds emitted by the same plugin
/// (it participates in `SneakContentType.plugin` equality); the remaining fields
/// feed the coordinator's existing `toggleSneakPeek` display parameters.
struct SneakContribution {
    var token: String
    var icon: String
    var title: String
    var subtitle: String
    var value: CGFloat
    var accentColor: Color?
    var duration: TimeInterval

    init(
        token: String = "",
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        value: CGFloat = 0,
        accentColor: Color? = nil,
        duration: TimeInterval = 1.5
    ) {
        self.token = token
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.accentColor = accentColor
        self.duration = duration
    }
}
