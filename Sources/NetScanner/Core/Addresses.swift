//
//  Addresses.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

// MARK: - IPv4

struct IPv4Address: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Address in host byte order.
    let value: UInt32

    init(_ value: UInt32) { self.value = value }

    init?(_ string: String) {
        var addr = in_addr()
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inet_pton(AF_INET, trimmed, &addr) == 1 else { return nil }
        self.value = UInt32(bigEndian: addr.s_addr)
    }

    init(_ addr: in_addr) { self.value = UInt32(bigEndian: addr.s_addr) }

    var inAddr: in_addr { in_addr(s_addr: value.bigEndian) }

    var description: String {
        "\(value >> 24).\((value >> 16) & 0xFF).\((value >> 8) & 0xFF).\(value & 0xFF)"
    }

    static func < (lhs: IPv4Address, rhs: IPv4Address) -> Bool { lhs.value < rhs.value }

    var isLinkLocal: Bool { value & 0xFFFF_0000 == 0xA9FE_0000 }
    var isMulticast: Bool { value & 0xF000_0000 == 0xE000_0000 }
    var isLoopback: Bool { value >> 24 == 127 }
    var isBroadcast: Bool { value == .max }

    var reversePointerName: String {
        "\(value & 0xFF).\((value >> 8) & 0xFF).\((value >> 16) & 0xFF).\(value >> 24).in-addr.arpa."
    }

    func socketAddress(port: UInt16 = 0) -> sockaddr_in {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = port.bigEndian
        sa.sin_addr = inAddr
        return sa
    }

    static func mask(prefixLength: Int) -> UInt32 {
        prefixLength <= 0 ? 0 : (prefixLength >= 32 ? .max : UInt32.max << UInt32(32 - prefixLength))
    }
}

// MARK: - IPv6

struct IPv6Address: Hashable, Comparable, Sendable, CustomStringConvertible {
    let high: UInt64
    let low: UInt64
    /// Interface scope for link-local addresses. Not part of equality.
    var scopeID: UInt32

    init(high: UInt64, low: UInt64, scopeID: UInt32 = 0) {
        self.high = high
        self.low = low
        self.scopeID = scopeID
    }

    init<C: Collection>(bytes: C, scopeID: UInt32 = 0) where C.Element == UInt8 {
        var h: UInt64 = 0, l: UInt64 = 0
        for (i, b) in bytes.prefix(16).enumerated() {
            if i < 8 { h = h << 8 | UInt64(b) } else { l = l << 8 | UInt64(b) }
        }
        self.init(high: h, low: l, scopeID: scopeID)
    }

    init(_ addr: in6_addr, scopeID: UInt32 = 0) {
        var bytes = withUnsafeBytes(of: addr) { Array($0) }
        var scope = scopeID
        // The BSD stack embeds the scope in bytes 2-3 of link-local addresses (KAME style).
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
            let embedded = UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            if scope == 0 { scope = embedded }
            bytes[2] = 0
            bytes[3] = 0
        }
        self.init(bytes: bytes, scopeID: scope)
    }

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        var scope: UInt32 = 0
        if let pct = s.firstIndex(of: "%") {
            let name = String(s[s.index(after: pct)...])
            scope = UInt32(name) ?? if_nametoindex(name)
            s = String(s[..<pct])
        }
        guard s.contains(":") else { return nil }
        var addr = in6_addr()
        guard inet_pton(AF_INET6, s, &addr) == 1 else { return nil }
        self.init(addr, scopeID: scope)
    }

    static func == (lhs: IPv6Address, rhs: IPv6Address) -> Bool { lhs.high == rhs.high && lhs.low == rhs.low }
    func hash(into hasher: inout Hasher) { hasher.combine(high); hasher.combine(low) }
    static func < (lhs: IPv6Address, rhs: IPv6Address) -> Bool { (lhs.high, lhs.low) < (rhs.high, rhs.low) }

    var bytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            out[i] = UInt8(truncatingIfNeeded: high >> UInt64(56 - 8 * i))
            out[i + 8] = UInt8(truncatingIfNeeded: low >> UInt64(56 - 8 * i))
        }
        return out
    }

    var in6Addr: in6_addr {
        var a = in6_addr()
        let b = bytes
        withUnsafeMutableBytes(of: &a) { buf in
            for i in 0..<16 { buf[i] = b[i] }
        }
        return a
    }

    var description: String {
        var a = in6Addr
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        _ = inet_ntop(AF_INET6, &a, &buf, socklen_t(buf.count))
        return String(cString: buf)
    }

    var interfaceName: String? {
        guard scopeID != 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard if_indextoname(scopeID, &buf) != nil else { return nil }
        return String(cString: buf)
    }

    /// Address including the `%interface` zone for link-local addresses.
    var scopedDescription: String {
        if isLinkLocal, let name = interfaceName { return "\(description)%\(name)" }
        return description
    }

    var isLinkLocal: Bool { high >> 54 == 0x3FA }
    var isMulticast: Bool { high >> 56 == 0xFF }
    var isLoopback: Bool { high == 0 && low == 1 }
    var isUnspecified: Bool { high == 0 && low == 0 }
    var isUniqueLocal: Bool { high >> 57 == 0x7E }
    var isGlobalUnicast: Bool { high >> 61 == 1 }

    var reversePointerName: String {
        let nibbles = bytes.reversed().flatMap { [String($0 & 0x0F, radix: 16), String($0 >> 4, radix: 16)] }
        return nibbles.joined(separator: ".") + ".ip6.arpa."
    }

    func masked(prefixLength: Int) -> IPv6Address {
        func mask(_ bits: Int) -> UInt64 { bits <= 0 ? 0 : (bits >= 64 ? .max : UInt64.max << UInt64(64 - bits)) }
        if prefixLength >= 64 {
            return IPv6Address(high: high, low: low & mask(prefixLength - 64), scopeID: scopeID)
        }
        return IPv6Address(high: high & mask(prefixLength), low: 0, scopeID: scopeID)
    }

    func adding(_ n: UInt64) -> IPv6Address {
        let (sum, overflow) = low.addingReportingOverflow(n)
        return IPv6Address(high: overflow ? high &+ 1 : high, low: sum, scopeID: scopeID)
    }

    func socketAddress(port: UInt16 = 0) -> sockaddr_in6 {
        var sa = sockaddr_in6()
        sa.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        sa.sin6_family = sa_family_t(AF_INET6)
        sa.sin6_port = port.bigEndian
        sa.sin6_addr = in6Addr
        sa.sin6_scope_id = (isLinkLocal || isMulticast) ? scopeID : 0
        return sa
    }
}

