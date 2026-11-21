//
//  ICMPPinger.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

/// ICMP / ICMPv6 echo sweeps using unprivileged `SOCK_DGRAM` ICMP sockets (no root needed on macOS).
enum ICMPPinger {
    struct Stats {
        var attempted = 0
        var sent = 0
        var blocked = 0
        /// Every send failed with a routing/permission error — typically Local Network privacy.
        var looksBlocked: Bool { attempted > 0 && sent == 0 && blocked > 0 }
    }

    private static let payload = Array("NetScanner probe".utf8)

    static func checksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum &+= UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i += 2
        }
        if i < data.count { sum &+= UInt32(data[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    static func echoRequest(type: UInt8, identifier: UInt16, sequence: UInt16, withChecksum: Bool) -> [UInt8] {
        var packet: [UInt8] = [type, 0, 0, 0,
                               UInt8(identifier >> 8), UInt8(identifier & 0xFF),
                               UInt8(sequence >> 8), UInt8(sequence & 0xFF)]
        packet += payload
        if withChecksum {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xFF)
        }
        return packet
    }

    // MARK: IPv4

    @discardableResult
    static func sweepV4(_ targets: [IPv4Address], timeout: TimeInterval, cancel: CancelToken,
                        onReply: (IPv4Address, TimeInterval) -> Void) -> Stats {
        var stats = Stats()
        guard !targets.isEmpty else { return stats }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return stats }
        defer { close(fd) }
        Socket.setNonBlocking(fd)
        Socket.setOption(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20)

        let identifier = UInt16.random(in: 1...0xFFFE)
        var sendTimes: [UInt32: CFAbsoluteTime] = [:]
        var replied = Set<UInt32>()
        var buffer = [UInt8](repeating: 0, count: 2048)

        func drain() {
            while let (count, from) = Socket.receive(fd, into: &buffer) {
                guard case .v4(let source) = from else { continue }
                // macOS delivers the IPv4 header on datagram ICMP sockets.
                var offset = 0
                if buffer[0] >> 4 == 4 { offset = Int(buffer[0] & 0x0F) * 4 }
                guard count >= offset + 8, buffer[offset] == 0 else { continue } // echo reply
                guard let sent = sendTimes[source.value], replied.insert(source.value).inserted else { continue }
                onReply(source, CFAbsoluteTimeGetCurrent() - sent)
            }
        }

        for (i, target) in targets.enumerated() {
            if cancel.isCancelled { break }
            let packet = echoRequest(type: 8, identifier: identifier, sequence: UInt16(truncatingIfNeeded: i), withChecksum: true)
            sendTimes[target.value] = CFAbsoluteTimeGetCurrent()
            stats.attempted += 1
            let err = Socket.send(fd, packet, to: .v4(target), port: 0)
            if err == 0 {
                stats.sent += 1
            } else if err == EHOSTUNREACH || err == EPERM || err == EACCES || err == ENETUNREACH {
                stats.blocked += 1
            } else if err == ENOBUFS {
                usleep(10_000)
            }
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
        return stats
    }

    // MARK: IPv6

    /// Pings explicit IPv6 targets and the all-nodes / all-routers multicast groups on each interface.
    static func sweepV6(_ targets: [IPv6Address], multicastInterfaces: [UInt32], timeout: TimeInterval,
                        cancel: CancelToken, onReply: (IPv6Address, TimeInterval) -> Void) {
        guard !targets.isEmpty || !multicastInterfaces.isEmpty else { return }
        let fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
        guard fd >= 0 else { return }
        defer { close(fd) }
        Socket.setNonBlocking(fd)
        Socket.setOption(fd, SOL_SOCKET, SO_RCVBUF, 1 << 20)
        Socket.setOption(fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, 1)
        Socket.setOption(fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP, 0)

        let identifier = UInt16.random(in: 1...0xFFFE)
        var sendTimes: [IPv6Address: CFAbsoluteTime] = [:]
        var multicastStart = CFAbsoluteTimeGetCurrent()
        var replied = Set<IPv6Address>()
        var buffer = [UInt8](repeating: 0, count: 2048)

        func drain() {
            while let (count, from) = Socket.receive(fd, into: &buffer) {
                guard count >= 8, buffer[0] == 129, case .v6(let source) = from else { continue } // echo reply
                guard !source.isLoopback, replied.insert(source).inserted else { continue }
                let started = sendTimes[source] ?? multicastStart
                onReply(source, CFAbsoluteTimeGetCurrent() - started)
            }
        }

        let groups = ["ff02::1", "ff02::2"].compactMap { IPv6Address($0) }
        multicastStart = CFAbsoluteTimeGetCurrent()
        for round in 0..<2 where !cancel.isCancelled {
            for index in multicastInterfaces {
                Socket.setOption(fd, IPPROTO_IPV6, IPV6_MULTICAST_IF, Int32(bitPattern: index))
                for group in groups {
                    var destination = group
                    destination.scopeID = index
                    let packet = echoRequest(type: 128, identifier: identifier, sequence: UInt16(round), withChecksum: false)
                    Socket.send(fd, packet, to: .v6(destination), port: 0)
                }
            }
            drain()
            if round == 0 { usleep(150_000) }
        }

        for (i, target) in targets.enumerated() {
            if cancel.isCancelled { break }
            let packet = echoRequest(type: 128, identifier: identifier, sequence: UInt16(truncatingIfNeeded: i + 2), withChecksum: false)
            sendTimes[target] = CFAbsoluteTimeGetCurrent()
            Socket.send(fd, packet, to: .v6(target), port: 0)
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
}
