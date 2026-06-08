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

/// To-do list feature, migrated to the plugin architecture.
///
/// Declares a notch tab + a settings section. There is no background service —
/// the list is pure `Defaults` (`.todoTasks`) — so it does **not** conform to
/// `PluginLifecycle`. Disabling it while its tab is open is handled generically
/// by `PluginHost.releaseActiveTabIfNeeded(for:)`.
final class TodoPlugin: Plugin, NotchTabProviding, SettingsProviding {
    static let id = PluginID.todo

    var displayName: String { String(localized: "To-Do List") }
    var icon: String { "checklist" }
    var defaultsEnableKey: Defaults.Key<Bool> { .enableTodoFeature }

    // MARK: NotchTabProviding

    var tab: TabDescriptor {
        TabDescriptor(label: String(localized: "Todo"), icon: "checklist", accentColor: .blue)
    }

    @MainActor func makeTabView() -> AnyView {
        AnyView(NotchTodoView())
    }

    /// Pending-task badge, honoring the user's "show badge" preference.
    @MainActor var tabBadgeCount: Int? {
        guard Defaults[.todoShowBadge] else { return nil }
        return Defaults[.todoTasks].filter { !$0.isCompleted }.count
    }

    /// Comfortable scroll height for the task list (was special-cased in
    /// `ContentView.calculateNotchSize` before migration).
    @MainActor func preferredNotchHeight(for baseSize: CGSize) -> CGFloat? {
        260
    }

    // MARK: SettingsProviding

    var settingsGroup: PluginSettingsGroup { .productivity }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(TodoSettings())
    }
}
