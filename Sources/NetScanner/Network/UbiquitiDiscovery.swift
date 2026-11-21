//
//  UbiquitiDiscovery.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

struct UbiquitiInterface: Sendable, Hashable {
    let mac: MACAddress
    let address: IPv4Address
}

struct UbiquitiInfo: Sendable, Hashable {
    var address: IPv4Address
    var baseMAC: MACAddress?
    var hostname: String?
    var productName: String?
    var platform: String?
    var model: String?
    var firmware: String?
    var osVersion: String?
    var uptime: TimeInterval?
    var interfaces: [UbiquitiInterface] = []

    /// Best short model code, e.g. "UDMPRO", "USL16LP", "U7PG2".
    var modelCode: String? { model ?? platform }

    /// MAC of the interface that owns the responding address.
    var macForAddress: MACAddress? {
        interfaces.first { $0.address == address }?.mac ?? baseMAC
    }

    var allMACs: [MACAddress] {
        var macs = interfaces.map(\.mac)
        if let baseMAC { macs.append(baseMAC) }
        var seen = Set<MACAddress>()
        return macs.filter { $0.isUsable && seen.insert($0).inserted }
    }
}

/// Ubiquiti Device Discovery Protocol (UDP 10001). UniFi consoles, switches, access points and
/// cameras answer with TLVs describing model, hostname and firmware.
///
/// TLVs observed from real gear: 0x01 MAC, 0x02 MAC+IPv4, 0x03 firmware, 0x06 product name,
/// 0x0A uptime, 0x0B hostname, 0x0C platform, 0x14/0x15 model, 0x16 OS version.
enum UbiquitiDiscovery {
    static let probeV1: [UInt8] = [0x01, 0x00, 0x00, 0x00]
    static let probeV2: [UInt8] = [0x02, 0x08, 0x00, 0x00]

    static func discover(unicast targets: [IPv4Address], broadcasts: [IPv4Address], timeout: TimeInterval,
                         cancel: CancelToken, onResult: (UbiquitiInfo) -> Void) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        Socket.setNonBlocking(fd)
        Socket.setOption(fd, SOL_SOCKET, SO_BROADCAST, 1)
        Socket.setOption(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20)

        var reported = Set<IPv4Address>()
        var buffer = [UInt8](repeating: 0, count: 4096)

        func drain() {
            while let (count, from) = Socket.receive(fd, into: &buffer) {
                guard case .v4(let source) = from,
                      let info = parse(Array(buffer[0..<count]), from: source) else { continue }
                // Prefer the richer v1 answer; report each device once.
                guard reported.insert(source).inserted else { continue }
                onResult(info)
            }
        }

        for address in broadcasts where !cancel.isCancelled {
            Socket.send(fd, probeV1, to: .v4(address), port: 10001)
            Socket.send(fd, probeV2, to: .v4(address), port: 10001)
        }
        for (i, target) in targets.enumerated() {
            if cancel.isCancelled { break }
            Socket.send(fd, probeV1, to: .v4(target), port: 10001)
            if i % 32 == 31 {
                drain()
                usleep(1_500)
            }
        }

        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while !cancel.isCancelled, CFAbsoluteTimeGetCurrent() < deadline {
            if Socket.waitReadable(fd, timeout: min(0.1, deadline - CFAbsoluteTimeGetCurrent())) { drain() }
        }
        drain()
    }

    static func parse(_ b: [UInt8], from address: IPv4Address) -> UbiquitiInfo? {
        guard b.count >= 4, b[0] == 1 || b[0] == 2 else { return nil }
        var info = UbiquitiInfo(address: address)
        var offset = 4
        var sawAnything = false

        func string(_ bytes: ArraySlice<UInt8>) -> String? {
            guard let s = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
                  !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { return nil }
            return s
        }

        while offset + 3 <= b.count {
            let type = b[offset]
            let length = Int(b[offset + 1]) << 8 | Int(b[offset + 2])
            offset += 3
            guard offset + length <= b.count else { break }
            let value = b[offset..<(offset + length)]
            offset += length
            sawAnything = true

            switch type {
            case 0x01:
                if length == 6 { info.baseMAC = MACAddress(bytes: value) }
            case 0x02:
                if length == 10, let mac = MACAddress(bytes: value.prefix(6)) {
                    let ip = value.dropFirst(6).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
                    if ip != 0 { info.interfaces.append(UbiquitiInterface(mac: mac, address: IPv4Address(ip))) }
                }
            case 0x03: info.firmware = string(value)
            case 0x06: info.productName = string(value)
            case 0x0A:
                if length == 4 { info.uptime = TimeInterval(value.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) }
            case 0x0B: info.hostname = string(value)
            case 0x0C: info.platform = string(value)
            case 0x14, 0x15:
                if let s = string(value) { info.model = info.model ?? s }
            case 0x16: info.osVersion = string(value)
            default: break
            }
        }

        guard sawAnything, info.hostname != nil || info.modelCode != nil || info.baseMAC != nil else { return nil }
        return info
    }
}
