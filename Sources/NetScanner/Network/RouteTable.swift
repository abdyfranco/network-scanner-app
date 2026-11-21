//
//  RouteTable.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

struct NeighborEntry: Sendable, Hashable {
    let address: IPAddress
    let mac: MACAddress
    let interfaceIndex: UInt32
}

/// Reads the kernel routing table through `sysctl(NET_RT_FLAGS)`: the ARP cache, the
/// IPv6 neighbor cache and the default gateways. No privileges required.
enum RouteTable {
    private static let rtaxDestination = 0
    private static let rtaxGateway = 1
    private static let rtaxMax = 8

    private struct Message {
        let header: rt_msghdr
        let destination: IPAddress?
        let gatewayAddress: IPAddress?
        let gatewayMAC: MACAddress?
        let hasDestination: Bool
    }

    static func neighbors() -> [NeighborEntry] {
        var result: [NeighborEntry] = []
        var seen = Set<IPAddress>()
        for family in [AF_INET, AF_INET6] {
            for message in messages(family: family, flags: RTF_LLINFO) {
                guard let address = message.destination, let mac = message.gatewayMAC, mac.isUsable else { continue }
                switch address {
                case .v4(let a) where a.isMulticast || a.isBroadcast || a.isLoopback || a.value & 0xFF == 0xFF: continue
                case .v6(let a) where a.isMulticast || a.isLoopback: continue
                default: break
                }
                guard seen.insert(address).inserted else { continue }
                result.append(NeighborEntry(address: address, mac: mac, interfaceIndex: UInt32(message.header.rtm_index)))
            }
        }
        return result
    }

    static func defaultGateways() -> [IPAddress] {
        var gateways: [IPAddress] = []
        for family in [AF_INET, AF_INET6] {
            for message in messages(family: family, flags: RTF_GATEWAY) {
                let isDefault: Bool
                switch message.destination {
                case .v4(let a)?: isDefault = a.value == 0
                case .v6(let a)?: isDefault = a.isUnspecified
                case nil: isDefault = !message.hasDestination
                }
                guard isDefault, let gw = message.gatewayAddress, !gateways.contains(gw) else { continue }
                gateways.append(gw)
            }
        }
        return gateways
    }

    private static func messages(family: Int32, flags: Int32) -> [Message] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, family, NET_RT_FLAGS, flags]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        length += 4096 // the table can grow between calls
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }

        var out: [Message] = []
        buffer.withUnsafeBytes { raw in
            let headerSize = MemoryLayout<rt_msghdr>.size
            var offset = 0
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
                let messageLength = Int(header.rtm_msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }

                var cursor = offset + headerSize
                var destination: IPAddress?
                var gatewayAddress: IPAddress?
                var gatewayMAC: MACAddress?
                var hasDestination = false

                for bit in 0..<rtaxMax where header.rtm_addrs & Int32(1 << bit) != 0 {
                    guard cursor + 2 <= offset + messageLength else { break }
                    let saLength = Int(raw[cursor])
                    if bit == rtaxDestination {
                        hasDestination = saLength > 0
                        destination = address(raw, at: cursor, interfaceIndex: UInt32(header.rtm_index))
                    } else if bit == rtaxGateway {
                        if Int32(raw[cursor + 1]) == AF_LINK {
                            gatewayMAC = linkAddress(raw, at: cursor)
                        } else {
                            gatewayAddress = address(raw, at: cursor, interfaceIndex: UInt32(header.rtm_index))
                        }
                    }
                    cursor += saLength == 0 ? 4 : (saLength + 3) & ~3
                }

                out.append(Message(header: header, destination: destination, gatewayAddress: gatewayAddress,
                                   gatewayMAC: gatewayMAC, hasDestination: hasDestination))
                offset += messageLength
            }
        }
        return out
    }

    private static func address(_ raw: UnsafeRawBufferPointer, at offset: Int, interfaceIndex: UInt32) -> IPAddress? {
        let length = Int(raw[offset])
        let family = Int32(raw[offset + 1])
        if family == AF_INET {
            guard length >= 8 else { return length == 0 ? .v4(IPv4Address(0)) : nil }
            let value = UInt32(raw[offset + 4]) << 24 | UInt32(raw[offset + 5]) << 16 | UInt32(raw[offset + 6]) << 8 | UInt32(raw[offset + 7])
            return .v4(IPv4Address(value))
        }
        if family == AF_INET6, length >= 24 {
            var bytes = Array(raw[(offset + 8)..<(offset + 24)])
            var scope: UInt32 = 0
            if length >= 28 { scope = raw.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self) }
            if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
                let embedded = UInt32(bytes[2]) << 8 | UInt32(bytes[3])
                if embedded != 0 { scope = embedded }
                bytes[2] = 0
                bytes[3] = 0
                if scope == 0 { scope = interfaceIndex }
            }
            return .v6(IPv6Address(bytes: bytes, scopeID: scope))
        }
        return nil
    }

    private static func linkAddress(_ raw: UnsafeRawBufferPointer, at offset: Int) -> MACAddress? {
        let nameLength = Int(raw[offset + 5])
        let addressLength = Int(raw[offset + 6])
        guard addressLength == 6 else { return nil }
        let start = offset + 8 + nameLength
        guard start + 6 <= raw.count else { return nil }
        return MACAddress(bytes: raw[start..<(start + 6)])
    }
}
