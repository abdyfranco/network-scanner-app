//
//  WiFiScanner.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import CoreWLAN
import Foundation

/// Scans for nearby Wi-Fi networks with the Mac's own Wi-Fi card, through CoreWLAN.
///
/// macOS hides BSSIDs, and the name of the network the Mac is on, from apps without Location access.
/// Everything else (names of nearby networks, channels, signal, security) comes through regardless.
enum WiFiScanner {
    enum Failure: Error, Equatable, Sendable {
        case noInterface
        case poweredOff
        case failed(String)
    }

    struct Scan: Sendable {
        var interfaceName: String?
        var networks: [WiFiNetwork]
        var connection: WiFiConnection?
    }

    /// Blocks for a few seconds while the radio listens on every channel, so call it off the main thread.
    static func scan() -> Result<Scan, Failure> {
        guard let interface = CWWiFiClient.shared().interface() else { return .failure(.noInterface) }
        guard interface.powerOn() else { return .failure(.poweredOff) }

        let found: Set<CWNetwork>
        do {
            found = try interface.scanForNetworks(withName: nil, includeHidden: true)
        } catch {
            // The radio can be busy, or macOS throttles scans that come too often. The system's
            // most recent results are still worth showing.
            guard let cached = interface.cachedScanResults(), !cached.isEmpty else {
                return .failure(.failed(error.localizedDescription))
            }
            found = cached
        }

        let connection = WiFiConnection(interface)
        var networks = found.map(WiFiNetwork.init)
            .sorted { $0.rssi != $1.rssi ? $0.rssi > $1.rssi : ($0.ssid ?? "") < ($1.ssid ?? "") }
        for index in networks.indices {
            // Only a BSSID identifies the access point the Mac is on: a mesh repeats one name on many.
            if let bssid = networks[index].bssid, bssid == connection?.bssid { networks[index].isConnected = true }
            if networks[index].bssid == nil {
                // Without a BSSID, give each row an identity of its own for this scan.
                networks[index].id = "\(networks[index].ssid ?? "")#\(networks[index].channel?.number ?? 0)#\(index)"
            }
        }
        return .success(Scan(interfaceName: interface.interfaceName, networks: networks, connection: connection))
    }
}

// MARK: - Values

enum WiFiBand: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case ghz2 = 1, ghz5, ghz6

    var id: Int { rawValue }

    init?(_ band: CWChannelBand) {
        switch band {
        case .band2GHz: self = .ghz2
        case .band5GHz: self = .ghz5
        case .band6GHz: self = .ghz6
        default: return nil
        }
    }

    /// "2.4 GHz", with the decimal separator of the user's language.
    var title: String {
        switch self {
        case .ghz2: return "\(2.4.formatted(.number.precision(.fractionLength(1)))) GHz"
        case .ghz5: return "5 GHz"
        case .ghz6: return "6 GHz"
        }
    }

    /// Channel numbers shown on the chart's axis, and the range it covers.
    var chartTicks: [Int] {
        switch self {
        case .ghz2: return [1, 3, 5, 7, 9, 11, 13]
        case .ghz5: return [36, 52, 64, 100, 116, 132, 149, 165]
        case .ghz6: return [1, 33, 65, 97, 129, 161, 193, 225]
        }
    }

    var chartDomain: ClosedRange<Double> {
        switch self {
        case .ghz2: return -1...16
        case .ghz5: return 30...171
        case .ghz6: return -5...237
        }
    }

    static func < (a: WiFiBand, b: WiFiBand) -> Bool { a.rawValue < b.rawValue }
}

struct WiFiChannel: Sendable, Hashable {
    var number: Int
    var band: WiFiBand?
    /// In MHz, when known.
    var width: Int?

    init(number: Int, band: WiFiBand?, width: Int?) {
        self.number = number
        self.band = band
        self.width = width
    }

    init(_ channel: CWChannel) {
        number = channel.channelNumber
        band = WiFiBand(channel.channelBand)
        switch channel.channelWidth {
        case .width20MHz: width = 20
        case .width40MHz: width = 40
        case .width80MHz: width = 80
        case .width160MHz: width = 160
        default: width = nil
        }
    }

    /// e.g. "108 · 5 GHz · 40 MHz".
    var summary: String {
        [String(number), band?.title, width.map { "\($0) MHz" }].compactMap { $0 }.joined(separator: " · ")
    }

