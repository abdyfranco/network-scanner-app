//
//  ScanEngine.swift
//  Network Scanner
//
//  Copyright © 2026 Advandz Technologies, LLC.
//

import Foundation

struct ScanOptions: Codable, Equatable, Sendable {
    var ipv4Sweep = true
    var ipv6Discovery = true
    var bonjour = true
    var multicastDNS = true
    var reverseDNS = true
    var netbios = true
    var ubiquiti = true
    var fingerprint = true
    var timeoutMilliseconds: Double = 800
    var parallelProbes: Int = 256

    var timeout: TimeInterval { timeoutMilliseconds / 1000 }

    static func load() -> ScanOptions {
        guard let data = UserDefaults.standard.data(forKey: "scanOptions"),
              let options = try? JSONDecoder().decode(ScanOptions.self, from: data) else { return ScanOptions() }
        return options
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "scanOptions") }
    }
}

enum NameSource: Sendable { case dns, mdns }

enum ScanEvent: Sendable {
    case alive(IPAddress, DiscoverySource, latency: TimeInterval?)
    case neighbor(IPAddress, MACAddress, DiscoverySource)
    case openPort(IPAddress, UInt16)
    case hostname(IPAddress, String, NameSource)
    case netbios(NetBIOSInfo)
    case ubiquiti(UbiquitiInfo)
    case bonjour(BonjourService, IPAddress)
    case progress(Double, String)
    case localNetworkDenied
}

struct ScanConfiguration: Sendable {
    var target: ScanTarget
    var options: ScanOptions
    /// Interfaces facing the target: used for IPv6 multicast, broadcasts and neighbor filtering.
    var interfaces: [NetworkInterface]
}

/// Runs every discovery technique concurrently and reports findings as a stream of events.
///
/// 1. Sweep: ICMP echo, TCP connect to a few ports, NetBIOS, UniFi discovery and IPv6 multicast
///    ping run in parallel while the ARP/NDP caches are harvested (probing forces ARP, so hosts
///    that ignore everything still reveal themselves). Bonjour browses for the whole scan.
/// 2. Fingerprint: common service ports on live hosts.
/// 3. Names: unicast reverse DNS and multicast DNS reverse lookups for every live host.
final class ScanEngine: @unchecked Sendable {
    private let cancel = CancelToken()

    func stop() { cancel.cancel() }
    var isCancelled: Bool { cancel.isCancelled }

