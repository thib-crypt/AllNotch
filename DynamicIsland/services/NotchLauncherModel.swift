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

import AppKit
import AtollExtensionKit
import Defaults
import SwiftUI

/// Central registry that builds the ordered destination and quick-action lists
/// consumed by the left navigation dock, the right quick-action cluster, and the
/// exhaustive Apps grid. It is the *single* place ordering is defined, so the
/// bars and the grid can never diverge (spec §4).
///
/// The lists are produced on demand from live `Defaults` + `PluginHost` +
/// coordinator state. Consuming views observe the relevant `@Default`/manager
/// sources themselves, so SwiftUI re-invokes these builders when inputs change.
@MainActor
final class NotchLauncherModel: ObservableObject {
    static let shared = NotchLauncherModel()
    private init() {}

    // MARK: - Stable destination ids

    /// Stable identity for a destination, used as the favorites ordering key.
    enum DestinationID {
        static let home = "dest-home"
        static let shelf = "dest-shelf"
        static let timer = "dest-timer"
        static let stats = "dest-stats"
        static let notes = "dest-notes"
        static let terminal = "dest-terminal"
        static func plugin(_ id: PluginID) -> String { "dest-plugin-\(id.rawValue)" }
        static func ext(_ experienceID: String) -> String { "dest-ext-\(experienceID)" }
    }

    /// Identity of the always-present Apps tab (left dock, last slot).
    static let appsDestinationID = "dest-apps"

    // MARK: - Right-cluster overflow bridge

    /// Quick-action ids that didn't fit in the right cluster and were pushed to
    /// the Apps grid. Written by the header after measuring available width;
    /// read by `AppsGridView`. Held here (rather than recomputed in the grid) so
    /// the grid stays width-agnostic.
    @Published var overflowedQuickActions: [QuickActionKind] = []

    func setOverflowedQuickActions(_ actions: [QuickActionKind]) {
        guard actions != overflowedQuickActions else { return }
        overflowedQuickActions = actions
    }

    // MARK: - Destinations

    /// All enabled destinations, ordered by the user's favorites list (pinned
    /// first, then the remainder in registry order). The Apps tab itself is not
    /// included — it is the grid's container, rendered separately by the dock.
    func destinations(
        coordinator: DynamicIslandViewCoordinator,
        extensionManager: ExtensionNotchExperienceManager
    ) -> [LauncherItem] {
        let base = baseDestinations(coordinator: coordinator, extensionManager: extensionManager)
        return applyOrder(base, order: Defaults[.notchFavoriteDestinations])
    }

    private func baseDestinations(
        coordinator: DynamicIslandViewCoordinator,
        extensionManager: ExtensionNotchExperienceManager
    ) -> [LauncherItem] {
        var items: [LauncherItem] = []

        if homeDestinationVisible {
            items.append(
                LauncherItem(
                    id: DestinationID.home,
                    kind: .destination,
                    icon: "house.fill",
                    label: String(localized: "Home"),
                    isSelected: coordinator.currentView == .home
                ) { coordinator.currentView = .home }
            )
        }

        if Defaults[.dynamicShelf] {
            items.append(
                LauncherItem(
                    id: DestinationID.shelf,
                    kind: .destination,
                    icon: "tray.fill",
                    label: String(localized: "Shelf"),
                    isSelected: coordinator.currentView == .shelf
                ) { coordinator.currentView = .shelf }
            )
        }

        if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab {
            items.append(
                LauncherItem(
                    id: DestinationID.timer,
                    kind: .destination,
                    icon: "timer",
                    label: String(localized: "Timer"),
                    isSelected: coordinator.currentView == .timer
                ) { coordinator.currentView = .timer }
            )
        }

        if Defaults[.enableStatsFeature] {
            items.append(
                LauncherItem(
                    id: DestinationID.stats,
                    kind: .destination,
                    icon: "chart.xyaxis.line",
                    label: String(localized: "Stats"),
                    isSelected: coordinator.currentView == .stats
                ) { coordinator.currentView = .stats }
            )
        }

        if Defaults[.enableNotes]
            || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
            let label = Defaults[.enableNotes] ? String(localized: "Notes") : String(localized: "Clipboard")
            let icon = Defaults[.enableNotes] ? "note.text" : "doc.on.clipboard"
            items.append(
                LauncherItem(
                    id: DestinationID.notes,
                    kind: .destination,
                    icon: icon,
                    label: label,
                    isSelected: coordinator.currentView == .notes
                ) { coordinator.currentView = .notes }
            )
        }

