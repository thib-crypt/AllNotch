/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

/// The left navigation dock of the open notch. Renders the favorite
/// destinations that fit (in user order) followed by the always-present Apps tab
/// in the last slot. Destinations that don't fit aren't clipped — they live in
/// the exhaustive Apps grid (`currentView == .apps`).
struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var launcher = NotchLauncherModel.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared

    // Observed purely so the dock re-renders when these inputs change; the
    // ordered destination list itself is built by `NotchLauncherModel`.
    @Default(.notchFavoriteDestinations) private var favoriteOrder
    @Default(.todoShowBadge) private var todoShowBadgeTrigger
    @Default(.todoTasks) private var todoTasksTrigger
    @Default(.enableStatsFeature) private var enableStatsFeature
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableNotes) private var enableNotes
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.enableTerminalFeature) private var enableTerminalFeature
    @Default(.dynamicShelf) private var dynamicShelf

    @Namespace private var animation

    private let slotWidth: CGFloat = 26
    private let spacing: CGFloat = 24

    private var destinations: [LauncherItem] {
        launcher.destinations(coordinator: coordinator, extensionManager: extensionNotchExperienceManager)
    }

    var body: some View {
        GeometryReader { geo in
            let allDestinations = destinations
            let capacity = slotCapacity(for: geo.size.width)
            // Reserve one slot for the always-present Apps tab.
            let favoriteCapacity = max(0, capacity - 1)
            let visible = Array(allDestinations.prefix(favoriteCapacity))

            HStack(spacing: spacing) {
                ForEach(visible) { item in
                    dockButton(item)
                }
                dockButton(appsItem)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: coordinator.currentView)
            .clipShape(Capsule())
            .onAppear { ensureValidSelection(with: allDestinations) }
        }
        .frame(height: 26)
    }

    private var appsItem: LauncherItem {
        LauncherItem(
            id: NotchLauncherModel.appsDestinationID,
            kind: .destination,
            icon: "square.grid.2x2.fill",
            label: String(localized: "Apps"),
            isSelected: coordinator.currentView == .apps
        ) { coordinator.currentView = .apps }
    }

    @ViewBuilder
    private func dockButton(_ item: LauncherItem) -> some View {
        let activeAccent = item.accentColor ?? .white

        TabButton(label: item.label, icon: item.icon, selected: item.isSelected) {
            item.activate()
        }
        .frame(height: 26)
        .foregroundStyle(item.isSelected ? activeAccent : .gray)
        .background {
            if item.isSelected {
                Capsule()
                    .fill((item.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                    .shadow(color: (item.accentColor ?? .clear).opacity(0.4), radius: 8)
                    .matchedGeometryEffect(id: "capsule", in: animation)
            } else {
                Capsule()
                    .fill(Color.clear)
                    .matchedGeometryEffect(id: "capsule", in: animation)
                    .hidden()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = item.badge, badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 8, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// Total number of fixed-width slots (including the Apps tab) that fit in the
    /// available width. Always at least 1 so the Apps tab is never dropped.
    private func slotCapacity(for width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let count = Int((width + spacing) / (slotWidth + spacing))
        return max(1, count)
    }

    private func ensureValidSelection(with destinations: [LauncherItem]) {
        if coordinator.currentView == .apps { return }
        if destinations.contains(where: { $0.isSelected }) { return }
        guard let first = destinations.first else {
            coordinator.currentView = .apps
            return
        }
        first.activate()
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
