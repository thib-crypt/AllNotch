# WeatherPlugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a shared `WeatherService` from `LockScreenWeatherManager`, delete all JSON-parsing boilerplate (~800 lines), and wire a full-featured `WeatherPlugin` (notch tab with current conditions + configurable forecast, settings, opt-in sneak peek) that all other consumers share.

**Architecture:** A new `WeatherService` singleton (`@MainActor ObservableObject`) owns all fetch/location/cache logic using Open-Meteo (primary) and wttr.in (fallback). `LockScreenWeatherManager` is refactored to observe `WeatherService.$current` and layer on battery/charging/bluetooth info to rebuild its `LockScreenWeatherSnapshot`. `WeatherPlugin` conforms to `NotchTabProviding + SettingsProviding + PluginLifecycle + SneakPeekProviding` and calls `WeatherService.startPolling()` on activate.

**Tech Stack:** Swift 5, SwiftUI, Combine, CoreLocation, URLSession, Defaults (sindresorhus), existing Open-Meteo + wttr.in APIs (no auth, open-source friendly).

---

## File Map

### New files
| Path | Responsibility |
|---|---|
| `DynamicIsland/models/WeatherData.swift` | Clean shared data model — no lock-screen concerns |
| `DynamicIsland/services/WeatherLocationService.swift` | CLLocationManager wrapper extracted from LockScreenWeatherManager |
| `DynamicIsland/services/WeatherService.swift` | Shared fetch/cache/polling service + private WeatherDataProvider actor |
| `DynamicIsland/Plugins/Weather/WeatherPlugin.swift` | Plugin registration, lifecycle, sneak peek logic |
| `DynamicIsland/components/Weather/WeatherTabView.swift` | Notch tab: current conditions + daily/hourly forecast |
| `DynamicIsland/components/Settings/WeatherSettings.swift` | Settings section for the plugin |

### Modified files
| Path | Change |
|---|---|
| `DynamicIsland/enums/generic.swift` | Add `WeatherForecastFormat` enum |
| `DynamicIsland/models/Constants.swift` | Add `enableWeatherFeature`, `weatherForecastFormat`, `weatherSneakPeekEnabled` Defaults keys |
| `DynamicIsland/Plugins/Core/PluginID.swift` | Add `static let weather` |
| `DynamicIsland/Plugins/Core/PluginHost.swift` | Register `WeatherPlugin()` in `allPlugins` |
| `DynamicIsland/managers/LockScreenWeatherManager.swift` | **Delete** ~800 lines of JSON parsing; observe `WeatherService.$current`; keep only snapshot-assembly logic |

### Deleted code (inside LockScreenWeatherManager.swift)
- `private actor LockScreenWeatherProvider` (entire actor)
- `@MainActor private final class LockScreenWeatherLocationProvider` (entire class — replaced by `WeatherLocationService`)
- `private struct WTTRResponse` and all nested `WTTR*` structs
- `private struct OpenMeteoForecastResponse` and nested structs
- `private enum WeatherProviderError`
- `private enum WeatherSymbolMapper`
- `private enum OpenMeteoSymbolMapper`
- `private func symbolAdjustedForDaylight`

---

## Build command (use for every build step)

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -20
```

Expected final line on success: `** BUILD SUCCEEDED **`

---

## Task 1 — WeatherData model, WeatherForecastFormat enum, Defaults keys

**Files:**
- Create: `DynamicIsland/models/WeatherData.swift`
- Modify: `DynamicIsland/enums/generic.swift` (append `WeatherForecastFormat`)
- Modify: `DynamicIsland/models/Constants.swift` (append three keys to `extension Defaults.Keys`)
- Modify: `DynamicIsland/Plugins/Core/PluginID.swift` (append `.weather`)

- [ ] **Step 1 — Create `WeatherData.swift`**

Create `DynamicIsland/models/WeatherData.swift` with the following content:

```swift
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
```

- [ ] **Step 2 — Add `WeatherForecastFormat` to `enums/generic.swift`**

Append to the end of `DynamicIsland/enums/generic.swift` (before the closing of the file, after the last enum):

```swift
/// Controls whether the WeatherPlugin notch tab shows a 3-day daily forecast or 6-hour hourly forecast.
enum WeatherForecastFormat: String, CaseIterable, Defaults.Serializable, Identifiable {
    case daily  = "daily"
    case hourly = "hourly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily:  return String(localized: "3-Day")
        case .hourly: return String(localized: "Hourly")
        }
    }
}
```

- [ ] **Step 3 — Add Defaults keys to `Constants.swift`**

Find the `extension Defaults.Keys` block in `DynamicIsland/models/Constants.swift`. Append these three keys after the existing lock-screen weather keys (around line 896):

```swift
    // MARK: Weather Plugin
    static let enableWeatherFeature    = Key<Bool>("enableWeatherFeature",    default: true)
    static let weatherForecastFormat   = Key<WeatherForecastFormat>("weatherForecastFormat", default: .daily)
    static let weatherSneakPeekEnabled = Key<Bool>("weatherSneakPeekEnabled", default: false)
