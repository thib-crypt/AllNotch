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

/// Customization for the open-notch bar: two reorderable lists controlling the
/// order of the left navigation dock (favorites) and the right quick-action
/// cluster. Items that don't fit either bar surface in the Apps grid.
struct NotchBarSettings: View {
    @ObservedObject private var launcher = NotchLauncherModel.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionManager = ExtensionNotchExperienceManager.shared

    @Default(.notchFavoriteDestinations) private var favoriteOrder
    @Default(.notchQuickActionsOrder) private var quickActionsOrder

    private var destinations: [LauncherItem] {
        launcher.destinations(coordinator: coordinator, extensionManager: extensionManager)
    }

    private var quickActions: [QuickActionKind] {
        launcher.quickActions()
    }

    var body: some View {
        // A `List` (not `Form`) is required: SwiftUI's `.onMove` drag-to-reorder
        // is ignored inside a grouped `Form` on macOS.
        List {
            Section {
                ForEach(destinations) { item in
                    row(icon: item.icon, label: item.label, accentColor: item.accentColor)
                }
                .onMove { indices, newOffset in
                    var ordered = destinations
                    ordered.move(fromOffsets: indices, toOffset: newOffset)
                    favoriteOrder = ordered.map { $0.id }
                }
            } header: {
                Text("Favorites (left dock)")
            } footer: {
                Text("Drag to reorder. Items that don't fit in the bar appear in Apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(quickActions) { action in
                    row(icon: action.icon, label: action.label, accentColor: nil)
                }
                .onMove { indices, newOffset in
                    var ordered = quickActions
                    ordered.move(fromOffsets: indices, toOffset: newOffset)
                    quickActionsOrder = ordered.map { $0.id }
                }
            } header: {
                Text("Quick Actions (right cluster)")
            } footer: {
                Text("Drag to reorder. Actions that don't fit appear in Apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func row(icon: String, label: String, accentColor: Color?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(accentColor ?? .accentColor)
            Text(label)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
