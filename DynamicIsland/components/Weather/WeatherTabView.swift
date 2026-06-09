/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import SwiftUI

struct WeatherTabView: View {
    @StateObject private var service = WeatherService.shared
    @Default(.lockScreenWeatherTemperatureUnit) private var tempUnit
    @Default(.weatherForecastFormat) private var forecastFormat

    var body: some View {
        Group {
            if let data = service.current {
                VStack(spacing: 0) {
                    currentConditionsRow(data: data)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Divider()
                        .opacity(0.25)
                        .padding(.horizontal, 12)

                    forecastSection(data: data)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
            } else if service.isFetching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cloud.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("No weather data")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Current conditions

    private func currentConditionsRow(data: WeatherData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: data.symbolName)
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatted(celsius: data.temperature))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))

                Text(data.description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)

                if let loc = data.locationName, !loc.isEmpty {
                    Label(loc, systemImage: "location.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            Spacer()

            if let minC = data.minTemperature, let maxC = data.maxTemperature {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("↑\(formatted(celsius: maxC))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("↓\(formatted(celsius: minC))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Forecast

    @ViewBuilder
    private func forecastSection(data: WeatherData) -> some View {
        switch forecastFormat {
        case .daily:
            dailyForecast(days: Array(data.dailyForecast.prefix(3)))
        case .hourly:
            hourlyForecast(hours: Array(data.hourlyForecast.prefix(6)))
        }
    }

    private func dailyForecast(days: [WeatherData.DailyPoint]) -> some View {
        VStack(spacing: 7) {
            ForEach(days) { day in
                HStack(spacing: 8) {
                    Text(shortDayName(day.date))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 32, alignment: .leading)

                    Image(systemName: day.symbolName)
                        .font(.system(size: 14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 20)

                    if day.precipitationChance > 0.1 {
                        Text("\(Int(day.precipitationChance * 100))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan.opacity(0.85))
                            .frame(width: 32, alignment: .leading)
                    } else {
                        Spacer().frame(width: 32)
                    }

                    Spacer()

                    Text("↑\(formatted(celsius: day.highTemperature))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Text("↓\(formatted(celsius: day.lowTemperature))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func hourlyForecast(hours: [WeatherData.HourlyPoint]) -> some View {
        HStack(spacing: 0) {
            ForEach(hours) { point in
                VStack(spacing: 4) {
                    Text(shortHour(point.time))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    Image(systemName: point.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .symbolRenderingMode(.hierarchical)

                    Text(formatted(celsius: point.temperature))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))

                    if point.precipitationChance > 0.1 {
                        Text("\(Int(point.precipitationChance * 100))%")
                            .font(.system(size: 10))
                            .foregroundStyle(.cyan.opacity(0.85))
                    } else {
                        Color.clear.frame(height: 12)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Formatting helpers

    private func formatted(celsius value: Double) -> String {
        let display = tempUnit.usesMetricSystem ? value : value * 9.0 / 5.0 + 32.0
        return "\(Int(round(display)))°"
    }

    private func shortDayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale  = .current
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func shortHour(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }
}
