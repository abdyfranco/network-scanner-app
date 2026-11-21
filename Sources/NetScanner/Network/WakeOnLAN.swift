//
//  WakeOnLAN.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation
import Darwin

/// Wake-on-LAN. The "magic packet" is six 0xFF bytes followed by the target's MAC sixteen times,
/// sent over UDP. A network card that is set to wake on it powers the machine up; for a sleeping Mac,
/// a Bonjour Sleep Proxy on the network (Apple TV, HomePod, AirPort) receives it and wakes the Mac.
enum WakeOnLAN {
    static func packet(for mac: MACAddress) -> [UInt8] {
        [UInt8](repeating: 0xFF, count: 6) + (0..<16).flatMap { _ in mac.bytes }
    }

    /// Sends the packet to every broadcast address given, plus the device's last known addresses,
    /// which reach it through a router when it's on another subnet. A few copies go out, as UDP can drop.
    /// Returns false when nothing could be sent at all (no network, or no Local Network access).
    static func wake(_ mac: MACAddress, broadcasts: [IPv4Address], lastKnown: [IPv4Address]) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        Socket.setOption(fd, SOL_SOCKET, SO_BROADCAST, 1)

        var seen = Set<IPv4Address>()
        let targets = ([IPv4Address(0xFFFF_FFFF)] + broadcasts + lastKnown).filter { seen.insert($0).inserted }
        let bytes = packet(for: mac)
        var sent = false
        for attempt in 0..<3 {
            if attempt > 0 { usleep(150_000) }
            for address in targets {
                // 9 (discard) is the usual port; some cards and tools use 7 (echo).
                for port: UInt16 in [9, 7] where Socket.send(fd, bytes, to: .v4(address), port: port) == 0 {
                    sent = true
                }
            }
        }
        return sent
    }
}