// MARK: - IPAddress

enum IPAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
    case v4(IPv4Address)
    case v6(IPv6Address)

    init?(_ string: String) {
        if let a = IPv4Address(string) {
            self = .v4(a)
        } else if let a = IPv6Address(string) {
            self = .v6(a)
        } else {
            return nil
        }
    }

    init?(socketAddress sa: UnsafePointer<sockaddr>) {
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            let sin = UnsafeRawPointer(sa).loadUnaligned(as: sockaddr_in.self)
            self = .v4(IPv4Address(sin.sin_addr))
        case AF_INET6:
            let sin6 = UnsafeRawPointer(sa).loadUnaligned(as: sockaddr_in6.self)
            self = .v6(IPv6Address(sin6.sin6_addr, scopeID: sin6.sin6_scope_id))
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .v4(let a): return a.description
        case .v6(let a): return a.description
        }
    }

    var scopedDescription: String {
        switch self {
        case .v4(let a): return a.description
        case .v6(let a): return a.scopedDescription
        }
    }

    var v4: IPv4Address? { if case .v4(let a) = self { return a }; return nil }
    var v6: IPv6Address? { if case .v6(let a) = self { return a }; return nil }
    var isV4: Bool { v4 != nil }
    var isV6: Bool { v6 != nil }
    var family: Int32 { isV4 ? AF_INET : AF_INET6 }

    var reversePointerName: String {
        switch self {
        case .v4(let a): return a.reversePointerName
        case .v6(let a): return a.reversePointerName
        }
    }

    /// Host component suitable for URLs (IPv6 in brackets with an escaped zone).
    var urlHost: String {
        switch self {
        case .v4(let a): return a.description
        case .v6(let a):
            if a.isLinkLocal, let name = a.interfaceName { return "[\(a.description)%25\(name)]" }
            return "[\(a.description)]"
        }
    }

    static func < (lhs: IPAddress, rhs: IPAddress) -> Bool {
        switch (lhs, rhs) {
        case (.v4(let a), .v4(let b)): return a < b
        case (.v6(let a), .v6(let b)):
            // Global addresses before link-local ones.
            if a.isLinkLocal != b.isLinkLocal { return !a.isLinkLocal }
            return a < b
        case (.v4, .v6): return true
        case (.v6, .v4): return false
        }
    }

    func withSocketAddress<R>(port: UInt16, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
        switch self {
        case .v4(let a):
            var sa = a.socketAddress(port: port)
            return withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        case .v6(let a):
            var sa = a.socketAddress(port: port)
            return withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        }
    }
}

// MARK: - MAC

struct MACAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// 48-bit value, first octet in the most significant position.
    let value: UInt64

    init(value: UInt64) { self.value = value & 0xFFFF_FFFF_FFFF }

    init?<C: Collection>(bytes: C) where C.Element == UInt8 {
        guard bytes.count == 6 else { return nil }
        self.value = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    init?(_ string: String) {
        let parts = string.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for p in parts {
            guard p.count <= 2, let b = UInt8(p, radix: 16) else { return nil }
            bytes.append(b)
        }
        self.init(bytes: bytes)
    }

    var bytes: [UInt8] { (0..<6).map { UInt8(truncatingIfNeeded: value >> UInt64(40 - 8 * $0)) } }

    var description: String { bytes.map { String(format: "%02X", $0) }.joined(separator: ":") }

    var firstOctet: UInt8 { UInt8(truncatingIfNeeded: value >> 40) }
    /// Randomized "private" addresses (iOS, Android, Windows, macOS) set the locally-administered bit.
    var isLocallyAdministered: Bool { firstOctet & 0x02 != 0 }
    var isMulticast: Bool { firstOctet & 0x01 != 0 }
    var isZero: Bool { value == 0 }
    var isUsable: Bool { !isZero && !isMulticast }

    static func < (lhs: MACAddress, rhs: MACAddress) -> Bool { lhs.value < rhs.value }
}
