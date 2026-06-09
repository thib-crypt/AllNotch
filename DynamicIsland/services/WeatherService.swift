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
import CoreLocation
import Defaults
import Foundation

// MARK: - WeatherService

/// Single shared source of weather data for all consumers (WeatherPlugin, LockScreenWeatherManager).
/// Fetches from Open-Meteo (primary) with automatic fallback to wttr.in.
/// Observers receive updates via `$current`; polling is started/stopped by consumers.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published private(set) var current: WeatherData?
    @Published private(set) var isFetching: Bool = false

    private let provider = WeatherDataProvider()
    private let locationService = WeatherLocationService()
    private var pollingTask: Task<Void, Never>?
    private var lastFetchDate: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeConfigChanges()
    }

    // MARK: - Polling lifecycle

    /// Starts background polling at the configured refresh interval.
    /// Idempotent — safe to call multiple times (no-op if already polling).
    func startPolling() {
        guard pollingTask == nil else { return }
        Task { await refresh(force: true) }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = Defaults[.lockScreenWeatherRefreshInterval]
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refresh(force: false)
            }
        }
    }

    /// Stops background polling.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Triggers a location authorization dialog if not yet determined.
    func requestLocationAccess() {
        locationService.prepareAuthorization()
    }

    // MARK: - Refresh

    /// Fetches fresh weather data.
    /// - Parameter force: If `false`, skips the fetch when data is still within the refresh interval.
    @discardableResult
    func refresh(force: Bool = false) async -> WeatherData? {
        let interval = Defaults[.lockScreenWeatherRefreshInterval]
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < interval {
            return current
        }
        isFetching = true
        defer { isFetching = false }

        locationService.prepareAuthorization()
        let location = await locationService.currentLocation()
        let geocodedName = await reverseGeocode(location)

        do {
            var data = try await provider.fetch(location: location)
            // Inject geocoded name for providers that can't supply one (Open-Meteo)
            if data.locationName == nil, let name = geocodedName {
                data = WeatherData(
                    symbolName: data.symbolName, description: data.description,
                    temperature: data.temperature, minTemperature: data.minTemperature,
                    maxTemperature: data.maxTemperature, locationName: name,
                    isDaytime: data.isDaytime, airQuality: data.airQuality,
                    sunCycle: data.sunCycle, hourlyForecast: data.hourlyForecast,
                    dailyForecast: data.dailyForecast, fetchedAt: data.fetchedAt
                )
            }
            current = data
            lastFetchDate = Date()
            return data
        } catch {
            NSLog("WeatherService: fetch failed — %@", error.localizedDescription)
            return current
        }
    }

    // MARK: - Reverse geocoding

    private var geocodedName: String?
    private var lastGeocodedLocation: CLLocation?

    private func reverseGeocode(_ location: CLLocation?) async -> String? {
        guard let location else { return nil }
        if let last = lastGeocodedLocation,
           let name = geocodedName,
           location.distance(from: last) < 1000 {
            return name
        }
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            let name = placemarks.first?.locality ?? placemarks.first?.administrativeArea
            geocodedName = name
            lastGeocodedLocation = location
            return name
        } catch {
            return nil
        }
    }

    // MARK: - Config observation

    private func observeConfigChanges() {
        let triggers: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.lockScreenWeatherProviderSource, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherTemperatureUnit, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherAQIScale, options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(triggers)
            .sink { [weak self] in
                guard let self else { return }
                self.lastFetchDate = nil
                Task { await self.refresh(force: true) }
            }
            .store(in: &cancellables)
    }
}

// MARK: - WeatherDataProvider (private actor)