    /// Where the signal sits, in channel numbers (5 MHz apart): its center and half its width.
    /// The reported channel is the primary 20 MHz one; a wider channel spans the aligned block
    /// of 20 MHz channels around it.
    var span: (center: Double, halfWidth: Double) {
        let width = self.width ?? 20
        let units = width / 5
        switch band {
        case .ghz2?:
            // 40 MHz in 2.4 GHz extends up from low channels and down from high ones.
            let center = width >= 40 ? number + (number <= 7 ? 2 : -2) : number
            return (Double(center), Double(width) / 10)
        case .ghz5?, .ghz6?:
            let base = band == .ghz6 ? 1 : (number >= 149 ? 149 : 36)
            let start = number >= base ? base + (number - base) / units * units : number
            return (Double(start) + Double(units) / 2 - 2, Double(units) / 2)
        case nil:
            return (Double(number), 2)
        }
    }
}

enum WiFiSecurity: Sendable, Hashable {
    case open, enhancedOpen, wep, dynamicWEP
    case personal(String)
    case enterprise(String)

    /// From what a nearby network advertises, strongest first.
    init(_ network: CWNetwork) {
        if network.supportsSecurity(.wpa3Enterprise) { self = .enterprise("WPA3") }
        else if network.supportsSecurity(.wpa2Enterprise) {
            self = .enterprise(network.supportsSecurity(.wpaEnterprise) ? "WPA/WPA2" : "WPA2")
        }
        else if network.supportsSecurity(.wpaEnterprise) { self = .enterprise("WPA") }
        else if network.supportsSecurity(.wpa3Transition) { self = .personal("WPA2/WPA3") }
        else if network.supportsSecurity(.wpa3Personal) { self = .personal("WPA3") }
        else if network.supportsSecurity(.wpa2Personal) {
            self = .personal(network.supportsSecurity(.wpaPersonal) ? "WPA/WPA2" : "WPA2")
        }
        else if network.supportsSecurity(.wpaPersonal) { self = .personal("WPA") }
        else if network.supportsSecurity(.dynamicWEP) { self = .dynamicWEP }
        else if network.supportsSecurity(.WEP) { self = .wep }
        else if network.supportsSecurity(.OWE) || network.supportsSecurity(.oweTransition) { self = .enhancedOpen }
        else { self = .open }
    }

    /// From what the Mac's current connection uses.
    init?(_ security: CWSecurity) {
        switch security {
        case .none: self = .open
        case .WEP: self = .wep
        case .dynamicWEP: self = .dynamicWEP
        case .wpaPersonal: self = .personal("WPA")
        case .wpaPersonalMixed: self = .personal("WPA/WPA2")
        case .wpa2Personal, .personal: self = .personal("WPA2")
        case .wpa3Personal: self = .personal("WPA3")
        case .wpa3Transition: self = .personal("WPA2/WPA3")
        case .wpaEnterprise: self = .enterprise("WPA")
        case .wpaEnterpriseMixed: self = .enterprise("WPA/WPA2")
        case .wpa2Enterprise, .enterprise: self = .enterprise("WPA2")
        case .wpa3Enterprise: self = .enterprise("WPA3")
        case .OWE, .oweTransition: self = .enhancedOpen
        default: return nil
        }
    }

    var isSecured: Bool { self != .open && self != .enhancedOpen }

    /// Named as in macOS's Wi-Fi settings, e.g. "WPA2/WPA3 Personal".
    var title: String {
        switch self {
        case .open: return String(localized: "Open")
        case .enhancedOpen: return "Enhanced Open"
        case .wep: return "WEP"
        case .dynamicWEP: return String(localized: "Dynamic WEP")
        case .personal(let version): return String(localized: "\(version) Personal")
        case .enterprise(let version): return String(localized: "\(version) Enterprise")
        }
    }
}

/// The Wi-Fi generation, from the newest 802.11 mode a network supports.
enum WiFiStandard: Int, Sendable, Comparable {
    case b = 1, a, g, wifi4, wifi5, wifi6, wifi6E, wifi7

    init?(_ mode: CWPHYMode, band: WiFiBand?) {
        switch mode {
        case .mode11b: self = .b
        case .mode11a: self = .a
        case .mode11g: self = .g
        case .mode11n: self = .wifi4
        case .mode11ac: self = .wifi5
        case .mode11ax: self = band == .ghz6 ? .wifi6E : .wifi6
        case .mode11be: self = .wifi7
        default: return nil
        }
    }

    init?(_ network: CWNetwork, band: WiFiBand?) {
        let modes: [CWPHYMode] = [.mode11be, .mode11ax, .mode11ac, .mode11n, .mode11g, .mode11a, .mode11b]
        guard let best = modes.first(where: network.supportsPHYMode) else { return nil }
        self.init(best, band: band)
    }

