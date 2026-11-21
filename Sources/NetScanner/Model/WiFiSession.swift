//
//  WiFiSession.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Observation

enum WiFiSort: String, CaseIterable, Identifiable {
    case signal, name, channel
    var id: String { rawValue }

    var title: String {
        switch self {
        case .signal: return String(localized: "Signal")
        case .name: return String(localized: "Name")
        case .channel: return String(localized: "Channel")
        }
    }
}

/// State of the Wi-Fi tab: the latest scan of nearby networks and the Mac's own connection.
@MainActor
@Observable
final class WiFiSession {
    enum Status: Equatable {
        case ready
        case noInterface
        case poweredOff
        case failed(String)
    }

    private(set) var networks: [WiFiNetwork] = []
    private(set) var connection: WiFiConnection?
    private(set) var interfaceName: String?
    private(set) var isScanning = false
    private(set) var status: Status = .ready
    private(set) var lastScanDate: Date?
    /// Created on the first scan, so the app never touches Location before the Wi-Fi tab is used.
    private(set) var location: LocationAccess?

    /// Filters the list; nil shows every band.
    var band: WiFiBand?
    var chartBand: WiFiBand = .ghz5
    var sort: WiFiSort = .signal
    /// Rescans every `rescanInterval` while the Wi-Fi tab is showing.
    var keepsScanning = false
    let rescanInterval: Duration = .seconds(20)

    /// Showing made-up networks (`--demo`): no scan, no Location prompt.
    @ObservationIgnored private var isSample = false
    /// Location access arrived mid-scan; scan again for the details that scan couldn't see.
    @ObservationIgnored private var rescanWhenDone = false

    /// True when macOS is withholding BSSIDs and the connected network's name.
    var detailsHidden: Bool { !isSample && location?.state != .granted }

    var visibleNetworks: [WiFiNetwork] {
        let filtered = networks.filter { band == nil || $0.channel?.band == band }
        switch sort {
        case .signal:
            return filtered
        case .name:
            return filtered.sorted { a, b in
                // Hidden networks go last.
                switch (a.ssid, b.ssid) {
                case let (x?, y?) where x != y: return x.localizedStandardCompare(y) == .orderedAscending
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.rssi > b.rssi
                }
            }
        case .channel:
            return filtered.sorted { ($0.channel?.number ?? 0, -$0.rssi) < ($1.channel?.number ?? 0, -$1.rssi) }
        }
    }

    /// Bands at least one network was heard on, for the chart's picker.
    var bandsHeard: [WiFiBand] {
        Array(Set(networks.compactMap(\.channel?.band))).sorted()
    }

    func networks(on band: WiFiBand) -> [WiFiNetwork] {
        networks.filter { $0.channel?.band == band }
    }

    func scan() async {
        guard !isSample, !isScanning else { return }
        if location == nil {
            let access = LocationAccess()
            // The permission prompt usually appears during the first scan, and is answered before it ends.
            access.onGranted = { [weak self] in
                guard let self else { return }
                if self.isScanning { self.rescanWhenDone = true } else { Task { await self.scan() } }
            }
            location = access
        }
        if location?.state == .notDetermined { location?.request() }

        isScanning = true
        let result = await Task.detached(priority: .userInitiated) { WiFiScanner.scan() }.value
        isScanning = false
        lastScanDate = Date()

        switch result {
        case .success(let scan):
            status = .ready
            let firstScan = networks.isEmpty
            networks = scan.networks
            connection = scan.connection
            interfaceName = scan.interfaceName
            if firstScan || !bandsHeard.contains(chartBand) { chartBand = preferredChartBand }
        case .failure(.failed(let message)):
            // Keep the last results on screen; the next scan may well work.
            status = .failed(message)
        case .failure(let failure):
            status = failure == .noInterface ? .noInterface : .poweredOff
            networks = []
            connection = nil
        }

        if rescanWhenDone {
            rescanWhenDone = false
            await scan()
        }
    }

    func requestLocationAccess() {
        location?.request()
    }

    /// The band the Mac is connected on, else the busiest one.
    private var preferredChartBand: WiFiBand {
        if let band = connection?.channel?.band { return band }
        let counts = Dictionary(grouping: networks.compactMap(\.channel?.band)) { $0 }.mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? .ghz5
    }

    /// Fills the tab with made-up networks for screenshots.
    func showSample(_ sample: [WiFiNetwork], connection: WiFiConnection?, interfaceName: String) {
        isSample = true
        networks = sample.sorted { $0.rssi > $1.rssi }
        self.connection = connection
        self.interfaceName = interfaceName
        lastScanDate = Date().addingTimeInterval(-40)
        chartBand = preferredChartBand
    }
}
