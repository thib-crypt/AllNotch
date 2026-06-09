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

import Combine
import Defaults
import Foundation
import SwiftUI

/// Central registry and orchestrator for feature plugins.
///
/// This is the *single* place where features are listed and ordered. The host is
/// **additive**: it feeds the existing notch tab bar, settings sidebar and sneak
/// peek pipeline rather than replacing them, so features not yet migrated keep
/// working unchanged.
@MainActor
final class PluginHost: ObservableObject {
    static let shared = PluginHost()

    /// THE single ordered list of features. Adding a feature = add one line here.
    let allPlugins: [any Plugin] = [
        ScreenshotPlugin(),
        TodoPlugin(),
        ColorPickerPlugin(),
        AgentsPlugin(),
        WeatherPlugin(),
        // … as more features migrate: TimerPlugin(), StatsPlugin() …
    ]

    private var cancellables = Set<AnyCancellable>()
    private var booted = false

    private init() {}

    // MARK: - Capability views (filtered)

    /// Notch tabs offered by *enabled* plugins, in registry order.
    var tabPlugins: [any NotchTabProviding] {
        allPlugins.compactMap { $0 as? NotchTabProviding }.filter { Defaults[$0.defaultsEnableKey] }
    }

    /// Settings sections offered by all plugins, in registry order.
    ///
    /// Not filtered by activation: a feature's enable toggle lives inside its
    /// settings view, so the section must stay reachable even when disabled.
    var settingsPlugins: [any SettingsProviding] {
        allPlugins.compactMap { $0 as? SettingsProviding }
    }

    /// Plugins whose backing toggle is currently on.
    var enabledPlugins: [any Plugin] {
        allPlugins.filter { Defaults[$0.defaultsEnableKey] }
    }

    // MARK: - Lookups

    func plugin(for id: PluginID) -> (any Plugin)? {
        allPlugins.first { $0.id == id }
    }

    func tabPlugin(for id: PluginID) -> (any NotchTabProviding)? {
        tabPlugins.first { $0.id == id }
    }

    func settingsPlugin(for id: PluginID) -> (any SettingsProviding)? {
        settingsPlugins.first { $0.id == id }
    }

    /// Position of a plugin tab within the enabled-tab order (used to compute
    /// notch tab-switch transition direction).
    func tabIndex(of id: PluginID) -> Int? {
        tabPlugins.firstIndex { $0.id == id }
    }

    // MARK: - Bootstrap

    /// Called once at launch. Activates enabled lifecycle plugins and installs a
    /// Defaults observer per plugin to react to toggles.
    func bootstrap() {
        guard !booted else { return }
        booted = true

        for plugin in allPlugins {
            if Defaults[plugin.defaultsEnableKey], let lifecycle = plugin as? PluginLifecycle {
                lifecycle.activate()
            }
            observeToggle(for: plugin)
        }
    }

    /// Observes a plugin's enable toggle. Every plugin is observed (not just
    /// lifecycle ones) so a tab-providing plugin can release the active tab when
    /// it is disabled, even if it has no background service to tear down.
    private func observeToggle(for plugin: any Plugin) {
        Defaults.publisher(plugin.defaultsEnableKey)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        (plugin as? PluginLifecycle)?.activate()
                    } else {
                        (plugin as? PluginLifecycle)?.deactivate()
                        self?.releaseActiveTabIfNeeded(for: plugin)
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// When a tab-providing plugin is disabled while its tab is open, fall back
    /// to Home so the notch never lingers on a now-hidden tab. (Replaces the
    /// per-feature `handle*FeatureToggle` resets in the coordinator.)
    @MainActor
    private func releaseActiveTabIfNeeded(for plugin: any Plugin) {
        guard plugin is NotchTabProviding else { return }
        let coordinator = DynamicIslandViewCoordinator.shared
        guard coordinator.currentView == .plugin(plugin.id) else { return }
        withAnimation(.smooth) {
            coordinator.currentView = .home
        }
    }

    // MARK: - Sneak peek relay

    /// Relays a plugin's notch-closed contribution to the coordinator as a
    /// generic `SneakContentType.plugin`. No-op if the plugin is disabled.
    func surface(_ contribution: SneakContribution, from id: PluginID) {
        guard let plugin = plugin(for: id), Defaults[plugin.defaultsEnableKey] else { return }
        DynamicIslandViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .plugin(id: id, token: contribution.token),
            duration: contribution.duration,
            value: contribution.value,
            icon: contribution.icon,
            title: contribution.title,
            subtitle: contribution.subtitle,
            accentColor: contribution.accentColor
        )
    }
}