```

- [ ] **Step 4 — Add `PluginID.weather` to `PluginID.swift`**

In `DynamicIsland/Plugins/Core/PluginID.swift`, append to the `extension PluginID` block:

```swift
    /// Weather conditions and forecast feature.
    static let weather = PluginID("weather")
```

- [ ] **Step 5 — Build to verify new types compile**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6 — Commit**

```bash
git add DynamicIsland/models/WeatherData.swift \
        DynamicIsland/enums/generic.swift \
        DynamicIsland/models/Constants.swift \
        DynamicIsland/Plugins/Core/PluginID.swift
git commit -m "feat(weather): add WeatherData model, WeatherForecastFormat enum, Defaults keys"
```

---

## Task 2 — WeatherLocationService

Extract the `CLLocationManager` wrapper from `LockScreenWeatherManager.swift` into its own file. The logic is identical to the private inner class `LockScreenWeatherLocationProvider`; only the name and isolation annotations change.

**Files:**
- Create: `DynamicIsland/services/WeatherLocationService.swift`

- [ ] **Step 1 — Create `WeatherLocationService.swift`**

Create `DynamicIsland/services/WeatherLocationService.swift`:

```swift
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
import Foundation

/// Thin `CLLocationManager` wrapper used by `WeatherService`.
/// Caches the last fix for 30 minutes before requesting a new one.
@MainActor
final class WeatherLocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var pendingContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var lastLocation: CLLocation?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Requests authorization if status is `.notDetermined`. Safe to call multiple times.
    func prepareAuthorization() {
        if CLLocationManager.authorizationStatus() == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Returns the current location asynchronously.
    /// Returns `nil` when permission is denied or the fix fails.
    func currentLocation() async -> CLLocation? {
        let status = CLLocationManager.authorizationStatus()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if let last = lastLocation, abs(last.timestamp.timeIntervalSinceNow) < 1800 {
                return last
            }
            manager.requestLocation()
            return await withCheckedContinuation { continuation in
                pendingContinuations.append(continuation)
            }
        default:
            return nil
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.lastLocation = locations.last
            self?.flushContinuations(with: locations.last)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.flushContinuations(with: nil)
        }
    }

    private func flushContinuations(with location: CLLocation?) {
        let all = pendingContinuations
        pendingContinuations.removeAll()
        all.forEach { $0.resume(returning: location) }
    }
}
```

- [ ] **Step 2 — Build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3 — Commit**

```bash
git add DynamicIsland/services/WeatherLocationService.swift
git commit -m "feat(weather): extract WeatherLocationService from LockScreenWeatherManager"
```

---

## Task 3 — WeatherService

The main shared service. Contains a `@MainActor` public class and a `private actor WeatherDataProvider` for thread-safe network calls. Reuses and moves the Open-Meteo / wttr.in fetch logic (and all private JSON structs + symbol mappers) that will be deleted from `LockScreenWeatherManager` in Task 4.

**Files:**
- Create: `DynamicIsland/services/WeatherService.swift`

- [ ] **Step 1 — Create `WeatherService.swift`**

Create `DynamicIsland/services/WeatherService.swift` with the full content below. This is the largest file in the plan — read it carefully before applying.

```swift
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
```

- [ ] **Step 2 — Build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

> **Note:** At this point `WeatherService` compiles alongside the old `LockScreenWeatherManager` code. Both define `WeatherSymbolMapper` / `OpenMeteoSymbolMapper` / `symbolAdjustedForDaylight` — but as `private` symbols in separate files they will not collide. They will be deleted from `LockScreenWeatherManager` in Task 4.

- [ ] **Step 3 — Commit**

```bash
git add DynamicIsland/services/WeatherService.swift
git commit -m "feat(weather): add shared WeatherService with Open-Meteo + wttr.in, hourly forecast, reverse geocoding"
```

---

## Task 4 — Refactor LockScreenWeatherManager

Delete ~800 lines of JSON-parsing boilerplate, wire the manager to observe `WeatherService.$current`, and keep only snapshot-assembly + battery/bluetooth logic.

**Files:**
- Modify: `DynamicIsland/managers/LockScreenWeatherManager.swift`

- [ ] **Step 1 — Replace the file content**

`LockScreenWeatherManager.swift` will shrink from ~1100 lines to ~280 lines. Replace the **entire file** with the following:

```swift
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

