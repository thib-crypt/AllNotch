/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Defaults
import SwiftUI

/// Weather conditions and forecast feature.
/// Surfaces a notch tab (current + forecast), a settings section,
/// and an optional sneak peek when conditions change significantly.
final class WeatherPlugin: Plugin, NotchTabProviding, SettingsProviding, PluginLifecycle, SneakPeekProviding {
    static let id = PluginID.weather

    var displayName: String { String(localized: "Weather") }
    var icon: String        { "cloud.sun.fill" }
    var defaultsEnableKey: Defaults.Key<Bool> { .enableWeatherFeature }

    // MARK: - NotchTabProviding

    var tab: TabDescriptor {
        TabDescriptor(label: String(localized: "Weather"), icon: "cloud.sun.fill", accentColor: .cyan)
    }

    @MainActor func makeTabView() -> AnyView {
        AnyView(WeatherTabView())
    }

    @MainActor func preferredNotchHeight(for baseSize: CGSize) -> CGFloat? {
        Defaults[.weatherForecastFormat] == .daily ? 290 : 270
    }

    // MARK: - SettingsProviding

    var settingsGroup: PluginSettingsGroup { .utilities }

    @MainActor func makeSettingsView() -> AnyView {
        AnyView(WeatherSettings())
    }

    // MARK: - PluginLifecycle

    @MainActor func activate() {
        WeatherService.shared.startPolling()
        startSneakPeekObservation()
    }

    @MainActor func deactivate() {
        sneakPeekObservation?.cancel()
        sneakPeekObservation = nil
        lastSneakData = nil
    }

    // MARK: - Sneak peek

    private var sneakPeekObservation: AnyCancellable?
    private var lastSneakData: WeatherData?

    @MainActor private func startSneakPeekObservation() {
        sneakPeekObservation = WeatherService.shared.$current
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] data in
                Task { @MainActor in self?.handleWeatherUpdate(data) }
            }
    }

    @MainActor private func handleWeatherUpdate(_ data: WeatherData) {
        guard Defaults[.weatherSneakPeekEnabled] else {
            lastSneakData = data
            return
        }
        defer { lastSneakData = data }
        guard let last = lastSneakData else { return }  // skip first fetch silently

        let symbolChanged = data.symbolName != last.symbolName
        let tempDelta     = abs(data.temperature - last.temperature)
        guard symbolChanged || tempDelta >= 5 else { return }

        let unit      = Defaults[.lockScreenWeatherTemperatureUnit]
        let tempValue = unit.usesMetricSystem ? data.temperature : data.temperature * 9.0 / 5.0 + 32.0
        let tempText  = "\(Int(round(tempValue)))°"

        PluginHost.shared.surface(
            SneakContribution(
                token:       "weather-change",
                icon:        data.symbolName,
                title:       tempText,
                subtitle:    data.description,
                value:       0,
                accentColor: .cyan,
                duration:    2.5
            ),
            from: PluginID.weather
        )
    }
}
