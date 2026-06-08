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

/// A plugin that contributes a full-panel tab to the open notch.
protocol NotchTabProviding: Plugin {
    var tab: TabDescriptor { get }
    @MainActor func makeTabView() -> AnyView

    /// Optional pending/unread count rendered as a small badge on the tab.
    /// Return `nil` (the default) for no badge; a value `> 0` shows the badge.
    @MainActor var tabBadgeCount: Int? { get }

    /// Optional preferred height for the open notch when this tab is active.
    /// Return `nil` (the default) to keep the coordinator's standard sizing.
    /// `baseSize` is the size the notch would otherwise use.
    @MainActor func preferredNotchHeight(for baseSize: CGSize) -> CGFloat?
}

extension NotchTabProviding {
    @MainActor var tabBadgeCount: Int? { nil }
    @MainActor func preferredNotchHeight(for baseSize: CGSize) -> CGFloat? { nil }
}