@MainActor
final class LockScreenWeatherManager: ObservableObject {
    static let shared = LockScreenWeatherManager()

    @Published private(set) var snapshot: LockScreenWeatherSnapshot?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe WeatherService: whenever fresh data arrives, rebuild and deliver the snapshot.
        WeatherService.shared.$current
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] data in
                guard let self else { return }
                let snap = self.makeSnapshot(from: data)
                self.snapshot = snap
                self.deliverIfLocked(snap, forceShow: false)
            }
            .store(in: &cancellables)

        observeAccessoryAndPreferenceChanges()

        if Defaults[.enableLockScreenWeatherWidget] {
            WeatherService.shared.startPolling()
        }
    }

    // MARK: - Public API (preserved for callers)

    func prepareLocationAccess() {
        WeatherService.shared.requestLocationAccess()
    }

    func showWeatherWidget() {
        guard Defaults[.enableLockScreenWeatherWidget] else {
            LockScreenWeatherPanelManager.shared.hide()
            return
        }
        if let data = WeatherService.shared.current {
            let snap = makeSnapshot(from: data)
            snapshot = snap
            deliver(snap, forceShow: true)
        }
        Task { await WeatherService.shared.refresh(force: false) }
    }

    func hideWeatherWidget() {
        LockScreenWeatherPanelManager.shared.hide()
    }

    @discardableResult
    func refresh(force: Bool = false) async -> LockScreenWeatherSnapshot? {
        _ = await WeatherService.shared.refresh(force: force)
        return snapshot
    }

    // MARK: - Snapshot assembly

    private func makeSnapshot(from data: WeatherData) -> LockScreenWeatherSnapshot {
        let unit       = Defaults[.lockScreenWeatherTemperatureUnit]
        let tempC      = data.temperature
        let tempValue  = unit.usesMetricSystem ? tempC : celsius(tempC, toFahrenheit: true)
        let tempText   = "\(Int(round(tempValue)))°"

        let minRaw = data.minTemperature.map { unit.usesMetricSystem ? $0 : celsius($0, toFahrenheit: true) }
        let maxRaw = data.maxTemperature.map { unit.usesMetricSystem ? $0 : celsius($0, toFahrenheit: true) }
        let temperatureInfo = LockScreenWeatherSnapshot.TemperatureInfo(
            current: tempValue, minimum: minRaw, maximum: maxRaw, unitSymbol: unit.symbol
        )

        let widgetStyle   = Defaults[.lockScreenWeatherWidgetStyle]
        let chargingInfo  = Defaults[.lockScreenBatteryShowsCharging]    ? makeChargingInfo()  : nil
        let bluetoothInfo = Defaults[.lockScreenBatteryShowsBluetooth]   ? makeBluetoothInfo() : nil
        let batteryInfo   = Defaults[.lockScreenBatteryShowsBatteryGauge]
            ? makeBatteryGaugeInfo(isCharging: chargingInfo != nil, widgetStyle: widgetStyle) : nil

        let providerSource = Defaults[.lockScreenWeatherProviderSource]
        let airQualityInfo: LockScreenWeatherSnapshot.AirQualityInfo?
        if let aq = data.airQuality,
           Defaults[.lockScreenWeatherShowsAQI],
           providerSource.supportsAirQuality {
            airQualityInfo = LockScreenWeatherSnapshot.AirQualityInfo(
                index: aq.index,
                category: LockScreenWeatherSnapshot.AirQualityInfo.Category(aq.category),
                scale: aq.scale
            )
        } else {
            airQualityInfo = nil
        }

        let shouldShowLocation = widgetStyle == .inline
            && Defaults[.lockScreenWeatherShowsLocation]
            && !(data.locationName?.isEmpty ?? true)

        let sunCycle: LockScreenWeatherSnapshot.SunCycleInfo?
        if let sc = data.sunCycle {
            sunCycle = LockScreenWeatherSnapshot.SunCycleInfo(sunrise: sc.sunrise, sunset: sc.sunset)
        } else {
            sunCycle = nil
        }

        let showsSunrise = Defaults[.lockScreenWeatherShowsSunrise]
            && widgetStyle == .inline
            && sunCycle?.sunrise != nil

        return LockScreenWeatherSnapshot(
            temperatureText: tempText,
            symbolName: data.symbolName,
            description: data.description,
            locationName: data.locationName,
            charging: chargingInfo,
            bluetooth: bluetoothInfo,
            battery: batteryInfo,
            showsLocation: shouldShowLocation,
            airQuality: airQualityInfo,
            widgetStyle: widgetStyle,
            showsChargingPercentage: Defaults[.lockScreenBatteryShowsChargingPercentage],
            temperatureInfo: temperatureInfo,
            usesGaugeTint: Defaults[.lockScreenWeatherUsesGaugeTint],
            sunCycle: sunCycle,
            showsSunrise: showsSunrise
        )
    }

    private func celsius(_ value: Double, toFahrenheit: Bool) -> Double {
        toFahrenheit ? value * 9.0 / 5.0 + 32.0 : value
    }

    // MARK: - Delivery

    private func deliverIfLocked(_ snap: LockScreenWeatherSnapshot, forceShow: Bool) {
        guard LockScreenManager.shared.currentLockStatus else { return }
        deliver(snap, forceShow: forceShow)
    }

    private func deliver(_ snap: LockScreenWeatherSnapshot, forceShow: Bool) {
        if forceShow {
            LockScreenWeatherPanelManager.shared.show(with: snap)
        } else {
            LockScreenWeatherPanelManager.shared.update(with: snap)
        }
    }

    // MARK: - Accessory & preference observation

    /// Rebuilds the snapshot from `WeatherService.shared.current` without re-fetching.
    /// Called when battery, bluetooth, or display-preference Defaults change.
    private func rebuildFromCurrentData(triggerBluetoothRefresh: Bool) {
        guard let data = WeatherService.shared.current else { return }
        if triggerBluetoothRefresh {
            BluetoothAudioManager.shared.refreshConnectedDeviceBatteries()
        }
        let snap = makeSnapshot(from: data)
        snapshot = snap
        deliverIfLocked(snap, forceShow: false)
    }

    private func observeAccessoryAndPreferenceChanges() {
        let bt = BluetoothAudioManager.shared
        bt.$connectedDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildFromCurrentData(triggerBluetoothRefresh: false) }
            .store(in: &cancellables)
        bt.$lastConnectedDevice
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildFromCurrentData(triggerBluetoothRefresh: false) }
            .store(in: &cancellables)

        let battery = BatteryStatusViewModel.shared
        Publishers.MergeMany([
            battery.$isCharging.map { _ in () }.eraseToAnyPublisher(),
            battery.$isPluggedIn.map { _ in () }.eraseToAnyPublisher(),
            battery.$timeToFullCharge.map { _ in () }.eraseToAnyPublisher(),
        ])
        .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuildFromCurrentData(triggerBluetoothRefresh: false) }
        .store(in: &cancellables)

        let displayKeys: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.lockScreenWeatherShowsLocation,         options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenBatteryShowsCharging,         options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenBatteryShowsChargingPercentage, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenBatteryShowsBluetooth,        options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenBatteryShowsBatteryGauge,     options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenBatteryUsesLaptopSymbol,      options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsSunrise,          options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherWidgetStyle,           options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherShowsAQI,              options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lockScreenWeatherUsesGaugeTint,         options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(displayKeys)
            .sink { [weak self] in self?.rebuildFromCurrentData(triggerBluetoothRefresh: true) }
            .store(in: &cancellables)

        Defaults.publisher(.enableLockScreenWeatherWidget, options: [])
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    WeatherService.shared.startPolling()
                    Task { await self.refresh(force: true) }
                } else {
                    LockScreenWeatherPanelManager.shared.hide()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Battery / charging / bluetooth helpers (unchanged from original)

    private func makeChargingInfo() -> LockScreenWeatherSnapshot.ChargingInfo? {
        let battery   = BatteryStatusViewModel.shared
        let macStatus = MacBatteryManager.shared.currentStatus()
        let isPluggedIn = battery.isPluggedIn || battery.isCharging
        let isCharging  = macStatus.isCharging || battery.isCharging
        guard isPluggedIn || isCharging else { return nil }
        let rawMinutes = macStatus.timeRemainingMinutes ?? (battery.timeToFullCharge > 0 ? battery.timeToFullCharge : nil)
        let remaining  = (rawMinutes ?? 0) > 0 ? rawMinutes : nil
        let rawLevel   = Int(round(Double(battery.levelBattery)))
        let level      = min(max(rawLevel, 0), 100)
        return LockScreenWeatherSnapshot.ChargingInfo(
            minutesRemaining: remaining, isCharging: isCharging,
            isPluggedIn: isPluggedIn, batteryLevel: isPluggedIn || isCharging ? level : nil
        )
    }

    private func makeBatteryGaugeInfo(isCharging: Bool, widgetStyle: LockScreenWeatherWidgetStyle) -> LockScreenWeatherSnapshot.BatteryInfo? {
        guard !isCharging else { return nil }
        let battery = BatteryStatusViewModel.shared
        let level   = min(max(Int(round(Double(battery.levelBattery))), 0), 100)
        guard level >= 0 else { return nil }
        return LockScreenWeatherSnapshot.BatteryInfo(
            batteryLevel: level, usesLaptopSymbol: Defaults[.lockScreenBatteryUsesLaptopSymbol]
        )
    }

    private func makeBluetoothInfo() -> LockScreenWeatherSnapshot.BluetoothInfo? {
        let manager = BluetoothAudioManager.shared
        guard manager.isBluetoothAudioConnected else { return nil }
        let device = manager.connectedDevices.last ?? manager.lastConnectedDevice
        guard let device, let batteryLevel = device.batteryLevel else { return nil }
        return LockScreenWeatherSnapshot.BluetoothInfo(
            deviceName: device.name,
            batteryLevel: min(max(batteryLevel, 0), 100),
            iconName: device.deviceType.sfSymbol
        )
    }
}
```

- [ ] **Step 2 — Build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` with no errors. Fix any "use of unresolved identifier" errors by checking that the deleted types (`LockScreenWeatherLocationProvider`, `LockScreenWeatherProvider`, etc.) are not referenced elsewhere. Use:
```bash
grep -rn "LockScreenWeatherProvider\|LockScreenWeatherLocationProvider\|WTTRResponse\|OpenMeteoForecastResponse\|WeatherProviderError" DynamicIsland/ --include="*.swift"
```
to confirm there are no remaining references.

