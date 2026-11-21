//
//  Device.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

enum DiscoverySource: String, CaseIterable, Codable, Sendable {
    case local = "This Mac"
    case icmp = "ICMP"
    case tcp = "TCP"
    case arp = "ARP"
    case ndp = "NDP"
    case mdns = "Bonjour"
    case netbios = "NetBIOS"
    case ubiquiti = "UniFi"

    /// Shown in the UI; the raw value is what gets stored.
    var title: String {
        self == .local ? String(localized: "This Mac") : rawValue
    }
}

struct Device: Identifiable, Equatable {
    let id = UUID()
    var ipv4: [IPv4Address] = []
    var ipv6: [IPv6Address] = []
    var mac: MACAddress?
    var extraMACs: Set<MACAddress> = []
    var vendor: String?

    var dnsName: String?
    var mdnsName: String?
    var netbiosName: String?
    var workgroup: String?
    var services: [BonjourService] = []
    var ubiquiti: UbiquitiInfo?
    var openPorts: Set<UInt16> = []

    var kind: DeviceKind = .unknown
    var modelName: String?
    var modelIdentifier: String?

    var latency: TimeInterval?
    var sources: Set<DiscoverySource> = []
    var isSelf = false
    var isGateway = false
    var isOnline = true
    var firstSeen = Date()
    var lastSeen = Date()

    /// Wake-on-LAN needs the device's MAC, and the Mac running the scan can't wake itself.
    var canWake: Bool {
        guard kind.supportsWakeOnLAN, !isSelf, let mac else { return false }
        return !mac.isMulticast && !mac.isZero
    }

    var addresses: [IPAddress] { ipv4.map(IPAddress.v4) + ipv6.map(IPAddress.v6) }
    var primaryAddress: IPAddress? { ipv4.first.map(IPAddress.v4) ?? ipv6.first.map(IPAddress.v6) }
    var primaryAddressText: String { primaryAddress?.description ?? "—" }
    var hasPrivateMAC: Bool { mac?.isLocallyAdministered ?? false }

    /// The best hostname found, in order of how authoritative it is for the device itself.
    var hostname: String? {
        mdnsName ?? dnsName ?? netbiosName ?? ubiquiti?.hostname ?? services.first(where: { !$0.host.isEmpty })?.host
    }

    /// A friendly name advertised over Bonjour, e.g. "Living Room" or "Abdy's MacBook Pro".
    var bonjourName: String? {
        let preference = ["_device-info._tcp", "_companion-link._tcp", "_airplay._tcp", "_raop._tcp", "_googlecast._tcp",
                          "_ipp._tcp", "_hap._tcp", "_smb._tcp", "_spotify-connect._tcp", "_sonos._tcp", "_http._tcp"]
        for type in preference {
            guard let service = services.first(where: { $0.type == type }) else { continue }
            if type == "_googlecast._tcp", let friendly = service.txt["fn"], !friendly.isEmpty { return friendly }
            var name = service.name
            if type == "_raop._tcp", let at = name.firstIndex(of: "@") { name = String(name[name.index(after: at)...]) }
            if !name.isEmpty { return name }
        }
        return services.first { Self.isFriendly($0.name) }?.name
    }

    /// Filters out instance names that are really identifiers (MACs, UUIDs, hex blobs).
    static func isFriendly(_ name: String) -> Bool {
        guard !name.isEmpty, name.count < 64, !name.contains("@") else { return false }
        let hexish = name.filter { $0.isHexDigit || $0 == "-" || $0 == ":" }
        return Double(hexish.count) / Double(name.count) < 0.8
    }

    var displayName: String {
        if let hostname {
            let short = HostnameResolver.shortName(hostname)
            if !Self.isFriendly(short), let bonjourName { return bonjourName }
            return short
        }
        if let bonjourName { return bonjourName }
        if let product = ubiquiti?.productName ?? modelName { return product }
        return primaryAddressText
    }

    var vendorText: String {
        if let vendor { return vendor }
        if hasPrivateMAC { return String(localized: "Private address") }
        if mac == nil { return isSelf ? "Apple" : String(localized: "No MAC · remote subnet") }
        return String(localized: "Unknown vendor")
    }

    var subtitle: String {
        if let modelName, modelName.caseInsensitiveCompare(kind.title) != .orderedSame { return "\(kind.title) · \(modelName)" }
        return kind.title
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = [displayName, hostname ?? "", bonjourName ?? "", vendor ?? "", mac?.description ?? "",
                        modelName ?? "", kind.title, netbiosName ?? ""] + addresses.map(\.description)
        return haystack.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