    func run(_ config: ScanConfiguration, emit: @escaping (ScanEvent) -> Void) async {
        let options = config.options
        let target = config.target
        let timeout = max(0.2, options.timeout)
        let cancel = self.cancel
        let alive = Locked(Set<IPAddress>())
        let reportedNeighbors = Locked(Set<NeighborEntry>())
        let interfaceIndexes = Set(config.interfaces.map(\.index))

        func markAlive(_ ip: IPAddress, _ source: DiscoverySource, _ latency: TimeInterval?) {
            alive.withLock { _ = $0.insert(ip) }
            emit(.alive(ip, source, latency: latency))
        }

        func harvestNeighbors() {
            for entry in RouteTable.neighbors() where target.contains(entry.address) {
                if case .v6(let a) = entry.address, a.isLinkLocal, !interfaceIndexes.isEmpty,
                   !interfaceIndexes.contains(entry.interfaceIndex) { continue }
                guard reportedNeighbors.withLock({ $0.insert(entry).inserted }) else { continue }
                alive.withLock { _ = $0.insert(entry.address) }
                emit(.neighbor(entry.address, entry.mac, entry.address.isV4 ? .arp : .ndp))
            }
        }

        emit(.progress(0.02, String(localized: "Preparing scan…")))

        // Bonjour browses for the whole scan.
        var bonjour: BonjourBrowser?
        let bonjourStarted = Date()
        if options.bonjour {
            let browser = BonjourBrowser()
            browser.start { service, ip in
                guard target.contains(ip) else { return }
                alive.withLock { _ = $0.insert(ip) }
                emit(.bonjour(service, ip))
            }
            bonjour = browser
        }

        // MARK: Phase 1 — sweep
        let v4 = options.ipv4Sweep ? target.ipv4 : []
        let sweepFinished = Locked(false)
        let poller = Task.detached {
            while !sweepFinished.current, !cancel.isCancelled {
                harvestNeighbors()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }

        emit(.progress(0.05, v4.isEmpty ? String(localized: "Discovering IPv6 neighbors…") : String(localized: "Probing \(v4.count) addresses…")))

        await withTaskGroup(of: Void.self) { group in
            if !v4.isEmpty {
                group.addTask {
                    await Blocking.run {
                        let stats = ICMPPinger.sweepV4(v4, timeout: timeout, cancel: cancel) { ip, rtt in
                            markAlive(.v4(ip), .icmp, rtt)
                        }
                        if stats.looksBlocked { emit(.localNetworkDenied) }
                    }
                }

                group.addTask {
                    await Blocking.run {
                        let ports = v4.count > 4096 ? [80, 443] : PortCatalog.discovery
                        var probes: [ProbeTarget] = []
                        probes.reserveCapacity(ports.count * v4.count)
                        for port in ports { for ip in v4 { probes.append(ProbeTarget(address: .v4(ip), port: port)) } }
                        let total = probes.count
                        var done = 0
                        TCPProber.run(probes, timeout: timeout, concurrency: options.parallelProbes, cancel: cancel) { probe, state, _ in
                            done += 1
                            if state != .filtered { markAlive(probe.address, .tcp, nil) }
                            if state == .open { emit(.openPort(probe.address, probe.port)) }
                            if done % 64 == 0 || done == total {
                                emit(.progress(0.05 + 0.55 * Double(done) / Double(max(total, 1)), String(localized: "Probing \(v4.count) addresses…")))
                            }
                        }
                    }
                }

                if options.netbios {
                    group.addTask {
                        await Blocking.run {
                            NetBIOSScanner.query(v4, timeout: max(timeout, 1.0), cancel: cancel) { info in
                                guard target.contains(.v4(info.address)) else { return }
                                alive.withLock { _ = $0.insert(.v4(info.address)) }
                                emit(.netbios(info))
                            }
                        }
                    }
                }
            }

            if options.ubiquiti, !target.ipv4.isEmpty {
                let broadcasts = config.interfaces.flatMap(\.ipv4).filter { !$0.address.isLinkLocal }.map(\.broadcast)
                let unicast = target.ipv4.count <= 4096 ? target.ipv4 : []
                group.addTask {
                    await Blocking.run {
                        UbiquitiDiscovery.discover(unicast: unicast, broadcasts: broadcasts, timeout: max(timeout, 1.5), cancel: cancel) { info in
                            // The broadcast reaches the whole subnet; keep only devices in the range being scanned.
                            guard target.contains(.v4(info.address)) else { return }
                            alive.withLock { _ = $0.insert(.v4(info.address)) }
                            emit(.ubiquiti(info))
                        }
                    }
                }
            }

            if options.ipv6Discovery {
                let explicit = target.ipv6
                let multicast = target.ipv6Prefixes.isEmpty ? [] : config.interfaces.map(\.index)
                group.addTask {
                    await Blocking.run {
                        ICMPPinger.sweepV6(explicit, multicastInterfaces: multicast, timeout: max(timeout, 1.5), cancel: cancel) { ip, rtt in
                            guard target.contains(.v6(ip)) else { return }
                            markAlive(.v6(ip), .icmp, rtt)
                        }
                    }
                }
                if !explicit.isEmpty {
                    group.addTask {
                        await Blocking.run {
                            var probes: [ProbeTarget] = []
                            for port in PortCatalog.discovery { for ip in explicit { probes.append(ProbeTarget(address: .v6(ip), port: port)) } }
                            TCPProber.run(probes, timeout: timeout, concurrency: options.parallelProbes, cancel: cancel) { probe, state, _ in
                                if state != .filtered { markAlive(probe.address, .tcp, nil) }
                                if state == .open { emit(.openPort(probe.address, probe.port)) }
                            }
                        }
                    }
                }
            }
        }

        sweepFinished.withLock { $0 = true }
        await poller.value
        harvestNeighbors()

        // MARK: Phase 2 — fingerprint live hosts
        if options.fingerprint, !cancel.isCancelled {
            let hosts = alive.current.filter { $0.isV4 || ($0.v6.map { !$0.isLinkLocal } ?? false) }.sorted()
            if !hosts.isEmpty {
                emit(.progress(0.62, String(localized: "Fingerprinting services on \(hosts.count) hosts…")))
                await Blocking.run {
                    var probes: [ProbeTarget] = []
                    for host in hosts { for port in PortCatalog.fingerprint { probes.append(ProbeTarget(address: host, port: port)) } }
                    let total = probes.count
                    var done = 0
                    TCPProber.run(probes, timeout: timeout, concurrency: options.parallelProbes, cancel: cancel) { probe, state, _ in
                        done += 1
                        if state == .open { emit(.openPort(probe.address, probe.port)) }
                        if done % 64 == 0 || done == total {
                            emit(.progress(0.62 + 0.13 * Double(done) / Double(max(total, 1)), String(localized: "Fingerprinting services on \(hosts.count) hosts…")))
                        }
                    }
                }
            }
        }

        // MARK: Phase 3 — names
        // Unicast PTR first, then multicast: running both for the same in-addr.arpa name at once makes
        // mDNSResponder merge the questions and the unicast lookup stalls until the multicast one times out.
        if !cancel.isCancelled, options.reverseDNS || options.multicastDNS {
            let hosts = alive.current.sorted()
            emit(.progress(0.78, String(localized: "Resolving names for \(hosts.count) hosts…")))
            if options.reverseDNS {
                let unicastTargets = hosts.filter { !($0.v6?.isLinkLocal ?? false) }
                await Blocking.run {
                    Blocking.forEach(unicastTargets, width: 16, cancel: cancel, deadline: 4) { ip in
                        if let name = HostnameResolver.reverseDNS(ip) { emit(.hostname(ip, name, .dns)) }
                    }
                }
            }
            if options.multicastDNS, !cancel.isCancelled {
                emit(.progress(0.85, String(localized: "Asking devices for their .local names…")))
                await Blocking.run {
                    HostnameResolver.multicastReverse(hosts, timeout: 2.0, cancel: cancel) { ip, name in
                        emit(.hostname(ip, name, .mdns))
                    }
                }
            }
        }

        // MARK: Wrap up — give Bonjour enough time to hear from sleepy devices.
        if let bonjour {
            let minimum: TimeInterval = 6
            let remaining = minimum - Date().timeIntervalSince(bonjourStarted)
            if remaining > 0, !cancel.isCancelled {
                emit(.progress(0.93, String(localized: "Listening for Bonjour services…")))
                await Blocking.run { Blocking.sleep(remaining, cancel: cancel) }
            }
            bonjour.stop()
        }
        harvestNeighbors()
        emit(.progress(1.0, cancel.isCancelled ? String(localized: "Scan stopped") : String(localized: "Scan complete")))
    }
}