- [ ] **Step 3 — Commit**

```bash
git add DynamicIsland/managers/LockScreenWeatherManager.swift
git commit -m "refactor(weather): delegate LockScreenWeatherManager to WeatherService, delete ~800 lines of JSON parsing"
```

---

## Task 5 — WeatherPlugin scaffolding

Register the plugin, wire lifecycle (start polling + sneak peek), and add it to `PluginHost`.

**Files:**
- Create: `DynamicIsland/Plugins/Weather/WeatherPlugin.swift`
- Modify: `DynamicIsland/Plugins/Core/PluginHost.swift`

- [ ] **Step 1 — Create `WeatherPlugin.swift`**

```swift
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

    private func startSneakPeekObservation() {
        sneakPeekObservation = WeatherService.shared.$current
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] data in
                self?.handleWeatherUpdate(data)
            }
    }

    private func handleWeatherUpdate(_ data: WeatherData) {
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
```

- [ ] **Step 2 — Register in `PluginHost.allPlugins`**

In `DynamicIsland/Plugins/Core/PluginHost.swift`, add `WeatherPlugin()` to the `allPlugins` array:

```swift
let allPlugins: [any Plugin] = [
    ScreenshotPlugin(),
    TodoPlugin(),
    ColorPickerPlugin(),
    AgentsPlugin(),
    WeatherPlugin(),      // ← add this line
]
```

