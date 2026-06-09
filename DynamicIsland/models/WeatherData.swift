/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// Shared weather data model. All temperatures are stored in raw Celsius.
/// Display formatting (°F conversion, text rounding) is done by the view layer using `lockScreenWeatherTemperatureUnit`.
/// This model has no lock-screen concerns (no battery, no bluetooth, no charging).
struct WeatherData: Equatable {

    // MARK: - Nested types

    /// One hourly forecast point (next ~12 hours).
    struct HourlyPoint: Equatable, Identifiable {
        var id: String { time.description }
        let time: Date
        let temperature: Double          // °C
        let symbolName: String           // SF Symbol name
        let precipitationChance: Double  // 0–1
        let isDaytime: Bool
    }

    /// One daily forecast point (next 3 days, excluding today).
    struct DailyPoint: Equatable, Identifiable {
        var id: String { date.description }
        let date: Date
        let symbolName: String           // SF Symbol name
        let description: String
        let lowTemperature: Double       // °C
        let highTemperature: Double      // °C
        let precipitationChance: Double  // 0–1
        let sunrise: Date?
        let sunset: Date?
    }

    struct SunCycleInfo: Equatable {
        let sunrise: Date?
        let sunset: Date?
    }

    struct AirQualityInfo: Equatable {
        enum Category: Equatable {
            case good, fair, moderate, unhealthyForSensitive
            case unhealthy, poor, veryPoor, veryUnhealthy
            case extremelyPoor, hazardous, unknown

            var displayName: String {
                switch self {
                case .good: return "Good"
                case .fair: return "Fair"
                case .moderate: return "Moderate"
                case .unhealthyForSensitive: return "Sensitive"
                case .unhealthy: return "Unhealthy"
                case .poor: return "Poor"
                case .veryPoor: return "Very Poor"
                case .veryUnhealthy: return "Very Unhealthy"
                case .extremelyPoor: return "Extremely Poor"
                case .hazardous: return "Hazardous"
                case .unknown: return "Unknown"
                }
            }
        }

        let index: Int
        let category: Category
        let scale: LockScreenWeatherAirQualityScale  // existing enum in enums/generic.swift
    }

    // MARK: - Current conditions

    let symbolName: String       // SF Symbol
    let description: String
    let temperature: Double      // °C
    let minTemperature: Double?  // °C, today's forecast low
    let maxTemperature: Double?  // °C, today's forecast high
    let locationName: String?
    let isDaytime: Bool

    // MARK: - Extended data

    let airQuality: AirQualityInfo?
    let sunCycle: SunCycleInfo?
    let hourlyForecast: [HourlyPoint]  // next ~12 hours, already filtered to future
    let dailyForecast: [DailyPoint]    // next 3 days, excluding today

    let fetchedAt: Date
}

// MARK: - Category conversion helpers

/// Bridges WeatherData's AQI category enum to LockScreenWeatherSnapshot's (identical structure).
extension LockScreenWeatherSnapshot.AirQualityInfo.Category {
    init(_ category: WeatherData.AirQualityInfo.Category) {
        switch category {
        case .good:                    self = .good
        case .fair:                    self = .fair
        case .moderate:                self = .moderate
        case .unhealthyForSensitive:   self = .unhealthyForSensitive
        case .unhealthy:               self = .unhealthy
        case .poor:                    self = .poor
        case .veryPoor:                self = .veryPoor
        case .veryUnhealthy:           self = .veryUnhealthy
        case .extremelyPoor:           self = .extremelyPoor
        case .hazardous:               self = .hazardous
        case .unknown:                 self = .unknown
        }
    }
}
