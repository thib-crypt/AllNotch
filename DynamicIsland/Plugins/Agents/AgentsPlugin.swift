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
import Defaults
import SwiftUI

/// AI agents feature (Open Island bridge), migrated to the plugin architecture.
///
/// The richest plugin: a notch tab, a settings section, and a background service
/// lifecycle. `activate()` starts the `AgentBridgeController` so hook events are
/// captured from launch (replacing the explicit start in `DynamicIslandApp`);
/// `deactivate()` tears the bridge down when the feature is switched off.
final class AgentsPlugin: Plugin, NotchTabProviding, SettingsProviding, PluginLifecycle {
    static let id = PluginID.agents

    /// Brand accent reused from the legacy Agents settings tab.
    private static let accent = Color(red: 0.85, green: 0.47, blue: 0.26)

    var displayName: String { String(localized: "Agents") }
    var icon: String { "cpu" }
    var defaultsEnableKey: Defaults.Key<Bool> { .enableAgentsFeature }

    // MARK: NotchTabProviding

    var tab: TabDescriptor {
        TabDescriptor(label: String(localized: "Agents"), icon: "cpu", accentColor: Self.accent)
    }

    @MainActor func makeTabView() -> AnyView {
        AnyView(AgentsTabView())
    }

    /// Grow the panel to exactly fit the live session list so nothing has to be
    /// reached by scrolling, capped at most of the screen height. `AgentsTabView`
    /// measures the intrinsic content height and publishes it on the bridge; when
    /// there are no sessions (or before the first measurement) we fall back to the
    /// base height so the empty state stays compact.
    @MainActor func preferredNotchHeight(for baseSize: CGSize) -> CGFloat? {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let cap = screenHeight * 0.85
        let measured = AgentBridgeController.shared.desiredPanelHeight
        let desired = measured > 0 ? measured : baseSize.height
        return min(max(baseSize.height, desired), cap)
    }

    // MARK: SettingsProviding

    var settingsGroup: PluginSettingsGroup { .developer }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(AgentsSettings())
    }

    // MARK: PluginLifecycle

    @MainActor func activate() {
        AgentBridgeController.shared.startIfNeeded()
    }

    @MainActor func deactivate() {
        AgentBridgeController.shared.stop()
    }
}