- [ ] **Step 3 — Build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4 — Commit**

```bash
git add DynamicIsland/Plugins/Weather/WeatherPlugin.swift \
        DynamicIsland/Plugins/Core/PluginHost.swift
git commit -m "feat(weather): register WeatherPlugin with lifecycle and sneak peek"
```

---

## Task 6 — WeatherTabView

The notch tab: current conditions header + switchable forecast section (daily 3-day or hourly 6-point based on `weatherForecastFormat`).

**Files:**
- Create: `DynamicIsland/components/Weather/WeatherTabView.swift`

- [ ] **Step 1 — Create `WeatherTabView.swift`**

```swift
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
                        .foregroundStyle(.secondary)
                    Text("No weather data")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let loc = data.locationName, !loc.isEmpty {
                    Label(loc, systemImage: "location.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)

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
```

- [ ] **Step 2 — Build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3 — Commit**

```bash
git add DynamicIsland/components/Weather/WeatherTabView.swift
git commit -m "feat(weather): add WeatherTabView with current conditions and daily/hourly forecast"
```

---

## Task 7 — WeatherSettings + final build

Settings section for the WeatherPlugin, wired into the existing Settings sidebar via the plugin system.

**Files:**
- Create: `DynamicIsland/components/Settings/WeatherSettings.swift`