/// Thread-safe network layer. All URL construction, JSON decoding, and data mapping lives here.
private actor WeatherDataProvider {
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func fetch(location: CLLocation?) async throws -> WeatherData {
        let source = Defaults[.lockScreenWeatherProviderSource]
        switch source {
        case .openMeteo:
            guard let location else {
                return try await fetchWttr(location: nil)
            }
            do {
                return try await fetchOpenMeteo(location: location)
            } catch {
                NSLog("WeatherDataProvider: Open-Meteo failed (%@), falling back to wttr.in", error.localizedDescription)
                return try await fetchWttr(location: location)
            }
        case .wttr:
            return try await fetchWttr(location: location)
        }
    }

    // MARK: Open-Meteo

    private func fetchOpenMeteo(location: CLLocation) async throws -> WeatherData {
        let lat = String(format: "%.4f", location.coordinate.latitude)
        let lon = String(format: "%.4f", location.coordinate.longitude)

        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude",  value: lat),
            URLQueryItem(name: "longitude", value: lon),
            URLQueryItem(name: "current",   value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly",    value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            URLQueryItem(name: "daily",     value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "4"),
            URLQueryItem(name: "timezone",  value: "auto"),
        ]
        if let param = unit.openMeteoTemperatureParameter {
            items.append(URLQueryItem(name: "temperature_unit", value: param))
        }
        components.queryItems = items
        guard let url = components.url else { throw WeatherFetchError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherFetchError.invalidResponse
        }

        let omDecoder = JSONDecoder()
        omDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try omDecoder.decode(OpenMeteoResponse.self, from: data)
        guard let current = payload.current else { throw WeatherFetchError.noData }

        let tempValue   = current.temperature2M ?? 0
        let code        = current.weatherCode ?? 0
        let isDaytime   = (current.isDay ?? 1) == 1
        let mapping     = OpenMeteoSymbolMapper.mapping(for: code)
        let symbolName  = symbolAdjustedForDaylight(mapping.symbol, isDaytime: isDaytime)

        let unit2 = Defaults[.lockScreenWeatherTemperatureUnit]
        // Open-Meteo returns temp in the unit we requested; store as Celsius always
        let tempCelsius: Double
        if unit2.usesMetricSystem {
            tempCelsius = tempValue
        } else {
            tempCelsius = (tempValue - 32) * 5 / 9
        }

        let minTempC = payload.daily?.temperature2MMin?[safe: 0].map { v -> Double in
            unit2.usesMetricSystem ? v : (v - 32) * 5 / 9
        }
        let maxTempC = payload.daily?.temperature2MMax?[safe: 0].map { v -> Double in
            unit2.usesMetricSystem ? v : (v - 32) * 5 / 9
        }

        let tz  = payload.timezone
        let utc = payload.utcOffsetSeconds

        let sunCycle: WeatherData.SunCycleInfo?
        let rise = (payload.daily?.sunrise?[safe: 0]).flatMap { parseLocalTime($0, timezone: tz, utcOffset: utc) }
        let set  = (payload.daily?.sunset?[safe: 0]).flatMap  { parseLocalTime($0, timezone: tz, utcOffset: utc) }
        sunCycle = (rise != nil || set != nil) ? WeatherData.SunCycleInfo(sunrise: rise, sunset: set) : nil

        let hourly = parseOpenMeteoHourly(payload.hourly, timezone: tz, utcOffset: utc)
        let daily  = parseOpenMeteoDaily(payload.daily, timezone: tz, utcOffset: utc)

        let scale = Defaults[.lockScreenWeatherAQIScale]
        var airQuality: WeatherData.AirQualityInfo?
        if Defaults[.lockScreenWeatherShowsAQI] {
            airQuality = try? await fetchOpenMeteoAQI(lat: lat, lon: lon, scale: scale)
        }

        return WeatherData(
            symbolName: symbolName, description: mapping.description,
            temperature: tempCelsius, minTemperature: minTempC, maxTemperature: maxTempC,
            locationName: nil,  // will be geocoded by WeatherService
            isDaytime: isDaytime, airQuality: airQuality, sunCycle: sunCycle,
            hourlyForecast: hourly, dailyForecast: daily, fetchedAt: Date()
        )
    }

    private func fetchOpenMeteoAQI(lat: String, lon: String, scale: LockScreenWeatherAirQualityScale) async throws -> WeatherData.AirQualityInfo? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude",  value: lat),
            URLQueryItem(name: "longitude", value: lon),
            URLQueryItem(name: "current",   value: scale.queryParameter),
            URLQueryItem(name: "timezone",  value: "auto"),
        ]
        guard let url = components.url else { throw WeatherFetchError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherFetchError.invalidResponse
        }
        let aqDecoder = JSONDecoder()
        aqDecoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try aqDecoder.decode(OpenMeteoAQResponse.self, from: data)
        guard let cur = payload.current else { return nil }
        let raw: Double?
        switch scale {
        case .us:       raw = cur.usAqi
        case .european: raw = cur.europeanAqi
        }
        guard let rawValue = raw else { return nil }
        let index = Int(round(rawValue))
        return WeatherData.AirQualityInfo(
            index: index,
            category: aqiCategory(index: index, scale: scale),
            scale: scale
        )
    }

    private func parseOpenMeteoHourly(_ hourly: OpenMeteoResponse.Hourly?, timezone: String?, utcOffset: Int?) -> [WeatherData.HourlyPoint] {
        guard let times = hourly?.time, let temps = hourly?.temperature2M else { return [] }
        let codes   = hourly?.weatherCode ?? []
        let precips = hourly?.precipitationProbability ?? []
        let isDays  = hourly?.isDay ?? []
        let now = Date()
        var points: [WeatherData.HourlyPoint] = []
        for i in 0..<min(times.count, temps.count) {
            guard let date = parseLocalTime(times[i], timezone: timezone, utcOffset: utcOffset),
                  date > now else { continue }
            let code      = codes[safe: i] ?? 0
            let isDaytime = (isDays[safe: i] ?? 1) == 1
            let base      = OpenMeteoSymbolMapper.mapping(for: code).symbol
            let symbol    = symbolAdjustedForDaylight(base, isDaytime: isDaytime)
            let unit      = Defaults[.lockScreenWeatherTemperatureUnit]
            let rawTemp   = temps[i]
            let tempC     = unit.usesMetricSystem ? rawTemp : (rawTemp - 32) * 5 / 9
            points.append(WeatherData.HourlyPoint(
                time: date, temperature: tempC, symbolName: symbol,
                precipitationChance: Double(precips[safe: i] ?? 0) / 100.0,
                isDaytime: isDaytime
            ))
            if points.count == 12 { break }
        }
        return points
    }

    private func parseOpenMeteoDaily(_ daily: OpenMeteoResponse.Daily?, timezone: String?, utcOffset: Int?) -> [WeatherData.DailyPoint] {
        guard let times = daily?.time else { return [] }
        let maxTemps = daily?.temperature2MMax ?? []
        let minTemps = daily?.temperature2MMin ?? []
        let codes    = daily?.weatherCode ?? []
        let precips  = daily?.precipitationProbabilityMax ?? []
        let sunrises = daily?.sunrise ?? []
        let sunsets  = daily?.sunset ?? []
        let unit     = Defaults[.lockScreenWeatherTemperatureUnit]
        // Skip index 0 (today), take 1…3
        return (1..<min(4, times.count)).compactMap { i in
            guard let date = parseDateOnly(times[i]) else { return nil }
            let code    = codes[safe: i] ?? 0
            let mapping = OpenMeteoSymbolMapper.mapping(for: code)
            let rawMax  = maxTemps[safe: i] ?? 0
            let rawMin  = minTemps[safe: i] ?? 0
            let maxC    = unit.usesMetricSystem ? rawMax : (rawMax - 32) * 5 / 9
            let minC    = unit.usesMetricSystem ? rawMin : (rawMin - 32) * 5 / 9
            let rise    = sunrises[safe: i].flatMap { parseLocalTime($0, timezone: timezone, utcOffset: utcOffset) }
            let set     = sunsets[safe: i].flatMap  { parseLocalTime($0, timezone: timezone, utcOffset: utcOffset) }
            return WeatherData.DailyPoint(
                date: date, symbolName: mapping.symbol, description: mapping.description,
                lowTemperature: minC, highTemperature: maxC,
                precipitationChance: Double(precips[safe: i] ?? 0) / 100.0,
                sunrise: rise, sunset: set
            )
        }
    }

    // MARK: wttr.in

    private func fetchWttr(location: CLLocation?) async throws -> WeatherData {
        let suffix: String
        if let coord = location?.coordinate {
            suffix = String(format: "%.4f,%.4f", coord.latitude, coord.longitude)
        } else {
            suffix = ""
        }
        let base = suffix.isEmpty ? "https://wttr.in/" : "https://wttr.in/\(suffix)"
        guard let url = URL(string: "\(base)?format=j1&aqi=yes") else { throw WeatherFetchError.invalidURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherFetchError.invalidResponse
        }
        let payload = try decoder.decode(WTTRResponse.self, from: data)
        guard let condition = payload.currentCondition.first else { throw WeatherFetchError.noData }

        let unit       = Defaults[.lockScreenWeatherTemperatureUnit]
        let usesMetric = unit.usesMetricSystem
        let rawTemp    = Double(usesMetric ? condition.tempC : condition.tempF) ?? 0
        let tempC      = usesMetric ? rawTemp : (rawTemp - 32) * 5 / 9

        let code       = Int(condition.weatherCode) ?? 113
        let isDaytime  = condition.isDaytime ?? true
        let base2      = WeatherSymbolMapper.symbol(for: code)
        let symbol     = symbolAdjustedForDaylight(base2, isDaytime: isDaytime)

        let todayForecast = payload.dailyWeather.first
        let rawMax = (usesMetric ? todayForecast?.maxtempC : todayForecast?.maxtempF).flatMap(Double.init)
        let rawMin = (usesMetric ? todayForecast?.mintempC : todayForecast?.mintempF).flatMap(Double.init)
        let maxC   = rawMax.map { usesMetric ? $0 : ($0 - 32) * 5 / 9 }
        let minC   = rawMin.map { usesMetric ? $0 : ($0 - 32) * 5 / 9 }

        let locationName = payload.nearestArea.first?.preferredName

        var airQuality: WeatherData.AirQualityInfo?
        if Defaults[.lockScreenWeatherShowsAQI],
           let index = condition.airQuality?.usIndexValue {
            let scale = LockScreenWeatherAirQualityScale.us
            airQuality = WeatherData.AirQualityInfo(
                index: index,
                category: aqiCategory(index: index, scale: scale),
                scale: scale
            )
        }

        let hourly = parseWttrHourly(payload.dailyWeather)
        let daily  = parseWttrDaily(payload.dailyWeather)

        // Sun cycle from today's astronomy
        let todayAstro = todayForecast?.astronomy?.first
        let rise = todayAstro?.sunrise.flatMap { parseWttrAstronomyTime($0, from: Date()) }
        let set  = todayAstro?.sunset.flatMap  { parseWttrAstronomyTime($0, from: Date()) }
        let sunCycle: WeatherData.SunCycleInfo? = (rise != nil || set != nil)
            ? WeatherData.SunCycleInfo(sunrise: rise, sunset: set) : nil

        return WeatherData(
            symbolName: symbol, description: condition.localizedDescription,
            temperature: tempC, minTemperature: minC, maxTemperature: maxC,
            locationName: locationName, isDaytime: isDaytime,
            airQuality: airQuality, sunCycle: sunCycle,
            hourlyForecast: hourly, dailyForecast: daily, fetchedAt: Date()
        )
    }

    private func parseWttrHourly(_ days: [WTTRDailyWeather]) -> [WeatherData.HourlyPoint] {
        let now      = Date()
        let usesMetric = Defaults[.lockScreenWeatherTemperatureUnit].usesMetricSystem
        var points: [WeatherData.HourlyPoint] = []
        for day in days.prefix(2) {
            guard let dateStr = day.date,
                  let baseDate = DateFormatter.wttrDate.date(from: dateStr) else { continue }
            for h in day.hourly ?? [] {
                guard let time = parseWttrHourlyTime(h.time, from: baseDate),
                      time > now else { continue }
                let rawTemp = Double(usesMetric ? h.tempC : h.tempF) ?? 0
                let tempC   = usesMetric ? rawTemp : (rawTemp - 32) * 5 / 9
                let code    = Int(h.weatherCode) ?? 113
                let hr      = Calendar.current.component(.hour, from: time)
                let isDaytime = hr >= 6 && hr < 20
                let symbol  = symbolAdjustedForDaylight(WeatherSymbolMapper.symbol(for: code), isDaytime: isDaytime)
                points.append(WeatherData.HourlyPoint(
                    time: time, temperature: tempC, symbolName: symbol,
                    precipitationChance: Double(h.chanceOfRain ?? "0").map { $0 / 100.0 } ?? 0,
                    isDaytime: isDaytime
                ))
                if points.count == 12 { break }
            }
            if points.count == 12 { break }
        }
        return points
    }

    private func parseWttrDaily(_ days: [WTTRDailyWeather]) -> [WeatherData.DailyPoint] {
        let usesMetric = Defaults[.lockScreenWeatherTemperatureUnit].usesMetricSystem
        return days.dropFirst().prefix(3).compactMap { day in
            guard let dateStr = day.date,
                  let date = DateFormatter.wttrDate.date(from: dateStr) else { return nil }
            let rawMax = Double(usesMetric ? (day.maxtempC ?? "0") : (day.maxtempF ?? "0")) ?? 0
            let rawMin = Double(usesMetric ? (day.mintempC ?? "0") : (day.mintempF ?? "0")) ?? 0
            let maxC   = usesMetric ? rawMax : (rawMax - 32) * 5 / 9
            let minC   = usesMetric ? rawMin : (rawMin - 32) * 5 / 9
            let code   = day.hourly?.first.flatMap { Int($0.weatherCode) } ?? 113
            let symbol = WeatherSymbolMapper.symbol(for: code)
            let rise   = day.astronomy?.first?.sunrise.flatMap { parseWttrAstronomyTime($0, from: date) }
            let set    = day.astronomy?.first?.sunset.flatMap  { parseWttrAstronomyTime($0, from: date) }
            let precip = Double(day.hourly?.first?.chanceOfRain ?? "0").map { $0 / 100.0 } ?? 0
            return WeatherData.DailyPoint(
                date: date, symbolName: symbol, description: "",
                lowTemperature: minC, highTemperature: maxC, precipitationChance: precip,
                sunrise: rise, sunset: set
            )
        }
    }

    // MARK: - Shared utilities

    private func parseLocalTime(_ value: String, timezone: String?, utcOffset: Int?) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let id = timezone, let tz = TimeZone(identifier: id) {
            formatter.timeZone = tz
        } else if let offset = utcOffset, let tz = TimeZone(secondsFromGMT: offset) {
            formatter.timeZone = tz
        }
        return formatter.date(from: value)
    }

    private func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func parseWttrHourlyTime(_ timeString: String, from date: Date) -> Date? {
        guard let hm = Int(timeString) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = hm / 100
        components.minute = hm % 100
        components.second = 0
        return cal.date(from: components)
    }

    private func parseWttrAstronomyTime(_ timeString: String, from date: Date) -> Date? {
        let cal = Calendar.current
        let dayComp = cal.dateComponents([.year, .month, .day], from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        let prefix = String(format: "%04d-%02d-%02d",
                            dayComp.year ?? 2024, dayComp.month ?? 1, dayComp.day ?? 1)
        return formatter.date(from: "\(prefix) \(timeString)")
    }

    private func aqiCategory(index: Int, scale: LockScreenWeatherAirQualityScale) -> WeatherData.AirQualityInfo.Category {
        switch scale {
        case .us:
            switch index {
            case ..<0:    return .unknown
            case 0...50:  return .good
            case 51...100: return .moderate
            case 101...150: return .unhealthyForSensitive
            case 151...200: return .unhealthy
            case 201...300: return .veryUnhealthy
            default:      return .hazardous
            }
        case .european:
            switch index {
            case ..<0:    return .unknown
            case 0...20:  return .good
            case 21...40: return .fair
            case 41...60: return .moderate
            case 61...80: return .poor
            case 81...100: return .veryPoor
            default:      return .extremelyPoor
            }
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - DateFormatter helper

private extension DateFormatter {
    static let wttrDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Symbol helpers (moved from LockScreenWeatherManager)

private enum WeatherSymbolMapper {
    static func symbol(for code: Int) -> String {
        switch code {
        case 113: return "sun.max.fill"
        case 116: return "cloud.sun.fill"
        case 119, 122: return "cloud.fill"
        case 143, 248, 260: return "cloud.fog.fill"
        case 176, 263, 266, 293, 296, 299, 302, 353, 356, 359: return "cloud.rain.fill"
        case 179, 182, 185, 311, 314, 317, 320, 362, 365: return "cloud.sleet.fill"
        case 227, 230, 281, 284, 323, 326, 329, 332, 335, 338, 368, 371, 374, 377: return "cloud.snow.fill"
        case 200, 386, 389, 392, 395: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

private enum OpenMeteoSymbolMapper {
    static func mapping(for code: Int) -> (symbol: String, description: String) {
        switch code {
        case 0:      return ("sun.max.fill",         "Clear sky")
        case 1:      return ("cloud.sun.fill",        "Mainly clear")
        case 2:      return ("cloud.sun.fill",        "Partly cloudy")
        case 3:      return ("cloud.fill",            "Overcast")
        case 45, 48: return ("cloud.fog.fill",        "Fog")
        case 51, 53, 55: return ("cloud.drizzle.fill","Drizzle")
        case 56, 57: return ("cloud.sleet.fill",      "Freezing drizzle")
        case 61, 63, 65: return ("cloud.rain.fill",   "Rain")
        case 66, 67: return ("cloud.sleet.fill",      "Freezing rain")
        case 71, 73, 75, 77: return ("cloud.snow.fill","Snow")
        case 80, 81, 82: return ("cloud.heavyrain.fill","Rain showers")
        case 85, 86: return ("cloud.snow.fill",       "Snow showers")
        case 95:     return ("cloud.bolt.rain.fill",  "Thunderstorm")
        case 96, 99: return ("cloud.bolt.rain.fill",  "Thunderstorm with hail")
        default:     return ("cloud.sun.fill",        "Cloudy")
        }
    }
}

private func symbolAdjustedForDaylight(_ symbol: String, isDaytime: Bool) -> String {
    guard !isDaytime else { return symbol }
    switch symbol {
    case "sun.max.fill":        return "moon.stars.fill"
    case "cloud.sun.fill":      return "cloud.moon.fill"
    case "cloud.sun.rain.fill": return "cloud.moon.rain.fill"
    case "cloud.sun.bolt.fill": return "cloud.moon.bolt.fill"
    default:                    return symbol
    }
}

// MARK: - JSON response structs

private enum WeatherFetchError: Error {
    case invalidURL, invalidResponse, noData
}

// Open-Meteo

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature2M: Double?
        let weatherCode: Int?
        let isDay: Int?
    }
    struct Hourly: Decodable {
        let time: [String]?
        let temperature2M: [Double]?
        let weatherCode: [Int]?
        let precipitationProbability: [Int]?
        let isDay: [Int]?
    }
    struct Daily: Decodable {
        let time: [String]?
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
        let weatherCode: [Int]?
        let precipitationProbabilityMax: [Int]?
        let sunrise: [String]?
        let sunset: [String]?
    }
    let current: Current?
    let hourly: Hourly?
    let daily: Daily?
    let timezone: String?
    let utcOffsetSeconds: Int?
}

private struct OpenMeteoAQResponse: Decodable {
    struct Current: Decodable {
        let usAqi: Double?
        let europeanAqi: Double?
    }
    let current: Current?
}

// wttr.in

private struct WTTRResponse: Decodable {
    let current_condition: [WTTRCurrentCondition]
    let nearest_area: [WTTRNearestArea]?
    let weather: [WTTRDailyWeather]?
    var currentCondition: [WTTRCurrentCondition] { current_condition }
    var nearestArea: [WTTRNearestArea]          { nearest_area ?? [] }
    var dailyWeather: [WTTRDailyWeather]        { weather ?? [] }
}

private struct WTTRCurrentCondition: Decodable {
    private enum CodingKeys: String, CodingKey {
        case tempC = "temp_C", tempF = "temp_F", weatherCode, weatherDesc, langEn = "lang_en"
        case airQuality = "air_quality", isday
    }
    let tempC: String
    let tempF: String
    let weatherCode: String
    let weatherDesc: [WTTRTextValue]?
    let langEn: [WTTRTextValue]?
    let airQuality: WTTRAirQuality?
    let isday: String?
    var localizedDescription: String {
        langEn?.first?.value.nilIfEmpty ?? weatherDesc?.first?.value ?? ""
    }
    var isDaytime: Bool? {
        guard let s = isday?.trimmingCharacters(in: .whitespaces) else { return nil }
        return s == "1" || s.lowercased() == "yes"
    }
}

private struct WTTRTextValue: Decodable { let value: String }

private struct WTTRAirQuality: Decodable {
    private enum CodingKeys: String, CodingKey { case usEpaIndex = "us-epa-index" }
    let usEpaIndex: String?
    var usIndexValue: Int? { usEpaIndex.flatMap(Int.init) }
}

private struct WTTRDailyWeather: Decodable {
    let date: String?
    let maxtempC: String?
    let maxtempF: String?
    let mintempC: String?
    let mintempF: String?
    let hourly: [WTTRHourlyPoint]?
    let astronomy: [WTTRAstronomy]?
}

private struct WTTRHourlyPoint: Decodable {
    private enum CodingKeys: String, CodingKey {
        case time, tempC, tempF, weatherCode, chanceOfRain = "chanceofrain"
    }
    let time: String
    let tempC: String
    let tempF: String
    let weatherCode: String
    let chanceOfRain: String?
}

private struct WTTRAstronomy: Decodable {
    let sunrise: String?
    let sunset: String?
}

private struct WTTRNearestArea: Decodable {
    let areaName: [WTTRTextValue]?
    let region: [WTTRTextValue]?
    let country: [WTTRTextValue]?
    var preferredName: String? {
        areaName?.first?.value.nilIfEmpty
        ?? region?.first?.value.nilIfEmpty
        ?? country?.first?.value.nilIfEmpty
    }
}

// MARK: - String helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