        if Defaults[.enableTerminalFeature] {
            items.append(
                LauncherItem(
                    id: DestinationID.terminal,
                    kind: .destination,
                    icon: "apple.terminal",
                    label: String(localized: "Terminal"),
                    isSelected: coordinator.currentView == .terminal
                ) { coordinator.currentView = .terminal }
            )
        }

        // Plugin-provided notch tabs (Todo, Agents, Weather, …) in registry order.
        for plugin in PluginHost.shared.tabPlugins {
            let descriptor = plugin.tab
            let pluginID = plugin.id
            items.append(
                LauncherItem(
                    id: DestinationID.plugin(pluginID),
                    kind: .destination,
                    icon: descriptor.icon,
                    label: descriptor.label,
                    accentColor: descriptor.accentColor,
                    badge: plugin.tabBadgeCount,
                    isSelected: coordinator.currentView == .plugin(pluginID)
                ) { coordinator.currentView = .plugin(pluginID) }
            )
        }

        // Extension-provided notch tabs.
        if extensionTabsEnabled {
            for payload in extensionManager.activeExperiences where payload.descriptor.tab != nil {
                guard let tab = payload.descriptor.tab else { continue }
                let experienceID = payload.descriptor.id
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                let isSelected = coordinator.currentView == .extensionExperience
                    && coordinator.selectedExtensionExperienceID == experienceID
                items.append(
                    LauncherItem(
                        id: DestinationID.ext(experienceID),
                        kind: .destination,
                        icon: iconName,
                        label: tab.title,
                        accentColor: accent,
                        isSelected: isSelected
                    ) {
                        coordinator.selectedExtensionExperienceID = experienceID
                        coordinator.currentView = .extensionExperience
                    }
                )
            }
        }

        return items
    }

    private var homeDestinationVisible: Bool {
        if Defaults[.enableMinimalisticUI] { return true }
        return Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror]
    }

    private var extensionTabsEnabled: Bool {
        Defaults[.enableThirdPartyExtensions]
            && Defaults[.enableExtensionNotchExperiences]
            && Defaults[.enableExtensionNotchTabs]
    }

    // MARK: - Grid sizing

    /// Estimated open-notch height needed to show the Apps grid without clipping
    /// the bottom rows, capped to 60% of the screen height (beyond which the grid
    /// scrolls vertically). Mirrors `AppsGridView`'s layout metrics so the real
    /// window matches the SwiftUI frame.
    func preferredGridHeight(
        baseSize: CGSize,
        coordinator: DynamicIslandViewCoordinator,
        extensionManager: ExtensionNotchExperienceManager
    ) -> CGFloat {
        let destCount = destinations(coordinator: coordinator, extensionManager: extensionManager).count
        let actionCount = overflowedQuickActions.count

        // Matches LazyVGrid(.adaptive(minimum: 64), spacing: 16) inside 16pt
        // horizontal padding on each side.
        let available = baseSize.width - 32
        let columns = max(1, Int((available + 16) / (64 + 16)))

        let rowHeight: CGFloat = 84 // tile (52) + caption + grid spacing (16)
        let destRows = Int(ceil(Double(destCount) / Double(columns)))
        let actionRows = actionCount > 0 ? Int(ceil(Double(actionCount) / Double(columns))) : 0

        var content: CGFloat = 28 // vertical padding (14 * 2)
        content += CGFloat(destRows) * rowHeight
        if actionRows > 0 {
            content += 16 /* section spacing */ + 24 /* header */ + CGFloat(actionRows) * rowHeight
        }

        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(max(baseSize.height, content), screenHeight * 0.6)
    }

    // MARK: - Quick actions

    /// All available quick actions, ordered by the user's list (then registry
    /// order for any not yet listed).
    func quickActions() -> [QuickActionKind] {
        let available = QuickActionKind.allCases.filter { $0.isAvailable }
        return applyOrder(available, order: Defaults[.notchQuickActionsOrder], id: { $0.id })
    }

    // MARK: - Ordering

    private func applyOrder(_ items: [LauncherItem], order: [String]) -> [LauncherItem] {
        applyOrder(items, order: order, id: { $0.id })
    }

    /// Stable sort: items whose id appears in `order` come first in that order;
    /// the rest keep their original (registry) order, appended at the end.
    private func applyOrder<T>(_ items: [T], order: [String], id: (T) -> String) -> [T] {
        guard !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { lhs, rhs in
            let lRank = rank[id(lhs.element)]
            let rRank = rank[id(rhs.element)]
            switch (lRank, rRank) {
            case let (.some(l), .some(r)): return l < r
            case (.some, .none):           return true
            case (.none, .some):           return false
            case (.none, .none):           return lhs.offset < rhs.offset
            }
        }
        .map { $0.element }
    }
}