- [ ] **Step 1 — Create `WeatherSettings.swift`**

```swift
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
```

- [ ] **Step 2 — Full clean build**

```bash
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  2>&1 | grep -E "error:|warning:.*WeatherService|BUILD"
```

Expected: `** BUILD SUCCEEDED **`. Address any remaining warnings about the weather subsystem.

- [ ] **Step 3 — Sanity-check: confirm old boilerplate is gone**

```bash
grep -rn "LockScreenWeatherProvider\|WTTRResponse\|OpenMeteoForecastResponse\|WeatherProviderError\|WeatherSymbolMapper\|OpenMeteoSymbolMapper" \
  DynamicIsland/managers/LockScreenWeatherManager.swift
```

Expected: **no output** (all boilerplate has been deleted).

- [ ] **Step 4 — Commit**

```bash
git add DynamicIsland/components/Settings/WeatherSettings.swift
git commit -m "feat(weather): add WeatherSettings section with provider, unit, forecast style, and sneak peek controls"
```

---

## Self-Review

**Spec coverage check:**

| Requirement | Task |
|---|---|
| WeatherService extracted from LockScreenWeatherManager | Tasks 3, 4 |
| LockScreen still works (LockScreenWeatherSnapshot unchanged) | Task 4 |
| Old JSON parsing boilerplate deleted | Task 4 |
| WeatherPlugin: tab with current conditions | Task 6 |
| WeatherPlugin: configurable forecast (daily / hourly) | Tasks 1, 5, 6, 7 |
| WeatherPlugin: settings section | Task 7 |
| Sneak peek (off by default, configurable) | Tasks 1, 5, 7 |
| Reverse geocoding for Open-Meteo location names | Task 3 |
| Hourly forecast data from both providers | Task 3 |
| PluginID + PluginHost registration | Tasks 1, 5 |
| Defaults keys | Task 1 |
| Build succeeds | Each task + Task 7 Step 2 |

**Placeholder scan:** No TBD/TODO in the plan. All code steps show the full implementation.

**Type consistency check:**
- `WeatherData.AirQualityInfo.Category` → converted via `LockScreenWeatherSnapshot.AirQualityInfo.Category.init(_:)` in `WeatherData.swift` Task 1 ✓
- `WeatherForecastFormat` defined in `enums/generic.swift` (Task 1), used in `WeatherPlugin` (Task 5), `WeatherTabView` (Task 6), `WeatherSettings` (Task 7) ✓
- `WeatherService.shared.startPolling()` called in `WeatherPlugin.activate()` (Task 5) and `LockScreenWeatherManager.init()` (Task 4) — both are `@MainActor`, consistent ✓
- `PluginID.weather` defined in Task 1, used in Tasks 5 ✓
- `Defaults[.enableWeatherFeature]` type `Bool` — consistent across all uses ✓
