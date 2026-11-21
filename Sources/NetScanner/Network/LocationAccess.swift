//
//  LocationAccess.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import CoreLocation
import Observation

/// Location permission, which macOS requires before it shows an app Wi-Fi BSSIDs and the name of the
/// network the Mac is on. The app never asks for or stores an actual location.
@MainActor
@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    enum State: Equatable {
        case notDetermined, granted, denied
        /// Location Services is off for the whole Mac.
        case servicesOff
    }

    private(set) var state: State = .notDetermined
    /// Called when access is granted, so the caller can scan again with full details.
    @ObservationIgnored var onGranted: (@MainActor () -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    private func refresh() {
        let status = manager.authorizationStatus
        let previous = state
        switch status {
        case .notDetermined: state = .notDetermined
        case .denied, .restricted: state = .denied
        default: state = .granted
        }
        if state == .granted, previous != .granted { onGranted?() }
        // A denial can mean Location Services is off altogether, which needs a different fix.
        // The check can be slow, so it stays off the main thread.
        if state == .denied {
            Task {
                let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
                if !enabled, self.state == .denied { self.state = .servicesOff }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    /// System Settings › Privacy & Security › Location Services.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
}
