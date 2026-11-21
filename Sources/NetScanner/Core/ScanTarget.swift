//
//  ScanTarget.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

struct IPv6Prefix: Hashable, Sendable, CustomStringConvertible {
    let address: IPv6Address
    let length: Int

    init(_ address: IPv6Address, length: Int) {
        self.address = address.masked(prefixLength: length)
        self.length = length
    }

    func contains(_ candidate: IPv6Address) -> Bool {
        guard candidate.masked(prefixLength: length) == address else { return false }
        if address.isLinkLocal, address.scopeID != 0, candidate.scopeID != 0 {
            return address.scopeID == candidate.scopeID
        }
        return true
    }

    var description: String { "\(address.scopedDescription)/\(length)" }
}

enum TargetError: LocalizedError {
    case empty
    case invalid(String)
    case tooLarge(String, Int)

    var errorDescription: String? {
        switch self {
        case .empty: return String(localized: "Enter a subnet, range or address to scan.")
        case .invalid(let token): return String(localized: "“\(token)” is not a valid address, CIDR block or range.")
        case .tooLarge(let token, let count):
            return String(localized: "“\(token)” expands to \(count) addresses. The limit is \(ScanTarget.maxIPv4) IPv4 or \(ScanTarget.maxIPv6Enumerated) IPv6 addresses.")
        }
    }
}

/// The set of addresses a scan covers.
///
/// Accepted syntax (comma, space or newline separated):
/// `192.168.1.0/24`, `10.0.0.1-10.0.0.50`, `10.0.0.1-50`, `192.168.1.7`,
/// `fe80::/64` (discovered via multicast), `2001:db8::/120`, `2001:db8::1-2001:db8::ff`.
struct ScanTarget: Sendable {
    static let maxIPv4 = 65_536
    static let maxIPv6Enumerated = 4_096

    private(set) var ipv4: [IPv4Address] = []
    private(set) var ipv6: [IPv6Address] = []
    private(set) var ipv6Prefixes: [IPv6Prefix] = []
    private var ipv4Set: Set<IPv4Address> = []
    private var ipv6Set: Set<IPv6Address> = []

    var isEmpty: Bool { ipv4.isEmpty && ipv6.isEmpty && ipv6Prefixes.isEmpty }

    func contains(_ ip: IPAddress) -> Bool {
        switch ip {
        case .v4(let a): return ipv4Set.contains(a)
        case .v6(let a): return ipv6Set.contains(a) || ipv6Prefixes.contains { $0.contains(a) }
        }
    }

    mutating func addIPv6Prefix(_ prefix: IPv6Prefix) {
        if !ipv6Prefixes.contains(where: { $0 == prefix && $0.address.scopeID == prefix.address.scopeID }) {
            ipv6Prefixes.append(prefix)
        }
    }

    var summary: String {
        var parts: [String] = []
        if !ipv4.isEmpty { parts.append(String(localized: "\(ipv4.count) IPv4 hosts")) }
        if !ipv6.isEmpty { parts.append(String(localized: "\(ipv6.count) IPv6 hosts")) }
        if !ipv6Prefixes.isEmpty { parts.append(String(localized: "\(ipv6Prefixes.count) IPv6 prefixes (multicast discovery)")) }
        return parts.joined(separator: " · ")
    }

    static func parse(_ text: String) throws -> ScanTarget {
        var target = ScanTarget()
        var v4: [IPv4Address] = []
        var v6: [IPv6Address] = []

        let tokens = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { throw TargetError.empty }

        for token in tokens {
            if let slash = token.firstIndex(of: "/") {
                let addressPart = String(token[..<slash])
                guard let length = Int(token[token.index(after: slash)...]) else { throw TargetError.invalid(token) }

                if let base = IPv4Address(addressPart), (0...32).contains(length) {
                    let network = base.value & IPv4Address.mask(prefixLength: length)
                    let size = UInt64(1) << UInt64(32 - length)
                    guard size <= UInt64(maxIPv4) else { throw TargetError.tooLarge(token, Int(size)) }
                    if length >= 31 {
                        for i in 0..<size { v4.append(IPv4Address(network &+ UInt32(i))) }
                    } else {
                        for i in 1..<(size - 1) { v4.append(IPv4Address(network &+ UInt32(i))) }
                    }
                } else if let base = IPv6Address(addressPart), (0...128).contains(length) {
                    let hostBits = 128 - length
                    if hostBits <= 12 {
                        let network = base.masked(prefixLength: length)
                        let count = UInt64(1) << UInt64(hostBits)
                        let start: UInt64 = count > 2 ? 1 : 0
                        for i in start..<count { v6.append(network.adding(i)) }
                    } else {
                        target.addIPv6Prefix(IPv6Prefix(base, length: length))
                    }
                } else {
                    throw TargetError.invalid(token)
                }
            } else if token.contains("-") {
                let parts = token.split(separator: "-", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { throw TargetError.invalid(token) }

                if let start = IPv4Address(parts[0]) {
                    let end: IPv4Address
                    if let e = IPv4Address(parts[1]) {
                        end = e
                    } else if let last = UInt8(parts[1]) {
                        end = IPv4Address((start.value & 0xFFFF_FF00) | UInt32(last))
                    } else {
                        throw TargetError.invalid(token)
                    }
                    guard end >= start else { throw TargetError.invalid(token) }
                    let count = Int(end.value - start.value) + 1
                    guard count <= maxIPv4 else { throw TargetError.tooLarge(token, count) }
                    for value in start.value...end.value { v4.append(IPv4Address(value)) }
                } else if let start = IPv6Address(parts[0]) {
                    let end: IPv6Address
                    if let e = IPv6Address(parts[1]) {
                        end = e
                    } else if let last = UInt16(parts[1], radix: 16) {
                        end = IPv6Address(high: start.high, low: (start.low & ~UInt64(0xFFFF)) | UInt64(last), scopeID: start.scopeID)
                    } else {
                        throw TargetError.invalid(token)
                    }
                    guard end.high == start.high, end.low >= start.low else { throw TargetError.invalid(token) }
                    let span = end.low - start.low
                    guard span < UInt64(maxIPv6Enumerated) else { throw TargetError.tooLarge(token, Int(clamping: span + 1)) }
                    for i in 0...span { v6.append(start.adding(i)) }
                } else {
                    throw TargetError.invalid(token)
                }
            } else if let a = IPv4Address(token) {
                v4.append(a)
            } else if let a = IPv6Address(token) {
                v6.append(a)
            } else {
                throw TargetError.invalid(token)
            }
        }

        var seen4 = Set<IPv4Address>()
        target.ipv4 = v4.filter { seen4.insert($0).inserted }.sorted()
        guard target.ipv4.count <= maxIPv4 else { throw TargetError.tooLarge(text, target.ipv4.count) }
        var seen6 = Set<IPv6Address>()
        target.ipv6 = v6.filter { seen6.insert($0).inserted }.sorted()
        guard target.ipv6.count <= maxIPv6Enumerated else { throw TargetError.tooLarge(text, target.ipv6.count) }
        target.ipv4Set = seen4
        target.ipv6Set = seen6
        return target
    }
}
