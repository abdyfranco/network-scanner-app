//
//  NetworkInterfaces.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin
import SystemConfiguration

struct IPv4Assignment: Hashable, Sendable {
    let address: IPv4Address
    let prefixLength: Int

    var network: IPv4Address { IPv4Address(address.value & IPv4Address.mask(prefixLength: prefixLength)) }
    var broadcast: IPv4Address { IPv4Address(network.value | ~IPv4Address.mask(prefixLength: prefixLength)) }
    var cidr: String { "\(network)/\(prefixLength)" }

    func contains(_ a: IPv4Address) -> Bool {
        a.value & IPv4Address.mask(prefixLength: prefixLength) == network.value
    }
}

struct IPv6Assignment: Hashable, Sendable {
    let address: IPv6Address
    let prefixLength: Int
    var prefix: IPv6Prefix { IPv6Prefix(address, length: prefixLength) }
}

struct NetworkInterface: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case wifi, ethernet, other }

    var id: String { name }
    let name: String
    let index: UInt32
    var displayName: String
    var kind: Kind = .other
    var mac: MACAddress?
    var ipv4: [IPv4Assignment] = []
    var ipv6: [IPv6Assignment] = []

    var symbol: String {
        switch kind {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .other: return "network"
        }
    }

    var primaryIPv4: IPv4Assignment? { ipv4.first { !$0.address.isLinkLocal } ?? ipv4.first }

    /// The subnet to suggest as a scan target. Very large subnets are narrowed to the local /24.
    var suggestedTarget: String? {
        guard let a = primaryIPv4 else {
            return ipv6.isEmpty ? nil : "fe80::%\(name)/64"
        }
        if a.prefixLength >= 22 { return a.cidr }
        let narrowed = IPv4Assignment(address: a.address, prefixLength: 24)
        return narrowed.cidr
    }

    /// IPv6 prefixes reachable on this link: link-local plus any global / ULA prefixes.
    var ipv6DiscoveryPrefixes: [IPv6Prefix] {
        var prefixes = [IPv6Prefix(IPv6Address(high: 0xFE80_0000_0000_0000, low: 0, scopeID: index), length: 64)]
        for assignment in ipv6 where !assignment.address.isLinkLocal {
            let p = assignment.prefix
            if !prefixes.contains(p) { prefixes.append(p) }
        }
        return prefixes
    }
}

enum InterfaceInventory {
    private static let ignoredPrefixes = ["lo", "awdl", "llw", "anpi", "ap", "gif", "stf", "utun", "ipsec", "pktap", "vmenet", "XHC"]

    static func current() -> [NetworkInterface] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }

        var interfaces: [String: NetworkInterface] = [:]
        var macs: [String: MACAddress] = [:]

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(cString: entry.ifa_name)
            guard let sa = entry.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)

            if family == AF_LINK {
                if let mac = linkAddress(sa) { macs[name] = mac }
                continue
            }

            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard !ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            var iface = interfaces[name] ?? NetworkInterface(name: name, index: if_nametoindex(name), displayName: name)
            switch family {
            case AF_INET:
                let addr = UnsafeRawPointer(sa).loadUnaligned(as: sockaddr_in.self)
                let prefix = entry.ifa_netmask.map { prefixLength(v4Mask: $0) } ?? 24
                iface.ipv4.append(IPv4Assignment(address: IPv4Address(addr.sin_addr), prefixLength: prefix))
            case AF_INET6:
                let addr = UnsafeRawPointer(sa).loadUnaligned(as: sockaddr_in6.self)
                var address = IPv6Address(addr.sin6_addr, scopeID: addr.sin6_scope_id)
                if address.isLinkLocal { address.scopeID = iface.index }
                let prefix = entry.ifa_netmask.map { prefixLength(v6Mask: $0) } ?? 64
                iface.ipv6.append(IPv6Assignment(address: address, prefixLength: prefix))
            default:
                continue
            }
            interfaces[name] = iface
        }

        var details: [String: (String, NetworkInterface.Kind)] = [:]
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for sc in all {
                guard let bsd = SCNetworkInterfaceGetBSDName(sc) as String? else { continue }
                let display = (SCNetworkInterfaceGetLocalizedDisplayName(sc) as String?) ?? bsd
                let type = SCNetworkInterfaceGetInterfaceType(sc) as String?
                let kind: NetworkInterface.Kind
                if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                    kind = .wifi
                } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
                    kind = .ethernet
                } else {
                    kind = .other
                }
                details[bsd] = (display, kind)
            }
        }

        let result = interfaces.values
            .filter { !$0.ipv4.isEmpty || $0.ipv6.contains { !$0.address.isLinkLocal } }
            .map { iface -> NetworkInterface in
                var i = iface
                i.mac = macs[i.name]
                if let (display, kind) = details[i.name] {
                    i.displayName = display
                    i.kind = kind
                } else if i.name.hasPrefix("bridge") {
                    i.displayName = String(localized: "Bridge")
                }
                i.ipv4.sort { $0.address < $1.address }
                i.ipv6.sort { IPAddress.v6($0.address) < IPAddress.v6($1.address) }
                return i
            }

        return result.sorted { a, b in
            let aHas = a.primaryIPv4 != nil, bHas = b.primaryIPv4 != nil
            if aHas != bHas { return aHas }
            return a.index < b.index
        }
    }

    private static func linkAddress(_ sa: UnsafeMutablePointer<sockaddr>) -> MACAddress? {
        let raw = UnsafeRawPointer(sa)
        let nameLength = Int(raw.load(fromByteOffset: 5, as: UInt8.self))
        let addressLength = Int(raw.load(fromByteOffset: 6, as: UInt8.self))
        guard addressLength == 6 else { return nil }
        let bytes = UnsafeRawBufferPointer(start: raw.advanced(by: 8 + nameLength), count: 6)
        guard let mac = MACAddress(bytes: bytes), mac.isUsable else { return nil }
        return mac
    }

    private static func prefixLength(v4Mask sa: UnsafeMutablePointer<sockaddr>) -> Int {
        let raw = UnsafeRawPointer(sa)
        let length = Int(sa.pointee.sa_len)
        var bits = 0
        for offset in 4..<8 where offset < max(length, 8) {
            bits += Int(raw.load(fromByteOffset: offset, as: UInt8.self).nonzeroBitCount)
        }
        return bits
    }

    private static func prefixLength(v6Mask sa: UnsafeMutablePointer<sockaddr>) -> Int {
        let raw = UnsafeRawPointer(sa)
        let length = Int(sa.pointee.sa_len)
        var bits = 0
        for offset in 8..<24 where offset < length {
            bits += Int(raw.load(fromByteOffset: offset, as: UInt8.self).nonzeroBitCount)
        }
        return bits == 0 ? 64 : bits
    }
}

enum LocalHost {
    /// e.g. "Mac16,1" or "MacBookPro18,3".
    static var hardwareModel: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static var computerName: String? {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
    }

    static var localHostName: String? {
        (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
    }
}
