//
//  NetBIOSScanner.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

struct NetBIOSInfo: Sendable, Hashable {
    let address: IPv4Address
    var name: String?
    var workgroup: String?
    var mac: MACAddress?
    var isFileServer: Bool
}

/// NetBIOS Name Service node-status (NBSTAT) queries on UDP 137. Windows, Samba (NAS, Linux)
/// and many printers answer with their machine name, workgroup and adapter MAC.
enum NetBIOSScanner {
    static let request: [UInt8] = {
        var packet: [UInt8] = [0x4E, 0x53, // transaction id
                               0x00, 0x00, // flags
                               0x00, 0x01, // questions
                               0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                               0x20]       // encoded name length
        packet += [0x43, 0x4B] + [UInt8](repeating: 0x41, count: 30) // "*" padded, first-level encoded
        packet += [0x00, 0x00, 0x21, 0x00, 0x01] // terminator, NBSTAT, IN
        return packet
    }()

    static func query(_ targets: [IPv4Address], timeout: TimeInterval, cancel: CancelToken,
                      onResult: (NetBIOSInfo) -> Void) {
        guard !targets.isEmpty else { return }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        Socket.setNonBlocking(fd)
        Socket.setOption(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20)

        var answered = Set<IPv4Address>()
        var buffer = [UInt8](repeating: 0, count: 2048)

        func drain() {
            while let (count, from) = Socket.receive(fd, into: &buffer) {
                guard case .v4(let source) = from, answered.insert(source).inserted,
                      let info = parse(Array(buffer[0..<count]), from: source) else { continue }
                onResult(info)
            }
        }

        for (i, target) in targets.enumerated() {
            if cancel.isCancelled { break }
            Socket.send(fd, request, to: .v4(target), port: 137)
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

    static func parse(_ b: [UInt8], from address: IPv4Address) -> NetBIOSInfo? {
        let n = b.count
        guard n > 57 else { return nil }
        var offset = 12
        if b[offset] & 0xC0 == 0xC0 {
            offset += 2
        } else {
            while offset < n, b[offset] != 0 { offset += Int(b[offset]) + 1 }
            offset += 1
        }
        offset += 10 // type, class, ttl, rdlength
        guard offset < n else { return nil }

        let count = Int(b[offset])
        offset += 1
        var name: String?
        var group: String?
        var fileServer = false

        for _ in 0..<count {
            guard offset + 18 <= n else { break }
            let rawName = String(bytes: b[offset..<(offset + 15)], encoding: .isoLatin1)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) ?? ""
            let suffix = b[offset + 15]
            let isGroup = b[offset + 16] & 0x80 != 0
            if suffix == 0x00, !isGroup, name == nil, !rawName.isEmpty { name = rawName }
            if suffix == 0x00, isGroup, group == nil, !rawName.isEmpty { group = rawName }
            if suffix == 0x20 { fileServer = true }
            offset += 18
        }

        var mac: MACAddress?
        if offset + 6 <= n, let m = MACAddress(bytes: b[offset..<(offset + 6)]), m.isUsable { mac = m }
        guard name != nil || group != nil else { return nil }
        return NetBIOSInfo(address: address, name: name, workgroup: group, mac: mac, isFileServer: fileServer)
    }
}
