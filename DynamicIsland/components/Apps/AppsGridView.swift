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

/// iPhone-home-screen-style launcher rendered in the open notch's content area
/// when `currentView == .apps`. Lists every enabled destination (the canonical,
/// exhaustive receptacle) plus any quick actions that overflowed the right
/// cluster. Selecting a tile switches the view or runs the action.
struct AppsGridView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var launcher = NotchLauncherModel.shared
    @ObservedObject private var extensionManager = ExtensionNotchExperienceManager.shared

    // Observed so the grid re-renders when destination/action availability or
    // ordering inputs change (the lists are computed live from these sources).
    @Default(.notchFavoriteDestinations) private var favoriteOrder
    @Default(.notchQuickActionsOrder) private var quickActionsOrder
    @Default(.dynamicShelf) private var dynamicShelf
    @Default(.enableStatsFeature) private var enableStatsFeature
    @Default(.enableNotes) private var enableNotes
    @Default(.enableClipboardManager) private var enableClipboardManager
    @Default(.enableTerminalFeature) private var enableTerminalFeature
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.todoTasks) private var todoTasksTrigger
    @Default(.todoShowBadge) private var todoShowBadgeTrigger

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 16)]

    private var destinations: [LauncherItem] {
        launcher.destinations(coordinator: coordinator, extensionManager: extensionManager)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                section(title: nil) {
                    let items = destinations
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            AppTile(
                                icon: item.icon,
                                label: item.label,
                                accentColor: item.accentColor ?? .white,
                                badge: item.badge,
                                isSelected: item.isSelected,
                                appearIndex: index,
                                action: { activate(item) }
                            )
                        }
                    }
                }

                if !launcher.overflowedQuickActions.isEmpty {
                    section(title: String(localized: "Quick Actions")) {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Array(launcher.overflowedQuickActions.enumerated()), id: \.element) { index, action in
                                QuickActionGridTile(kind: action, appearIndex: index)
                                    .environmentObject(vm)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func activate(_ item: LauncherItem) {
        withAnimation(.smooth(duration: 0.3)) {
            item.activate()
        }
    }
}

/// A grid tile for a quick action that overflowed the right cluster. Reuses the
/// existing popover/panel/menu presentations, anchored to the tile itself.
private struct QuickActionGridTile: View {
    let kind: QuickActionKind
    var appearIndex: Int = 0

    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var showPopover = false

    var body: some View {
        switch kind {
        case .screenshot:
            Menu {
                ScreenCaptureMenuContent()
            } label: {
                AppTileLabel(icon: kind.icon, label: kind.label, appearIndex: appearIndex)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.white)
        default:
            AppTile(
                icon: kind.icon,
                label: kind.label,
                appearIndex: appearIndex,
                action: handleTap
            )
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverContent
            }
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        switch kind {
        case .clipboard:   ClipboardPopover()
        case .colorPicker: ColorPickerPopover()
        case .timer:       TimerPopover()
        default:           EmptyView()
        }
    }

    private func handleTap() {
        switch kind {
        case .mirror:
            vm.toggleCameraPreview()
        case .clipboard:
            switch Defaults[.clipboardDisplayMode] {
            case .panel:       ClipboardPanelManager.shared.toggleClipboardPanel()
            case .popover:     showPopover.toggle()
            case .separateTab: DynamicIslandViewCoordinator.shared.currentView = .notes
            }
        case .colorPicker:
            switch Defaults[.colorPickerDisplayMode] {
            case .panel:   ColorPickerPanelManager.shared.toggleColorPickerPanel()
            case .popover: showPopover.toggle()
            }
        case .timer:
            showPopover.toggle()
        case .settings:
            SettingsWindowController.shared.showWindow()
        case .screenshot:
            break // handled by Menu
        }
    }
}

/// A non-interactive tile label, used inside a `Menu` (which provides its own
/// hit target) so the screenshot action keeps the squircle look.
private struct AppTileLabel: View {
    let icon: String
    let label: String
    var appearIndex: Int = 0

    var body: some View {
        AppTile(icon: icon, label: label, appearIndex: appearIndex, action: {})
            .allowsHitTesting(false)
    }
}
