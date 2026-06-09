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

// MARK: - LockScreenWeatherSnapshot
//
// Preserved verbatim from the original LockScreenWeatherManager: this type is the
// lock-screen-facing view model consumed by LockScreenWeatherPanelManager,
// LockScreenWidgetPreviewManager and LockScreenWeatherWidget. The WeatherService
// refactor only moved the *fetching* out of this file; the snapshot model stays.

struct LockScreenWeatherSnapshot: Equatable {
    struct SunCycleInfo: Equatable {
        let sunrise: Date?
        let sunset: Date?
    }

    struct TemperatureInfo: Equatable {
        let current: Double
        let minimum: Double?
        let maximum: Double?
        let unitSymbol: String

        var displayMinimum: String? {
            guard let minimum else { return nil }
            return Self.formatted(value: minimum)
        }

        var displayMaximum: String? {
            guard let maximum else { return nil }
            return Self.formatted(value: maximum)
        }

        var displayCurrent: String {
            Self.formatted(value: current)
        }

        private static func formatted(value: Double) -> String {
            let rounded = Int(round(value))
            return "\(rounded)"
        }
    }

    struct ChargingInfo: Equatable {
        let minutesRemaining: Int?
        let isCharging: Bool
        let isPluggedIn: Bool
        let batteryLevel: Int?

        var iconName: String {
            if isCharging {
                return "bolt.fill"
            }
            if isPluggedIn {
                return "powerplug.portrait.fill"
            }
            return ""
        }
    }

    struct BluetoothInfo: Equatable {
        let deviceName: String
        let batteryLevel: Int
        let iconName: String
    }

    struct BatteryInfo: Equatable {
        let batteryLevel: Int
        let usesLaptopSymbol: Bool
    }

    struct AirQualityInfo: Equatable {
        enum Category: String, Equatable {
            case good
            case fair
            case moderate
            case unhealthyForSensitive
            case unhealthy
            case poor
            case veryPoor
            case veryUnhealthy
            case extremelyPoor
            case hazardous
            case unknown

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
        let scale: LockScreenWeatherAirQualityScale
    }

    let temperatureText: String
    let symbolName: String
    let description: String
    let locationName: String?
    let charging: ChargingInfo?
    let bluetooth: BluetoothInfo?
    let battery: BatteryInfo?
    let showsLocation: Bool
    let airQuality: AirQualityInfo?
    let widgetStyle: LockScreenWeatherWidgetStyle
    let showsChargingPercentage: Bool
    let temperatureInfo: TemperatureInfo?
    let usesGaugeTint: Bool
    let sunCycle: SunCycleInfo?
    let showsSunrise: Bool
}

extension LockScreenWeatherSnapshot.AirQualityInfo.Category {
    init(index: Int, scale: LockScreenWeatherAirQualityScale) {
        switch scale {
        case .us:
            switch index {
            case ..<0:
                self = .unknown
            case 0...50:
                self = .good
            case 51...100:
                self = .moderate
            case 101...150:
                self = .unhealthyForSensitive
            case 151...200:
                self = .unhealthy
            case 201...300:
                self = .veryUnhealthy
            case 301...:
                self = .hazardous
            default:
                self = .unknown
            }
        case .european:
            switch index {
            case ..<0:
                self = .unknown
            case 0...20:
                self = .good
            case 21...40:
                self = .fair
            case 41...60:
                self = .moderate
            case 61...80:
                self = .poor
            case 81...100:
                self = .veryPoor
            case 101...:
                self = .extremelyPoor
            default:
                self = .unknown
            }
        }
    }
}
