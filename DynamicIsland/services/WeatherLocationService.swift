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