    /// Trademarks and standard names, the same in every language.
    var title: String {
        switch self {
        case .b: return "802.11b"
        case .a: return "802.11a"
        case .g: return "802.11g"
        case .wifi4: return "Wi-Fi 4"
        case .wifi5: return "Wi-Fi 5"
        case .wifi6: return "Wi-Fi 6"
        case .wifi6E: return "Wi-Fi 6E"
        case .wifi7: return "Wi-Fi 7"
        }
    }

    static func < (a: WiFiStandard, b: WiFiStandard) -> Bool { a.rawValue < b.rawValue }
}

/// One access point (BSSID) heard in a scan.
struct WiFiNetwork: Identifiable, Sendable, Hashable {
    var id: String
    var ssid: String?
    var bssid: MACAddress?
    var vendor: String?
    var channel: WiFiChannel?
    /// dBm.
    var rssi: Int
    var noise: Int
    var security: WiFiSecurity
    var standard: WiFiStandard?
    var countryCode: String?
    var isConnected = false

    init(id: String, ssid: String?, bssid: MACAddress?, vendor: String? = nil, channel: WiFiChannel?, rssi: Int, noise: Int,
         security: WiFiSecurity, standard: WiFiStandard?, countryCode: String? = nil, isConnected: Bool = false) {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        self.vendor = vendor
        self.channel = channel
        self.rssi = rssi
        self.noise = noise
        self.security = security
        self.standard = standard
        self.countryCode = countryCode
        self.isConnected = isConnected
    }

    init(_ network: CWNetwork) {
        let bssid = network.bssid.flatMap(MACAddress.init)
        let channel = network.wlanChannel.map(WiFiChannel.init)
        self.init(id: bssid?.description ?? UUID().uuidString,
                  ssid: network.ssid.flatMap { $0.isEmpty ? nil : $0 },
                  bssid: bssid,
                  // Access points often use locally administered BSSIDs, which carry no maker.
                  vendor: bssid.flatMap { $0.isLocallyAdministered ? nil : OUIDatabase.shared.vendor(for: $0) },
                  channel: channel,
                  rssi: network.rssiValue,
                  noise: network.noiseMeasurement,
                  security: WiFiSecurity(network),
                  standard: WiFiStandard(network, band: channel?.band),
                  countryCode: network.countryCode)
    }

    var isHidden: Bool { ssid == nil }

    var displayName: String { ssid ?? String(localized: "Hidden Network") }

    /// 0…1 for signal bars: -90 dBm and weaker is nothing, -50 dBm and stronger is full.
    var signalLevel: Double { min(1, max(0, Double(rssi + 90) / 40)) }
}

/// The network the Mac's Wi-Fi is on right now.
struct WiFiConnection: Sendable, Hashable {
    var interfaceName: String?
    var hardwareAddress: MACAddress?
    var ssid: String?
    var bssid: MACAddress?
    var channel: WiFiChannel?
    var rssi: Int
    var noise: Int
    /// Mbps.
    var transmitRate: Double
    var standard: WiFiStandard?
    var security: WiFiSecurity?
    var countryCode: String?

    init(interfaceName: String?, hardwareAddress: MACAddress?, ssid: String?, bssid: MACAddress?, channel: WiFiChannel?, rssi: Int,
         noise: Int, transmitRate: Double, standard: WiFiStandard?, security: WiFiSecurity?, countryCode: String?) {
        self.interfaceName = interfaceName
        self.hardwareAddress = hardwareAddress
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.rssi = rssi
        self.noise = noise
        self.transmitRate = transmitRate
        self.standard = standard
        self.security = security
        self.countryCode = countryCode
    }

    /// Nil when the interface isn't joined to a network.
    init?(_ interface: CWInterface) {
        guard let channel = interface.wlanChannel(), interface.rssiValue() != 0 else { return nil }
        let wlanChannel = WiFiChannel(channel)
        self.init(interfaceName: interface.interfaceName,
                  hardwareAddress: interface.hardwareAddress().flatMap(MACAddress.init),
                  ssid: interface.ssid().flatMap { $0.isEmpty ? nil : $0 },
                  bssid: interface.bssid().flatMap(MACAddress.init),
                  channel: wlanChannel,
                  rssi: interface.rssiValue(),
                  noise: interface.noiseMeasurement(),
                  transmitRate: interface.transmitRate(),
                  standard: WiFiStandard(interface.activePHYMode(), band: wlanChannel.band),
                  security: WiFiSecurity(interface.security()),
                  countryCode: interface.countryCode())
    }

    /// Signal-to-noise ratio in dB, when the card reports noise.
    var snr: Int? { noise < 0 ? rssi - noise : nil }
}
