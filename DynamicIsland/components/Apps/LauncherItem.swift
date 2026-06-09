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

/// A single launchable entry surfaced *both* in the notch bars (left navigation
/// dock / right quick-action cluster) and in the exhaustive Apps grid. Built by
/// `NotchLauncherModel`, which is the single source of truth for ordering so the
/// bars and the grid can never diverge.
struct LauncherItem: Identifiable {
    enum Kind {
        /// A selectable notch view (system tab, plugin tab, extension tab, or the
        /// Apps grid itself).
        case destination
        /// A customizable quick action from the right cluster.
        case action
    }

    /// Stable identity, used as the ordering/pinning key in Defaults.
    let id: String
    let kind: Kind
    /// SF Symbol name.
    let icon: String
    /// Grid tile caption + VoiceOver label.
    let label: String
    var accentColor: Color?
    /// Optional pending/unread count rendered as a small badge.
    var badge: Int?
    /// Whether this destination is the currently active view.
    var isSelected: Bool
    /// Destination → set `currentView`; action → toggle/capture.
    let activate: () -> Void

    init(
        id: String,
        kind: Kind,
        icon: String,
        label: String,
        accentColor: Color? = nil,
        badge: Int? = nil,
        isSelected: Bool = false,
        activate: @escaping () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.icon = icon
        self.label = label
        self.accentColor = accentColor
        self.badge = badge
        self.isSelected = isSelected
        self.activate = activate
    }
}
