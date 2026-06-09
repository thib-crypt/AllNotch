/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CoreLocation
import Defaults
import SwiftUI

struct WeatherSettings: View {
    @Default(.enableWeatherFeature)           private var isEnabled
    @Default(.lockScreenWeatherProviderSource) private var providerSource
    @Default(.lockScreenWeatherTemperatureUnit) private var temperatureUnit
    @Default(.weatherForecastFormat)           private var forecastFormat
    @Default(.weatherSneakPeekEnabled)         private var sneakPeekEnabled
    @Default(.lockScreenWeatherRefreshInterval) private var refreshInterval

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Enable Weather"), isOn: $isEnabled)
            }

            if isEnabled {
                Section(String(localized: "Data Source")) {
                    Picker(String(localized: "Provider"), selection: $providerSource) {
                        ForEach(LockScreenWeatherProviderSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }

                    Picker(String(localized: "Temperature"), selection: $temperatureUnit) {
                        ForEach(LockScreenWeatherTemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }

                    Picker(String(localized: "Refresh Every"), selection: $refreshInterval) {
                        Text(String(localized: "15 min")).tag(TimeInterval(15 * 60))
                        Text(String(localized: "30 min")).tag(TimeInterval(30 * 60))
                        Text(String(localized: "1 hour")).tag(TimeInterval(60 * 60))
                    }

                    LocationStatusRow()
                }

                Section(String(localized: "Notch Tab")) {
                    Picker(String(localized: "Forecast Style"), selection: $forecastFormat) {
                        ForEach(WeatherForecastFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Notifications")) {
                    Toggle(String(localized: "Sneak peek on weather change"), isOn: $sneakPeekEnabled)
                    if sneakPeekEnabled {
                        Text(String(localized: "The notch briefly shows weather when conditions change by ≥5° or the weather symbol changes."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Location status row

private struct LocationStatusRow: View {
    @State private var status: CLAuthorizationStatus = CLLocationManager.authorizationStatus()

    var body: some View {
        HStack {
            Text(String(localized: "Location"))
            Spacer()
            locationStatusView
        }
        .onAppear {
            status = CLLocationManager.authorizationStatus()
        }
    }

    @ViewBuilder
    private var locationStatusView: some View {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            Label(String(localized: "Allowed"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .denied, .restricted:
            Button(String(localized: "Open Privacy Settings")) {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
                )
            }
            .buttonStyle(.borderless)
            .font(.callout)
        default:
            Button(String(localized: "Allow Location Access")) {
                WeatherService.shared.requestLocationAccess()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    status = CLLocationManager.authorizationStatus()
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }
}
